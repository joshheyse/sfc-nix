{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.hardware.xilinx.xrtManagement;
  inherit (config.boot.kernelPackages) kernel;
  defaultPackage = pkgs.callPackage ./xrt-xclmgmt.nix {
    inherit kernel;
  };
in {
  options.hardware.xilinx.xrtManagement = {
    enable = mkEnableOption "the XRT management driver for AMD/Xilinx Alveo cards";

    package = mkOption {
      type = types.package;
      default = defaultPackage;
      defaultText = literalExpression "pkgs.callPackage ./xrt-xclmgmt.nix { kernel = config.boot.kernelPackages.kernel; }";
      description = "The XRT xclmgmt kernel-module package to use.";
    };

    loadModuleAtBoot = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to load the xclmgmt module at boot.";
    };
  };

  config = mkIf cfg.enable {
    boot = {
      extraModulePackages = [cfg.package];
      kernelModules = mkIf cfg.loadModuleAtBoot ["xclmgmt"];
    };

    # /run/booted-system keeps the module tree selected at boot. Load from the
    # new generation explicitly so a switch that adds xclmgmt can activate it
    # without requiring a reboot first.
    systemd.services.xrt-xclmgmt = mkIf cfg.loadModuleAtBoot {
      description = "XRT management kernel module loader";
      after = ["systemd-modules-load.service"];
      wantedBy = ["multi-user.target"];

      unitConfig = {
        ConditionPathExists = "!/sys/module/xclmgmt";
        # A kernel upgrade builds modules only for the next kernel. In that
        # case, defer loading until reboot rather than failing activation.
        ConditionPathIsDirectory = "${config.system.modulesTree}/lib/modules/%v";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.kmod}/bin/modprobe -d ${config.system.modulesTree} xclmgmt";
      };
    };
  };
}
