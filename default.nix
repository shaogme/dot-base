{ pkgs }:
let
  lib = pkgs.lib.extend (self: super: {
    container = import ./core/container-lib.nix { lib = self; };
  });
in
{
  inherit lib;
  nixosModules = {
    default = { ... }: {
      _module.args.lib = lib;
      imports = [
        (import ./app/default.nix { inherit lib; })
        ./core/default.nix
        ./hardware/default.nix
      ];
    };
    kernel-xanmod = ./kernel/xanmod.nix;
  };
}
