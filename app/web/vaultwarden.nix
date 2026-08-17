{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.vaultwarden;

  replaceLoopback = url:
    if url == null then null
    else if cfg.proxy.autoReplaceLoopback then
      builtins.replaceStrings
        [ "127.0.0.1" "localhost" ]
        [ cfg.proxy.hostDomain cfg.proxy.hostDomain ]
        url
    else
      url;

  proxyEnv =
    if cfg.proxy.enable == false then {
      # 显式取消并覆盖任何继承的代理环境变量
      http_proxy = "";
      https_proxy = "";
      ftp_proxy = "";
      all_proxy = "";
      no_proxy = "";
      HTTP_PROXY = "";
      HTTPS_PROXY = "";
      FTP_PROXY = "";
      ALL_PROXY = "";
      NO_PROXY = "";
    } else if cfg.proxy.enable == true || cfg.proxy.default != null || cfg.proxy.httpProxy != null || cfg.proxy.httpsProxy != null || cfg.proxy.allProxy != null then
      let
        httpP = replaceLoopback (if cfg.proxy.httpProxy != null then cfg.proxy.httpProxy else config.base.proxy.httpProxy);
        httpsP = replaceLoopback (if cfg.proxy.httpsProxy != null then cfg.proxy.httpsProxy else config.base.proxy.httpsProxy);
        allP = replaceLoopback (if cfg.proxy.allProxy != null then cfg.proxy.allProxy else config.base.proxy.allProxy);
        noP = if cfg.proxy.noProxy != null then cfg.proxy.noProxy else config.base.proxy.noProxy;
      in filterAttrs (_: v: v != null) {
        http_proxy = httpP;
        HTTP_PROXY = httpP;
        https_proxy = httpsP;
        HTTPS_PROXY = httpsP;
        all_proxy = allP;
        ALL_PROXY = allP;
        no_proxy = noP;
        NO_PROXY = noP;
      }
    else {};
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
      default = config.base.containerBackend;
      description = "Container backend to use";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
      description = "Internal port to map Vaultwarden's port 80 to";
    };

    proxy = {
      enable = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "Proxy behavior for Vaultwarden container: true to explicitly enable, false to explicitly disable/cancel inheritance, null to inherit default.";
      };
      default = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "http://127.0.0.1:2080";
        description = "Default proxy URL for Vaultwarden container.";
      };
      httpProxy = mkOption {
        type = types.nullOr types.str;
        default = cfg.proxy.default;
        example = "http://127.0.0.1:2080";
        description = "HTTP proxy URL for Vaultwarden container.";
      };
      httpsProxy = mkOption {
        type = types.nullOr types.str;
        default = cfg.proxy.default;
        example = "http://127.0.0.1:2080";
        description = "HTTPS proxy URL for Vaultwarden container.";
      };
      allProxy = mkOption {
        type = types.nullOr types.str;
        default = cfg.proxy.default;
        example = "socks5://127.0.0.1:2080";
        description = "ALL_PROXY URL for Vaultwarden container.";
      };
      noProxy = mkOption {
        type = types.nullOr types.str;
        default = if cfg.proxy.enable == true then "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12" else null;
        description = "NO_PROXY list for Vaultwarden container.";
      };
      autoReplaceLoopback = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically replace 127.0.0.1 and localhost in proxy URLs with hostDomain.";
      };
      hostDomain = mkOption {
        type = types.str;
        default = "host.docker.internal";
        description = "Host gateway domain name for Vaultwarden container.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # --- Always enabled logic (including Nginx sites) ---
    {
      # Ensure Nginx core is enabled if domain is set
      base.app.web.nginx.enable = mkIf (cfg.domain != null) true;

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
    }

    # --- Logic disabled in testMode ---
    (mkIf (!config.base.testMode) {
      # Ensure backend is enabled
      base.container.${cfg.backend}.enable = true;
      
      # 如果没有配置域名，则开放端口直接访问
      networking.firewall.allowedTCPPorts = mkIf (cfg.domain == null) [ cfg.port ];

      systemd.tmpfiles.rules = [
        "d /var/lib/vaultwarden 0755 root root -"
      ];

      virtualisation.oci-containers = {
        backend = cfg.backend;
        containers.vaultwarden = {
          image = "docker.io/vaultwarden/server:latest";
          ports = if (cfg.domain != null) 
                  then [ "127.0.0.1:${toString cfg.port}:80" ]
                  else [ "${toString cfg.port}:80" ];
          volumes = [
            "/var/lib/vaultwarden:/data"
          ];
          environment = (optionalAttrs (cfg.domain != null) {
            DOMAIN = "https://${cfg.domain}";
          }) // proxyEnv;
          autoStart = true;
        };
      };
    })
  ]);
}
