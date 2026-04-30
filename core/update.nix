{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;
in {
  options.base.update = {
    enable = mkEnableOption "System automatic update and maintenance service";

    type = mkOption {
      type = types.enum [ "flake" "legacy" ];
      default = "flake";
      description = "Update mode: 'flake' uses Nix Flakes, 'legacy' uses legacy NixOS paths.";
    };

    flake = {
      uri = mkOption {
        type = types.str;
        default = "";
        example = "github:owner/repo#host";
        description = "Flake URI. If empty and type is 'flake', the default path will be used.";
      };
    };

    git = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Git sync service for pulling configuration from remote repository to local path.";
      };
      url = mkOption {
        type = types.str;
        default = "";
        description = "Remote Git repository URL.";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "The name of the branch to sync.";
      };
      targetPath = mkOption {
        type = types.str;
        default = "/etc/nixos";
        description = "Absolute path to sync to locally.";
      };
      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "Sync frequency (systemd OnCalendar format).";
      };
    };

    autoUpgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable automatic upgrades (nixos-rebuild).";
      };
      dates = mkOption {
        type = types.str;
        default = "04:00";
        description = "The time at which automatic upgrades are performed.";
      };
      randomizedDelaySec = mkOption {
        type = types.str;
        default = "1h";
        description = "Random delay time for upgrades to avoid many machines updating at the same time.";
      };
      allowReboot = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to allow automatic reboot if the kernel changes after upgrade.";
      };
    };

    gc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable Nix garbage collection.";
      };
      dates = mkOption {
        type = types.str;
        default = "weekly";
        description = "Frequency of garbage collection.";
      };
      olderThan = mkOption {
        type = types.str;
        default = "7d";
        description = "Delete generations older than this number of days.";
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
          echo "Initializing clone repository: ${cfg.git.url} -> ${cfg.git.targetPath}"
          mkdir -p "$(dirname "${cfg.git.targetPath}")"
          git clone "${cfg.git.url}" "${cfg.git.targetPath}"
        fi
        cd "${cfg.git.targetPath}"
        echo "Syncing branch ${cfg.git.branch}..."
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
