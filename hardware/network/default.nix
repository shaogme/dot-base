{ lib, config, options, pkgs, ... }:
with lib;
let
  cfg = config.base.hardware.network;
  facterDhcpOptionExists = hasAttrByPath [ "hardware" "facter" "detected" "dhcp" "enable" ] options;

  addressModule = types.submodule {
    options = {
      address = mkOption {
        type = types.str;
        description = "IP 地址";
      };
      prefixLength = mkOption {
        type = types.int;
        description = "子网掩码长度 / 前缀长度";
      };
    };
  };

  routeModule = types.submodule {
    options = {
      destination = mkOption {
        type = types.str;
        description = "路由目标 CIDR (如 0.0.0.0/0 或 10.0.0.0/8)";
      };
      gateway = mkOption {
        type = types.str;
        description = "路由网关地址";
      };
      metric = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "路由优先级 (Metric)";
      };
    };
  };

  interfaceModule = types.submodule ({ name, ... }: {
    options = {
      matchName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "匹配物理/虚拟网卡名称。若为 null，默认使用属性名。";
      };

      dhcp = mkOption {
        type = types.enum [ "yes" "no" "ipv4" "ipv6" ];
        default = "no";
        description = "DHCP 模式 (yes, no, ipv4, ipv6)";
      };

      macAddress = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "覆盖或克隆 MAC 地址 (硬件地址)";
      };

      mtu = mkOption {
        type = types.nullOr types.int;
        default = null;
        description = "网卡最大传输单元 (MTU)";
      };

      ipv4 = {
        addresses = mkOption {
          type = types.listOf addressModule;
          default = [ ];
          description = "静态 IPv4 地址列表";
        };
        gateway = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "IPv4 默认网关";
        };
        routes = mkOption {
          type = types.listOf routeModule;
          default = [ ];
          description = "自定义静态 IPv4 路由";
        };
      };

      ipv6 = {
        addresses = mkOption {
          type = types.listOf addressModule;
          default = [ ];
          description = "静态 IPv6 地址列表";
        };
        gateway = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "IPv6 默认网关";
        };
        routes = mkOption {
          type = types.listOf routeModule;
          default = [ ];
          description = "自定义静态 IPv6 路由";
        };
      };

      systemd-networkd = {
        extraNetworkConfig = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "额外注入 systemd-networkd networkConfig 块的键值对";
        };
        extraLinkConfig = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "额外注入 systemd-networkd linkConfig 块的键值对";
        };
      };

      networkmanager = {
        extraProfileConfig = mkOption {
          type = types.attrsOf types.anything;
          default = { };
          description = "额外注入 NetworkManager 关联 profile keyfile 键值块 (如 { connection = { autoconnect = false; }; })";
        };
      };
    };
  });

  # NetworkManager profile keyfile helper functions
  mkNmAddresses = addrs:
    listToAttrs (imap0 (i: a: {
      name = "address${toString (i + 1)}";
      value = "${a.address}/${toString a.prefixLength}";
    }) addrs);

  mkNmRoutes = routes:
    listToAttrs (imap0 (i: r: {
      name = "route${toString (i + 1)}";
      value = "${r.destination},${r.gateway}" + (if r.metric != null then ",${toString r.metric}" else "");
    }) routes);

  isIPv6 = s: hasInfix ":" s;
  ipv4Dns = filter (s: !isIPv6 s) cfg.nameservers;
  ipv6Dns = filter isIPv6 cfg.nameservers;
