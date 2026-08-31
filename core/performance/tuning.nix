{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.performance.tuning;
in {
  options.base.performance.tuning = {
    enable = mkOption {
      type = types.bool;
      default = cfg.profile != "none";
      defaultText = literalExpression "config.base.performance.tuning.profile != \"none\"";
      description = "Whether to enable TuneD performance tuning.";
    };

    profile = mkOption {
      type = types.enum [
        "none"
        "vps"
        "desktop"
        "desktop-performance"
        "desktop-powersave"
      ];
      default = "none";
      description = ''
        Tuned performance profile preset:
        - `vps`: Tailored for VPS / virtual machines (disables PPD, recommends virtual-guest profile).
        - `desktop`: Balanced desktop profile with power-profiles-daemon (PPD) support.
        - `desktop-performance`: High throughput performance profile for desktops / workstations.
        - `desktop-powersave`: Power saving profile for desktops / laptops.
        - `none`: No predefined profile preset applied.
      '';
    };

    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "The tuned package to use (overrides services.tuned.package).";
    };

    ppdSettings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Settings for TuneD's power-profiles-daemon compatibility service.";
    };

    ppdSupport = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Whether to enable translation of power-profiles-daemon API calls to TuneD.";
    };

    profiles = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Profiles for TuneD. See tuned.conf(5) for details.";
    };

    recommend = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "TuneD rules for recommend_profile, written to /etc/tuned/recommend.conf.";
    };

    settings = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      description = "Configuration for TuneD. See tuned-main.conf(5) for details.";
    };
  };

  config = mkIf cfg.enable {
    services.tuned = mkMerge [
      # 1. 基础服务开关与包定制
      {
        enable = true;
      }
      (mkIf (cfg.package != null) {
        package = cfg.package;
      })

      # 2. ppdSupport 设置
      (mkIf (cfg.ppdSupport != null) {
        ppdSupport = cfg.ppdSupport;
      })

      # 3. 各预设 Profile 配置
      # --- VPS / 虚拟机优化模式 ---
      (mkIf (cfg.profile == "vps") {
        ppdSupport = mkDefault false;
        recommend = {
          "virtual-guest" = mkDefault { };
        };
      })

      # --- Desktop 桌面平衡模式 ---
      (mkIf (cfg.profile == "desktop") {
        ppdSupport = mkDefault true;
        ppdSettings = {
          main = {
            default = mkDefault "balanced";
            battery_detection = mkDefault true;
          };
          profiles = {
            power-saver = mkDefault "desktop-powersave";
            balanced = mkDefault "desktop";
            performance = mkDefault "throughput-performance";
          };
        };
        recommend = {
          desktop = mkDefault { };
        };
      })

      # --- Desktop-Performance 桌面高性能模式 ---
      (mkIf (cfg.profile == "desktop-performance") {
        ppdSupport = mkDefault true;
        ppdSettings = {
          main = {
            default = mkDefault "performance";
            battery_detection = mkDefault true;
          };
          profiles = {
            power-saver = mkDefault "powersave";
            balanced = mkDefault "desktop";
            performance = mkDefault "throughput-performance";
          };
        };
        recommend = {
          "throughput-performance" = mkDefault { };
        };
      })

      # --- Desktop-Powersave 桌面省电模式 ---
      (mkIf (cfg.profile == "desktop-powersave") {
        ppdSupport = mkDefault true;
        ppdSettings = {
          main = {
            default = mkDefault "power-saver";
            battery_detection = mkDefault true;
          };
          profiles = {
            power-saver = mkDefault "desktop-powersave";
            balanced = mkDefault "balanced-battery";
            performance = mkDefault "desktop";
          };
        };
        recommend = {
          "desktop-powersave" = mkDefault { };
        };
      })

      # 4. 通用配置透传
      (mkIf (cfg.profiles != { }) {
        profiles = cfg.profiles;
      })
      (mkIf (cfg.settings != { }) {
        settings = cfg.settings;
      })
      (mkIf (cfg.recommend != { }) {
        recommend = cfg.recommend;
      })
      (mkIf (cfg.ppdSettings != { }) {
        ppdSettings = cfg.ppdSettings;
      })
    ];
  };
}
