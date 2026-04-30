{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.alist;
in {
  options.base.app.web.alist = {
    enable = mkEnableOption "Alist File Listing";
    
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for Alist (enables Nginx integration)";
    };

    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "podman";
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
      "d /var/lib/alist 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;
      containers.alist = {
        image = "xhofe/alist:beta";
        ports = [ "5244:5244" ];
        volumes = [
          "/var/lib/alist:/opt/alist/data"
        ];
        environment = {
          PUID = "0";
          PGID = "0";
          UMASK = "022";
        };
        autoStart = true;
      };
    };

    # 使用新的 sites 抽象层
    # 这里不需要指定 SSL 证书路径或 enableACME，nginx.nix 会自动处理
    # 也不需要再手动允许 UDP 443 端口，nginx.nix 会自动处理
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