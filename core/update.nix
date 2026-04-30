{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;
in {
  options.base.update = {
    enable = mkEnableOption "系统自动更新与维护服务";

    type = mkOption {
      type = types.enum [ "flake" "legacy" ];
      default = "flake";
      description = "更新模式：'flake' 使用 Nix Flakes, 'legacy' 使用传统 NixOS 路径。";
    };

    flake = {
      uri = mkOption {
        type = types.str;
        default = "";
        example = "github:owner/repo#host";
        description = "Flake URI。如果为空且 type 为 'flake'，将使用默认路径。";
      };
    };

    git = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "是否启用 Git 同步服务，用于从远程仓库拉取配置到本地路径。";
      };
      url = mkOption {
        type = types.str;
        default = "";
        description = "远程 Git 仓库地址。";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "同步的分支名称。";
      };
      targetPath = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "同步到本地的绝对路径。";
      };
      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "同步频率 (systemd OnCalendar 格式)。";
      };
    };

    autoUpgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "是否启用自动升级 (nixos-rebuild)。";
      };
      dates = mkOption {
        type = types.str;
        default = "04:00";
        description = "执行自动升级的时间点。";
      };
      randomizedDelaySec = mkOption {
        type = types.str;
        default = "1h";
        description = "随机延迟升级的时间，避免大量机器同时更新。";
      };
      allowReboot = mkOption {
        type = types.bool;
        default = false;
        description = "升级后如果内核变更是否允许自动重启。";
      };
    };

    gc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "是否启用 Nix 垃圾回收。";
      };
      dates = mkOption {
        type = types.str;
        default = "weekly";
        description = "执行垃圾回收的频率。";
      };
      olderThan = mkOption {
        type = types.str;
        default = "7d";
        description = "删除早于此天数的生成版本 (generations)。";
      };
    };
  };

  config = mkIf cfg.enable {
    # --- Git 同步服务 ---
    systemd.services.sync-config = mkIf cfg.git.enable {
      description = "Sync NixOS configuration from Git";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.coreutils ];
      script = ''
        if [ ! -d "${cfg.git.targetPath}/.git" ]; then
          echo "初始化克隆仓库: ${cfg.git.url} -> ${cfg.git.targetPath}"
          mkdir -p "$(dirname "${cfg.git.targetPath}")"
          git clone "${cfg.git.url}" "${cfg.git.targetPath}"
        fi
        cd "${cfg.git.targetPath}"
        echo "正在同步分支 ${cfg.git.branch}..."
        git fetch origin
        git reset --hard "origin/${cfg.git.branch}"
        git clean -fd
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.sync-config = mkIf cfg.git.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.git.interval;
        RandomizedDelaySec = "5min";
      };
    };

    # --- 自动升级配置 ---
    system.autoUpgrade = mkIf cfg.autoUpgrade.enable {
      enable = true;
      dates = cfg.autoUpgrade.dates;
      randomizedDelaySec = cfg.autoUpgrade.randomizedDelaySec;
      allowReboot = cfg.autoUpgrade.allowReboot;
      
      flake = mkIf (cfg.type == "flake" && cfg.flake.uri != "") cfg.flake.uri;
      
      flags = mkIf (cfg.type == "legacy") [
        "-I" "nixos-config=${cfg.git.targetPath}/configuration.nix"
      ];
    };

    # --- 垃圾回收与存储优化 ---
    nix.gc = mkIf cfg.gc.enable {
      automatic = true;
      dates = cfg.gc.dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    # 进一步优化：如果启用了 GC，通常也希望启用 store 优化
    nix.settings.auto-optimise-store = mkDefault true;
  };
}
