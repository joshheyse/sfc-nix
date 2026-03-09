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
  which,
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
    which # needed by mmake scripts
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

    export HOME="$TMPDIR"

    # Copy onload source to a writable location, patch shebangs, and
    # replace /bin/pwd with pwd (doesn't exist in nix sandbox)
    cp -r "${onloadSrc}" "$TMPDIR/onload-src"
    chmod -R u+w "$TMPDIR/onload-src"
    find "$TMPDIR/onload-src/scripts" -type f -exec sed -i 's|/bin/pwd|pwd|g' {} +
    patchShebangs "$TMPDIR/onload-src/scripts"
    export ONLOAD_TREE="$TMPDIR/onload-src"
    export PATH="$ONLOAD_TREE/scripts:$PATH"

    # Initialize a fake git repo so version detection works
    git init -q
    git config user.email "nix-build@localhost"
    git config user.name "Nix Build"
    git add -A
    git commit -q -m "nix build" --allow-empty

    echo "Building TCPDirect${lib.optionalString ndebug " (release, NDEBUG=1)"}..."
    make -j$NIX_BUILD_CORES \
      CC="${stdenv.cc}/bin/gcc" \
      CLINK="${stdenv.cc}/bin/gcc" \
      ONLOAD_TREE="$TMPDIR/onload-src" \
      ${lib.optionalString ndebug "NDEBUG=1"}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/include/zf

    # Install libraries
    echo "Installing TCPDirect libraries..."
    find build -name 'libonload_zf*' -exec cp -P {} $out/lib/ \;
    echo "  Installed: $(ls $out/lib/)"

    # Install zf_stackdump tool
    echo "Installing zf_stackdump..."
    local binFile
    binFile=$(find build -name zf_stackdump -type f | head -1)
    if [ -n "$binFile" ]; then
      cp "$binFile" $out/bin/
    fi

    ${lib.optionalString withExamples ''
      # Install ZF sample applications
      echo "Installing TCPDirect sample applications..."
      for app in zfsink zfsend zfudppingpong zftcppingpong zfaltpingpong zftcpmtpong; do
        # Prefer shared-linked binaries
        local appFile
        appFile=$(find "build" -path "*/shared/$app" -type f | head -1)
        if [ -z "$appFile" ]; then
          appFile=$(find "build" -path "*/static/$app" -type f | head -1)
        fi
        if [ -n "$appFile" ]; then
          cp "$appFile" $out/bin/
          echo "  Installed $app"
        fi
      done

      # Install trade_sim applications
      for app in trader_tcpdirect_ds_efvi trader_tcpdirect_ds_efvi_ct_rx; do
        local appFile
        appFile=$(find "build" -path "*/shared/$app" -type f | head -1)
        if [ -z "$appFile" ]; then
          appFile=$(find "build" -path "*/static/$app" -type f | head -1)
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
