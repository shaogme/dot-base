{ lib ? (import <nixpkgs> {}).lib }:
with lib;
let
  # 辅助函数：选取列表中第一个非 null 的值
  firstNonNull = findFirst (x: x != null) null;

  # 通用端口选项属性集构造器（供预定义端口和 extraPorts 子模块复用）
  mkPortOptionDefs = { name ? "container", def ? {} }:
    let
      resolvedDef = if isInt def then { port = def; } else if isAttrs def then def else {};
      mkPortOpt = default: desc: mkOption {
        type = types.nullOr types.port;
        inherit default;
        description = "${desc} for ${name}.";
      };
      mkAlias = target: mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Alias for ${target}.";
      };
      mkAliases = target: names: genAttrs names (_: mkAlias target);

      defaultPort = resolvedDef.port or resolvedDef.hostPort or null;
      defaultContainerPort = resolvedDef.containerPort or resolvedDef.internalPort or defaultPort;
      defaultStart = resolvedDef.start or resolvedDef.from or resolvedDef.hostStart or resolvedDef.hostFrom or null;
      defaultEnd = resolvedDef.end or resolvedDef.to or resolvedDef.hostEnd or resolvedDef.hostTo or null;
      defaultContainerStart = resolvedDef.containerStart or resolvedDef.internalStart or resolvedDef.containerFrom or resolvedDef.internalFrom or defaultStart;
      defaultContainerEnd = resolvedDef.containerEnd or resolvedDef.internalEnd or resolvedDef.containerTo or resolvedDef.internalTo or defaultEnd;
      defaultFirewallOpen =
        if resolvedDef ? firewall && isAttrs resolvedDef.firewall && resolvedDef.firewall ? open then
          resolvedDef.firewall.open
        else if resolvedDef ? firewall && isBool resolvedDef.firewall then
          resolvedDef.firewall
        else
          false;
    in
    {
      enable = mkOption {
        type = types.bool;
        default = resolvedDef.enable or true;
        description = "Enable or disable ${name} port mapping.";
      };
      port = mkPortOpt defaultPort "Host port number";
      containerPort = mkPortOpt defaultContainerPort "Container internal port number";
      start = mkPortOpt defaultStart "Host start port for range";
      end = mkPortOpt defaultEnd "Host end port for range";
      containerStart = mkPortOpt defaultContainerStart "Container start port for range";
      containerEnd = mkPortOpt defaultContainerEnd "Container end port for range";
      bindIp = mkOption {
        type = types.str;
        default = resolvedDef.bindIp or "";
        description = "Host IP address to bind port mapping (e.g. '127.0.0.1').";
      };
      protocol = mkOption {
        type = types.either (types.enum [ "both" "tcp" "udp" "tcp+udp" "all" ]) (types.listOf (types.enum [ "tcp" "udp" ]));
        default = resolvedDef.protocol or "both";
        description = "Protocol to open: 'both', 'tcp', 'udp' or list of protocols (default: 'both').";
      };
      firewall = {
        open = mkOption {
          type = types.bool;
          default = defaultFirewallOpen;
          description = "Whether to open firewall for ${name} port (default: false).";
        };
      };
    }
    // mkAliases "port" [ "hostPort" ]
    // mkAliases "containerPort" [ "internalPort" ]
    // mkAliases "start" [ "from" "hostStart" "hostFrom" ]
    // mkAliases "end" [ "to" "hostEnd" "hostTo" ]
    // mkAliases "containerStart" [ "internalStart" "containerFrom" "internalFrom" ]
    // mkAliases "containerEnd" [ "internalEnd" "containerTo" "internalTo" ];

  # 容器网络配置子模块构造器
  mkNetworkOptionDefs = { defaultMode ? "bridge" }: {
    mode = mkOption {
      type = types.enum [ "host" "bridge" "container" "custom" "none" ];
      default = defaultMode;
      description = "Container network mode ('host', 'bridge', 'container', 'custom', 'none').";
    };

    containerName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Target container name when network mode is 'container'.";
    };

    customNetwork = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Custom network name when network mode is 'custom'.";
    };

    networks = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional networks to connect the container to.";
    };

    autoAddHostGateway = mkOption {
      type = types.bool;
      default = true;
      description = "Automatically add '--add-host=host.docker.internal:host-gateway' in non-host mode.";
    };

    extraOptions = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Extra network-related OCI flags.";
    };
  };

  proxyLib = import ./proxy-lib.nix { inherit lib; };
