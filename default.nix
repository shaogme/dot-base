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
    default = { pkgs ? null, lib, ... } @ moduleArgs:
      let
        extLib = lib.extend (self: super: {
          container = import ./core/container-lib.nix { lib = self; };
        });
        argsWithLib = moduleArgs // { lib = extLib; };
      in
      {
        imports = [
          (import ./app/default.nix argsWithLib)
          (import ./core/default.nix argsWithLib)
          (import ./hardware/default.nix argsWithLib)
        ];
      };
    kernel-xanmod = ./kernel/xanmod.nix;
  };
}
