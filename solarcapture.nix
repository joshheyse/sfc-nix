# SolarCapture - high-speed packet capture and processing for Solarflare NICs
#
# Provides capture tools, a processing pipeline framework, and Python bindings.
# Depends on libciul (ef_vi) from OpenOnload for zero-copy packet access.
#
# Parameterized build:
#   openonload          - the openonload package (provides libraries)
#   onloadSrc           - the onload source tree (needed for headers at build time)
{
  lib,
  stdenv,
  fetchFromGitHub,
  openonload,
  onloadSrc,
  gnumake,
  gcc,
  python3,
  autoconf,
  patchelf,
  zlib,
  libaio,
  which,
  flex,
  bison,
  linuxHeaders,
}:
stdenv.mkDerivation rec {
  pname = "solarcapture";
  version = "1.7.3";

  src = fetchFromGitHub {
    owner = "Xilinx-CNS";
    repo = "solarcapture";
    rev = "solarcapture-${version}";
    hash = "sha256-UgMK8S3RzJv6fCOmcn6WU5xX8Jv/vzEtMm0lOPsb8BY=";
  };

  nativeBuildInputs = [
    gnumake
    gcc
    python3
    autoconf
    patchelf
    which
    flex
    bison
  ];

  buildInputs = [
    openonload
    zlib
    libaio
    linuxHeaders
  ];

  NIX_CFLAGS_COMPILE = "-Wno-error=unused-result -Wno-error=stringop-truncation -Wno-error=format-truncation -Wno-error=format-overflow -Wno-error=address-of-packed-member";

  postPatch = ''
        patchShebangs src/

        # Fix hardcoded /bin/pwd
        substituteInPlace src/Makefile \
          --replace-quiet '/bin/pwd' 'pwd'

        # Fix hardcoded /usr/bin/python3 for version detection
        substituteInPlace src/Makefile \
          --replace-quiet '/usr/bin/python3' '${python3}/bin/python3'

        # Force Linux packet capture type - the bundled libpcap checks /usr/include
        # which doesn't exist in the Nix sandbox
        substituteInPlace src/Makefile \
          --replace-quiet "configure --disable-shared" "configure --with-pcap=linux --disable-shared" \
          --replace-quiet "configure --with-sfsc=.." "configure --with-pcap=linux --with-sfsc=.."

        # Rewrite solar_clusterd Makefile to use nix python paths and onload headers
        cat > src/solar_clusterd/Makefile <<CLUSTERMK
    PYTHON_CFLAGS = -I${python3}/include/python${python3.pythonVersion} -fPIC
    PYTHON_LIBS = -L${python3}/lib -lpython${python3.pythonVersion}

    CFLAGS += \$(PYTHON_CFLAGS)
    CFLAGS += -I$TMPDIR/onload-src/src/include -Werror -Wall -Wundef -Wstrict-prototypes -Wpointer-arith -Wnested-externs -g -O2 -DNDEBUG
    LIBS   += \$(PYTHON_LIBS)

    SRCS := filter_string cluster_protocol
    OBJS := \$(patsubst %,%.o,\$(SRCS))

    %.o: %.c
    	\$(CC) \$(CFLAGS) -c \$< -o \$@

    all: cluster_protocol.so

    cluster_protocol.so: \$(OBJS)
    	\$(CC) -shared -g -Wl,-E \$^ \$(PYTHON_LIBS) -o \$@

    clean:
    	rm -f *.o *.so *.pyc
    CLUSTERMK
  '';

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"

    # Copy onload source to a writable location (needed for headers)
    cp -r "${onloadSrc}" "$TMPDIR/onload-src"
    chmod -R u+w "$TMPDIR/onload-src"
    patchShebangs "$TMPDIR/onload-src/scripts"
    find "$TMPDIR/onload-src/scripts" -type f -exec sed -i 's|/bin/pwd|pwd|g' {} +
    export ONLOAD_TREE="$TMPDIR/onload-src"

    cd src

    # Generate the version header before parallel build to avoid race.
    gcc core/compiled_ef_vi_version.c -o compiled_ef_vi_version \
      "${openonload}/lib/libciul1.a"
    ./compiled_ef_vi_version > include/compiled_ef_vi_version.h
    rm -f compiled_ef_vi_version

    # Build everything
    make -j$NIX_BUILD_CORES \
      EFVI_LIB="${openonload}/lib/libciul1.a" \
      ONLOAD_TREE="$TMPDIR/onload-src" \
      PYTHON3="${python3}/bin/python3"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib

    # Install binaries - check both src/ and build/ directories
    for bin in solar_capture solar_capture_monitor solar_replay solar_debug \
               solar_libpcap solar_balancer solar_css_tunnel_bridge; do
      local found
      found=$(find .. -name "$bin" -type f -executable 2>/dev/null | head -1)
      if [ -n "$found" ]; then
        cp "$found" $out/bin/
        echo "  Installed $bin"
      fi
    done

    # Install libraries
    find .. -name 'libsolarcapture*.so*' -exec cp -P {} $out/lib/ \;
    find .. -name 'libsolarcapture*.a' -exec cp {} $out/lib/ \;

    # Install Python module
    local pymoddir
    pymoddir=$(find .. -path "*/python/solar_capture" -type d 2>/dev/null | head -1)
    if [ -n "$pymoddir" ]; then
      mkdir -p $out/${python3.sitePackages}
      cp -r "$pymoddir" $out/${python3.sitePackages}/
    fi

    # Install solar_clusterd Python script
    if [ -f solar_clusterd/solar_clusterd ]; then
      cp solar_clusterd/solar_clusterd $out/bin/
      chmod +x $out/bin/solar_clusterd
    fi

    runHook postInstall
  '';

  dontPatchELF = false;

  preFixup = ''
    local rpath="$out/lib:${openonload}/lib:${lib.makeLibraryPath buildInputs}"
    for bin in $out/bin/*; do
      if [ -f "$bin" ] && [ -x "$bin" ]; then
        patchelf --set-rpath "$rpath" "$bin" 2>&1 || true
      fi
    done
    # Fix all .so files including Python modules
    find $out -name '*.so' -o -name '*.so.*' | while read lib_file; do
      if [ -f "$lib_file" ]; then
        patchelf --set-rpath "$rpath" "$lib_file" 2>&1 || true
      fi
    done
  '';

  meta = with lib; {
    description = "SolarCapture - high-speed packet capture and processing for Solarflare NICs";
    homepage = "https://github.com/Xilinx-CNS/solarcapture";
    license = licenses.mit;
    platforms = ["x86_64-linux"];
    maintainers = [];
  };
}
