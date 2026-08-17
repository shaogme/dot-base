{ config, pkgs, lib, ... }:
let
  container = if lib ? container then lib.container else import ../../core/container-lib.nix { inherit lib; };
  appModule = container.mkContainerApp {
    name = "vaultwarden";
    description = "Vaultwarden Password Manager";
    optPath = [ "base" "app" "web" "vaultwarden" ];
    image = "docker.io/vaultwarden/server:latest";
    internalPort = 80;
    defaultHostPort = 8000;
    extraOptions = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 8000;
        description = "Internal port to map Vaultwarden's port 80 to";
      };
    };
    volumes = [
      "/var/lib/vaultwarden:/data"
    ];
    nginxExtraConfig = ''
      client_max_body_size 128M;
    '';
    extraContainerConfig = cfg: {
      environment = lib.optionalAttrs (cfg.domain != null) {
        DOMAIN = "https://${cfg.domain}";
      };
    };
  };
in
appModule { inherit config pkgs lib; }
