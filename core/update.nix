{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.update;

  # 1. 计算路径与 URI
  syncTarget = cfg.sync.targetPath;
  configSubpath = if cfg.path != "" then "/${cfg.path}" else "";
  hostSuffix = if cfg.host != "" then "#${cfg.host}" else "";

  inferredFlakeUri =
    if cfg.upgrade.flakeUri != "" then
      cfg.upgrade.flakeUri
    else if cfg.sync.enable || cfg.sync.targetPath != "" then
      "path:${syncTarget}${configSubpath}${hostSuffix}"
    else
      "";

  legacyConfigPath = "${syncTarget}${configSubpath}/configuration.nix";
  nixpkgsPath = builtins.path { name = "nixpkgs"; path = pkgs.path; };

  # 2. 生成核心更新执行脚本
  updateScript = pkgs.writeShellScriptBin cfg.command.name ''
    set -euo pipefail

    # ANSI Colors
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'

    log_info() { echo -e "''${BLUE}==>''${NC} ''${BOLD}$*''${NC}"; }
    log_success() { echo -e "''${GREEN}==> SUCCESS:''${NC} $*"; }
    log_warn() { echo -e "''${YELLOW}==> WARNING:''${NC} $*"; }
    log_error() { echo -e "''${RED}==> ERROR:''${NC} $*" >&2; }

    # 默认配置（由 Nix 模块定义）
    DEFAULT_DO_PULL="${if cfg.upgrade.pullBeforeUpdate then "1" else "0"}"
    SYNC_ENABLED="${if cfg.sync.enable then "1" else "0"}"
    SYNC_URL="${cfg.sync.url}"
    SYNC_BRANCH="${cfg.sync.branch}"
    SYNC_TARGET="${cfg.sync.targetPath}"
    SYNC_DESTRUCTIVE="${if cfg.sync.destructive then "1" else "0"}"
    UPGRADE_TYPE="${cfg.upgrade.type}"
    FLAKE_URI="${inferredFlakeUri}"
    LEGACY_CONFIG="${legacyConfigPath}"
    NIXPKGS_PATH="${nixpkgsPath}"
    DEFAULT_ACTION="${cfg.upgrade.action}"
    DEFAULT_ALLOW_REBOOT="${if cfg.upgrade.allowReboot then "1" else "0"}"
    EXTRA_FLAGS=(${lib.escapeShellArgs cfg.upgrade.extraFlags})

    DO_PULL="$DEFAULT_DO_PULL"
    ACTION="$DEFAULT_ACTION"
    ALLOW_REBOOT="$DEFAULT_ALLOW_REBOOT"
    SYNC_ONLY=0
    RUN_AS_SERVICE=0

    show_help() {
      cat <<EOF
Usage: ${cfg.command.name} [OPTIONS]

NixOS System Upgrade & Maintenance Utility (${cfg.upgrade.type} mode)

Options:
  -p, --pull          Pull/sync remote git repository before rebuilding
  -n, --no-pull       Do NOT pull git repository (build local changes directly) [DEFAULT]
  -s, --sync-only     Only perform git synchronization, do not rebuild system
  -a, --action <ACT>  Set rebuild action: switch, boot, test, build, dry-activate (Default: $DEFAULT_ACTION)
  -b, --boot          Shortcut for --action boot
  -t, --test          Shortcut for --action test
  -d, --dry-run       Shortcut for --action dry-activate
  -r, --reboot        Reboot system if kernel changed after upgrade
      --no-reboot     Do not reboot system even if kernel changed
      --service       Delegate execution to background systemd service (base-upgrade.service)
  -h, --help          Show this help message

Configuration Summary:
  Target Host:        ${cfg.host}
  Mode:               ${cfg.upgrade.type}
  Flake URI:          ''${FLAKE_URI:-"(none)"}
  Sync Path:          $SYNC_TARGET (Enabled: $SYNC_ENABLED)
  Default Pull:       $([ "$DEFAULT_DO_PULL" = "1" ] && echo "Yes" || echo "No")
  Default Action:     $DEFAULT_ACTION
  Auto-Reboot:        $([ "$DEFAULT_ALLOW_REBOOT" = "1" ] && echo "Yes" || echo "No")
EOF
    }

    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -p|--pull)
          DO_PULL=1
          shift
          ;;
        -n|--no-pull)
          DO_PULL=0
          shift
          ;;
        -s|--sync-only)
          SYNC_ONLY=1
          shift
          ;;
        -a|--action)
          if [[ $# -lt 2 ]]; then
            log_error "Option --action requires an argument."
            exit 1
          fi
          ACTION="$2"
          shift 2
          ;;
        -b|--boot)
          ACTION="boot"
          shift
          ;;
        -t|--test)
          ACTION="test"
          shift
          ;;
        -d|--dry-run)
          ACTION="dry-activate"
          shift
          ;;
        -r|--reboot)
          ALLOW_REBOOT=1
          shift
          ;;
        --no-reboot)
          ALLOW_REBOOT=0
          shift
          ;;
        --service)
          RUN_AS_SERVICE=1
          shift
          ;;
        --service-mode)
          # 内部由 systemd service 调用的模式
          shift
          ;;
        -h|--help)
          show_help
          exit 0
          ;;
        *)
          log_error "Unknown argument: $1"
          show_help >&2
          exit 1
          ;;
      esac
    done

    # 检查 root 权限
    if [ "$EUID" -ne 0 ]; then
      log_warn "This command requires root privileges. Elevating with sudo..."
      exec sudo "$0" "$@"
    fi

    # 如果指定通过服务运行
    if [ "$RUN_AS_SERVICE" -eq 1 ]; then
      log_info "Triggering base-upgrade.service via systemctl..."
      systemctl start base-upgrade.service
      log_info "Streaming service logs (Press Ctrl+C to exit log streaming)..."
      exec journalctl -u base-upgrade.service -f -n 50
    fi

    # 获取全局文件锁，防止并发执行
    LOCK_FILE="/run/lock/dot-update.lock"
    mkdir -p "$(dirname "$LOCK_FILE")"
    exec 200>"$LOCK_FILE"
    if ! ${pkgs.flock}/bin/flock -n 200; then
      log_error "Another update or sync process is currently running. Exiting."
      exit 1
    fi

    log_info "Starting system maintenance on host [${cfg.host}]..."

    # --- 1. Git 同步阶段 ---
    if [ "$DO_PULL" -eq 1 ] || [ "$SYNC_ONLY" -eq 1 ]; then
      if [ "$SYNC_ENABLED" -ne 1 ]; then
        log_warn "Git sync is not enabled in configuration, skipping git pull."
      elif [ -z "$SYNC_URL" ]; then
        log_warn "Git sync URL is empty, skipping git pull."
      else
        log_info "Synchronizing repository from $SYNC_URL (branch: $SYNC_BRANCH)..."
        if [ ! -d "$SYNC_TARGET/.git" ]; then
          log_info "Initializing repository clone: $SYNC_URL -> $SYNC_TARGET"
          mkdir -p "$(dirname "$SYNC_TARGET")"
          ${pkgs.git}/bin/git clone "$SYNC_URL" "$SYNC_TARGET"
        fi

        cd "$SYNC_TARGET"
        if [ "$SYNC_DESTRUCTIVE" -eq 1 ]; then
          log_info "Performing destructive sync (fetch + reset --hard origin/$SYNC_BRANCH)..."
          ${pkgs.git}/bin/git fetch origin
          ${pkgs.git}/bin/git reset --hard "origin/$SYNC_BRANCH"
          ${pkgs.git}/bin/git clean -fd
        else
          log_info "Performing safe git pull origin $SYNC_BRANCH..."
          ${pkgs.git}/bin/git pull origin "$SYNC_BRANCH"
        fi
        log_success "Git repository synchronized successfully."
      fi
    else
      log_info "Skipping git pull (building local changes directly)."
    fi

    if [ "$SYNC_ONLY" -eq 1 ]; then
      log_success "Sync completed successfully (--sync-only)."
      exit 0
    fi

    # --- 2. NixOS Rebuild 构建与激活阶段 ---
    BOOTED_KERNEL=""
    if [ -e "/run/booted-system/kernel" ]; then
      BOOTED_KERNEL="$(readlink -f /run/booted-system/kernel 2>/dev/null || true)"
    fi

    log_info "Executing nixos-rebuild $ACTION (Mode: $UPGRADE_TYPE)..."

    if [ "$UPGRADE_TYPE" = "flake" ]; then
      if [ -z "$FLAKE_URI" ]; then
        log_error "Flake URI is not configured and cannot be inferred!"
        exit 1
      fi
      log_info "Target Flake URI: $FLAKE_URI"
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$ACTION" --flake "$FLAKE_URI" "''${EXTRA_FLAGS[@]}"
    elif [ "$UPGRADE_TYPE" = "legacy" ]; then
      log_info "Target Legacy Config: $LEGACY_CONFIG"
      ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$ACTION" \
        -I "nixos-config=$LEGACY_CONFIG" \
        -I "nixpkgs=$NIXPKGS_PATH" \
        "''${EXTRA_FLAGS[@]}"
    else
      log_error "Unknown upgrade type: $UPGRADE_TYPE"
      exit 1
    fi

    log_success "System rebuild ($ACTION) finished successfully!"

    # --- 3. 内核检测与自动重启 ---
    if [ "$ACTION" = "switch" ] || [ "$ACTION" = "boot" ]; then
      if [ -n "$BOOTED_KERNEL" ] && [ -e "/nix/var/nix/profiles/system/kernel" ]; then
        NEW_KERNEL="$(readlink -f /nix/var/nix/profiles/system/kernel 2>/dev/null || true)"
        if [ -n "$NEW_KERNEL" ] && [ "$BOOTED_KERNEL" != "$NEW_KERNEL" ]; then
          log_warn "Kernel update detected! Current booted: $BOOTED_KERNEL, New: $NEW_KERNEL"
          if [ "$ALLOW_REBOOT" -eq 1 ]; then
            log_warn "System is configured to reboot automatically. Rebooting in 5 seconds..."
            sleep 5
            ${pkgs.systemd}/bin/systemctl reboot
          else
            log_warn "Please reboot your system when convenient to apply the new kernel."
          fi
        fi
      fi
    fi
  '';

  # 3. 注入别名软件包
  updateCliPackages = pkgs.runCommand "dot-update-cli" { } ''
    mkdir -p $out/bin
    cp ${updateScript}/bin/${cfg.command.name} $out/bin/${cfg.command.name}
    ${concatMapStringsSep "\n" (alias: ''
      ln -sf $out/bin/${cfg.command.name} $out/bin/${alias}
    '') cfg.command.aliases}
  '';

