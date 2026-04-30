{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.vaultwarden;
in {
  options.base.app.web.vaultwarden = {
    enable = mkEnableOption "Vaultwarden Password Manager";
    
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for Vaultwarden (enables Nginx integration)";
    };

    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "podman";
      description = "Container backend to use";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Internal port to map Vaultwarden's port 80 to";
    };
  };

  config = mkIf cfg.enable {
    # Ensure backend is enabled
    base.container.${cfg.backend}.enable = true;
    
    # Ensure Nginx core is enabled if domain is set
    base.app.web.nginx.enable = mkIf (cfg.domain != null) true;

    # 如果没有配置域名，则开放端口直接访问
    networking.firewall.allowedTCPPorts = mkIf (cfg.domain == null) [ cfg.port ];

    systemd.tmpfiles.rules = [
      "d /var/lib/vaultwarden 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;
      containers.vaultwarden = {
        image = "vaultwarden/server:latest";
        ports = if (cfg.domain != null) 
                then [ "127.0.0.1:${toString cfg.port}:80" ]
                else [ "${toString cfg.port}:80" ];
        volumes = [
          "/var/lib/vaultwarden:/data"
        ];
        environment = mkIf (cfg.domain != null) {
          DOMAIN = "https://${cfg.domain}";
        };
        autoStart = true;
      };
    };

    # Nginx 反向代理
    base.app.web.nginx.sites = mkIf (cfg.domain != null) {
      "${cfg.domain}" = {
        # 启用 HTTP3 和 QUIC
        http3 = true;
        quic = true;
        
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          extraConfig = ''
            client_max_body_size 128M;
          '';
        };
      };
    };
  };
}
