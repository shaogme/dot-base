{ pkgs, library }:
let
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
        };
        # 最小化配置以满足评估要求
        boot.loader.grub.enable = false;
        fileSystems."/".device = "/dev/dummy";
      }
    ];
  };
  cfg = eval.config;
in
pkgs.runCommand "static-check" { } ''
  echo "正在验证基础配置..."
  
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

  echo "静态检查通过！"
  touch $out
''

