{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.openlist;
in {
  options.base.app.web.openlist = {
    enable = mkEnableOption "OpenList File Listing";
    
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for OpenList (enables Nginx integration)";
    };

    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = config.base.containerBackend;
      description = "Container backend to use";
    };
  };

  config = mkIf cfg.enable {
    # Ensure backend is enabled
    base.container.${cfg.backend}.enable = true;
    
    # Ensure Nginx core is enabled if domain is set
    base.app.web.nginx.enable = mkIf (cfg.domain != null) true;

    # 如果没有配置域名，则开放端口直接访问
    networking.firewall.allowedTCPPorts = mkIf (cfg.domain == null) [ 5244 ];

    systemd.tmpfiles.rules = [
      "d /var/lib/openlist 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;
      containers.openlist = {
        image = "openlistteam/openlist:latest";
        ports = [ "5244:5244" ];
        volumes = [
          "/var/lib/openlist:/opt/openlist/data"
        ];
        user = "0:0";
        environment = {
          UMASK = "022";
        };
        autoStart = true;
      };
    };

    # 使用新的 sites 抽象层
    base.app.web.nginx.sites = mkIf (cfg.domain != null) {
      "${cfg.domain}" = {
        # 启用 HTTP3 和 QUIC
        http3 = true;
        quic = true;
        
        locations."/" = {
          proxyPass = "http://127.0.0.1:5244";
          extraConfig = ''
            client_max_body_size 0;
          '';
        };
      };
    };
  };
}
