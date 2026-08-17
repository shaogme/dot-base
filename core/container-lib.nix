{ lib ? (import <nixpkgs> {}).lib }:
with lib;
rec {
  # 统一的空代理环境变量集合，供 host 网络或明确无需代理的容器使用
  emptyProxyEnv = {
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
  };

  # 容器代理配置项生成器
  mkProxyOptions = { description ? "container", ... }: {
    enable = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Proxy behavior for ${description} container: true to explicitly enable, false to explicitly disable/cancel inheritance, null to inherit default.";
    };
    default = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:2080";
      description = "Default proxy URL for ${description} container.";
    };
    httpProxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:2080";
      description = "HTTP proxy URL for ${description} container.";
    };
    httpsProxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "http://127.0.0.1:2080";
      description = "HTTPS proxy URL for ${description} container.";
    };
    allProxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "socks5://127.0.0.1:2080";
      description = "ALL_PROXY URL for ${description} container.";
    };
    noProxy = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "NO_PROXY list for ${description} container.";
    };
    autoReplaceLoopback = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically replace 127.0.0.1 and localhost in proxy URLs with hostDomain.";
    };
    hostDomain = mkOption {
      type = types.str;
      default = "host.docker.internal";
      description = "Host gateway domain name for ${description} container.";
    };
  };

  # 容器代理环境变量解析函数
  mkProxyEnv = { proxyCfg, baseProxy }:
    if proxyCfg.enable == false then
      emptyProxyEnv
    else if proxyCfg.enable == true || proxyCfg.default != null || proxyCfg.httpProxy != null || proxyCfg.httpsProxy != null || proxyCfg.allProxy != null then
      let
        replaceLoopback = url:
          if url == null then null
          else if proxyCfg.autoReplaceLoopback then
            builtins.replaceStrings
              [ "127.0.0.1" "localhost" ]
              [ proxyCfg.hostDomain proxyCfg.hostDomain ]
              url
          else
            url;

        httpP = replaceLoopback (
          if proxyCfg.httpProxy != null then proxyCfg.httpProxy
          else if proxyCfg.default != null then proxyCfg.default
          else baseProxy.httpProxy
        );
        httpsP = replaceLoopback (
          if proxyCfg.httpsProxy != null then proxyCfg.httpsProxy
          else if proxyCfg.default != null then proxyCfg.default
          else baseProxy.httpsProxy
        );
        allP = replaceLoopback (
          if proxyCfg.allProxy != null then proxyCfg.allProxy
          else if proxyCfg.default != null then proxyCfg.default
          else baseProxy.allProxy
        );
        noP =
          if proxyCfg.noProxy != null then proxyCfg.noProxy
          else if proxyCfg.enable == true then "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12"
          else baseProxy.noProxy;
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

  # 通用 Backend Option 生成器
  mkBackendOption = { default ? "podman", description ? "Container backend to use" }:
    mkOption {
      type = types.enum [ "docker" "podman" ];
      inherit default description;
    };

  # 标准 Web 容器应用模块生成器
  mkContainerApp = {
    name,
    description ? name,
    optPath,
    image,
    internalPort,
    defaultHostPort ? internalPort,
    dataDirs ? [ "/var/lib/${name}" ],
    volumes ? [ "/var/lib/${name}:/data" ],
    extraOptions ? {},
    extraContainerConfig ? (cfg: {}),
    nginxExtraConfig ? "",
    proxyWebsockets ? false,
  }:
  { config, pkgs, lib, ... }:
  let
    cfg = getAttrFromPath optPath config;
    proxyEnv = mkProxyEnv { proxyCfg = cfg.proxy; baseProxy = config.base.proxy; };
    hostPort = if cfg ? port then cfg.port else defaultHostPort;
  in {
    options = setAttrByPath optPath ({
      enable = mkEnableOption description;

      domain = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Domain name for ${description} (enables Nginx integration)";
      };

      backend = mkOption {
        type = types.enum [ "docker" "podman" ];
        default = config.base.containerBackend;
        description = "Container backend to use";
      };

      proxy = mkProxyOptions { inherit description; };
    } // extraOptions);

    config = mkIf cfg.enable (mkMerge [
      # --- Always enabled logic (including Nginx sites) ---
      {
        base.app.web.nginx.enable = mkIf (cfg.domain != null) true;

        base.app.web.nginx.sites = mkIf (cfg.domain != null) {
          "${cfg.domain}" = {
            http3 = true;
            quic = true;

            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString hostPort}";
              inherit proxyWebsockets;
              extraConfig = nginxExtraConfig;
            };
          };
        };
      }

      # --- Logic disabled in testMode ---
      (mkIf (!config.base.testMode) {
        base.container.${cfg.backend}.enable = true;

        networking.firewall.allowedTCPPorts = mkIf (cfg.domain == null) [ hostPort ];

        systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 root root -") dataDirs;

        virtualisation.oci-containers = {
          backend = cfg.backend;
          containers.${name} = mkMerge [
            {
              inherit image volumes;
              ports = if (cfg.domain != null)
                      then [ "127.0.0.1:${toString hostPort}:${toString internalPort}" ]
                      else [ "${toString hostPort}:${toString internalPort}" ];
              environment = proxyEnv;
              autoStart = true;
            }
            (if isFunction extraContainerConfig then extraContainerConfig cfg else extraContainerConfig)
          ];
        };
      })
    ]);
  };
}
