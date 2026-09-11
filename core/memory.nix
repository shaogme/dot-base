{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.base.memory;

  # 1. 计算实际生效的内存优化机制
  effectiveType =
    if cfg.type != "auto" then cfg.type
    else if (config.swapDevices or []) != [ ] then "zswap"
    else "zram";

  isZram = cfg.enable && effectiveType == "zram" && cfg.mode != "none";
  isZswap = cfg.enable && effectiveType == "zswap" && cfg.mode != "none";

  # 2. 档位预设参数字典
  modePresets = {
    aggressive = {
      zramPercent = 100;
      zswapPercent = 40;
      swappiness = 150;
      vfsCachePressure = 50;
      dirtyBackgroundBytes = null;
      dirtyBytes = null;
      panicOnOom = null;
      cores = 1;
      maxJobs = 1;
    };
    balanced = {
      zramPercent = 80;
      zswapPercent = 30;
      swappiness = 120;
      vfsCachePressure = 65;
      dirtyBackgroundBytes = "16777216";
      dirtyBytes = "50331648";
      panicOnOom = null;
      cores = 2;
      maxJobs = 1;
    };
    conservative = {
      zramPercent = 50;
      zswapPercent = 20;
      swappiness = 80;
      vfsCachePressure = 100;
      dirtyBackgroundBytes = null;
      dirtyBytes = null;
      panicOnOom = 0;
      cores = 0;
      maxJobs = 2;
    };
  };

  currentPreset = modePresets.${cfg.mode} or null;
in {
  options.base.memory = {
    enable = mkOption {
      type = types.bool;
      default = cfg.mode != "none" && cfg.type != "none";
      description = "Whether to enable base memory optimization.";
    };

    type = mkOption {
      type = types.enum [ "auto" "zswap" "zram" "none" ];
      default = "auto";
      description = ''
        Memory swap compression mechanism:
        - `zswap`: In-memory compressed cache for physical swap device (requires swapDevices).
        - `zram`: In-memory virtual compressed swap device (pure RAM, swapless).
        - `auto`: Automatically use zswap if swapDevices are configured, else fall back to zram.
        - `none`: Completely disable compressed swap mechanism.
      '';
    };

    mode = mkOption {
      type = types.enum [ "aggressive" "balanced" "conservative" "none" ];
      default = "none";
      description = "Memory optimization mode: aggressive (<1G), balanced (<2G), conservative (>=4G), or none.";
    };

    zram = {
      algorithm = mkOption {
        type = types.str;
        default = "zstd";
        description = "Compression algorithm for zram.";
      };
      priority = mkOption {
        type = types.int;
        default = 100;
        description = "Swap priority for zram device.";
      };
      memoryPercent = mkOption {
        type = types.nullOr (types.ints.between 1 200);
        default = null;
        description = "Override percentage of total RAM for zram (null uses mode preset).";
      };
    };

    zswap = {
      compressor = mkOption {
        type = types.enum [ "zstd" "lz4" "lzo" "lz4hc" "deflate" "842" ];
        default = "zstd";
        description = "Kernel compression algorithm for zswap.";
      };
      zpool = mkOption {
        type = types.enum [ "zsmalloc" "zbud" ];
        default = "zsmalloc";
        description = "Kernel pool allocator for zswap.";
      };
      maxPoolPercent = mkOption {
        type = types.nullOr (types.ints.between 1 100);
        default = null;
        description = "Override max RAM pool percentage for zswap (null uses mode preset).";
      };
      shrinkerEnabled = mkOption {
        type = types.bool;
        default = true;
        description = "Enable zswap shrinker to write back cold pages to physical swap under memory pressure.";
      };
      acceptThresholdPercent = mkOption {
        type = types.ints.between 1 100;
        default = 90;
        description = "Threshold percentage to resume accepting pages into zswap.";
      };
    };
  };

  config = mkMerge [
    # 1. 静态断言约束
    {
      assertions = [
        {
          assertion = isZswap -> (config.swapDevices or [ ]) != [ ];
          message = ''
            [base.memory] 配置错误：启用了 zswap 机制，但未检测到任何可用的物理 Swap 设备 (config.swapDevices 为空)。
            zswap 必须作为物理 Swap 分区或文件的缓存运行。
            请通过 exts.hardware.disk.btrfs.swapSize 配置物理 Swap 分区，或将 base.memory.type 设为 "zram"。
          '';
        }
        {
          assertion = !(config.zramSwap.enable && config.boot.zswap.enable);
          message = "[base.memory] 互斥冲突：zramSwap 与 boot.zswap 绝不能同时启用，否则会导致严重的内存管理开销和双重压缩。";
        }
      ];
    }

    # 2. 全局通用基线（启用优化时均应用）
    (mkIf (cfg.enable && cfg.mode != "none" && effectiveType != "none") {
      boot.kernelParams = [ "lru_gen_enabled=1" ]; # MGLRU
      systemd.oomd.enable = false;

      # 内核通用 sysctl
      boot.kernel.sysctl = mkMerge [
        (mkIf (currentPreset != null) {
          "vm.swappiness" = currentPreset.swappiness;
          "vm.vfs_cache_pressure" = currentPreset.vfsCachePressure;
        })
        (mkIf (currentPreset != null && currentPreset.dirtyBackgroundBytes != null) {
          "vm.dirty_background_bytes" = currentPreset.dirtyBackgroundBytes;
        })
        (mkIf (currentPreset != null && currentPreset.dirtyBytes != null) {
          "vm.dirty_bytes" = currentPreset.dirtyBytes;
        })
        (mkIf (currentPreset != null && currentPreset.panicOnOom != null) {
          "vm.panic_on_oom" = currentPreset.panicOnOom;
        })
      ];

      # Nix 构建并行度限制
      nix.settings = mkIf (currentPreset != null) {
        cores = currentPreset.cores;
        max-jobs = currentPreset.maxJobs;
      };
    })

    # 3. zram 生效路径
    (mkIf isZram {
      zramSwap = {
        enable = true;
        algorithm = cfg.zram.algorithm;
        priority = cfg.zram.priority;
        memoryPercent =
          if cfg.zram.memoryPercent != null then cfg.zram.memoryPercent
          else currentPreset.zramPercent;
      };
    })

    # 4. zswap 生效路径 (直接对接 NixOS 原生 boot.zswap 模块)
    (mkIf isZswap {
      # 确保 zramSwap 完全关闭
      zramSwap.enable = mkForce false;

      boot.zswap = {
        enable = true;
        compressor = cfg.zswap.compressor;
        zpool = cfg.zswap.zpool;
        maxPoolPercent =
          if cfg.zswap.maxPoolPercent != null then cfg.zswap.maxPoolPercent
          else currentPreset.zswapPercent;
        shrinkerEnabled = cfg.zswap.shrinkerEnabled;
        acceptThresholdPercent = cfg.zswap.acceptThresholdPercent;
      };
    })
  ];
}
