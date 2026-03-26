# ebpf_asm - eBPF program assembler using Intel-like syntax
#
# Assembles eBPF programs from human-readable assembly into ELF object files.
{
  lib,
  stdenv,
  fetchFromGitHub,
  python3,
  makeWrapper,
}:
stdenv.mkDerivation rec {
  pname = "ebpf-asm";
  version = "0.8";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "ebpf_asm";
    rev = version;
    hash = "sha256-JYziiBa5CZOCDRHgYPgEKw1Yb332+GHshaFmiA1FUJI=";
  };

  nativeBuildInputs = [makeWrapper];
  buildInputs = [python3];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/ebpf_asm $out/bin $out/share/ebpf_asm

    # Install Python modules
    cp ebpf_asm.py paren.py $out/lib/ebpf_asm/

    # Create wrapper
    makeWrapper ${python3}/bin/python3 $out/bin/ebpf_asm \
      --add-flags "$out/lib/ebpf_asm/ebpf_asm.py" \
      --set PYTHONPATH "$out/lib/ebpf_asm"

    # Install include files and examples
    cp defs.i net_hdrs.i $out/share/ebpf_asm/
    cp -r examples $out/share/ebpf_asm/ || true

    runHook postInstall
  '';

  meta = with lib; {
    description = "eBPF program assembler using Intel-like syntax";
    homepage = "https://github.com/Xilinx-CNS/ebpf_asm";
    license = licenses.mit;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
