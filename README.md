# sfc-nix

Nix flake for Solarflare NIC tooling — [OpenOnload](https://github.com/Xilinx-CNS/onload), [TCPDirect](https://github.com/Xilinx-CNS/tcpdirect), [sfptpd](https://github.com/Xilinx-CNS/sfptpd), [SolarCapture](https://github.com/Xilinx-CNS/solarcapture), and more.

Provides kernel bypass networking, precision time sync, packet capture, and performance measurement tools for Solarflare NICs on NixOS.

## Flake Outputs

| Output | Description |
|--------|-------------|
| `packages.x86_64-linux.default` | Onload userspace libs + headers + core tools (no kernel modules) |
| `packages.x86_64-linux.with-examples` | Above + ef_vi sample binaries (eflatency, sfnt-pingpong, etc.) |
| `packages.x86_64-linux.tcpdirect` | TCPDirect libs + headers + zf_stackdump |
| `packages.x86_64-linux.tcpdirect-with-examples` | Above + ZF sample apps (zftcppingpong, zfudppingpong, etc.) |
| `packages.x86_64-linux.sfptpd` | Solarflare Enhanced PTP Daemon — hardware timestamped time sync |
| `packages.x86_64-linux.solarcapture` | High-speed packet capture and processing framework |
| `packages.x86_64-linux.sysjitter` | System jitter measurement for latency-sensitive isolated cores |
| `packages.x86_64-linux.sfnettest` | Network latency (sfnt-pingpong) and throughput (sfnt-stream) tools |
| `packages.x86_64-linux.ebpf-asm` | eBPF program assembler with Intel-like syntax |
| `nixosModules.default` | NixOS module (`networking.openonload.*`) with kernel modules |
| `overlays.default` | Adds all packages to nixpkgs |
| `devShells.x86_64-linux.default` | Shell with onload, tcpdirect, sfnettest, sysjitter, gcc, make |

## Build Modes

Both OpenOnload and TCPDirect default to **release mode** (`NDEBUG=1`): assertions disabled, `-fomit-frame-pointer` enabled. Pass `ndebug = false` for debug builds with extra logging and assertions.

## NixOS Usage (Production)

```nix
# flake.nix
inputs.sfc-nix.url = "git+ssh://git@github.com/joshheyse/sfc-nix";
inputs.sfc-nix.inputs.nixpkgs.follows = "nixpkgs";

# In nixosConfiguration modules:
sfc-nix.nixosModules.default

# In configuration.nix:
networking.openonload.enable = true;
```

### Module Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | bool | `false` | Enable OpenOnload |
| `package` | package | auto | Override the OpenOnload package |
| `loadModulesAtBoot` | bool | `true` | Load kernel modules at boot |
| `useOutOfTreeSfc` | bool | `true` | Use out-of-tree sfc driver (blocks in-kernel module) |
| `accessGroup` | string | `"wheel"` | Group for ef_vi device access |
| `installExamples` | bool | `false` | Install ef_vi sample binaries |

### What the Module Does

- Loads out-of-tree sfc + onload kernel modules at boot
- Forces the out-of-tree sfc driver via modprobe `install` override
- Starts `onload_cp_server` (required for TCPDirect/ZF)
- Auto-brings-up sfc interfaces after module load
- Sets udev rules for device permissions

## Dev Shell Usage

```bash
# Quick shell with ef_vi + ZF tools and headers
nix develop git+ssh://git@github.com/joshheyse/sfc-nix

# Compile ef_vi code
gcc -I$EFVI_INCLUDE_PATH -L$EFVI_LIB_PATH -lciul1 your_code.c

# Compile TCPDirect code
gcc -I$ZF_INCLUDE_PATH -L$ZF_LIB_PATH -lonload_zf your_code.c
```

## Consuming in Another Flake

```nix
{
  inputs.sfc-nix.url = "git+ssh://git@github.com/joshheyse/sfc-nix";
  inputs.sfc-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { self, nixpkgs, sfc-nix, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      onload = sfc-nix.packages.x86_64-linux.default;
      tcpdirect = sfc-nix.packages.x86_64-linux.tcpdirect;
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
