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
          proxy = {
            enable = true;
            default = "http://127.0.0.1:2080";
            allProxy = "socks5://127.0.0.1:2080";
          };
          container.docker.enable = true;
          app.web.openlist = {
            enable = true;
            proxy.mode = "disable";
            ports.web.port = 5080;
            extraPorts.custom = {
              port = 3000;
              protocol = "tcp";
              firewall.open = true;
            };
          };
          app.web.vaultwarden = {
            enable = true;
            nginx = {
              enable = true;
              domain = "vw.example.com";
            };
            proxy = {
              mode = "overwrite";
              httpProxy = "http://127.0.0.1:8888";
            };
          };
          app.proxy.x-ui-yg = {
            enable = true;
            nginx = {
              enable = true;
              domain = "x-ui.example.com";
            };
            ports.nodes.enable = false; # 测试：通过 enable = false 关闭单个预定义端口
          };
          app.proxy.v2raya = {
            enable = true;
            nginx = {
              enable = true;
              domain = "v2raya.example.com";
            };
          };
          app.proxy.s-ui = {
            enable = true;
            proxy.mode = "auto";
            nginx = {
              enable = true;
              domain = "s-ui.example.com";
            };
            ports = {
              subscription = null; # 测试：通过 null 关闭单个预定义端口
              nodes = {
                start = 12000;
                end = 12010;
                firewall.open = true;
              };
            };
            extraPorts = {
              disabledPort = {
                port = 7777;
                enable = false;
                firewall.open = true;
              };
              nullPort = null;
              apiTcp = {
                port = 8888;
                protocol = "tcp";
                firewall.open = true;
              };
              dnsUdp = {
                port = 9999;
                protocol = "udp";
                firewall.open = true;
              };
              rangeTcp = {
                start = 13000;
                end = 13010;
                protocol = "tcp";
                firewall.open = true;
              };
            };
          };
          app.proxy.hysteria = {
            enable = true;
            instances.main = {
              domain = "hy.test.com";
              portHopping = {
                enable = true;
                range = "20000-50000";
                interface = "eth0";
              };
              settings = {
                listen = ":20000";
                bandwidth = {
                  up = "100 mbps";
                  down = "100 mbps";
                };
              };
            };
          };
          performance.tuning.profile = "vps";
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
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
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
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
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
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
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
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgScripted = evalScripted.config;

  # 5. Podman 与 Proxy 模式评估
  evalPodman = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          proxy = {
            enable = true;
            default = "http://127.0.0.1:2080";
            allProxy = "socks5://127.0.0.1:2080";
          };
          container.podman.enable = true;
          app.web.openlist.enable = true;
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgPodman = evalPodman.config;

  # 6. AMD 显卡桌面环境评估
  evalAmdGraphics = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.graphics.mode = "amd";
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgAmdGraphics = evalAmdGraphics.config;

  # 7. NVIDIA 显卡桌面环境评估
  evalNvidiaGraphics = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.graphics = {
            mode = "nvidia";
            nvidia.open = true;
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgNvidiaGraphics = evalNvidiaGraphics.config;

  # 7.1 AMD + NVIDIA 混合双显卡 PRIME Offload 模式评估
  evalHybridOffload = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.graphics = {
            mode = "hybrid-amd-nvidia";
            hybrid = {
              strategy = "offload";
              integratedBusId = "PCI:5:0:0";
              discreteBusId = "PCI:1:0:0";
            };
            nvidia.open = true;
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgHybridOffload = evalHybridOffload.config;

  # 7.2 AMD + NVIDIA 混合双显卡 Compute-Only 模式评估
  evalHybridCompute = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          hardware.graphics = {
            mode = "hybrid-amd-nvidia";
            hybrid = {
              strategy = "compute-only";
            };
          };
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgHybridCompute = evalHybridCompute.config;

  # 8. Desktop 调优评估
  evalDesktopTuning = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          performance.tuning.profile = "desktop";
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgDesktopTuning = evalDesktopTuning.config;

  # 9. Desktop-Performance 调优评估
  evalPerfTuning = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          performance.tuning.profile = "desktop-performance";
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgPerfTuning = evalPerfTuning.config;

  # 10. Desktop-Powersave 调优评估
  evalPowerTuning = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    modules = [
      { nixpkgs.hostPlatform = pkgs.stdenv.hostPlatform.system; }
      library.nixosModules.default
      {
        base = {
          enable = true;
          performance.tuning.profile = "desktop-powersave";
        };
        boot.loader.grub.enable = false;
        fileSystems."/" = {
          device = "/dev/dummy";
          fsType = "ext4";
        };
      }
    ];
  };
  cfgPowerTuning = evalPowerTuning.config;
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
  if [[ "${if cfg.virtualisation.oci-containers.containers ? x-ui-yg then "true" else "false"}" != "true" ]]; then
    echo "错误: 应包含 x-ui-yg 容器配置"
    exit 1
  fi

  # 6. 验证性能调优 (VPS 模式及各桌面 Profile)
  if [[ "${if cfg.services.tuned.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: VPS 模式应启用 Tuned 服务"
    exit 1
  fi
  if [[ "${if cfg.services.tuned.ppdSupport then "true" else "false"}" != "false" ]]; then
    echo "错误: VPS 模式应禁用 ppdSupport"
    exit 1
  fi
  if [[ "${if cfg.services.tuned.recommend ? "virtual-guest" then "true" else "false"}" != "true" ]]; then
    echo "错误: VPS 模式应推荐 virtual-guest profile"
    exit 1
  fi
  if [[ "${if cfgDesktopTuning.services.tuned.ppdSupport then "true" else "false"}" != "true" ]]; then
    echo "错误: desktop 模式应启用 ppdSupport"
    exit 1
  fi
  if [[ "${cfgDesktopTuning.services.tuned.ppdSettings.main.default}" != "balanced" ]]; then
    echo "错误: desktop 模式默认 PPD profile 应为 balanced"
    exit 1
  fi
  if [[ "${if cfgDesktopTuning.services.tuned.recommend ? desktop then "true" else "false"}" != "true" ]]; then
    echo "错误: desktop 模式应推荐 desktop profile"
    exit 1
  fi
  if [[ "${cfgPerfTuning.services.tuned.ppdSettings.main.default}" != "performance" ]]; then
    echo "错误: desktop-performance 模式默认 PPD profile 应为 performance"
    exit 1
  fi
  if [[ "${cfgPowerTuning.services.tuned.ppdSettings.main.default}" != "power-saver" ]]; then
    echo "错误: desktop-powersave 模式默认 PPD profile 应为 power-saver"
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

  # 13. 验证 Proxy 配置与 nix-daemon 注入
  if [[ "${if cfg.networking.proxy.default == "http://127.0.0.1:2080" then "true" else "false"}" != "true" ]]; then
    echo "错误: networking.proxy.default 配置不符合预期"
    exit 1
  fi
  if [[ "${cfg.systemd.services.nix-daemon.environment.http_proxy}" != "http://127.0.0.1:2080" ]]; then
    echo "错误: nix-daemon http_proxy 环境变量注入不符合预期"
    exit 1
  fi
  if [[ "${cfg.systemd.services.nix-daemon.environment.ALL_PROXY}" != "socks5://127.0.0.1:2080" ]]; then
    echo "错误: nix-daemon ALL_PROXY 环境变量注入不符合预期"
    exit 1
  fi

  # 14. 验证 Docker 代理配置与 host.docker.internal 替换
  if [[ "${cfg.systemd.services.docker.environment.http_proxy}" != "http://127.0.0.1:2080" ]]; then
    echo "错误: Docker daemon http_proxy 环境变量注入不符合预期"
    exit 1
  fi
  if [[ "${cfg.environment.etc."docker/config.json".text}" != *"host.docker.internal"* ]]; then
    echo "错误: Docker 客户端配置文件未能正确将 127.0.0.1 替换为 host.docker.internal"
    exit 1
  fi

  # 15. 验证 Podman 代理配置与 containers.conf
  if [[ "${if cfgPodman.virtualisation.containers.containersConf.settings.engine.http_proxy == true then "true" else "false"}" != "true" ]]; then
    echo "错误: Podman containers.conf engine.http_proxy 应为 true"
    exit 1
  fi
  if [[ "${if builtins.elem "http_proxy=http://host.docker.internal:2080" cfgPodman.virtualisation.containers.containersConf.settings.engine.env then "true" else "false"}" != "true" ]]; then
    echo "错误: Podman containers.conf 未能正确注入 host.docker.internal 的 http_proxy 环境变量"
    exit 1
  fi
  if [[ "${if builtins.elem "ALL_PROXY=socks5://host.docker.internal:2080" cfgPodman.virtualisation.containers.containersConf.settings.engine.env then "true" else "false"}" != "true" ]]; then
    echo "错误: Podman containers.conf 未能正确注入 host.docker.internal 的 ALL_PROXY 环境变量"
    exit 1
  fi
  if [[ "${cfgPodman.virtualisation.oci-containers.containers.openlist.environment.http_proxy}" != "http://host.docker.internal:2080" ]]; then
    echo "错误: OpenList 容器在 auto 模式下未能正确继承 host.docker.internal 的 http_proxy 环境变量"
    exit 1
  fi

  # 16. 验证 OpenList 显式取消代理配置与端口映射 (mode = "disable")
  if [[ "${cfg.virtualisation.oci-containers.containers.openlist.environment.http_proxy}" != "" ]]; then
    echo "错误: OpenList 容器未能显式清空 http_proxy 环境变量"
    exit 1
  fi
  if [[ "${if builtins.elem "5080:5244" cfg.virtualisation.oci-containers.containers.openlist.ports then "true" else "false"}" != "true" ]]; then
    echo "错误: OpenList 覆写宿主机端口后容器端口映射 5080:5244 不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "3000:3000/tcp" cfg.virtualisation.oci-containers.containers.openlist.ports then "true" else "false"}" != "true" ]]; then
    echo "错误: OpenList extraPorts 容器端口映射 3000:3000/tcp 不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 5080 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: OpenList 默认不应在防火墙开放 TCP 端口 5080"
    exit 1
  fi
  if [[ "${if builtins.elem 3000 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "true" ]]; then
    echo "错误: OpenList 防火墙开放 extraPorts TCP 端口 3000 不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 3000 cfg.networking.firewall.allowedUDPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: OpenList extraPorts TCP 端口不应在 UDP 放行"
    exit 1
  fi

  # 17. 验证 Vaultwarden 独立代理配置、host.docker.internal 替换与 Nginx 本地反代端口映射
  if [[ "${cfg.virtualisation.oci-containers.containers.vaultwarden.environment.http_proxy}" != "http://host.docker.internal:8888" ]]; then
    echo "错误: Vaultwarden 独立代理配置未能正确替换为 host.docker.internal"
    exit 1
  fi
  if [[ "${if builtins.elem "127.0.0.1:8000:80" cfg.virtualisation.oci-containers.containers.vaultwarden.ports then "true" else "false"}" != "true" ]]; then
    echo "错误: Vaultwarden 容器端口映射 127.0.0.1:8000:80 不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 8000 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: Vaultwarden 在启用 Nginx 时不应在外部防火墙开放 8000 端口"
    exit 1
  fi

  # 18. 验证 Hysteria 服务配置与 systemd 生成
  if [[ "${if cfg.systemd.services ? "hysteria-main" then "true" else "false"}" != "true" ]]; then
    echo "错误: Hysteria systemd 服务未能正确生成"
    exit 1
  fi

  # 19. 验证 S-UI 服务配置、容器定义及客户覆盖 auto proxy 规则
  if [[ "${if cfg.virtualisation.oci-containers.containers ? s-ui then "true" else "false"}" != "true" ]]; then
    echo "错误: 应包含 s-ui 容器配置"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.s-ui.image}" != "docker.io/alireza7/s-ui:latest" ]]; then
    echo "错误: s-ui 容器镜像不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "--network=host" cfg.virtualisation.oci-containers.containers.s-ui.extraOptions then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui 容器应使用 --network=host 网络模式"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.s-ui.environment.http_proxy}" != "http://127.0.0.1:2080" ]]; then
    echo "错误: s-ui 在显式设置 proxy.mode = 'auto' 时未能正确按 auto 规则继承宿主机 http_proxy 环境变量"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.s-ui.environment.ALL_PROXY}" != "socks5://127.0.0.1:2080" ]]; then
    echo "错误: s-ui 在显式设置 proxy.mode = 'auto' 时未能正确按 auto 规则继承宿主机 ALL_PROXY 环境变量"
    exit 1
  fi
  if [[ "${if builtins.elem "/var/lib/s-ui/db:/app/db" cfg.virtualisation.oci-containers.containers.s-ui.volumes then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui 容器数据库挂载路径不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "/var/lib/s-ui/cert:/app/cert" cfg.virtualisation.oci-containers.containers.s-ui.volumes then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui 容器证书挂载路径不符合预期"
    exit 1
  fi
  if [[ "${if cfg.services.nginx.virtualHosts ? "s-ui.example.com" then "true" else "false"}" != "true" ]]; then
    echo "错误: Nginx 未能正确生成 s-ui.example.com 虚拟主机配置"
    exit 1
  fi
  if [[ "${if builtins.elem { from = 12000; to = 12010; } cfg.networking.firewall.allowedTCPPortRanges then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui ports TCP 端口范围放行不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem { from = 12000; to = 12010; } cfg.networking.firewall.allowedUDPPortRanges then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui ports UDP 端口范围放行不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 8888 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui ports 单端口 TCP 放行不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 8888 cfg.networking.firewall.allowedUDPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: s-ui ports 单端口 TCP 放行不应放行 UDP"
    exit 1
  fi
  if [[ "${if builtins.elem 9999 cfg.networking.firewall.allowedUDPPorts then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui ports 单端口 UDP 放行不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem 9999 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: s-ui ports 单端口 UDP 放行不应放行 TCP"
    exit 1
  fi
  if [[ "${if builtins.elem { from = 13000; to = 13010; } cfg.networking.firewall.allowedTCPPortRanges then "true" else "false"}" != "true" ]]; then
    echo "错误: s-ui extraPorts TCP 端口范围放行不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem { from = 13000; to = 13010; } cfg.networking.firewall.allowedUDPPortRanges then "true" else "false"}" != "false" ]]; then
    echo "错误: s-ui extraPorts TCP 端口范围不应放行 UDP"
    exit 1
  fi
  if [[ "${if builtins.elem 2096 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: s-ui 已被置为 null 的 subscription 端口不应在防火墙放行"
    exit 1
  fi
  if [[ "${if builtins.elem 7777 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "false" ]]; then
    echo "错误: s-ui extraPorts 中 enable = false 的端口 7777 不应在防火墙放行"
    exit 1
  fi

  # 20. 验证 X-UI-YG 服务配置、容器定义及默认 disable proxy
  if [[ "${cfg.virtualisation.oci-containers.containers.x-ui-yg.image}" != "ghcr.io/shaogme/x-ui-yg-docker:alpine" ]]; then
    echo "错误: x-ui-yg 容器镜像不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "--network=host" cfg.virtualisation.oci-containers.containers.x-ui-yg.extraOptions then "true" else "false"}" != "true" ]]; then
    echo "错误: x-ui-yg 容器应使用 --network=host 网络模式"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.x-ui-yg.environment.http_proxy}" != "" ]]; then
    echo "错误: x-ui-yg 默认应禁用代理 (http_proxy 应为空)"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.x-ui-yg.environment.ALL_PROXY}" != "" ]]; then
    echo "错误: x-ui-yg 默认应禁用代理 (ALL_PROXY 应为空)"
    exit 1
  fi
  if [[ "${if builtins.elem "/var/lib/x-ui-yg:/usr/local/x-ui" cfg.virtualisation.oci-containers.containers.x-ui-yg.volumes then "true" else "false"}" != "true" ]]; then
    echo "错误: x-ui-yg 容器挂载路径不符合预期"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.x-ui-yg.environment.XUI_PORT}" != "54321" ]]; then
    echo "错误: x-ui-yg 环境变量 XUI_PORT 不符合预期"
    exit 1
  fi
  if [[ "${if cfg.services.nginx.virtualHosts ? "x-ui.example.com" then "true" else "false"}" != "true" ]]; then
    echo "错误: Nginx 未能正确生成 x-ui.example.com 虚拟主机配置"
    exit 1
  fi
  if [[ "${if builtins.elem { from = 10000; to = 10100; } cfg.networking.firewall.allowedTCPPortRanges then "true" else "false"}" != "false" ]]; then
    echo "错误: x-ui-yg 已设置 enable = false 的 nodes 端口范围不应在防火墙放行"
    exit 1
  fi

  # 21. 验证 v2rayA 服务配置、容器定义、持久化路径及 host 模式
  if [[ "${if cfg.virtualisation.oci-containers.containers ? v2raya then "true" else "false"}" != "true" ]]; then
    echo "错误: 应包含 v2raya 容器配置"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.v2raya.image}" != "docker.io/mzz2017/v2raya:latest" ]]; then
    echo "错误: v2raya 容器镜像不符合预期"
    exit 1
  fi
  if [[ "${if builtins.elem "--network=host" cfg.virtualisation.oci-containers.containers.v2raya.extraOptions then "true" else "false"}" != "true" ]]; then
    echo "错误: v2raya 容器应使用 --network=host 网络模式"
    exit 1
  fi
  if [[ "${if builtins.elem "--privileged" cfg.virtualisation.oci-containers.containers.v2raya.extraOptions then "true" else "false"}" != "true" ]]; then
    echo "错误: v2raya 容器应包含 --privileged 选项"
    exit 1
  fi
  if [[ "${if builtins.elem "/var/lib/v2raya:/etc/v2raya" cfg.virtualisation.oci-containers.containers.v2raya.volumes then "true" else "false"}" != "true" ]]; then
    echo "错误: v2raya 容器持久化挂载路径不符合预期 (/var/lib/v2raya:/etc/v2raya)"
    exit 1
  fi
  if [[ "${if builtins.elem "/etc/resolv.conf:/etc/resolv.conf" cfg.virtualisation.oci-containers.containers.v2raya.volumes then "true" else "false"}" != "true" ]]; then
    echo "错误: v2raya 容器 resolv.conf 挂载路径不符合预期 (/etc/resolv.conf:/etc/resolv.conf)"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.v2raya.environment.http_proxy}" != "" ]]; then
    echo "错误: v2raya 默认应禁用代理 (http_proxy 应为空)"
    exit 1
  fi
  if [[ "${cfg.virtualisation.oci-containers.containers.v2raya.environment.ALL_PROXY}" != "" ]]; then
    echo "错误: v2raya 默认应禁用代理 (ALL_PROXY 应为空)"
    exit 1
  fi
  if [[ "${if cfg.services.nginx.virtualHosts ? "v2raya.example.com" then "true" else "false"}" != "true" ]]; then
    echo "错误: Nginx 未能正确生成 v2raya.example.com 虚拟主机配置"
    exit 1
  fi
  if [[ "${if builtins.elem 2017 cfg.networking.firewall.allowedTCPPorts then "true" else "false"}" != "true" ]]; then
    echo "错误: v2raya 面板端口 2017 应在防火墙放行"
    exit 1
  fi

  # 22. 验证 AMD 显卡驱动、Early KMS、32 位支持与 ROCm OpenCL（不应隐式开启 Xserver）
  if [[ "${if cfg.services.xserver.enable then "true" else "false"}" != "false" ]]; then
    echo "错误: 未开启显卡/图形模块时 services.xserver.enable 应默认为 false"
    exit 1
  fi
  if [[ "${if cfgAmdGraphics.services.xserver.enable then "true" else "false"}" != "false" ]]; then
    echo "错误: AMD 显卡开启时不应隐式开启 services.xserver.enable"
    exit 1
  fi
  if [[ "${if builtins.elem "amdgpu" cfgAmdGraphics.services.xserver.videoDrivers then "true" else "false"}" != "true" ]]; then
    echo "错误: AMD 显卡配置应将 amdgpu 注入 services.xserver.videoDrivers"
    exit 1
  fi
  if [[ "${if builtins.elem "amdgpu" cfgAmdGraphics.boot.initrd.kernelModules then "true" else "false"}" != "true" ]]; then
    echo "错误: AMD 显卡配置应在 boot.initrd.kernelModules 中加载 amdgpu"
    exit 1
  fi
  if [[ "${if cfgAmdGraphics.hardware.graphics.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: AMD 显卡配置应自动启用 hardware.graphics.enable"
    exit 1
  fi
  if [[ "${if cfgAmdGraphics.hardware.graphics.enable32Bit then "true" else "false"}" != "true" ]]; then
    echo "错误: AMD 显卡配置应默认启用 hardware.graphics.enable32Bit"
    exit 1
  fi
  if [[ "${if builtins.elem pkgs.rocmPackages.clr.icd cfgAmdGraphics.hardware.graphics.extraPackages then "true" else "false"}" != "true" ]]; then
    echo "错误: AMD 显卡配置应在 extraPackages 中包含 rocmPackages.clr.icd"
    exit 1
  fi
  if [[ "${if cfgAmdGraphics.environment.sessionVariables ? LIBVA_DRIVER_NAME then "true" else "false"}" == "true" ]]; then
    echo "错误: AMD 显卡配置不应存在 LIBVA_DRIVER_NAME 全局污染"
    exit 1
  fi

  # 23. 验证 NVIDIA 纯独显驱动、modesetting 与 VA-API 环境变量（纯 N 卡模式下注入）
  if [[ "${if cfgNvidiaGraphics.services.xserver.enable then "true" else "false"}" != "false" ]]; then
    echo "错误: NVIDIA 显卡开启时不应隐式开启 services.xserver.enable"
    exit 1
  fi
  if [[ "${if builtins.elem "nvidia" cfgNvidiaGraphics.services.xserver.videoDrivers then "true" else "false"}" != "true" ]]; then
    echo "错误: NVIDIA 显卡配置应将 nvidia 注入 services.xserver.videoDrivers"
    exit 1
  fi
  if [[ "${if cfgNvidiaGraphics.hardware.nvidia.modesetting.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: NVIDIA 显卡配置应启用 modesetting"
    exit 1
  fi
  if [[ "${if cfgNvidiaGraphics.hardware.nvidia.open then "true" else "false"}" != "true" ]]; then
    echo "错误: NVIDIA 显卡配置应应用 open = true 设置"
    exit 1
  fi
  if [[ "${cfgNvidiaGraphics.environment.sessionVariables.LIBVA_DRIVER_NAME}" != "nvidia" ]]; then
    echo "错误: 纯 NVIDIA 显卡配置未能注入 LIBVA_DRIVER_NAME = nvidia 环境变量"
    exit 1
  fi
  if [[ "${cfgNvidiaGraphics.environment.sessionVariables.NVD_BACKEND}" != "direct" ]]; then
    echo "错误: 纯 NVIDIA 显卡配置未能注入 NVD_BACKEND = direct 环境变量"
    exit 1
  fi

  # 24. 验证 AMD + NVIDIA 混合双显卡 PRIME Offload 模式 (核心重构测试)
  if [[ "${if builtins.elem "amdgpu" cfgHybridOffload.services.xserver.videoDrivers then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应将 amdgpu 注入 videoDrivers"
    exit 1
  fi
  if [[ "${if builtins.elem "nvidia" cfgHybridOffload.services.xserver.videoDrivers then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应将 nvidia 注入 videoDrivers"
    exit 1
  fi
  if [[ "${if builtins.elem "amdgpu" cfgHybridOffload.boot.initrd.kernelModules then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应在 initrd 中加载 amdgpu (Early KMS)"
    exit 1
  fi
  if [[ "${if cfgHybridOffload.hardware.nvidia.prime.offload.enable then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应启用 PRIME offload"
    exit 1
  fi
  if [[ "${cfgHybridOffload.hardware.nvidia.prime.amdgpuBusId}" != "PCI:5:0:0" ]]; then
    echo "错误: Hybrid Offload 模式未能正确配置 prime.amdgpuBusId"
    exit 1
  fi
  if [[ "${cfgHybridOffload.hardware.nvidia.prime.nvidiaBusId}" != "PCI:1:0:0" ]]; then
    echo "错误: Hybrid Offload 模式未能正确配置 prime.nvidiaBusId"
    exit 1
  fi
  if [[ "${if cfgHybridOffload.hardware.nvidia.powerManagement.finegrained then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应默认开启 finegrained 动态电源管理"
    exit 1
  fi
  if [[ "${if cfgHybridOffload.environment.sessionVariables ? LIBVA_DRIVER_NAME then "true" else "false"}" == "true" ]]; then
    echo "错误: Hybrid Offload 模式绝不应向全局 sessionVariables 注入 LIBVA_DRIVER_NAME 污染"
    exit 1
  fi
  if [[ "${if builtins.any (p: p.name == "nvidia-offload" || (p.pname or "") == "nvidia-offload") cfgHybridOffload.environment.systemPackages then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Offload 模式应在 systemPackages 中注入 nvidia-offload 包装命令"
    exit 1
  fi

  # 25. 验证 AMD + NVIDIA 混合双显卡 Compute-Only 模式
  if [[ "${if builtins.elem "amdgpu" cfgHybridCompute.services.xserver.videoDrivers then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Compute 模式应将 amdgpu 注入 videoDrivers"
    exit 1
  fi
  if [[ "${if builtins.elem "nvidia" cfgHybridCompute.services.xserver.videoDrivers then "true" else "false"}" != "false" ]]; then
    echo "错误: Hybrid Compute 模式不应将 nvidia 注入 videoDrivers (不参与显示)"
    exit 1
  fi
  if [[ "${if builtins.elem "nvidia_uvm" cfgHybridCompute.boot.kernelModules then "true" else "false"}" != "true" ]]; then
    echo "错误: Hybrid Compute 模式应在 boot.kernelModules 中加载 nvidia_uvm 算力模块"
    exit 1
  fi

  echo "静态测试与多模式网络/显卡覆盖检查全部通过！"
  touch $out
''
