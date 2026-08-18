{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "vaultwarden";
    description = "Vaultwarden Password Manager";
    optPath = [ "base" "app" "web" "vaultwarden" ];
    image = "docker.io/vaultwarden/server:latest";
    ports = {
      port = 8000;
      internalPort = 80;
    };
    volumes = [
      "/var/lib/vaultwarden:/data"
    ];
    environment = cfg: lib.optionalAttrs cfg.nginx.enable {
      DOMAIN = "https://${cfg.nginx.domain}";
    };
    nginx = {
      extraConfig = ''
        client_max_body_size 128M;
      '';
    };
  };
in
appModule { inherit config pkgs lib; }
