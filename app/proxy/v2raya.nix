{ config, pkgs, lib, ... }:
let
  appModule = lib.container.mkContainerApp {
    name = "v2raya";
    description = "v2rayA Proxy Panel";
    optPath = [ "base" "app" "proxy" "v2raya" ];
    image = "docker.io/mzz2017/v2raya:latest";
    defaultNetworkMode = "host";
    proxy = {
      defaultMode = "disable";
    };
    ports = {
      panel = {
        port = 2017;
        containerPort = 2017;
        protocol = "tcp";
        firewall.open = true;
      };
    };
    dataDirs = [
      "/var/lib/v2raya"
    ];
    volumes = [
      "/var/lib/v2raya:/etc/v2raya"
      "/etc/resolv.conf:/etc/resolv.conf"
    ];
    containerExtraOptions = [
      "--privileged"
      "--memory=512m"
    ];
    environment = {
      TZ = "Asia/Shanghai";
      V2RAYA_LOG_FILE = "/tmp/v2raya.log";
    };
    nginx = {
      portName = "panel";
      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 0;
      '';
    };
  };
in
appModule { inherit config pkgs lib; }
