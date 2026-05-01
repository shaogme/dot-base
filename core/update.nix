{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;
in {
  options.base.update = {
    enable = mkEnableOption "System automatic update and maintenance service";

    host = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "The hostname used for Flake builds (#hostname). Defaults to system hostname.";
    };

    path = mkOption {
      type = types.str;
      default = "";
      description = "The relative path to the configuration within the flake (e.g., 'hosts/myhost'). Defaults to the repository root.";
    };

    sync = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to enable Git sync service for pulling configuration from remote repository.";
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
      destructive = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to allow destructive modifications (git reset --hard and git clean).";
      };
      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "Sync frequency (systemd OnCalendar format).";
      };
    };

    upgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable automatic upgrades (nixos-rebuild).";
      };
      type = mkOption {
        type = types.enum [ "flake" "legacy" ];
        default = "flake";
        description = "Upgrade mode: 'flake' uses Nix Flakes, 'legacy' uses legacy NixOS paths.";
      };
      flakeUri = mkOption {
        type = types.str;
        default = "";
        description = "Manual Flake URI. If sync.enable is true, this is automatically inferred from sync.targetPath.";
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
    systemd.services.sync-config = mkIf cfg.sync.enable {
      description = "Sync NixOS configuration from Git";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.coreutils ];
      script = ''
        if [ ! -d "${cfg.sync.targetPath}/.git" ]; then
          echo "Initializing clone repository: ${cfg.sync.url} -> ${cfg.sync.targetPath}"
          mkdir -p "$(dirname "${cfg.sync.targetPath}")"
          git clone "${cfg.sync.url}" "${cfg.sync.targetPath}"
        fi
        
        cd "${cfg.sync.targetPath}"
        echo "Syncing branch ${cfg.sync.branch}..."
        
        if [ "${if cfg.sync.destructive then "1" else "0"}" = "1" ]; then
          echo "Performing destructive sync (hard reset)..."
          git fetch origin
          git reset --hard "origin/${cfg.sync.branch}"
          git clean -fd
        else
          echo "Performing non-destructive sync (pull)..."
          git pull origin "${cfg.sync.branch}"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.sync-config = mkIf cfg.sync.enable {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.sync.interval;
        RandomizedDelaySec = "5min";
      };
    };

    # --- 自动升级配置 ---
    system.autoUpgrade = mkIf cfg.upgrade.enable {
      enable = true;
      dates = cfg.upgrade.dates;
      randomizedDelaySec = cfg.upgrade.randomizedDelaySec;
      allowReboot = cfg.upgrade.allowReboot;

      flake = mkIf (cfg.upgrade.type == "flake") (
        let
          baseUri = if cfg.sync.enable then "path:${cfg.sync.targetPath}" else cfg.upgrade.flakeUri;
          pathSuffix = if cfg.path != "" then "/${cfg.path}" else "";
          hostSuffix = if cfg.host != "" then "#${cfg.host}" else "";
        in mkIf (baseUri != "") "${baseUri}${pathSuffix}${hostSuffix}"
      );

      flags = mkIf (cfg.upgrade.type == "legacy") [
        "-I" "nixos-config=${cfg.sync.targetPath}${if cfg.path != "" then "/${cfg.path}" else ""}/configuration.nix"
      ];
    };

    # --- 垃圾回收与存储优化 ---
    nix.gc = mkIf cfg.gc.enable {
      automatic = true;
      dates = cfg.gc.dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    # 如果启用了 GC，默认启用 store 优化
    nix.settings.auto-optimise-store = mkDefault true;
  };
}
