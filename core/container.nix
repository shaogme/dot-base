{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.container;
  proxyCfg = cfg.proxy;
  baseProxy = config.base.proxy;
  proxyLib = import ./proxy-lib.nix { inherit lib; };

  containerHttpProxy = proxyLib.replaceLoopback { url = baseProxy.httpProxy; inherit (proxyCfg) hostDomain; enable = proxyCfg.autoReplaceLoopback; };
  containerHttpsProxy = proxyLib.replaceLoopback { url = baseProxy.httpsProxy; inherit (proxyCfg) hostDomain; enable = proxyCfg.autoReplaceLoopback; };
  containerAllProxy = proxyLib.replaceLoopback { url = baseProxy.allProxy; inherit (proxyCfg) hostDomain; enable = proxyCfg.autoReplaceLoopback; };
  containerNoProxy = baseProxy.noProxy;

  # 当回环地址被替换时，通过 engine.env 覆盖 host 传递的 127.0.0.1 环境变量
  hasLoopbackReplaced = proxyCfg.autoReplaceLoopback && (
    (baseProxy.httpProxy != null && containerHttpProxy != baseProxy.httpProxy) ||
    (baseProxy.httpsProxy != null && containerHttpsProxy != baseProxy.httpsProxy) ||
    (baseProxy.allProxy != null && containerAllProxy != baseProxy.allProxy)
  );

  containerEnvList = optionals (proxyCfg.enable && hasLoopbackReplaced) (
    (optional (containerHttpProxy != null) "HTTP_PROXY=${containerHttpProxy}")
    ++ (optional (containerHttpProxy != null) "http_proxy=${containerHttpProxy}")
    ++ (optional (containerHttpsProxy != null) "HTTPS_PROXY=${containerHttpsProxy}")
    ++ (optional (containerHttpsProxy != null) "https_proxy=${containerHttpsProxy}")
    ++ (optional (containerAllProxy != null) "ALL_PROXY=${containerAllProxy}")
    ++ (optional (containerAllProxy != null) "all_proxy=${containerAllProxy}")
    ++ (optional (containerNoProxy != "") "NO_PROXY=${containerNoProxy}")
    ++ (optional (containerNoProxy != "") "no_proxy=${containerNoProxy}")
  );
in {
  options.base.containerBackend = mkOption {
    type = types.enum [ "docker" "podman" ];
    default = "podman";
    description = "Default container backend to use for all modules";
  };

  options.base.container = {
    docker = {
      enable = mkEnableOption "Docker container engine";
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open firewall for Docker container interface";
      };
    };
    podman = {
      enable = mkEnableOption "Podman container engine";
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = "Open firewall for Podman container interfaces";
      };
    };
    proxy = {
      enable = mkOption {
        type = types.bool;
        default = config.base.proxy.enable;
        defaultText = literalExpression "config.base.proxy.enable";
        description = "Enable proxy integration for containers (maps to containers.conf http_proxy and Docker proxy).";
      };
      autoReplaceLoopback = mkOption {
        type = types.bool;
        default = true;
        description = "Automatically replace 127.0.0.1 and localhost in proxy URLs with hostDomain for container traffic.";
      };
      hostDomain = mkOption {
        type = types.str;
        default = "host.docker.internal";
        description = "Host gateway domain name to reach host from inside containers.";
      };
    };
  };

  config = mkMerge [
    # --- Docker Configuration ---
    (mkIf (cfg.docker.enable && !config.base.testMode) {
      virtualisation.docker = {
        enable = true;
        daemon.settings = {
          experimental = true;
          default-address-pools = [{ base = "172.30.0.0/16"; size = 24; }];
        };
        rootless = {
          enable = true;
          setSocketVariable = true;
          daemon.settings = { dns = [ "1.1.1.1" "8.8.8.8" ]; };
        };
      };

      # Docker daemon proxy for image pulls (runs on host network namespace)
      systemd.services.docker.environment = mkIf (proxyCfg.enable && baseProxy.enable) (
        lib.filterAttrs (_: v: v != null) {
          HTTP_PROXY = baseProxy.httpProxy;
          HTTPS_PROXY = baseProxy.httpsProxy;
          ALL_PROXY = baseProxy.allProxy;
          NO_PROXY = baseProxy.noProxy;
          http_proxy = baseProxy.httpProxy;
          https_proxy = baseProxy.httpsProxy;
          all_proxy = baseProxy.allProxy;
          no_proxy = baseProxy.noProxy;
        }
      );

      # Global client config to inject proxy into containers
      environment.etc."docker/config.json" = mkIf (proxyCfg.enable && (containerHttpProxy != null || containerHttpsProxy != null)) {
        text = builtins.toJSON {
          proxies = {
            default = lib.filterAttrs (_: v: v != null) {
              httpProxy = containerHttpProxy;
              httpsProxy = containerHttpsProxy;
              noProxy = containerNoProxy;
            };
          };
        };
      };

      boot.kernel.sysctl = {
        "net.ipv4.conf.eth0.forwarding" = 1; # enable port forwarding
      };

      users.users.root.extraGroups = [ "docker" ];

      environment.systemPackages = with pkgs; [
        docker-compose
      ];

      networking.firewall.trustedInterfaces = mkIf cfg.docker.openFirewall [ "docker0" ];
    })

    # --- Podman Configuration ---
    (mkIf (cfg.podman.enable && !config.base.testMode) {
      virtualisation.podman = {
        enable = true;
        # Docker 兼容模式 (若 Docker 同时也启用了，则禁用此兼容模式以避免冲突)
        dockerCompat = !cfg.docker.enable;
        dockerSocket.enable = !cfg.docker.enable;
        # 启用容器间 DNS 解析 (支持容器名互访)
        defaultNetwork.settings.dns_enabled = true;
      };

      # containers.conf 全局容器代理配置
      virtualisation.containers.containersConf.settings = mkIf (proxyCfg.enable && !config.base.testMode) {
        engine = {
          http_proxy = true;
        } // (optionalAttrs (containerEnvList != [ ]) {
          env = containerEnvList;
        });
      };

      environment.systemPackages = with pkgs; [
        podman-compose
        docker-compose
      ];

      networking.firewall.trustedInterfaces = mkIf cfg.podman.openFirewall [ "podman0" "podman1" ];
    })
  ];
}
