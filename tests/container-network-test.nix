{ pkgs ? (import <nixpkgs> {}) }:
let
  lib = pkgs.lib;
  baseLib = import ../default.nix { inherit pkgs lib; };

  eval = extraModules: import (pkgs.path + "/nixos/lib/eval-config.nix") {
    inherit pkgs lib;
    system = "x86_64-linux";
    modules = [
      baseLib.nixosModules.default
      {
        base.enable = true;
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/null";
      }
    ] ++ extraModules;
  };

  # 1. 默认 Host 模式测试 (s-ui)
  evalSuiDefault = eval [
    {
      base.app.proxy.s-ui.enable = true;
    }
  ];

  # 2. 覆盖为 Bridge 模式测试 (s-ui)
  evalSuiBridge = eval [
    {
      base.app.proxy.s-ui = {
        enable = true;
        network.mode = "bridge";
      };
    }
  ];

  # 3. 覆盖为 Bridge 模式并修改端口 + 启用 Nginx (s-ui)
  evalSuiBridgeNginx = eval [
    {
      base.app.proxy.s-ui = {
        enable = true;
        network.mode = "bridge";
        ports.panel.port = 8443;
        nginx = {
          enable = true;
          domain = "sui.example.com";
        };
      };
    }
  ];

  # 4. 自定义网络模式 (s-ui)
  evalSuiCustom = eval [
    {
      base.app.proxy.s-ui = {
        enable = true;
        network = {
          mode = "custom";
          customNetwork = "proxy-net";
        };
      };
    }
  ];

  # 5. 默认 Bridge 模式切换到 Host 模式 (vaultwarden)
  evalVaultwardenHost = eval [
    {
      base.app.web.vaultwarden = {
        enable = true;
        network.mode = "host";
      };
    }
  ];

  # 6. 默认 Bridge 模式 (vaultwarden)
  evalVaultwardenBridge = eval [
    {
      base.app.web.vaultwarden = {
        enable = true;
      };
    }
  ];

  # 7. 全局代理与自适应 Loopback 替换测试 (Host 模式)
  evalProxyHost = eval [
    {
      base.proxy = {
        enable = true;
        default = "http://127.0.0.1:2080";
      };
      base.app.proxy.s-ui = {
        enable = true;
        network.mode = "host";
        proxy.mode = "auto";
      };
    }
  ];

  # 8. 全局代理与自适应 Loopback 替换测试 (Bridge 模式)
  evalProxyBridge = eval [
    {
      base.proxy = {
        enable = true;
        default = "http://127.0.0.1:2080";
      };
      base.app.proxy.s-ui = {
        enable = true;
        network.mode = "bridge";
        proxy.mode = "auto";
      };
    }
  ];

  # 9. 显式覆盖 autoReplaceLoopback
  evalProxyBridgeExplicitNoReplace = eval [
    {
      base.proxy = {
        enable = true;
        default = "http://127.0.0.1:2080";
      };
      base.app.proxy.s-ui = {
        enable = true;
        network.mode = "bridge";
        proxy = {
          mode = "auto";
          autoReplaceLoopback = false;
        };
      };
    }
  ];

  # 断言辅助函数
  assertMsg = cond: msg: if cond then true else throw "Assertion failed: ${msg}";

  runChecks = [
    # 检查 1: s-ui 默认是 host
    (assertMsg
      (evalSuiDefault.config.base.app.proxy.s-ui.network.mode == "host")
      "s-ui default network.mode should be host")
    (assertMsg
      (lib.elem "--network=host" evalSuiDefault.config.virtualisation.oci-containers.containers.s-ui.extraOptions)
      "s-ui default extraOptions should include --network=host")
    (assertMsg
      (evalSuiDefault.config.virtualisation.oci-containers.containers.s-ui.ports == [])
      "s-ui default ports should be empty in host mode")
    (assertMsg
      (lib.elem 2095 evalSuiDefault.config.networking.firewall.allowedTCPPorts)
      "s-ui default firewall should open panel TCP port 2095")
    (assertMsg
      (lib.elem { from = 10100; to = 10200; } evalSuiDefault.config.networking.firewall.allowedTCPPortRanges)
      "s-ui default firewall should open node TCP range 10100-10200")

    # 检查 2: s-ui 切换为 bridge 模式
    (assertMsg
      (evalSuiBridge.config.base.app.proxy.s-ui.network.mode == "bridge")
      "s-ui mode should be bridge")
    (assertMsg
      (lib.elem "--network=bridge" evalSuiBridge.config.virtualisation.oci-containers.containers.s-ui.extraOptions)
      "s-ui bridge extraOptions should include --network=bridge")
    (assertMsg
      (lib.elem "--add-host=host.docker.internal:host-gateway" evalSuiBridge.config.virtualisation.oci-containers.containers.s-ui.extraOptions)
      "s-ui bridge extraOptions should include --add-host")
    (assertMsg
      (lib.elem "2095:2095/tcp" evalSuiBridge.config.virtualisation.oci-containers.containers.s-ui.ports)
      "s-ui bridge ports should map 2095:2095/tcp")
    (assertMsg
      (lib.elem "2096:2096/tcp" evalSuiBridge.config.virtualisation.oci-containers.containers.s-ui.ports)
      "s-ui bridge ports should map 2096:2096/tcp")
    (assertMsg
      (lib.elem "10100-10200:10100-10200" evalSuiBridge.config.virtualisation.oci-containers.containers.s-ui.ports)
      "s-ui bridge ports should map 10100-10200:10100-10200")

    # 检查 3: s-ui bridge 模式 + Nginx 反代 + 自定义端口
    (assertMsg
      (lib.elem "127.0.0.1:8443:2095/tcp" evalSuiBridgeNginx.config.virtualisation.oci-containers.containers.s-ui.ports)
      "s-ui bridge+nginx should bind effectiveHostPort 8443 to 127.0.0.1:8443:2095/tcp")
    (assertMsg
      (evalSuiBridgeNginx.config.services.nginx.virtualHosts."sui.example.com".locations."/".proxyPass == "http://127.0.0.1:8443")
      "nginx proxyPass should target http://127.0.0.1:8443")

    # 检查 4: s-ui 自定义网络
    (assertMsg
      (lib.elem "--network=proxy-net" evalSuiCustom.config.virtualisation.oci-containers.containers.s-ui.extraOptions)
      "s-ui custom network should include --network=proxy-net")

    # 检查 5: vaultwarden 默认 bridge
    (assertMsg
      (lib.elem "8000:80" evalVaultwardenBridge.config.virtualisation.oci-containers.containers.vaultwarden.ports)
      "vaultwarden bridge should map 8000:80")

    # 检查 6: vaultwarden 切换为 host
    (assertMsg
      (evalVaultwardenHost.config.virtualisation.oci-containers.containers.vaultwarden.ports == [])
      "vaultwarden in host mode should have empty ports")
    (assertMsg
      (lib.elem "--network=host" evalVaultwardenHost.config.virtualisation.oci-containers.containers.vaultwarden.extraOptions)
      "vaultwarden in host mode should include --network=host")

    # 检查 7: Host 模式下代理直通 127.0.0.1 (不替换)
    (assertMsg
      (evalProxyHost.config.virtualisation.oci-containers.containers.s-ui.environment.HTTP_PROXY == "http://127.0.0.1:2080")
      "Host mode container proxy should NOT replace 127.0.0.1")

    # 检查 8: Bridge 模式下代理自动替换为 host.docker.internal
    (assertMsg
      (evalProxyBridge.config.virtualisation.oci-containers.containers.s-ui.environment.HTTP_PROXY == "http://host.docker.internal:2080")
      "Bridge mode container proxy should automatically replace 127.0.0.1 with host.docker.internal")

    # 检查 9: 显式设置 autoReplaceLoopback = false 时不替换
    (assertMsg
      (evalProxyBridgeExplicitNoReplace.config.virtualisation.oci-containers.containers.s-ui.environment.HTTP_PROXY == "http://127.0.0.1:2080")
      "Explicit autoReplaceLoopback=false should prevent replacing 127.0.0.1")
  ];
in
pkgs.runCommand "container-network-test" {
  checks = builtins.deepSeq runChecks true;
} ''
  echo "All container dual network tests passed successfully!" > $out
''
