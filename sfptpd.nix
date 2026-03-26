# sfptpd - Solarflare Enhanced PTP Daemon
#
# Precision Time Protocol synchronization using Solarflare NIC hardware
# timestamping. Supports PTP, PPS, NTP/chrony integration, and freerun modes.
#
# Parameterized build:
#   withGps ? false  - true = enable GPS/GPSD integration
{
  lib,
  stdenv,
  fetchFromGitHub,
  gnumake,
  gcc,
  libmnl,
  libcap,
  withGps ? false,
  gpsd ? null,
}:
stdenv.mkDerivation rec {
  pname = "sfptpd";
  version = "3.9.0.1007";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "sfptpd";
    rev = "v${version}";
    hash = "sha256-DyBKcsQCAtAkqX7ud5DV1J1yaPrFTmE074Yotq17VCA=";
  };

  nativeBuildInputs = [
    gnumake
    gcc
  ];

  buildInputs =
    [
      libmnl
      libcap
    ]
    ++ lib.optionals withGps [
      gpsd
    ];

  # sfptpd uses -std=c2x and -Werror
  NIX_CFLAGS_COMPILE = "-Wno-error=format-truncation";

  postPatch = ''
    patchShebangs scripts/
  '';

  buildPhase = ''
    runHook preBuild

    make -j$NIX_BUILD_CORES \
      ${lib.optionalString (!withGps) "NO_GPS=1"} \
      INST_INITS= \
      all

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    make install \
      DESTDIR="$out" \
      prefix="" \
      ${lib.optionalString (!withGps) "NO_GPS=1"} \
      INST_INITS= \
      INST_OMIT=sfptpmon

    # Move binaries from sbin to bin for NixOS conventions
    if [ -d "$out/sbin" ]; then
      mkdir -p "$out/bin"
      mv "$out/sbin"/* "$out/bin/"
      rmdir "$out/sbin"
    fi

    # Install sfptpmon separately if python3 is available
    local sfptpmon
    sfptpmon=$(find build -name sfptpmon -type f | head -1)
    if [ -n "$sfptpmon" ]; then
      install -Dm755 "$sfptpmon" "$out/bin/sfptpmon"
    fi

    # Install default config as a reference
    mkdir -p "$out/share/sfptpd"
    cp config/default.cfg "$out/share/sfptpd/sfptpd.conf.default"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Solarflare Enhanced PTP Daemon - precision time synchronization";
    homepage = "https://github.com/Xilinx-CNS/sfptpd";
    license = licenses.bsd3;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
