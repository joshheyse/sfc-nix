{
  description = "Solarflare NIC tooling - OpenOnload, TCPDirect, sfptpd, SolarCapture, and more for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {inherit system;};

    # Onload source tree (needed by tcpdirect at build time)
    onloadSrc = pkgs.fetchFromGitHub {
      owner = "Xilinx-CNS";
      repo = "onload";
      rev = "v${onloadVersion}";
      hash = "sha256-wyvTtOjD6fwuT2OGGhr10F0Q7hXE97mGREhq7Ns14hw=";
    };
    onloadVersion = "9.0.2";

    # Userspace-only openonload (no kernel modules)
    basePackage = pkgs.callPackage ./package.nix {};

    # TCPDirect (userspace-only)
    tcpdirectPackage = pkgs.callPackage ./tcpdirect.nix {
      openonload = basePackage;
      inherit onloadSrc;
    };

    # TCPDirect with examples
    tcpdirectWithExamplesPackage = pkgs.callPackage ./tcpdirect.nix {
      openonload = basePackage;
      inherit onloadSrc;
      withExamples = true;
    };

    # Additional Solarflare tools
    sfptpdPackage = pkgs.callPackage ./sfptpd.nix {};
    sysjitterPackage = pkgs.callPackage ./sysjitter.nix {};
    sfnettestPackage = pkgs.callPackage ./sfnettest.nix {};
    ebpfAsmPackage = pkgs.callPackage ./ebpf-asm.nix {};
    solarcapturePackage = pkgs.callPackage ./solarcapture.nix {
      openonload = basePackage;
      inherit onloadSrc;
    };
  in {
    packages.${system} = {
      default = basePackage;
      inherit (basePackage) examples;
      tcpdirect = tcpdirectPackage;
      tcpdirect-with-examples = tcpdirectWithExamplesPackage;
      sfptpd = sfptpdPackage;
      sysjitter = sysjitterPackage;
      sfnettest = sfnettestPackage;
      ebpf-asm = ebpfAsmPackage;
      solarcapture = solarcapturePackage;
    };

    nixosModules.default = import ./module.nix;

    overlays.default = final: _prev: {
      openonload = final.callPackage ./package.nix {};
      tcpdirect = final.callPackage ./tcpdirect.nix {
        inherit (final) openonload;
        inherit onloadSrc;
      };
      sfptpd = final.callPackage ./sfptpd.nix {};
      sysjitter = final.callPackage ./sysjitter.nix {};
      sfnettest = final.callPackage ./sfnettest.nix {};
      ebpf-asm = final.callPackage ./ebpf-asm.nix {};
      solarcapture = final.callPackage ./solarcapture.nix {
        inherit (final) openonload;
        inherit onloadSrc;
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      name = "solarflare-dev";
      buildInputs = [
        basePackage
        basePackage.examples
        tcpdirectWithExamplesPackage
        sfnettestPackage
        sysjitterPackage
        pkgs.gcc
        pkgs.gnumake
      ];

      shellHook = ''
        export EFVI_INCLUDE_PATH="${basePackage}/include"
        export EFVI_LIB_PATH="${basePackage}/lib"
        export ZF_INCLUDE_PATH="${tcpdirectWithExamplesPackage}/include"
        export ZF_LIB_PATH="${tcpdirectWithExamplesPackage}/lib"
      '';
    };
  };
}
