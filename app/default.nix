{ lib ? (import <nixpkgs> {}).lib, ... }:
let
  container = if lib ? container then lib.container else import ../core/container-lib.nix { inherit lib; };
in
{
  imports = [
    (import ./web/openlist.nix { inherit container lib; })
    ./web/nginx.nix
    ./web/x-ui-yg.nix
    (import ./web/vaultwarden.nix { inherit container lib; })
    ./proxy/hysteria.nix
  ];
}
