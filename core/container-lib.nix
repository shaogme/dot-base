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
      example = "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
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
  mkBackendOption = { description ? "Container backend to use" }:
    mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "podman";
      inherit description;
    };

  # 通用端口范围 Option 生成器
  mkPortRangeOption = {
    defaultStart ? 10000,
    defaultEnd ? 10100,
    description ? "Port range to open in firewall for proxy services",
  }:
    mkOption {
      inherit description;
      default = { start = defaultStart; end = defaultEnd; };
      type = types.submodule {
        options = {
          start = mkOption {
            type = types.int;
            default = defaultStart;
            description = "Start port";
          };
          end = mkOption {
            type = types.int;
            default = defaultEnd;
            description = "End port";
          };
        };
      };
    };

  # 通用容器应用模块生成器
  mkContainerApp = {
    name,
    description ? name,
    optPath,
    image,
    port ? null,
    internalPort ? port,
    networkMode ? "bridge", # "bridge" | "host"
    includePortRange ? false,
    defaultPortRange ? { start = 10000; end = 10100; },
    includeProxy ? (networkMode == "bridge"),
    dataDirs ? [ "/var/lib/${name}" ],
    volumes ? [ "/var/lib/${name}:/data" ],
    environment ? {},
    containerExtraOptions ? [],
    extraOptions ? {},
    extraContainerConfig ? (cfg: {}),
    nginx ? {},
  }:
  { config, pkgs, lib, ... }:
  let
    cfg = getAttrFromPath optPath config;

    effectiveHostPort = if cfg ? port then cfg.port else port;
    effectiveInternalPort = if internalPort != null then internalPort else effectiveHostPort;

    # 解析可执行函数或静态配置
    resolveVal = val: if isFunction val then val cfg else val;

    resolvedDataDirs = resolveVal dataDirs;
    resolvedVolumes = resolveVal volumes;
    resolvedEnv = resolveVal environment;
    resolvedContainerExtraOptions = resolveVal containerExtraOptions;
    resolvedExtraContainerConfig = resolveVal extraContainerConfig;
    resolvedNginxExtraConfig = resolveVal cfg.nginx.extraConfig;

    # 计算容器环境变量
    proxyEnv =
      if includeProxy && (cfg ? proxy) then
        mkProxyEnv { proxyCfg = cfg.proxy; baseProxy = config.base.proxy; }
      else if networkMode == "host" then
        emptyProxyEnv
      else
        {};

    combinedEnv = resolvedEnv // proxyEnv;

    # 网络与端口相关配置
    isHostNetwork = networkMode == "host";
    containerExtraOpts = (optional isHostNetwork "--network=host") ++ resolvedContainerExtraOptions;

    containerPorts =
      if isHostNetwork then
        []
      else if effectiveHostPort != null && effectiveInternalPort != null then
        if cfg.nginx.enable
        then [ "127.0.0.1:${toString effectiveHostPort}:${toString effectiveInternalPort}" ]
        else [ "${toString effectiveHostPort}:${toString effectiveInternalPort}" ]
      else
        [];
  in {
    options = setAttrByPath optPath ({
      enable = mkEnableOption description;

      nginx = {
        enable = mkEnableOption "Nginx reverse proxy for ${description}";

        domain = mkOption {
          type = types.str;
          description = "Domain name for ${description}";
        };

        proxyWebsockets = mkOption {
          type = types.bool;
          default = if nginx ? proxyWebsockets then nginx.proxyWebsockets else true;
          description = "Enable websocket proxying in Nginx for ${description}";
        };

        extraConfig = mkOption {
          type = types.lines;
          default = if nginx ? extraConfig then nginx.extraConfig else "";
          description = "Extra Nginx configuration for ${description}";
        };
      };

      backend = mkOption {
        type = types.enum [ "docker" "podman" ];
        default = config.base.containerBackend;
        description = "Container backend to use";
      };

      image = mkOption {
        type = types.str;
        default = image;
        description = "${description} container image";
      };
    }
    // (optionalAttrs (port != null) {
      port = mkOption {
        type = types.port;
        default = port;
        description = "Port for ${description}";
      };
    })
    // (optionalAttrs includeProxy {
      proxy = mkProxyOptions { inherit description; };
    })
    // (optionalAttrs includePortRange {
      proxyPorts = mkPortRangeOption {
        defaultStart = defaultPortRange.start;
        defaultEnd = defaultPortRange.end;
      };
    })
    // extraOptions);

    config = mkIf cfg.enable (mkMerge [
      # --- Always enabled logic (including Nginx sites) ---
      {
        base.app.web.nginx.enable = mkIf cfg.nginx.enable true;

        base.app.web.nginx.sites = mkIf (cfg.nginx.enable && effectiveHostPort != null) {
          "${cfg.nginx.domain}" = {
            http3 = true;
            quic = true;

            locations."/" = {
              proxyPass = "http://127.0.0.1:${toString effectiveHostPort}";
              proxyWebsockets = cfg.nginx.proxyWebsockets;
              extraConfig = resolvedNginxExtraConfig;
            };
          };
        };
      }

      # --- Logic disabled in testMode ---
      (mkIf (!config.base.testMode) {
        base.container.${cfg.backend}.enable = true;

        networking.firewall = mkMerge [
          (mkIf (effectiveHostPort != null && !cfg.nginx.enable) {
            allowedTCPPorts = [ effectiveHostPort ];
          })
          (mkIf (cfg ? proxyPorts) {
            allowedTCPPortRanges = [
              { from = cfg.proxyPorts.start; to = cfg.proxyPorts.end; }
            ];
            allowedUDPPortRanges = [
              { from = cfg.proxyPorts.start; to = cfg.proxyPorts.end; }
            ];
          })
        ];

        systemd.tmpfiles.rules = map (dir: "d ${dir} 0755 root root -") resolvedDataDirs;

        virtualisation.oci-containers = {
          backend = cfg.backend;
          containers.${name} = mkMerge [
            {
              image = cfg.image;
              volumes = resolvedVolumes;
              ports = containerPorts;
              extraOptions = containerExtraOpts;
              environment = combinedEnv;
              autoStart = true;
            }
            resolvedExtraContainerConfig
          ];
        };
      })
    ]);
  };
}
