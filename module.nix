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
    withExamples = cfg.installExamples;
  };
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

    installExamples = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to install ef_vi sample binaries (eflatency, efpingpong, etc.).";
    };
  };

  config = mkIf cfg.enable {
    # Group all environment settings together
    environment = {
      # Add OpenOnload package to system packages (provides onload, ef_vi tools, etc.)
      systemPackages = [cfg.package];

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
      # Blacklist in-kernel sfc driver when using out-of-tree driver
      blacklistedKernelModules = mkIf cfg.useOutOfTreeSfc [
        "sfc"
        "sfc_siena"
      ];

      # Load OpenOnload kernel modules
      extraModulePackages = [cfg.package];

      # Module load order is important:
      # sfc -> sfc_resource -> sfc_char -> onload
      kernelModules = mkIf cfg.loadModulesAtBoot [
        "sfc"
        "sfc_resource"
        "sfc_char"
        "onload"
      ];

      # Ensure modules are loaded in the correct order via modprobe dependencies
      extraModprobeConfig = ''
        # OpenOnload module dependencies
        softdep sfc_resource pre: sfc
        softdep sfc_char pre: sfc_resource
        softdep onload pre: sfc_char
      '';
    };

    # Systemd service to ensure modules are loaded correctly and interfaces configured
    systemd.services.openonload = {
      description = "OpenOnload kernel module loader";
      after = ["network-pre.target"];
      before = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.kmod}/bin/modprobe onload";
      };

      # Only start if not already loaded
      unitConfig = {
        ConditionPathExists = "!/sys/module/onload";
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
  };
}
