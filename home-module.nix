{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.pi;
in
{
  options.programs.pi = {
    enable = lib.mkEnableOption "pi - coding agent CLI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ./package.nix { }";
      description = "The pi package to use.";
    };

    enableBinSymlink = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = ''
        Whether to create a symlink at ~/.local/bin/pi.
        Enabled by default on Linux to ensure the binary is in a standard location.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.file.".local/bin/pi" = lib.mkIf cfg.enableBinSymlink {
      source = "${cfg.package}/bin/pi";
    };
  };
}
