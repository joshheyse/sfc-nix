# OpenOnload NixOS module - kernel bypass networking for Solarflare NICs
#
# Provides EFVI (Ethernet Fabric Virtual Interface) for ultra-low-latency networking.
# Includes kernel modules, userspace libraries, and optionally sample applications.
{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.networking.openonload;

  # Build OpenOnload package against the current kernel
  inherit (config.boot.kernelPackages) kernel;
  openonloadPackage = pkgs.callPackage ./package.nix {
    inherit kernel;
  };

  sfptpdPackage = pkgs.callPackage ./sfptpd.nix {};
in {
  options.networking.openonload = {
    enable = mkEnableOption "OpenOnload kernel bypass networking for Solarflare NICs";

    package = mkOption {
      type = types.package;
      default = openonloadPackage;
      defaultText = literalExpression "pkgs.callPackage ./package.nix { kernel = config.boot.kernelPackages.kernel; }";
      description = "The OpenOnload package to use.";
    };

    loadModulesAtBoot = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to load OpenOnload kernel modules at boot.";
    };

    useOutOfTreeSfc = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Use the out-of-tree sfc driver from OpenOnload instead of the in-kernel driver.
        Required for full EFVI performance. When enabled, the in-kernel sfc driver will
        be blacklisted.
      '';
    };

    accessGroup = mkOption {
      type = types.str;
      default = "wheel";
      description = "Group allowed to access ef_vi devices (onload, sfc_char).";
    };

    physModeGid = mkOption {
      type = types.either (types.enum ["root-only" "cap-net-raw"]) types.int;
      default = "root-only";
      description = ''
        Who is allowed to allocate `EF_PD_PHYS_MODE` protection domains via ef_vi.
        PHYS_MODE bypasses the IOMMU and gives userspace direct physical-address DMA —
        required for the lowest-latency RX paths in ef_vi-based apps.

        - "root-only": pass -2 (upstream module default). Only EUID=0 may use PHYS_MODE.
        - "cap-net-raw": pass -1. Any process holding CAP_NET_RAW (e.g. via setcap) may
          use PHYS_MODE. Recommended for hosts running setcap'd binaries instead of root.
        - <integer gid>: only members of that group.

        With the default, even a setcap'd binary (cap_net_raw+ep) is rejected — the
        symptom is `ef_pd_alloc_by_name` returning -EPERM.
      '';
    };

    installExamples = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to install ef_vi sample binaries (eflatency, efpingpong, etc.).";
    };

    sfptpd = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable sfptpd to discipline the Solarflare NIC hardware clock.
          Required for accurate hardware timestamps from ef_vi/TCPDirect.
          When enabled, also enables chrony for system clock NTP sync.
        '';
      };

      package = mkOption {
        type = types.package;
        default = sfptpdPackage;
        description = "The sfptpd package to use.";
      };

      mode = mkOption {
        type = types.enum ["freerun" "crny"];
        default = "crny";
        description = ''
          Sync mode for sfptpd:
          - "crny": Sync NIC clock to system clock, which chrony syncs via NTP
          - "freerun": NIC clock runs free, synced to system clock at startup only
        '';
      };
    };
  };

  config = mkIf cfg.enable (let
    physModeGidValue =
      if cfg.physModeGid == "root-only"
      then "-2"
      else if cfg.physModeGid == "cap-net-raw"
      then "-1"
      else toString cfg.physModeGid;
  in {
    # Group all environment settings together
    environment = {
      # Add OpenOnload package to system packages (provides onload, ef_vi tools, etc.)
      systemPackages =
        [cfg.package]
        ++ optionals cfg.installExamples [cfg.package.examples]
        ++ optionals cfg.sfptpd.enable [cfg.sfptpd.package];

      # Set library path for applications using ef_vi
      sessionVariables = {
        LD_LIBRARY_PATH = "${cfg.package}/lib";
      };

      # Add ef_vi include path for development
      variables = {
        EFVI_INCLUDE_PATH = "${cfg.package}/include";
      };
    };

    # Group all boot settings together
    boot = {
      # Onload intercepts the syscall table via an indirect call into
      # x64_sys_call, whose endbr64 the kernel deliberately seals at boot —
      # with CONFIG_X86_KERNEL_IBT active, sfc_resource refuses to load
      # ("check_syscall_ibt_valid: FATAL") and /dev/onload never appears.
      # Upstream requires disabling IBT and has no fix planned
      # (Xilinx-CNS/onload#299, #332). Takes effect after a reboot.
      kernelParams = optional pkgs.stdenv.hostPlatform.isx86_64 "ibt=off";

      # Blacklist in-kernel sfc driver when using out-of-tree driver
      blacklistedKernelModules = mkIf cfg.useOutOfTreeSfc [
        "sfc"
        "sfc_siena"
      ];

      # Use the kmod output — contains only .ko files, keeping the initrd small
      extraModulePackages = [cfg.package.kmod];

      # Module load order is important:
      # sfc -> sfc_resource -> sfc_char -> onload
      kernelModules = mkIf cfg.loadModulesAtBoot [
        "sfc"
        "sfc_resource"
        "sfc_char"
        "onload"
      ];

      # Module loading configuration:
      # - Override in-kernel sfc with install commands that force our out-of-tree module
      # - Block sfc_siena entirely (we don't need it)
      # - Softdeps ensure correct load order: sfc -> sfc_resource -> sfc_char -> onload
      extraModprobeConfig = ''
        ${optionalString cfg.useOutOfTreeSfc ''
          # Force modprobe to load our out-of-tree sfc from the openonload package.
          # Without this, the in-kernel sfc may be found first despite blacklisting,
          # because boot.kernelModules explicitly loads modules (bypassing blacklist).
          install sfc ${pkgs.kmod}/bin/insmod ${cfg.package.kmod}/lib/modules/${kernel.modDirVersion}/extra/openonload/sfc.ko
          # Block the in-kernel sfc_siena entirely
          install sfc_siena /bin/false
        ''}
        # OpenOnload module dependencies
        softdep sfc_resource pre: sfc
        softdep sfc_char pre: sfc_resource
        softdep onload pre: sfc_char

        # Let systemd manage onload_cp_server instead of the kernel spawning it.
        # Without this, the kernel rejects the server with ENONET when no onloaded
        # apps are running yet.
        options onload cplane_spawn_server=0

        # Gate EF_PD_PHYS_MODE protection-domain allocation. See physModeGid option.
        options sfc_char phys_mode_gid=${physModeGidValue}
        options onload phys_mode_gid=${physModeGidValue}
      '';
    };

    # Systemd services for OpenOnload and related daemons
    systemd.services = {
      # Ensure modules are loaded correctly and interfaces configured
      openonload = {
        description = "OpenOnload kernel module loader";
        after = ["network-pre.target"];
        before = ["network.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.kmod}/bin/modprobe onload";
        };

        # Bring up sfc interfaces after module load
        postStart = ''
          # Wait briefly for interfaces to appear
          sleep 1
          for iface in /sys/class/net/*; do
            iface_name="$(basename "$iface")"
            if [ -e "$iface/device/driver" ]; then
              driver="$(basename "$(readlink "$iface/device/driver")")"
              if [ "$driver" = "sfc" ]; then
                ${pkgs.iproute2}/bin/ip link set "$iface_name" up || true
              fi
            fi
          done
        '';

        # Only start if not already loaded
        unitConfig = {
          ConditionPathExists = "!/sys/module/onload";
        };
      };

      # Onload control plane server - required for TCPDirect/ZF
      onload-cp = {
        description = "Onload Control Plane Server";
        after = ["openonload.service"];
        requires = ["openonload.service"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.package}/bin/onload_cp_server";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };

      # sfptpd: discipline the NIC hardware clock for accurate hardware timestamps
      sfptpd = mkIf cfg.sfptpd.enable {
        description = "Solarflare Enhanced PTP Daemon";
        after =
          ["openonload.service" "network.target"]
          ++ optionals (cfg.sfptpd.mode == "crny") ["chronyd.service"];
        requires = ["openonload.service"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          Type = "simple";
          ExecStart = "${cfg.sfptpd.package}/bin/sfptpd -f /etc/sfptpd.conf";
          Restart = "on-failure";
          RestartSec = 5;
          # sfptpd needs capabilities to adjust hardware clocks
          AmbientCapabilities = "CAP_SYS_TIME CAP_NET_ADMIN CAP_NET_RAW";
        };
      };
    };

    # udev rules for Solarflare devices
    services.udev.extraRules = ''
      # Solarflare X2 network adapters
      SUBSYSTEM=="net", ACTION=="add", DRIVERS=="sfc", TAG+="systemd", ENV{SYSTEMD_WANTS}+="openonload.service"

      # Allow users in the configured group to access ef_vi
      KERNEL=="onload", MODE="0660", GROUP="${cfg.accessGroup}"
      KERNEL=="sfc_char", MODE="0660", GROUP="${cfg.accessGroup}"
    '';

    # sfptpd chrony integration
    services.chrony = mkIf (cfg.sfptpd.enable && cfg.sfptpd.mode == "crny") {
      enable = true;
      extraConfig = ''
        # Allow sfptpd to query chrony's tracking data
        allow 127.0.0.1
        allow ::1
      '';
    };

    environment.etc."sfptpd.conf" = mkIf cfg.sfptpd.enable {
      text =
        if cfg.sfptpd.mode == "crny"
        then ''
          [general]
          sync_module crny crny1
          message_log syslog
          stats_log off

          # Sync NIC clocks to system clock; let chrony handle NTP
          clock_readonly system

          [crny1]
          # Chrony is the NTP source for the system clock.
          # sfptpd syncs the NIC PHC to match.
        ''
        else ''
          [general]
          sync_module freerun fr1
          message_log syslog
          stats_log off
          clock_readonly system
          non_solarflare_nics off

          [fr1]
          interface system
        '';
    };
  });
}