in
rec {
  inherit (proxyLib) emptyProxyEnv mkProxyOptions resolveProxyEnv replaceLoopback;
  # 兼容性别名
  mkProxyEnv = resolveProxyEnv;

  # 通用 Backend Option 生成器
  mkBackendOption = { description ? "Container backend to use" }:
    mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "podman";
      inherit description;
    };

  # 预定义端口配置项 Option 构造器
  mkPredefinedPortOption = name: def:
    mkOption {
      type = types.nullOr (types.coercedTo types.port (p: { port = p; }) (types.submodule {
        options = mkPortOptionDefs { inherit name def; };
      }));
      default = {};
      description = "Port configuration for ${name}. Set to null or enable = false to disable.";
    };

  # 用户额外添加端口映射子模块定义
  extraPortSubmodule = types.nullOr (types.coercedTo types.port (p: { port = p; }) (types.submodule {
    options = mkPortOptionDefs { name = "port"; def = {}; };
  }));

  # 规范化单条端口配置
  normalizePortItem = item:
    let
      hPort = firstNonNull [ item.port item.hostPort ];
      cPort = firstNonNull [ item.containerPort item.internalPort hPort ];

      hStart = firstNonNull [ item.start item.from item.hostStart item.hostFrom ];
      hEnd = firstNonNull [ item.end item.to item.hostEnd item.hostTo ];

      cStart = firstNonNull [ item.containerStart item.internalStart item.containerFrom item.internalFrom hStart ];
      cEnd = firstNonNull [ item.containerEnd item.internalEnd item.containerTo item.internalTo hEnd ];

      p = item.protocol;
      hasTCP = if isList p then elem "tcp" p else elem p [ "both" "tcp" "tcp+udp" "all" ];
      hasUDP = if isList p then elem "udp" p else elem p [ "both" "udp" "tcp+udp" "all" ];
      firewallOpen =
        if item ? firewall && isAttrs item.firewall && item.firewall ? open then
          item.firewall.open
        else if item ? firewall && isBool item.firewall then
          item.firewall
        else
          false;
      bindIp = if item ? bindIp && item.bindIp != null then item.bindIp else "";
    in
      if hStart != null && hEnd != null then {
        kind = "range";
        start = hStart;
        end = hEnd;
        containerStart = if cStart != null then cStart else hStart;
        containerEnd = if cEnd != null then cEnd else hEnd;
        inherit hasTCP hasUDP bindIp;
        firewall = firewallOpen;
      } else if hPort != null then {
        kind = "port";
        port = hPort;
        containerPort = if cPort != null then cPort else hPort;
        inherit hasTCP hasUDP bindIp;
        firewall = firewallOpen;
      } else
        throw "Invalid port configuration in ports option";

  # 通用容器应用模块生成器
  mkContainerApp = {
    name,
    description ? name,
    optPath,
    image,
    defaultNetworkMode ? "bridge", # "bridge" | "host" | "container" | "custom" | "none"
    ports ? {},
    includeProxy ? true,
    proxy ? {},
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

    isHostNetwork = cfg.network.mode == "host";
    isContainerNetwork = cfg.network.mode == "container";
    isBridgeNetwork = cfg.network.mode == "bridge";
    isCustomNetwork = cfg.network.mode == "custom";

    declaredPorts = if isAttrs ports then ports else {};

    # 规范化端口列表
    enabledPorts = filterAttrs (_: p: p != null && p.enable) cfg.ports;
    enabledExtraPorts = filterAttrs (_: p: p != null && p.enable) cfg.extraPorts;

    allEnabledPortValues = (attrValues enabledPorts) ++ (attrValues enabledExtraPorts);
    normalizedPorts = map normalizePortItem allEnabledPortValues;

    # 确定用于 Nginx 反代的 effectiveHostPort
    # 由 cfg.nginx.port 显式指定，或通过 cfg.nginx.portName 引用已配置的命名端口
    effectiveHostPort =
      if cfg.nginx.port != null then
        cfg.nginx.port
      else if cfg.nginx.portName != null then
        let
          targetPort =
            if (enabledPorts ? ${cfg.nginx.portName}) && enabledPorts.${cfg.nginx.portName} != null then
              enabledPorts.${cfg.nginx.portName}
            else if (enabledExtraPorts ? ${cfg.nginx.portName}) && enabledExtraPorts.${cfg.nginx.portName} != null then
              enabledExtraPorts.${cfg.nginx.portName}
            else
              null;
        in
          if targetPort != null then
            (if targetPort.port != null then targetPort.port else targetPort.hostPort)
          else
            null
      else
        null;

    # 解析可执行函数或静态配置
    resolveVal = val: if isFunction val then val cfg else val;

    resolvedDataDirs = resolveVal dataDirs;
    resolvedVolumes = resolveVal volumes;
    resolvedEnv = resolveVal environment;
    resolvedContainerExtraOptions = resolveVal containerExtraOptions;
    resolvedExtraContainerConfig = resolveVal extraContainerConfig;
    resolvedNginxExtraConfig = resolveVal cfg.nginx.extraConfig;

    # 计算自适应代理环境变量
    effectiveAutoReplaceLoopback =
      if (cfg ? proxy) && cfg.proxy.autoReplaceLoopback != null then
        cfg.proxy.autoReplaceLoopback
      else
        !isHostNetwork;

    proxyEnv =
      if includeProxy && (cfg ? proxy) then
        mkProxyEnv {
          proxyCfg = cfg.proxy // { autoReplaceLoopback = effectiveAutoReplaceLoopback; };
          baseProxy = config.base.proxy;
        }
      else
        {};

    combinedEnv = resolvedEnv // proxyEnv;

    # 网络与端口相关配置
    networkOpts =
      (optional isHostNetwork "--network=host")
      ++ (optional isBridgeNetwork "--network=bridge")
      ++ (optional isCustomNetwork "--network=${cfg.network.customNetwork}")
      ++ (optional isContainerNetwork "--network=container:${cfg.network.containerName}")
      ++ (optional (cfg.network.mode == "none") "--network=none")
      ++ (map (net: "--network=${net}") cfg.network.networks)
      ++ (optional (!isHostNetwork && cfg.network.autoAddHostGateway) "--add-host=host.docker.internal:host-gateway")
      ++ cfg.network.extraOptions;

    containerExtraOpts = networkOpts ++ resolvedContainerExtraOptions;

    containerPorts =
      if isHostNetwork || isContainerNetwork then
        []
      else
        concatMap (item:
          let
            protoSuffix =
              if item.hasTCP && item.hasUDP then ""
              else if item.hasTCP then "/tcp"
              else "/udp";
            bindPrefix =
              if cfg.nginx.enable && item.kind == "port" && item.port == effectiveHostPort then
                "127.0.0.1:"
              else if item.bindIp != "" then
                "${item.bindIp}:"
              else
                "";
          in
          if item.kind == "port" then
            [ "${bindPrefix}${toString item.port}:${toString item.containerPort}${protoSuffix}" ]
          else
            [ "${bindPrefix}${toString item.start}-${toString item.end}:${toString item.containerStart}-${toString item.containerEnd}${protoSuffix}" ]
        ) normalizedPorts;

    firewallItems = filter (item: item.firewall) normalizedPorts;
  in {
    options = setAttrByPath optPath ({
      enable = mkEnableOption description;

      network = mkNetworkOptionDefs { defaultMode = defaultNetworkMode; };

      ports = mapAttrs mkPredefinedPortOption declaredPorts;

      extraPorts = mkOption {
        type = types.attrsOf extraPortSubmodule;
        default = {};
        description = "Extra user-defined port mappings for ${description}.";
      };

      nginx = {
        enable = mkEnableOption "Nginx reverse proxy for ${description}";

        domain = mkOption {
          type = types.str;
          description = "Domain name for ${description}";
        };

        portName = mkOption {
          type = types.nullOr types.str;
          default = if nginx ? portName then nginx.portName else null;
          description = "Name of the port in ports/extraPorts to proxy through Nginx for ${description}";
        };

        port = mkOption {
          type = types.nullOr types.port;
          default = if nginx ? port then nginx.port else null;
          description = "Explicit port number to proxy through Nginx for ${description} (overrides portName)";
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
      proxy = mkProxyOptions ({
        inherit description;
      } // proxy);
    })
    // extraOptions);

    config = mkIf cfg.enable (mkMerge [
      # --- Always enabled logic (including Nginx sites) ---
      {
        assertions = [
          {
            assertion = !cfg.nginx.enable || (effectiveHostPort != null);
            message = "Container '${name}' has nginx reverse proxy enabled, but effectiveHostPort could not be resolved. Please specify 'nginx.port' or a valid 'nginx.portName'.";
          }
          {
            assertion = (cfg.network.mode != "container") || (cfg.network.containerName != null);
            message = "Container '${name}' has network.mode set to 'container', but 'network.containerName' is not specified.";
          }
          {
            assertion = (cfg.network.mode != "custom") || (cfg.network.customNetwork != null);
            message = "Container '${name}' has network.mode set to 'custom', but 'network.customNetwork' is not specified.";
          }
        ];

        base.app.web.nginx.enable = mkIf cfg.nginx.enable true;

        base.app.web.nginx.sites = mkIf cfg.nginx.enable {
          "${cfg.nginx.domain}" = {
            http3 = true;
            quic = true;

            locations."/" = {
              proxyPass =
                if effectiveHostPort != null then
                  "http://127.0.0.1:${toString effectiveHostPort}"
                else
                  throw "Container '${name}' has nginx enabled, but effectiveHostPort could not be resolved.";
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
          allowedTCPPortRanges = map (x: { from = x.start; to = x.end; }) (filter (x: x.kind == "range" && x.hasTCP) firewallItems);
          allowedUDPPortRanges = map (x: { from = x.start; to = x.end; }) (filter (x: x.kind == "range" && x.hasUDP) firewallItems);
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
