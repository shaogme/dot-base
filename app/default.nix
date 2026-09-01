{ config, pkgs, lib, ... } @ args:
{
  imports = [
    (import ./web/openlist.nix args)
    (import ./web/nginx.nix args)
    (import ./proxy/x-ui-yg.nix args)
    (import ./proxy/s-ui.nix args)
    (import ./proxy/v2raya.nix args)
    (import ./web/vaultwarden.nix args)
    (import ./proxy/hysteria.nix args)
  ];
}
