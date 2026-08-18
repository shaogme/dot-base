{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "x-ui-yg";
    description = "X-UI-YG Panel";
    optPath = [ "base" "app" "proxy" "x-ui-yg" ];
    image = "ghcr.io/shaogme/x-ui-yg-docker:alpine";
    networkMode = "host";
    ports = [
      54321
      { start = 10000; end = 10100; }
    ];
    extraOptions = {
      username = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Initial username (leave empty for random generation on first run)";
      };
      password = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Initial password (leave empty for random generation on first run)";
      };
    };
    dataDirs = [
      "/var/lib/x-ui-yg"
      "/var/lib/x-ui-yg/cert"
    ];
    volumes = [
      "/var/lib/x-ui-yg:/usr/local/x-ui"
      "/var/lib/x-ui-yg/cert:/root/cert"
    ];
    containerExtraOptions = [
      "--tty"
      "--memory=512m"
    ];
    environment = cfg: {
      TZ = "Asia/Shanghai";
      XUI_USER = cfg.username;
      XUI_PASS = cfg.password;
      XUI_PORT = "54321";
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