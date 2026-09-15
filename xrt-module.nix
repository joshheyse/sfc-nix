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
  };
}
