# cns-sysjitter - System jitter measurement for latency-sensitive applications
#
# Measures the maximum jitter experienced by user-level code, useful for
# validating CPU isolation and tuning on cores running latency-critical workloads.
{
  lib,
  stdenv,
  fetchFromGitHub,
  gnumake,
}:
stdenv.mkDerivation rec {
  pname = "sysjitter";
  version = "1.4";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "cns-sysjitter";
    rev = "sysjitter-${version}";
    hash = "sha256-+pNxrK4JPoP4+ZTxpf+39I3sFnngDq8Kp3KeAKTSfyo=";
  };

  nativeBuildInputs = [gnumake];

  buildPhase = ''
    runHook preBuild
    make -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp sysjitter $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "System jitter measurement tool for latency-sensitive applications";
    homepage = "https://github.com/Xilinx-CNS/cns-sysjitter";
    license = licenses.gpl3Only;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
