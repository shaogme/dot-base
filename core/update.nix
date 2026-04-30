{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;
in {
  options.base.update = {
    enable = mkEnableOption "System auto-update and garbage collection";
    
    git = {
      url = mkOption {
        type = types.str;
        default = "";
        description = "URL of the Git repository containing NixOS configuration";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "Branch to sync from";
      };
      configDir = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "Local directory where the configuration is stored";
      };
      dir = mkOption {
        type = types.str;
        default = ".";
        description = "Relative path within the repository where configuration.nix is located";
      };
      syncInterval = mkOption {
        type = types.str;
        default = "hourly";
        description = "Interval for syncing configuration from Git (systemd OnCalendar format)";
      };
    };

    autoUpgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Enable nixos-rebuild based on the synced configuration";
      };
      dates = mkOption {
        type = types.str;
        default = "04:00";
        description = "When to perform the auto-upgrade";
      };
      allowReboot = mkOption {
        type = types.bool;
        default = false;
        description = "Allow reboot after update";
      };
    };
  };

  config = mkIf cfg.enable {
    # --- Git 同步服务 ---
    # 定期从远程仓库拉取代码并强制重置本地状态
    systemd.services.sync-config = mkIf (cfg.git.url != "") {
      description = "Sync NixOS configuration from Git";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.coreutils ];
      script = ''
        if [ ! -d "${cfg.git.configDir}/.git" ]; then
          echo "Initial clone from ${cfg.git.url}..."
          mkdir -p "${cfg.git.configDir}"
          git clone "${cfg.git.url}" "${cfg.git.configDir}"
        fi
        cd "${cfg.git.configDir}"
        echo "Fetching and resetting to origin/${cfg.git.branch}..."
        git fetch origin
        git reset --hard "origin/${cfg.git.branch}"
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.sync-config = mkIf (cfg.git.url != "") {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.git.syncInterval;
        RandomizedDelaySec = "5min";
      };
    };

    # --- 自动更新配置 (nixos-rebuild) ---
    system.autoUpgrade = mkIf cfg.autoUpgrade.enable {
      enable = true;
      dates = cfg.autoUpgrade.dates;
      allowReboot = cfg.autoUpgrade.allowReboot;
      
      # 非 Flake 模式：通过 flags 注入本地配置路径 (支持子目录)
      flags = [
        "-I" "nixos-config=${cfg.git.configDir}/${cfg.git.dir}/configuration.nix"
      ];
    };

    # --- 垃圾回收与存储优化 ---
    nix.gc = {
      automatic = true;
      dates = "weekly"; # 每周执行
      options = "--delete-older-than 30d"; # 删除 30 天前的旧版本
    };
  };
}
