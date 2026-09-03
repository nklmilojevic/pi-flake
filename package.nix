{
  lib,
  stdenv,
  fetchurl,
}:
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  platform =
    sources.platforms.${stdenv.hostPlatform.system}
      or (throw "Unsupported platform: ${stdenv.hostPlatform.system}");

  # The prebuilt napi addons shipped next to the binary (clipboard, and the
  # darwin-modifiers addon on macOS) are dlopen'd at runtime and need libgcc_s
  # beyond bare glibc.
  runtimeLibraries = [ stdenv.cc.cc.lib ];

  # The aarch64 release binary is linked with 64 KiB segment alignment (every
  # PT_LOAD carries p_align 0x10000); the x86_64 one uses 4 KiB. patchelf
  # assumes 4 KiB unless told otherwise.
  elfPageSize = if stdenv.hostPlatform.isAarch64 then "65536" else "4096";
in
stdenv.mkDerivation {
  pname = "pi";
  version = sources.version;

  src = fetchurl {
    url = platform.url;
    hash = platform.hash;
  };

  sourceRoot = "pi";

  # The release artifact is a Bun single-file executable: the JS bundle and the
  # compressed assets live inside the ELF/Mach-O image. Stripping rewrites the
  # file and breaks it, and on macOS it also voids the signature.
  dontStrip = true;

  # All ELF rewriting happens in postFixup with an explicit page size; the
  # default --shrink-rpath pass has no such flag.
  dontPatchELF = true;

  # pi resolves its theme/, docs/, examples/, export-html/, native/ and
  # node_modules/ trees relative to the executable, so the whole release tree
  # is kept together and only a symlink is exposed on PATH. The symlink
  # resolves back into libexec, which keeps that lookup working.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/libexec" "$out/bin"
    cp -R . "$out/libexec/pi"
    chmod -R u+w "$out/libexec/pi"
    chmod +x "$out/libexec/pi/pi"
    ln -s "$out/libexec/pi/pi" "$out/bin/pi"
    runHook postInstall
  '';

  # Only the interpreter may be rewritten on the launcher. Growing the dynamic
  # section of a Bun single-file executable — `--add-needed`, `--set-rpath`,
  # and therefore autoPatchelfHook — shifts the payload appended to the binary
  # and makes the aarch64 build SIGSEGV before main. The launcher needs nothing
  # beyond glibc anyway: DT_NEEDED is libc, ld-linux, libpthread, libdl and
  # libm, all resolved from the interpreter's built-in search path. The napi
  # addons are ordinary shared objects, so they take a normal rpath.
  postFixup = lib.optionalString stdenv.hostPlatform.isLinux ''
    patchelf \
      --page-size ${elfPageSize} \
      --set-interpreter "$(cat "$NIX_CC/nix-support/dynamic-linker")" \
      "$out/libexec/pi/pi"

    find "$out/libexec/pi" -name '*.node' -type f -print0 | while IFS= read -r -d "" addon; do
      patchelf --set-rpath "${lib.makeLibraryPath runtimeLibraries}" "$addon"
    done
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    export HOME="$TMPDIR"
    export PI_OFFLINE=1
    $out/bin/pi --version | grep -q "${sources.version}"
    $out/bin/pi --help | grep -q "pi - AI coding assistant"
    runHook postInstallCheck
  '';

  meta = {
    description = "Coding agent CLI with read, bash, edit and write tools and session management";
    homepage = "https://pi.dev";
    changelog = "https://github.com/earendil-works/pi/releases/tag/v${sources.version}";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "pi";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
