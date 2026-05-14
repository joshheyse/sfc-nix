# OpenOnload package - kernel bypass networking for Solarflare NICs
#
# Parameterized build:
#   kernel ? null        - null = userspace-only, non-null = full build with kernel modules
#   ndebug ? true        - true = release build (NDEBUG=1, no assertions, -fomit-frame-pointer)
{
  lib,
  stdenv,
  fetchFromGitHub,
  kernel ? null,
  ndebug ? true,
  perl,
  python3,
  which,
  kmod,
  gawk,
  gnused,
  coreutils,
  bash,
  gnumake,
  gcc,
  binutils,
  libcap,
  libmnl,
  libnl,
  autoconf,
  automake,
  libtool,
  pkg-config,
  patchelf,
  nukeReferences,
}:
stdenv.mkDerivation rec {
  pname = "openonload";
  version = "9.0.2";

  outputs = ["out" "examples"] ++ lib.optionals (kernel != null) ["kmod"];

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "onload";
    rev = "v${version}";
    hash = "sha256-wyvTtOjD6fwuT2OGGhr10F0Q7hXE97mGREhq7Ns14hw=";
  };

  nativeBuildInputs = [
    perl
    python3
    which
    kmod
    gawk
    nukeReferences
    gnused
    coreutils
    bash
    gnumake
    gcc
    binutils
    autoconf
    automake
    libtool
    pkg-config
    patchelf
    stdenv.cc.libc # For libc_compat header generation
  ];

  buildInputs =
    [
      libcap
      libmnl
      libnl
    ]
    ++ lib.optionals (kernel != null) [
      kernel.dev
    ];

  # Kernel module build requires these (only when building with kernel)
  KERNELDIR =
    lib.optionalString (kernel != null)
    "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build";
  INSTALL_MOD_PATH =
    lib.optionalString (kernel != null)
    (placeholder "out");

  # Fix GCC warnings treated as errors
  NIX_CFLAGS_COMPILE = "-Wno-error=unused-result -Wno-error=stringop-truncation";

  # Don't strip kernel modules
  dontStrip = true;

  postPatch = ''
    patchShebangs scripts/
    patchShebangs mk/
    patchShebangs src/

    # Fix ALL hardcoded /bin paths - search and replace in all shell scripts
    find . -type f \( -name "*.sh" -o -name "mmaketool" -o -name "mmakebuildtree" -o -name "mmake" -o -name "fns" -o -name "mmake-fns" \) -exec \
      sed -i \
        -e 's|/bin/pwd|pwd|g' \
        -e 's|/bin/uname|uname|g' \
        -e 's|/bin/sed|sed|g' \
        -e 's|/bin/mkdir|mkdir|g' \
        -e 's|/bin/rm|rm|g' \
        -e 's|/bin/ln|ln|g' \
        -e 's|/bin/cp|cp|g' \
        -e 's|/bin/cat|cat|g' \
        -e 's|/bin/grep|grep|g' \
        -e 's|/bin/echo|echo|g' \
        {} \;

    ${lib.optionalString (kernel != null) ''
      # Fix kernel build path detection - OpenOnload looks in /lib/modules
      substituteInPlace scripts/mmaketool \
        --replace-quiet 'KPATH="/lib/modules/$KVER/build"' \
          'KPATH="''${KPATH:-${kernel.dev}/lib/modules/$KVER/build}"'

      # Also fix mmakebuildtree kernel path check
      substituteInPlace scripts/mmakebuildtree \
        --replace-quiet '/lib/modules/' '${kernel.dev}/lib/modules/'
    ''}
  '';

  configurePhase = ''
    runHook preConfigure

    # Set up environment for OpenOnload build system
    export PATH="$PWD/scripts:$PATH"
    export ONLOAD_TREE="$PWD"
    export HOME="$TMPDIR"

    ${lib.optionalString ndebug ''
      export NDEBUG=1
    ''}

    ${lib.optionalString (kernel != null) ''
      # Tell OpenOnload where to find the kernel build
      export KVER="${kernel.modDirVersion}"
      export KPATH="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"

      # Initialize build tree for driver (kernel modules)
      mmakebuildtree --driver
    ''}

    # Initialize build tree for userspace
    mmakebuildtree --user

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    export PATH="$PWD/scripts:$PATH"
    export ONLOAD_TREE="$PWD"
    export HOME="$TMPDIR"
    ${lib.optionalString ndebug "export NDEBUG=1"}

    local topPath="$(mmaketool --toppath)"

    ${lib.optionalString (kernel != null) ''
      export KVER="${kernel.modDirVersion}"
      export KPATH="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"

      local driverBuild="$(mmaketool --driverbuild)"
      echo "Building driver (kernel modules)..."
      make -C "$topPath/build/$driverBuild" -j$NIX_BUILD_CORES \
        KERNELDIR="$KPATH" \
        KVER="$KVER"
    ''}

    local userBuild="$(mmaketool --userbuild)"
    echo "Building userspace${lib.optionalString ndebug " (release, NDEBUG=1)"}..."
    # The full build is needed to generate headers like libc_compat.h
    # We remove the unit tests directory to avoid linking issues
    rm -rf "$topPath/build/$userBuild/tests/unit" || true

    make -C "$topPath/build/$userBuild" -j$NIX_BUILD_CORES \
      ${lib.optionalString ndebug "NDEBUG=1"}

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    export PATH="$PWD/scripts:$PATH"
    export ONLOAD_TREE="$PWD"
    export HOME="$TMPDIR"
    ${lib.optionalString ndebug "export NDEBUG=1"}

    local userBuild="$(mmaketool --userbuild)"
    local topPath="$(mmaketool --toppath)"

    # Create output directories
    mkdir -p $out/bin
    mkdir -p $out/lib
    mkdir -p $out/include/etherfabric

    ${lib.optionalString (kernel != null) ''
      export KVER="${kernel.modDirVersion}"
      export KPATH="${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"

      local driverBuild="$(mmaketool --driverbuild)"

      # Install kernel modules to separate kmod output (keeps initrd small).
      # Strip embedded nix store paths (build dir, compiler toolchain) from .ko files
      # so nix's closure scanner doesn't pull linux-dev/rustc/llvm/gcc into the initrd.
      mkdir -p $kmod/lib/modules/${kernel.modDirVersion}/extra/openonload

      echo "Installing kernel modules..."
      find "$topPath/build/$driverBuild" -name '*.ko' -exec cp {} $kmod/lib/modules/${kernel.modDirVersion}/extra/openonload/ \;

      echo "Stripping store references from kernel modules..."
      find $kmod -name '*.ko' -exec nuke-refs -e $kmod {} \;

      # Install module load/unload scripts to main output
      mkdir -p $out/share/openonload
      cp src/driver/linux/load.sh $out/share/openonload/
      cp src/driver/linux/unload.sh $out/share/openonload/
    ''}

    # Install userspace libraries
    echo "Installing userspace libraries..."
    find "$topPath/build/$userBuild" -name '*.so*' -exec cp -P {} $out/lib/ \;
    find "$topPath/build/$userBuild" -name '*.a' -exec cp {} $out/lib/ \;

    # Install ELF binaries from the build tree. Paths come from upstream
    # mmake.mk targets (src/tools/{cplane,ip}/mmake.mk). Missing entries fail
    # the build so a future upstream layout change can't silently drop tools.
    echo "Installing ELF binaries..."
    for src in \
        tools/cplane/onload_cp_client \
        tools/cplane/onload_cp_server \
        tools/ip/onload_stackdump \
        tools/ip/onload_tcpdump.bin \
        tools/ip/onload_fuser; do
      local full="$topPath/build/$userBuild/$src"
      if [ -f "$full" ]; then
        cp "$full" "$out/bin/"
      else
        echo "ERROR: expected binary not built: $full" >&2
        exit 1
      fi
    done

    # Install user-facing wrapper scripts from the source tree.
    echo "Installing wrapper scripts..."
    for script in onload onload_tool onload_tcpdump sfcirqaffinity sfcaffinity_config; do
      if [ -f "scripts/$script" ]; then
        install -m755 "scripts/$script" "$out/bin/$script"
      else
        echo "ERROR: expected script not found: scripts/$script" >&2
        exit 1
      fi
    done

    # Install ef_vi sample applications to separate output (avoids changing
    # the main derivation hash when toggling examples on/off, which would
    # otherwise force a kernel module rebuild and new initrd).
    mkdir -p $examples/bin
    echo "Installing ef_vi sample applications..."
    local efviDir="$topPath/build/$userBuild/tests/ef_vi"
    for sample in eflatency efpingpong efsend efsink efforward eftap efrss \
                  efsend_pio efsend_pio_warm efsink_packed efforward_packed \
                  efjumborx exchange trader_onload_ds_efvi \
                  efrink_controller efrink_consumer \
                  efdelegated_client efdelegated_server \
                  efsend_timestamping efsend_warming efsend_cplane; do
      # Check both possible locations
      if [ -f "$efviDir/$sample" ]; then
        cp "$efviDir/$sample" $examples/bin/
        echo "  Installed $sample"
      elif [ -f "$efviDir/$sample/$sample" ]; then
        cp "$efviDir/$sample/$sample" $examples/bin/
        echo "  Installed $sample"
      fi
    done

    # Install sfnt-pingpong if available
    local sfntDir="$topPath/build/$userBuild/tests/sfnt-pingpong"
    if [ -f "$sfntDir/sfnt-pingpong" ]; then
      cp "$sfntDir/sfnt-pingpong" $examples/bin/
      echo "  Installed sfnt-pingpong"
    fi

    # Install headers for ef_vi development
    echo "Installing headers..."
    cp -r src/include/etherfabric/* $out/include/etherfabric/

    runHook postInstall
  '';

  # Disable automatic shrinking that happens before our fixes
  dontPatchELF = false;

  # Fix library paths in binaries and libraries BEFORE the fixup phase checks RPATH
  preFixup = ''
    echo "=== Fixing RPATH in binaries ==="
    for bin in $out/bin/* $examples/bin/*; do
      if [ -f "$bin" ] && [ -x "$bin" ]; then
        echo "Fixing $bin"
        patchelf --set-rpath "$out/lib:${lib.makeLibraryPath buildInputs}" "$bin" 2>&1 || echo "  (skipped)"
      fi
    done

    echo "=== Fixing RPATH in libraries ==="
    for lib_file in $out/lib/*.so $out/lib/*.so.*; do
      if [ -f "$lib_file" ]; then
        echo "Fixing $lib_file"
        patchelf --set-rpath "$out/lib:${lib.makeLibraryPath buildInputs}" "$lib_file" 2>&1 || echo "  (skipped)"
      fi
    done
    echo "=== Done fixing RPATH ==="
  '';

  meta = with lib; {
    description = "OpenOnload - high performance user-level network stack with EFVI support";
    homepage = "https://github.com/Xilinx-CNS/onload";
    license = with licenses; [gpl2Only lgpl21Only bsd3];
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
