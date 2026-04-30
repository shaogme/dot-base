{ pkgs }:
{
  nixosModules = {
    default = { ... }: {
      imports = [
        ./app/default.nix
        ./core/default.nix
        ./hardware/default.nix
      ];
    };
    kernel-xanmod = ./kernel/xanmod.nix;
  };
}
