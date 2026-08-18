{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "s-ui";
    description = "S-UI (Sing-box UI) Panel";
    optPath = [ "base" "app" "proxy" "s-ui" ];
    image = "docker.io/alireza7/s-ui:latest";
    networkMode = "host";
    ports = [
      2095
      { start = 10100; end = 10200; }
    ];
    dataDirs = [
      "/var/lib/s-ui"
      "/var/lib/s-ui/db"
      "/var/lib/s-ui/cert"
    ];
    volumes = [
      "/var/lib/s-ui/db:/app/db"
      "/var/lib/s-ui/cert:/app/cert"
      "/var/lib/s-ui/cert:/root/cert"
    ];
    containerExtraOptions = [
      "--tty"
      "--memory=512m"
    ];
    environment = {
      TZ = "Asia/Shanghai";
    };
    nginx = {
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 0;
      '';
    };
  };
in
appModule { inherit config pkgs lib; }
