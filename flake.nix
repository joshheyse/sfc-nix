{
  description = "OpenOnload & TCPDirect - kernel bypass networking for Solarflare NICs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-25.11";
  };

  outputs = {nixpkgs}: let
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

    # Userspace-only with examples
    withExamplesPackage = pkgs.callPackage ./package.nix {
      withExamples = true;
    };

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
  in {
    packages.${system} = {
      default = basePackage;
      with-examples = withExamplesPackage;
      tcpdirect = tcpdirectPackage;
      tcpdirect-with-examples = tcpdirectWithExamplesPackage;
    };

    nixosModules.default = import ./module.nix;

    overlays.default = final: _prev: {
      openonload = final.callPackage ./package.nix {};
      tcpdirect = final.callPackage ./tcpdirect.nix {
        inherit (final) openonload;
        inherit onloadSrc;
      };
    };

    devShells.${system}.default = pkgs.mkShell {
      name = "openonload-dev";
      buildInputs = [
        withExamplesPackage
        tcpdirectWithExamplesPackage
        pkgs.gcc
        pkgs.gnumake
      ];

      shellHook = ''
        export EFVI_INCLUDE_PATH="${withExamplesPackage}/include"
        export EFVI_LIB_PATH="${withExamplesPackage}/lib"
        export ZF_INCLUDE_PATH="${tcpdirectWithExamplesPackage}/include"
        export ZF_LIB_PATH="${tcpdirectWithExamplesPackage}/lib"
      '';
    };
  };
}
