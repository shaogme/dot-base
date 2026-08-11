{ pkgs, library }:
let
  # 1. systemd-networkd 模式评估
  eval = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          auth.root.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... dummy@test" ];
          memory.mode = "aggressive";
          dns.smartdns.mode = "china";
          container.docker.enable = true;
          performance.tuning.enable = true;
          update.enable = true;
          hardware.network = {
            enable = true;
            backend = "systemd-networkd";
            interfaces.eth0 = {
              dhcp = "yes";
              macAddress = "52:54:00:12:34:56";
              mtu = 1500;
              systemd-networkd.extraLinkConfig = {
                RequiredForOnline = "no";
              };
            };
          };
        };
        # 最小化配置以满足评估要求
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/dummy";
      }
    ];
  };
  cfg = eval.config;

  # 2. Static systemd-networkd configuration with a Facter report.
  evalFacterStatic = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        hardware.facter.report = {
          hardware.network_interface = [
            {
              sub_class.name = "Ethernet";
              unix_device_names = [ "eth0" ];
            }
          ];
        };

        base = {
          enable = true;
          auth.root.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... dummy@test" ];
          hardware.network = {
            enable = true;
            interfaces.eth0 = {
              dhcp = "no";
              ipv4.addresses = [ { address = "192.0.2.2"; prefixLength = 24; } ];
              ipv4.gateway = "192.0.2.1";
            };
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/dummy";
      }
    ];
  };
  cfgFacterStatic = evalFacterStatic.config;

  # 3. NetworkManager 模式评估
  evalNm = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.network = {
            enable = true;
            backend = "networkmanager";
            nameservers = [ "1.1.1.1" "2606:4700:4700::1111" ];
            interfaces.eth0 = {
              dhcp = "no";
              macAddress = "52:54:00:12:34:56";
              mtu = 1500;
              ipv4.addresses = [ { address = "192.168.1.100"; prefixLength = 24; } ];
              ipv4.gateway = "192.168.1.1";
              ipv4.routes = [ { destination = "10.0.0.0/8"; gateway = "192.168.1.254"; metric = 100; } ];
              networkmanager.extraProfileConfig = {
                connection.autoconnect = true;
              };
            };
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/dummy";
      }
    ];
  };
  cfgNm = evalNm.config;

  # 4. Scripted 模式评估
  evalScripted = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.network = {
            enable = true;
            backend = "scripted";
            interfaces.eth0 = {
              dhcp = "no";
              macAddress = "52:54:00:ab:cd:ef";
              mtu = 1400;
              ipv4.addresses = [ { address = "10.0.0.2"; prefixLength = 24; } ];
              ipv4.gateway = "10.0.0.1";
              ipv4.routes = [ { destination = "172.16.0.0/16"; gateway = "10.0.0.254"; metric = 50; } ];
            };
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/dummy";
      }
    ];
  };
  cfgScripted = evalScripted.config;
