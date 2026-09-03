# pi Nix Flake

A Nix flake that packages [pi](https://pi.dev), the coding agent CLI from the
[earendil-works](https://github.com/earendil-works/pi) AI agent toolkit.

## Features

- Pre-built binaries from official GitHub releases - no Bun compile
- Multi-platform: Linux (x86_64, aarch64) and macOS (x86_64, aarch64)
- Automatic hourly updates via GitHub Actions
- Stable releases only, no prereleases
- Home Manager module

## Why not npm?

The usual way to get pi is `npm i -g @earendil-works/pi-coding-agent`, which
puts a mutable install outside the store and self-updates behind your back.
This flake wraps the official release tarball instead - the same binary the
installer script ships - so pi is pinned in `sources.json` and updated by a
commit like everything else.

## How it's packaged

pi ships a directory, not a single file. The Bun binary resolves `theme/`,
`docs/`, `export-html/`, `native/` and `node_modules/` relative to itself, so
the whole release tree lands in `$out/libexec/pi` and `$out/bin/pi` is a
relative symlink into it. That keeps the lookup working.

On Linux only the ELF interpreter of the launcher is rewritten. Nothing else
may be touched: growing the dynamic section of a Bun single-file executable
(`--add-needed`, `--set-rpath`, hence also `autoPatchelfHook`) shifts the
payload appended to the binary and makes the aarch64 build SIGSEGV before main.
The launcher needs nothing beyond glibc anyway. The napi addons next to it
(`clipboard`, and `darwin-modifiers` on macOS) are ordinary shared objects, so
those do get a normal rpath for `libgcc_s`.

The aarch64 binary is linked with 64 KiB segment alignment, so patchelf runs
with an explicit `--page-size`.

## Usage

### Run directly

```bash
nix run github:nklmilojevic/pi-flake -- --version
```

### Install with nix profile

```bash
nix profile install github:nklmilojevic/pi-flake
```

### Use the overlay

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    pi.url = "github:nklmilojevic/pi-flake";
  };

  outputs = { nixpkgs, pi, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ({ pkgs, ... }: {
          nixpkgs.overlays = [ pi.overlays.default ];
          environment.systemPackages = [ pkgs.pi ];
        })
      ];
    };
  };
}
```

### Home Manager module

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    pi.url = "github:nklmilojevic/pi-flake";
  };

  outputs = { nixpkgs, home-manager, pi, ... }: {
    homeConfigurations.myuser = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      modules = [
        pi.homeManagerModules.default
        {
          programs.pi.enable = true;
        }
      ];
    };
  };
}
```

## Version Updates

Updated hourly via GitHub Actions. The workflow:

1. Checks GitHub releases for new stable versions
2. Downloads binaries for all platforms
3. Computes SHA256 hashes
4. Updates `sources.json` and commits

Current version is tracked in [sources.json](./sources.json).

`pi update --self` won't work here, the store is read only. Bump `sources.json`
instead, or just let the workflow do it.

## Manual Update

1. Actions > "Update pi version" > "Run workflow"
2. Or run locally: `bash update.sh`

## Development

```bash
cd dev && nix develop
```

## License

The Nix code in this repository is provided under the MIT license.
pi itself is licensed under the [MIT license](https://github.com/earendil-works/pi/blob/main/LICENSE).
