{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "openlist";
    description = "OpenList File Listing";
    optPath = [ "base" "app" "web" "openlist" ];
    image = "docker.io/openlistteam/openlist:latest";
    internalPort = 5244;
    volumes = [
      "/var/lib/openlist:/opt/openlist/data"
    ];
    nginxExtraConfig = ''
      client_max_body_size 0;
    '';
    extraContainerConfig = cfg: {
      user = "0:0";
      environment = {
        UMASK = "022";
      };
    };
  };
in
appModule { inherit config pkgs lib; }