in
pkgs.runCommand "static-check" { } ''
  echo "正在验证基础配置与网络模块测试覆盖..."
  
  # 1. 验证 SSH 服务
  if [[ "${if cfg.services.openssh.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: base 模块应默认启用 SSH 服务"
    exit 1
  fi

  # 2. 验证时区与本地化
  if [[ "${cfg.time.timeZone}" != "Asia/Shanghai" ]]; then
    echo "错误: 时区应为 Asia/Shanghai"
    exit 1
  fi
  if [[ "${cfg.i18n.defaultLocale}" != "zh_CN.UTF-8" ]]; then
    echo "错误: 默认语言应为 zh_CN.UTF-8"
    exit 1
  fi

  # 3. 验证内存优化 (Aggressive 模式)
  if [[ "${if cfg.zramSwap.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: Aggressive 模式应启用 zramSwap"
    exit 1
  fi
  if [[ "${toString cfg.zramSwap.memoryPercent}" != "100" ]]; then
    echo "错误: Aggressive 模式 memoryPercent 应为 100"
    exit 1
  fi
  if [[ "${toString cfg.nix.settings.cores}" != "1" ]]; then
    echo "错误: Aggressive 模式 nix.settings.cores 应为 1"
    exit 1
  fi

  # 4. 验证 SmartDNS (China 模式)
  if [[ "${if cfg.services.smartdns.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: SmartDNS 应启用"
    exit 1
  fi
  if [[ "${if cfg.services.resolved.enable then "true" else "false"}" == "true" ]]; then
    echo "错误: 启用 SmartDNS 时应禁用 systemd-resolved"
    exit 1
  fi

  # 5. 验证容器服务 (Docker)
  if [[ "${if cfg.virtualisation.docker.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: 应启用 Docker 服务"
    exit 1
  fi

  # 6. 验证性能调优
  if [[ "${if cfg.services.tuned.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: 应启用 Tuned 服务"
    exit 1
  fi

  # 7. 验证自动更新
  if [[ "${if cfg.system.autoUpgrade.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: 应启用系统自动升级"
    exit 1
  fi
  if [[ "${if cfg.nix.gc.automatic then "true" else "false"}" != "true" ]]; then
    echo "错误: 应启用自动垃圾回收"
    exit 1
  fi

  # 8. 验证防火墙
  if [[ "${if cfg.networking.nftables.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: 应启用 nftables 防火墙"
    exit 1
  fi

  # 9. 验证 systemd-networkd 模式属性
  if [[ "${if cfg.networking.useNetworkd then "true" else "false"}" != "true" ]]; then
    echo "错误: systemd-networkd 模式应启用 useNetworkd"
    exit 1
  fi
  if [[ "${cfg.systemd.network.networks."10-eth0".linkConfig.MACAddress}" != "52:54:00:12:34:56" ]]; then
    echo "错误: systemd-networkd linkConfig MACAddress 配置未正确应用"
    exit 1
  fi
  if [[ "${cfg.systemd.network.networks."10-eth0".linkConfig.RequiredForOnline}" != "no" ]]; then
    echo "错误: systemd-networkd extraLinkConfig 扩展属性未正确合并"
    exit 1
  fi

  # 10. Facter 自动 DHCP 不得覆盖静态 networkd 配置
  if [[ "${if cfgFacterStatic.hardware.facter.detected.dhcp.enable then "true" else "false"}" != "false" ]]; then
    echo "错误: 启用统一网络模块时应默认禁用 Facter 自动 DHCP"
    exit 1
  fi
  if [[ "${if cfgFacterStatic.systemd.network.networks ? "40-eth0" then "true" else "false"}" != "false" ]]; then
    echo "错误: Facter 不应生成竞争的 40-eth0 networkd unit"
    exit 1
  fi
  if [[ "${cfgFacterStatic.systemd.network.networks."10-eth0".networkConfig.DHCP}" != "no" ]]; then
    echo "错误: 静态 networkd unit 的 DHCP 设置不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "192.0.2.2/24" cfgFacterStatic.systemd.network.networks."10-eth0".address then "true" else "false"}" != "true" ]]; then
    echo "错误: 静态 networkd unit 未包含 IPv4 地址"
    exit 1
  fi

  # 11. 验证 NetworkManager 模式属性与 keyfile 生成
  if [[ "${if cfgNm.networking.networkmanager.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: networkmanager 模式应启用 NetworkManager 服务"
    exit 1
  fi
  if [[ "${if cfgNm.networking.useNetworkd then "true" else "false"}" == "true" ]]; then
    echo "错误: networkmanager 模式应禁用 systemd-networkd"
    exit 1
  fi
  if [[ "${cfgNm.networking.networkmanager.ensureProfiles.profiles.eth0.ethernet.cloned-mac-address}" != "52:54:00:12:34:56" ]]; then
    echo "错误: NetworkManager profile 克隆 MAC 地址配置不符合预期"
    exit 1
  fi
  if [[ "${cfgNm.networking.networkmanager.ensureProfiles.profiles.eth0.ipv4.address1}" != "192.168.1.100/24" ]]; then
    echo "错误: NetworkManager profile 静态 IP 地址配置不符合预期"
    exit 1
  fi
  if [[ "${cfgNm.networking.networkmanager.ensureProfiles.profiles.eth0.ipv4.gateway}" != "192.168.1.1" ]]; then
    echo "错误: NetworkManager profile 静态 Gateway 配置不符合预期"
    exit 1
  fi
  if [[ "${cfgNm.networking.networkmanager.ensureProfiles.profiles.eth0.ipv4.route1}" != "10.0.0.0/8,192.168.1.254,100" ]]; then
    echo "错误: NetworkManager profile 静态 Route 配置不符合预期"
    exit 1
  fi
  if [[ "${if cfgNm.networking.networkmanager.ensureProfiles.profiles.eth0.connection.autoconnect then "true" else "false"}" != "true" ]]; then
    echo "错误: NetworkManager extraProfileConfig 未能成功合并扩展属性"
    exit 1
  fi

  # 12. 验证 Scripted 模式属性
  if [[ "${if cfgScripted.networking.useNetworkd then "true" else "false"}" == "true" ]]; then
    echo "错误: scripted 模式应禁用 systemd-networkd"
    exit 1
  fi
  if [[ "${cfgScripted.networking.interfaces.eth0.macAddress}" != "52:54:00:ab:cd:ef" ]]; then
    echo "错误: scripted 模式 MAC 地址配置不符合预期"
    exit 1
  fi
  if [[ "${toString cfgScripted.networking.interfaces.eth0.mtu}" != "1400" ]]; then
    echo "错误: scripted 模式 MTU 配置不符合预期"
    exit 1
  fi
  if [[ "${cfgScripted.networking.defaultGateway.address}" != "10.0.0.1" ]]; then
    echo "错误: scripted 模式 defaultGateway 不符合预期"
    exit 1
  fi

  echo "静态测试与多模式网络覆盖检查全部通过！"
  touch $out
''
