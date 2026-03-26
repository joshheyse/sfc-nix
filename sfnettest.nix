# cns-sfnettest - Network latency and throughput measurement tools
#
# Provides sfnt-pingpong (latency) and sfnt-stream (throughput) for
# benchmarking network performance with Solarflare NICs.
{
  lib,
  stdenv,
  fetchFromGitHub,
  gnumake,
}:
stdenv.mkDerivation rec {
  pname = "sfnettest";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "cns-sfnettest";
    rev = "sfnettest-${version}";
    hash = "sha256-vLs8sCJcZfVknHGpK21U5LOzajpz8IFTAAWzHf28W20=";
  };

  nativeBuildInputs = [gnumake];

  # Newer GCC flags false positives in upstream code
  NIX_CFLAGS_COMPILE = "-Wno-error=maybe-uninitialized -Wno-error=unused-result";

  buildPhase = ''
    runHook preBuild
    # Create version.mk so the Makefile doesn't try hg/git
    echo "SFNT_VERSION := ${version}" > src/version.mk
    make -C src -j$NIX_BUILD_CORES
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp src/sfnt-pingpong $out/bin/
    cp src/sfnt-stream $out/bin/
    runHook postInstall
  '';

  meta = with lib; {
    description = "Network latency and throughput measurement tools for Solarflare NICs";
    homepage = "https://github.com/Xilinx-CNS/cns-sfnettest";
    license = licenses.gpl2Only;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
