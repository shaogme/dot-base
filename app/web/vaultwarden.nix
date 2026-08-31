{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "vaultwarden";
    description = "Vaultwarden Password Manager";
    optPath = [ "base" "app" "web" "vaultwarden" ];
    image = "docker.io/vaultwarden/server:latest";
    defaultNetworkMode = "bridge";
    ports = {
      web = {
        port = 8000;
        containerPort = 80;
      };
    };
    volumes = [
      "/var/lib/vaultwarden:/data"
    ];
    environment = cfg: lib.optionalAttrs cfg.nginx.enable {
      DOMAIN = "https://${cfg.nginx.domain}";
    };
    nginx = {
      portName = "web";
      extraConfig = ''
        client_max_body_size 128M;
      '';
    };
  };
in
appModule { inherit config pkgs lib; }
