{ pkgs ? null, lib ? null, ... } @ args:
let
  resolvedLib =
    if lib != null then lib
    else if pkgs != null && pkgs ? lib then pkgs.lib
    else (import <nixpkgs> { }).lib;

  container = import ./core/container-lib.nix { lib = resolvedLib; };
  extendedLib = resolvedLib.extend (self: super: {
    inherit container;
  });
in
{
  lib = extendedLib;
  nixosModules = {
    default = { lib, ... }: {
      _module.args.lib = lib.extend (self: super: {
        container = import ./core/container-lib.nix { lib = self; };
      });
      imports = [
        ./app/default.nix
        ./core/default.nix
        ./hardware/default.nix
      ];
    };
    kernel-xanmod = ./kernel/xanmod.nix;
  };
}
