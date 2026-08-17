{ ... }:
{
  imports = [
    ./web/openlist.nix
    ./web/nginx.nix
    ./proxy/x-ui-yg.nix
    ./web/vaultwarden.nix
    ./proxy/hysteria.nix
  ];
}
