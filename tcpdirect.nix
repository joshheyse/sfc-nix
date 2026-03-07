# TCPDirect (ZF) package - zero-copy ultra-low-latency networking
#
# Builds against the OpenOnload source tree for headers and static libs.
# Produces libonload_zf.so, libonload_zf_static.a, zf_stackdump, and
# optionally sample applications (zftcppingpong, zfudppingpong, etc.).
#
# Parameterized build:
#   openonload           - the openonload package (provides headers + libs)
#   onloadSrc            - the onload source tree (needed for build-time includes)
#   withExamples ? false - true = also install ZF sample/test applications
#   ndebug ? true        - true = release build (NDEBUG=1)
{
  lib,
  stdenv,
  fetchFromGitHub,
  openonload,
  onloadSrc,
  withExamples ? false,
  ndebug ? true,
  gnumake,
  gcc,
  patchelf,
  git,
}:
stdenv.mkDerivation rec {
  pname = "tcpdirect";
  version = "9.0.2";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "tcpdirect";
    rev = "tcpdirect-${version}";
    hash = "sha256-ANQPYIx43yb/xr9stvwx4i2vGmLwhO1rA7WZJJb0ScI=";
  };

  nativeBuildInputs = [
    gnumake
    gcc
    patchelf
    git # needed for version info during build
  ];

  buildInputs = [
    openonload
  ];

  # Fix GCC warnings treated as errors
  NIX_CFLAGS_COMPILE = "-Wno-error=unused-result -Wno-error=stringop-truncation -Wno-error=format-truncation";

  dontStrip = true;

  postPatch = ''
    patchShebangs scripts/
  '';

  buildPhase = ''
    runHook preBuild

    # Point to onload source tree for headers and build-time includes
    export ONLOAD_TREE="${onloadSrc}"
    export HOME="$TMPDIR"

    # Initialize a fake git repo so version detection works
    git init -q
    git add -A
    git commit -q -m "nix build" --allow-empty

    echo "Building TCPDirect${lib.optionalString ndebug " (release, NDEBUG=1)"}..."
    make -j$NIX_BUILD_CORES \
      CC="${stdenv.cc}/bin/gcc" \
      CLINK="${stdenv.cc}/bin/gcc" \
      ONLOAD_TREE="${onloadSrc}" \
      CITOOLS_LIB="${openonload}/lib/libcitools1.a" \
      CIUL_LIB="${openonload}/lib/libciul1.a" \
      ${lib.optionalString ndebug "NDEBUG=1"}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/include/zf

    # Install libraries
    echo "Installing TCPDirect libraries..."
    local buildRoot="build"
    local libDir
    libDir=$(find "$buildRoot" -type d -name lib | head -1)
    if [ -n "$libDir" ]; then
      cp -P "$libDir"/libonload_zf* $out/lib/ 2>/dev/null || true
    fi

    # Install zf_stackdump tool
    echo "Installing zf_stackdump..."
    local binFile
    binFile=$(find "$buildRoot" -name zf_stackdump -type f | head -1)
    if [ -n "$binFile" ]; then
      cp "$binFile" $out/bin/
    fi

    ${lib.optionalString withExamples ''
      # Install ZF sample applications
      echo "Installing TCPDirect sample applications..."
      for app in zfsink zfsend zfudppingpong zftcppingpong zfaltpingpong zftcpmtpong; do
        # Prefer shared-linked binaries
        local appFile
        appFile=$(find "$buildRoot" -path "*/shared/$app" -type f | head -1)
        if [ -z "$appFile" ]; then
          appFile=$(find "$buildRoot" -path "*/static/$app" -type f | head -1)
        fi
        if [ -n "$appFile" ]; then
          cp "$appFile" $out/bin/
          echo "  Installed $app"
        fi
      done

      # Install trade_sim applications
      for app in trader_tcpdirect_ds_efvi trader_tcpdirect_ds_efvi_ct_rx; do
        local appFile
        appFile=$(find "$buildRoot" -path "*/shared/$app" -type f | head -1)
        if [ -z "$appFile" ]; then
          appFile=$(find "$buildRoot" -path "*/static/$app" -type f | head -1)
        fi
        if [ -n "$appFile" ]; then
          cp "$appFile" $out/bin/
          echo "  Installed $app"
        fi
      done
    ''}

    # Install headers
    echo "Installing TCPDirect headers..."
    cp -r src/include/zf/* $out/include/zf/

    runHook postInstall
  '';

  dontPatchELF = false;

  preFixup = ''
    echo "=== Fixing RPATH in TCPDirect binaries ==="
    for bin in $out/bin/*; do
      if [ -f "$bin" ] && [ -x "$bin" ]; then
        echo "Fixing $bin"
        patchelf --set-rpath "$out/lib:${openonload}/lib:${lib.makeLibraryPath buildInputs}" "$bin" 2>&1 || echo "  (skipped)"
      fi
    done

    echo "=== Fixing RPATH in TCPDirect libraries ==="
    for lib_file in $out/lib/*.so $out/lib/*.so.*; do
      if [ -f "$lib_file" ]; then
        echo "Fixing $lib_file"
        patchelf --set-rpath "$out/lib:${openonload}/lib:${lib.makeLibraryPath buildInputs}" "$lib_file" 2>&1 || echo "  (skipped)"
      fi
    done
    echo "=== Done fixing RPATH ==="
  '';

  meta = with lib; {
    description = "TCPDirect (ZF) - zero-copy ultra-low-latency TCP/UDP stack";
    homepage = "https://github.com/Xilinx-CNS/tcpdirect";
    license = licenses.mit;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
