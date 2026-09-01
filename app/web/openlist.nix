{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "openlist";
    description = "OpenList File Listing";
    optPath = [ "base" "app" "web" "openlist" ];
    image = "docker.io/openlistteam/openlist:latest";
    defaultNetworkMode = "bridge";
    ports = {
      web = {
        port = 5244;
        containerPort = 5244;
      };
    };
    volumes = [
      "/var/lib/openlist:/opt/openlist/data"
    ];
    environment = {
      UMASK = "022";
    };
    extraContainerConfig = {
      user = "0:0";
    };
    nginx = {
      portName = "web";
      extraConfig = ''
        client_max_body_size 0;
      '';
    };
  };
in
appModule { inherit config pkgs lib; }