in {
  options.base.update = {
    enable = mkEnableOption "Base update and maintenance subsystem";

    host = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "The target hostname used for Flake builds (#hostname) or directory layout.";
    };

    path = mkOption {
      type = types.str;
      default = "";
      description = "The relative subpath within the repository to the host configuration.";
    };

    sync = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Whether Git repository sync capability is configured.";
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
        description = "Local absolute filesystem path where configuration repository is located.";
      };
      destructive = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to allow destructive modifications (git reset --hard and git clean -fd).";
      };
      interval = mkOption {
        type = types.str;
        default = "hourly";
        description = "Periodic sync timer schedule (systemd OnCalendar format).";
      };
      timer = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "Whether to enable periodic background Git sync timer.";
        };
      };
    };

    upgrade = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable system upgrade capabilities (CLI update command and systemd service).
          When set to false, the base-upgrade service is completely disabled and CLI update commands are removed from PATH.
        '';
      };

      type = mkOption {
        type = types.enum [ "flake" "legacy" ];
        default = "flake";
        description = "Upgrade mode: 'flake' uses Nix Flakes, 'legacy' uses legacy NixOS channels/NIX_PATH.";
      };

      action = mkOption {
        type = types.enum [ "switch" "boot" "test" "build" "dry-activate" ];
        default = "switch";
        description = "Default rebuild action performed during upgrade.";
      };

      pullBeforeUpdate = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to pull/sync Git repository before executing upgrade by default. Defaults to false.";
      };

      flakeUri = mkOption {
        type = types.str;
        default = "";
        description = "Explicit Flake URI. If empty and sync is configured, inferred from sync.targetPath.";
      };

      extraFlags = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments passed directly to nixos-rebuild.";
      };

      allowReboot = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to automatically reboot if the kernel has changed after upgrade.";
      };

      timer = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Whether to enable scheduled periodic automatic upgrades (Systemd Timer).
            When false, automatic periodic execution is disabled, but manual execution via CLI or systemd service remains available as long as upgrade.enable is true.
          '';
        };

        dates = mkOption {
          type = types.str;
          default = "04:00";
          description = "Schedule for automatic upgrades (systemd OnCalendar format).";
        };

        randomizedDelaySec = mkOption {
          type = types.str;
          default = "1h";
          description = "Random delay for scheduled automatic upgrades to prevent thundering herd.";
        };
      };
    };

    command = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to install the manual update CLI command in system PATH (requires upgrade.enable = true).";
      };

      name = mkOption {
        type = types.str;
        default = "dot-update";
        description = "Primary binary name for the update CLI utility.";
      };

      aliases = mkOption {
        type = types.listOf types.str;
        default = [ "base-update" "nixos-update" ];
        description = "Symlink aliases created in PATH for the update CLI utility.";
      };
    };

    gc = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to enable automatic Nix store garbage collection.";
      };
      dates = mkOption {
        type = types.str;
        default = "weekly";
        description = "Schedule of garbage collection.";
      };
      olderThan = mkOption {
        type = types.str;
        default = "7d";
        description = "Delete generations older than this timeframe.";
      };
    };
  };

  config = mkIf (cfg.enable && !config.base.testMode) {
    # 1. 向系统 PATH 注入 CLI 命令及别名（仅当 upgrade.enable 且 command.enable 时注入）
    environment.systemPackages = mkIf (cfg.upgrade.enable && cfg.command.enable) [
      updateCliPackages
    ];

    # 2. 独立的 Git 定时同步服务 (可选)
    systemd.services.sync-config = mkIf (cfg.sync.enable && cfg.sync.timer.enable) {
      description = "Periodic sync NixOS configuration from Git";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.coreutils ];
      script = ''
        if [ ! -d "${cfg.sync.targetPath}/.git" ]; then
          mkdir -p "$(dirname "${cfg.sync.targetPath}")"
          git clone "${cfg.sync.url}" "${cfg.sync.targetPath}"
        fi
        cd "${cfg.sync.targetPath}"
        if [ "${if cfg.sync.destructive then "1" else "0"}" = "1" ]; then
          git fetch origin
          git reset --hard "origin/${cfg.sync.branch}"
          git clean -fd
        else
          git pull origin "${cfg.sync.branch}"
        fi
      '';
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
    };

    systemd.timers.sync-config = mkIf (cfg.sync.enable && cfg.sync.timer.enable) {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.sync.interval;
        RandomizedDelaySec = "5min";
      };
    };

    # 3. 系统升级 Service (仅当 upgrade.enable = true 时注册)
    systemd.services.base-upgrade = mkIf cfg.upgrade.enable {
      description = "Base NixOS System Upgrade Service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.git pkgs.nixos-rebuild pkgs.nix pkgs.coreutils pkgs.systemd pkgs.flock ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        ExecStart = "${updateScript}/bin/${cfg.command.name} --service-mode";
        StandardOutput = "journal+console";
        StandardError = "journal+console";
      };
    };

    # 4. 系统升级 Timer (独立子配置项：仅当 upgrade.enable && upgrade.timer.enable 时激活)
    systemd.timers.base-upgrade = mkIf (cfg.upgrade.enable && cfg.upgrade.timer.enable) {
      description = "Base NixOS Scheduled Automatic Upgrade Timer";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.upgrade.timer.dates;
        RandomizedDelaySec = cfg.upgrade.timer.randomizedDelaySec;
        Persistent = true;
      };
    };

    # 5. Nix 垃圾回收与存储优化
    nix.gc = mkIf cfg.gc.enable {
      automatic = true;
      dates = cfg.gc.dates;
      options = "--delete-older-than ${cfg.gc.olderThan}";
    };

    nix.settings.auto-optimise-store = mkDefault true;
  };
}
