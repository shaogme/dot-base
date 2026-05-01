{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.x-ui-yg;
in {
  options.base.app.web.x-ui-yg = {
    enable = mkEnableOption "X-UI-YG Panel";

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for X-UI-YG (enables Nginx integration)";
    };

    username = mkOption {
      type = types.str;
      default = "";
      description = "Initial username (leave empty for random generation on first run)";
    };

    password = mkOption {
      type = types.str;
      default = "";
      description = "Initial password (leave empty for random generation on first run)";
    };
    
    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = config.base.containerBackend;
      description = "Container backend to use";
    };

    # [新增] 防火墙端口范围配置
    proxyPorts = mkOption {
      description = "Port range to open in firewall for proxy services";
      default = { start = 10000; end = 10005; };
      type = types.submodule {
        options = {
          start = mkOption { 
            type = types.int; 
            default = 10000;
            description = "Start port";
          };
          end = mkOption { 
            type = types.int; 
            default = 10005; 
            description = "End port";
          };
        };
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # --- Always enabled logic (including Nginx sites) ---
    {
      # Ensure Nginx core is enabled if domain is set
      base.app.web.nginx.enable = mkIf (cfg.domain != null) true;

      # 使用新的 sites 抽象层
      base.app.web.nginx.sites = mkIf (cfg.domain != null) {
        "${cfg.domain}" = {
          http3 = true;
          quic = true;
          
          locations."/" = {
            proxyPass = "http://127.0.0.1:54321";
            proxyWebsockets = true;
            extraConfig = ''
              client_max_body_size 0;
            '';
          };
        };
      };
    }

    # --- Logic disabled in testMode ---
    (mkIf (!config.base.testMode) {
      # Ensure backend is enabled
      base.container.${cfg.backend}.enable = true;
      
      networking.firewall = {
        allowedTCPPorts = mkIf (cfg.domain == null) [ 54321 ];
        # [修改] 使用配置的端口范围
        allowedTCPPortRanges = [
          { from = cfg.proxyPorts.start; to = cfg.proxyPorts.end; }
        ];
        allowedUDPPortRanges = [
          { from = cfg.proxyPorts.start; to = cfg.proxyPorts.end; }
        ];
      };

      systemd.tmpfiles.rules = [
        "d /var/lib/x-ui-yg 0755 root root -"
        "d /var/lib/x-ui-yg/cert 0755 root root -"
      ];

      virtualisation.oci-containers = {
        backend = cfg.backend;
        containers.x-ui-yg = {
          image = "ghcr.io/shaogme/x-ui-yg-docker:alpine";
          # 使用 host 网络模式
          extraOptions = [
            "--network=host"
            "--tty"
            "--memory=512m"
          ];
          volumes = [
            "/var/lib/x-ui-yg:/usr/local/x-ui"
            "/var/lib/x-ui-yg/cert:/root/cert"
          ];
          environment = {
            TZ = "Asia/Shanghai";
            XUI_USER = cfg.username;
            XUI_PASS = cfg.password;
            XUI_PORT = "54321";
          };
          autoStart = true;
        };
      };
    })
  ]);
}