in
{
  options.base.hardware.network = {
    enable = mkEnableOption "统一网络配置抽象模块";

    backend = mkOption {
      type = types.enum [ "systemd-networkd" "networkmanager" "scripted" ];
      default = "systemd-networkd";
      description = "网络底层后端驱动。可选：systemd-networkd (默认)、networkmanager 或 scripted (NixOS 传统脚本模式)。";
    };

    nameservers = mkOption {
      type = types.listOf types.str;
      default = [
        "1.1.1.1"
        "8.8.8.8"
        "2606:4700:4700::1111"
        "2001:4860:4860::8888"
      ];
      description = "全局 DNS 服务器列表";
    };

    preference = mkOption {
      type = types.enum [ "ipv4" "ipv6" ];
      default = "ipv4";
      description = "协议栈优先级。默认为 ipv4 (修改 /etc/gai.conf 优先 IPv4)";
    };

    usePredictableInterfaceNames = mkOption {
      type = types.bool;
      default = true;
      description = "是否启用可预测的网卡命名规则 (如 ens18 代替 eth0)";
    };

    interfaces = mkOption {
      type = types.attrsOf interfaceModule;
      default = { };
      description = "网卡接口配置字典";
    };
  };

  config = mkIf (cfg.enable && !config.base.testMode) (mkMerge [
    # 通用基础配置
    {
      networking = {
        nameservers = mkDefault cfg.nameservers;
        usePredictableInterfaceNames = cfg.usePredictableInterfaceNames;
      };

      # IPv4 / IPv6 优先级调优
      environment.etc."gai.conf".text = mkIf (cfg.preference == "ipv4") ''
        label ::1/128       0
        label ::/0          1
        label 2002::/16     2
        label ::/96         3
        label ::ffff:0:0/96 4
        precedence ::1/128       50
        precedence ::/0          40
        precedence 2002::/16     30
        precedence ::/96         20
        precedence ::ffff:0:0/96 100
      '';
    }

    # Facter's generated DHCP unit would otherwise win over this module's
    # static networkd unit because it is named 40-<interface>.network.
    (optionalAttrs facterDhcpOptionExists {
      hardware.facter.detected.dhcp.enable = mkDefault false;
    })

    # 1. 后端 A: systemd-networkd 模式
    (mkIf (cfg.backend == "systemd-networkd") {
      networking = {
        networkmanager.enable = false;
        useNetworkd = true;
        useDHCP = false;
      };

      systemd.network = {
        enable = true;

        networks = mapAttrs' (ifaceName: ifaceCfg:
          nameValuePair "10-${ifaceName}" (
            let
              defaultRoutes =
                (optional (ifaceCfg.ipv4.gateway != null) {
                  Gateway = ifaceCfg.ipv4.gateway;
                  GatewayOnLink = true;
                })
                ++ (optional (ifaceCfg.ipv6.gateway != null) {
                  Gateway = ifaceCfg.ipv6.gateway;
                  GatewayOnLink = true;
                });
            in
            {
              matchConfig = {
                Name = if ifaceCfg.matchName != null then ifaceCfg.matchName else ifaceName;
              };

              networkConfig = {
                DHCP = ifaceCfg.dhcp;
                DNS = cfg.nameservers;
              } // ifaceCfg.systemd-networkd.extraNetworkConfig;

              linkConfig = { }
                // optionalAttrs (ifaceCfg.macAddress != null) { MACAddress = ifaceCfg.macAddress; }
                // optionalAttrs (ifaceCfg.mtu != null) { MTUBytes = toString ifaceCfg.mtu; }
                // ifaceCfg.systemd-networkd.extraLinkConfig;

              address = (map (a: "${a.address}/${toString a.prefixLength}") ifaceCfg.ipv4.addresses)
                ++ (map (a: "${a.address}/${toString a.prefixLength}") ifaceCfg.ipv6.addresses);

              routes = defaultRoutes ++ (map (r:
                {
                  Destination = r.destination;
                  Gateway = r.gateway;
                } // (optionalAttrs (r.metric != null) { Metric = r.metric; })
              ) (ifaceCfg.ipv4.routes ++ ifaceCfg.ipv6.routes));
            }
          )
        ) cfg.interfaces;
      };
    })

    # 2. 后端 B: networkmanager 模式
    (mkIf (cfg.backend == "networkmanager") {
      networking = {
        networkmanager = {
          enable = true;
          ensureProfiles.profiles = mapAttrs (ifaceName: ifaceCfg:
            let
              devName = if ifaceCfg.matchName != null then ifaceCfg.matchName else ifaceName;

              baseProfile = {
                connection = {
                  id = ifaceName;
                  type = "ethernet";
                  "interface-name" = devName;
                };

                ethernet = optionalAttrs (ifaceCfg.macAddress != null) {
                  "cloned-mac-address" = ifaceCfg.macAddress;
                } // optionalAttrs (ifaceCfg.mtu != null) {
                  mtu = ifaceCfg.mtu;
                };

                ipv4 = {
                  method =
                    if (ifaceCfg.dhcp == "yes" || ifaceCfg.dhcp == "ipv4") then
                      "auto"
                    else if (ifaceCfg.ipv4.addresses != [ ] || ifaceCfg.ipv4.gateway != null) then
                      "manual"
                    else
                      "disabled";
                }
                // (optionalAttrs (ifaceCfg.ipv4.addresses != [ ]) (mkNmAddresses ifaceCfg.ipv4.addresses))
                // (optionalAttrs (ifaceCfg.ipv4.gateway != null) { gateway = ifaceCfg.ipv4.gateway; })
                // (optionalAttrs (ifaceCfg.ipv4.routes != [ ]) (mkNmRoutes ifaceCfg.ipv4.routes))
                // (optionalAttrs (ipv4Dns != [ ]) { dns = concatStringsSep ";" ipv4Dns + ";"; });

                ipv6 = {
                  method =
                    if (ifaceCfg.dhcp == "yes" || ifaceCfg.dhcp == "ipv6") then
                      "auto"
                    else if (ifaceCfg.ipv6.addresses != [ ] || ifaceCfg.ipv6.gateway != null) then
                      "manual"
                    else
                      "disabled";
                }
                // (optionalAttrs (ifaceCfg.ipv6.addresses != [ ]) (mkNmAddresses ifaceCfg.ipv6.addresses))
                // (optionalAttrs (ifaceCfg.ipv6.gateway != null) { gateway = ifaceCfg.ipv6.gateway; })
                // (optionalAttrs (ifaceCfg.ipv6.routes != [ ]) (mkNmRoutes ifaceCfg.ipv6.routes))
                // (optionalAttrs (ipv6Dns != [ ]) { dns = concatStringsSep ";" ipv6Dns + ";"; });
              };
            in
            recursiveUpdate baseProfile ifaceCfg.networkmanager.extraProfileConfig
          ) cfg.interfaces;
        };
        useNetworkd = false;
        useDHCP = false;
      };
    })

    # 3. 后端 C: scripted (传统模式)
    (mkIf (cfg.backend == "scripted") {
      networking = {
        networkmanager.enable = false;
        useNetworkd = false;

        interfaces = mapAttrs (ifaceName: ifaceCfg: {
          useDHCP = (ifaceCfg.dhcp == "yes" || ifaceCfg.dhcp == "ipv4");

          macAddress = mkIf (ifaceCfg.macAddress != null) ifaceCfg.macAddress;
          mtu = mkIf (ifaceCfg.mtu != null) ifaceCfg.mtu;

          ipv4 = {
            addresses = map (a: {
              address = a.address;
              prefixLength = a.prefixLength;
            }) ifaceCfg.ipv4.addresses;

            routes = map (r: {
              address = head (splitString "/" r.destination);
              prefixLength = toInt (elemAt (splitString "/" r.destination) 1);
              via = r.gateway;
            } // (optionalAttrs (r.metric != null) { metric = r.metric; })) ifaceCfg.ipv4.routes;
          };

          ipv6 = {
            addresses = map (a: {
              address = a.address;
              prefixLength = a.prefixLength;
            }) ifaceCfg.ipv6.addresses;

            routes = map (r: {
              address = head (splitString "/" r.destination);
              prefixLength = toInt (elemAt (splitString "/" r.destination) 1);
              via = r.gateway;
            } // (optionalAttrs (r.metric != null) { metric = r.metric; })) ifaceCfg.ipv6.routes;
          };
        }) cfg.interfaces;

        defaultGateway = let
          gws = filter (g: g != null) (mapAttrsToList (_: v: v.ipv4.gateway) cfg.interfaces);
        in mkIf (gws != [ ]) (head gws);

        defaultGateway6 = let
          gws6 = filter (g: g != null) (mapAttrsToList (_: v: v.ipv6.gateway) cfg.interfaces);
        in mkIf (gws6 != [ ]) (head gws6);
      };
    })
  ]);
}
