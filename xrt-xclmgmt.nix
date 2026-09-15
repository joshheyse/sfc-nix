# XRT management driver for Alveo accelerator cards.
{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel,
  kmod,
  nukeReferences,
}:
stdenv.mkDerivation rec {
  pname = "xrt-xclmgmt";
  version = "2026.1-unstable-2026-09-14";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "XRT";
    rev = "d8ececf957676346bce66eb760aae8036921379c";
    hash = "sha256-zAXtIpP1PIbve5EXWodEoK5qnVaaRyZnCrum3k4fVsI=";
  };

  nativeBuildInputs =
    kernel.moduleBuildDependencies
    ++ [
      kmod
      nukeReferences
    ];

  dontConfigure = true;
  dontStrip = true;

  postPatch = ''
    cp ${./xrt-version.h} src/runtime_src/core/pcie/driver/linux/include/version.h
  '';

  buildPhase = ''
    runHook preBuild

    make -C src/runtime_src/core/pcie/driver/linux/xocl/mgmtpf \
      -j$NIX_BUILD_CORES \
      module_path=$PWD/src/runtime_src/core/pcie/driver/linux/xocl/mgmtpf \
      KERNEL_SRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    moduleDir=$out/lib/modules/${kernel.modDirVersion}/extra/xrt
    mkdir -p "$moduleDir"
    cp src/runtime_src/core/pcie/driver/linux/xocl/mgmtpf/xclmgmt.ko "$moduleDir/"
    nuke-refs -e "$out" "$moduleDir/xclmgmt.ko"

    runHook postInstall
  '';

  meta = {
    description = "XRT management kernel driver for AMD/Xilinx Alveo accelerator cards";
    homepage = "https://github.com/Xilinx/XRT";
    license = lib.licenses.gpl2Only;
    platforms = lib.platforms.linux;
  };
}
