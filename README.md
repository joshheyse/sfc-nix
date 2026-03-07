# openonload-nix

Nix flake for [OpenOnload](https://github.com/Xilinx-CNS/onload) and [TCPDirect](https://github.com/Xilinx-CNS/tcpdirect) - kernel bypass networking for Solarflare NICs.

Provides userspace libraries, headers, and tools for EFVI and ZF (TCPDirect) development, plus a NixOS module for full kernel module integration.

## Flake Outputs

| Output | Description |
|--------|-------------|
| `packages.x86_64-linux.default` | Onload userspace libs + headers + core tools (no kernel modules) |
| `packages.x86_64-linux.with-examples` | Above + ef_vi sample binaries (eflatency, sfnt-pingpong, etc.) |
| `packages.x86_64-linux.tcpdirect` | TCPDirect libs + headers + zf_stackdump |
| `packages.x86_64-linux.tcpdirect-with-examples` | Above + ZF sample apps (zftcppingpong, zfudppingpong, etc.) |
| `nixosModules.default` | NixOS module (`networking.openonload.*`) with kernel modules |
| `overlays.default` | Adds `pkgs.openonload` and `pkgs.tcpdirect` |
| `devShells.x86_64-linux.default` | Shell with all examples, gcc, make, env vars set |

## Build Modes

Both OpenOnload and TCPDirect default to **release mode** (`NDEBUG=1`): assertions disabled, `-fomit-frame-pointer` enabled. Pass `ndebug = false` for debug builds with extra logging and assertions.

## NixOS Usage (Production)

```nix
# flake.nix
inputs.openonload.url = "github:joshheyse/openonload-nix";
inputs.openonload.inputs.nixpkgs.follows = "nixpkgs";

# In nixosConfiguration modules:
openonload.nixosModules.default

# In configuration.nix:
networking.openonload.enable = true;
```

### Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable OpenOnload |
| `package` | package | auto | Override the OpenOnload package |
| `loadModulesAtBoot` | bool | `true` | Load kernel modules at boot |
| `useOutOfTreeSfc` | bool | `true` | Use out-of-tree sfc driver |
| `accessGroup` | string | `"wheel"` | Group for ef_vi device access |
| `installExamples` | bool | `false` | Install ef_vi sample binaries |

## Dev Shell Usage

```bash
# Quick shell with ef_vi + ZF tools and headers
nix develop github:joshheyse/openonload-nix

# Compile ef_vi code
gcc -I$EFVI_INCLUDE_PATH -L$EFVI_LIB_PATH -lciul1 your_code.c

# Compile TCPDirect code
gcc -I$ZF_INCLUDE_PATH -L$ZF_LIB_PATH -lonload_zf your_code.c
```

## Consuming in Another Flake

```nix
{
  inputs.openonload.url = "github:joshheyse/openonload-nix";
  inputs.openonload.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, openonload, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      onload = openonload.packages.x86_64-linux.default;
      tcpdirect = openonload.packages.x86_64-linux.tcpdirect;
    in pkgs.mkShell {
      buildInputs = [ onload tcpdirect pkgs.gcc ];
      # Onload headers: ${onload}/include/etherfabric/
      # Onload libs: ${onload}/lib/ (libciul1.so, libonload_ext.so)
      # ZF headers: ${tcpdirect}/include/zf/
      # ZF libs: ${tcpdirect}/lib/ (libonload_zf.so)
    };
  };
}
```
