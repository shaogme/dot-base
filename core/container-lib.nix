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

  # 解析端口字符串形式，例如 "8080", "8080:80", "8080:80/tcp", "10000-10100", "10000-10100:10000-10100/udp"
  parsePortString = str:
    let
      protoParts = splitString "/" str;
      mappingPart = head protoParts;
      proto = if length protoParts > 1 then elemAt protoParts 1 else "both";
      colonParts = splitString ":" mappingPart;
      hostPart = head colonParts;
      containerPart = if length colonParts > 1 then elemAt colonParts 1 else null;
      hostDash = splitString "-" hostPart;
      isHostRange = length hostDash == 2;
      containerDash = if containerPart != null then splitString "-" containerPart else [];
      isContainerRange = length containerDash == 2;
    in
      if isHostRange then {
        from = toInt (head hostDash);
        to = toInt (elemAt hostDash 1);
        internalFrom = if isContainerRange then toInt (head containerDash) else null;
        internalTo = if isContainerRange then toInt (elemAt containerDash 1) else null;
        protocol = proto;
      } else {
        port = toInt hostPart;
        internalPort = if containerPart != null then toInt containerPart else null;
        protocol = proto;
      };

  # 端口项子模块定义
  portItemSubmodule = types.submodule {
    options = {
      port = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port number (alias: hostPort)";
      };
      hostPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host port number";
      };
      internalPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container internal port number (alias: containerPort)";
      };
      containerPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container internal port number";
      };
      from = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host start port for range (alias: start, hostFrom, hostStart)";
      };
      to = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host end port for range (alias: end, hostTo, hostEnd)";
      };
      start = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host start port for range";
      };
      end = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Host end port for range";
      };
      internalFrom = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container start port for range (alias: internalStart, containerFrom, containerStart)";
      };
      internalTo = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container end port for range (alias: internalEnd, containerTo, containerEnd)";
      };
      internalStart = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container start port for range";
      };
      internalEnd = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Container end port for range";
      };
      range = mkOption {
        type = types.nullOr (types.either (types.attrsOf types.port) types.str);
        default = null;
        description = "Port range specification";
      };
      protocol = mkOption {
        type = types.either (types.enum [ "both" "tcp" "udp" "tcp+udp" "all" ]) (types.listOf (types.enum [ "tcp" "udp" ]));
        default = "both";
        description = "Protocol to open: 'both', 'tcp', 'udp' or list of protocols (default: 'both')";
      };
    };
  };

  # 端口项类型，支持数字 (如 8080)、字符串 (如 \"8080:80/tcp\")、属性集 (如 { port = 8000; internalPort = 80; }) 自动转换
  portItemType = types.coercedTo
    (types.either types.port (types.either types.str (types.attrsOf types.anything)))
    (val:
      if isInt val then { port = val; }
      else if isString val then parsePortString val
      else val
    )
    portItemSubmodule;

  # 支持单个对象或数组的 ports 类型
  portsOptionType = types.coercedTo
    (types.either portItemType (types.listOf portItemType))
    (val: if isList val then val else [ val ])
    (types.listOf portItemType);

  # 规范化单条端口配置
  normalizePortItem = raw:
    let
      item =
        if isInt raw then { port = raw; protocol = "both"; }
        else if isString raw then parsePortString raw
        else raw;

      rangeObj = item.range or null;
      rStart = if rangeObj != null && isAttrs rangeObj then (rangeObj.from or rangeObj.start or null) else null;
      rEnd = if rangeObj != null && isAttrs rangeObj then (rangeObj.to or rangeObj.end or null) else null;

      hFrom = if item.from or null != null then item.from else if item.start or null != null then item.start else if item.hostFrom or null != null then item.hostFrom else if item.hostStart or null != null then item.hostStart else rStart;
      hTo = if item.to or null != null then item.to else if item.end or null != null then item.end else if item.hostTo or null != null then item.hostTo else if item.hostEnd or null != null then item.hostEnd else rEnd;

      cFrom = if item.internalFrom or null != null then item.internalFrom else if item.internalStart or null != null then item.internalStart else if item.containerFrom or null != null then item.containerFrom else if item.containerStart or null != null then item.containerStart else hFrom;
      cTo = if item.internalTo or null != null then item.internalTo else if item.internalEnd or null != null then item.internalEnd else if item.containerTo or null != null then item.containerTo else if item.containerEnd or null != null then item.containerEnd else hTo;

      hPort = if item.port or null != null then item.port else if item.hostPort or null != null then item.hostPort else null;
      cPort = if item.internalPort or null != null then item.internalPort else if item.containerPort or null != null then item.containerPort else hPort;

      p = item.protocol or "both";
      hasTCP = if isList p then elem "tcp" p else elem p [ "both" "tcp" "tcp+udp" "all" ];
      hasUDP = if isList p then elem "udp" p else elem p [ "both" "udp" "tcp+udp" "all" ];
    in
      if hFrom != null && hTo != null then {
        kind = "range";
        from = hFrom;
        to = hTo;
        internalFrom = cFrom;
        internalTo = cTo;
        inherit hasTCP hasUDP;
      } else if hPort != null then {
        kind = "port";
        port = hPort;
        internalPort = cPort;
        inherit hasTCP hasUDP;
      } else
        throw "Invalid port configuration in ports option";

  # 通用容器应用模块生成器
  mkContainerApp = {
    name,
    description ? name,
    optPath,
    image,
    ports ? [],
    networkMode ? "bridge", # "bridge" | "host"
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

    defaultPortsList = if isList ports then ports else (if ports != null then [ ports ] else []);

    # 规范化端口列表
    normalizedPorts = map normalizePortItem cfg.ports;
    portItems = filter (x: x.kind == "port") normalizedPorts;
    effectiveHostPort = if portItems != [] then (head portItems).port else null;

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
      else
        concatMap (item:
          if item.kind == "port" then
            if cfg.nginx.enable && item.port == effectiveHostPort then
              [ "127.0.0.1:${toString item.port}:${toString item.internalPort}" ]
            else if item.hasTCP && item.hasUDP then
              [ "${toString item.port}:${toString item.internalPort}" ]
            else if item.hasTCP then
              [ "${toString item.port}:${toString item.internalPort}/tcp" ]
            else
              [ "${toString item.port}:${toString item.internalPort}/udp" ]
          else
            if item.hasTCP && item.hasUDP then
              [ "${toString item.from}-${toString item.to}:${toString item.internalFrom}-${toString item.internalTo}" ]
            else if item.hasTCP then
              [ "${toString item.from}-${toString item.to}:${toString item.internalFrom}-${toString item.internalTo}/tcp" ]
            else
              [ "${toString item.from}-${toString item.to}:${toString item.internalFrom}-${toString item.internalTo}/udp" ]
        ) normalizedPorts;

    firewallItems = filter (item:
      !(cfg.nginx.enable && item.kind == "port" && item.port == effectiveHostPort)
    ) normalizedPorts;
  in {
    options = setAttrByPath optPath ({
      enable = mkEnableOption description;

      ports = mkOption {
        type = portsOptionType;
        default = defaultPortsList;
        description = "Port mappings and firewall configurations for ${description}. Supports single port/object or array.";
      };

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
    // (optionalAttrs includeProxy {
      proxy = mkProxyOptions { inherit description; };
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

        networking.firewall = {
          allowedTCPPorts = map (x: x.port) (filter (x: x.kind == "port" && x.hasTCP) firewallItems);
          allowedUDPPorts = map (x: x.port) (filter (x: x.kind == "port" && x.hasUDP) firewallItems);
          allowedTCPPortRanges = map (x: { inherit (x) from to; }) (filter (x: x.kind == "range" && x.hasTCP) firewallItems);
          allowedUDPPortRanges = map (x: { inherit (x) from to; }) (filter (x: x.kind == "range" && x.hasUDP) firewallItems);
        };

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
