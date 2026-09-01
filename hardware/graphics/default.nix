{ config, lib, pkgs, options, ... }:

with lib;

let
  cfg = config.base.hardware.graphics;

  # 状态推导标志
  isAmdActive = cfg.enable && (cfg.mode == "amd" || cfg.mode == "hybrid-amd-nvidia" || (cfg.mode == "custom" && cfg.custom.amd.enable));
  isNvidiaActive = cfg.enable && (cfg.mode == "nvidia" || cfg.mode == "hybrid-amd-nvidia" || cfg.mode == "hybrid-intel-nvidia" || (cfg.mode == "custom" && cfg.custom.nvidia.enable));
  isHybrid = cfg.enable && (cfg.mode == "hybrid-amd-nvidia" || cfg.mode == "hybrid-intel-nvidia" || (cfg.mode == "custom" && cfg.custom.isHybrid));

  isOffload = isHybrid && (cfg.hybrid.strategy == "offload");
  isSync = isHybrid && (cfg.hybrid.strategy == "sync");
  isComputeOnly = isHybrid && (cfg.hybrid.strategy == "compute-only");

  # 动态电源管理 (Dynamic D3 / Finegrained) 联动判定
  dynamicD3Enabled = isNvidiaActive && (if isHybrid then cfg.hybrid.powerManagement.dynamicD3 else cfg.nvidia.powerManagement.finegrained);

  # 独显按需渲染与局部 VA-API 包装器
  nvidiaOffloadPkg = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export VK_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json
    export LIBVA_DRIVER_NAME=nvidia
    export NVD_BACKEND=direct
    export MOZ_DISABLE_RDD_SANDBOX=1
    exec "$@"
  '';

  primeRunPkg = pkgs.writeShellScriptBin "prime-run" ''
    exec ${nvidiaOffloadPkg}/bin/nvidia-offload "$@"
  '';
in
{
  options.base.hardware.graphics = {
    enable = mkOption {
      type = types.bool;
      default = cfg.mode != "none";
      description = "是否启用图形驱动与硬件加速支持。";
    };

    mode = mkOption {
      type = types.enum [
        "none"
        "amd"
        "nvidia"
        "hybrid-amd-nvidia"
        "hybrid-intel-nvidia"
        "custom"
      ];
      default = "none";
      description = "图形硬件拓扑模式：'amd' (纯 AMD 卡), 'nvidia' (纯 NVIDIA 卡), 'hybrid-amd-nvidia' (AMD 核显 + NVIDIA 独显), 'hybrid-intel-nvidia' (Intel 核显 + NVIDIA 独显), 'custom' (高级自定义模式)。";
    };

    enable32Bit = mkOption {
      type = types.bool;
      default = true;
      description = "是否启用 32 位图形支持与加速库 (对 Steam、Wine 及 32 位应用必需)。";
    };

    hybrid = {
      strategy = mkOption {
        type = types.enum [
          "offload"
          "sync"
          "compute-only"
        ];
        default = "offload";
        description = "双显卡协同工作策略：'offload' (PRIME 渲染卸载，默认), 'sync' (PRIME 同步直连), 'compute-only' (纯算力模式，NVIDIA 仅用于 CUDA/AI 计算，不参与桌面显示)。";
      };

      integratedBusId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "集显/主显 PCI Bus ID (例如 AMD 常用 \"PCI:5:0:0\" 或 Intel \"PCI:0:2:0\")。";
      };

      discreteBusId = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "独显 PCI Bus ID (例如 \"PCI:1:0:0\")。";
      };

      powerManagement = {
        dynamicD3 = mkOption {
          type = types.bool;
          default = true;
          description = "是否启用 NVIDIA Turing 及更新架构的精细化动态电源管理 (Runtime D3cold，闲置彻底关断独显)。";
        };
      };
    };

    amd = {
      initrd = mkOption {
        type = types.bool;
        default = true;
        description = "是否在 initrd (早期内核启动阶段) 加载 amdgpu 模块 (Early KMS)，消除启动画面闪烁与撕裂。";
      };

      opencl = mkOption {
        type = types.bool;
        default = true;
        description = "是否启用 ROCm/OpenCL 运行时支持 (rocmPackages.clr.icd)。";
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "额外注入的 64 位 AMD 图形/视频加速包。";
      };

      extraPackages32 = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "额外注入的 32 位 AMD 图形/视频加速包。";
      };
    };

    nvidia = {
      modesetting = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "是否启用 modesetting 内核参数 (Wayland 合成器如 Hyprland/Sway/GNOME/KDE 必需)。";
        };
      };

      open = mkOption {
        type = types.bool;
        default = false;
        description = "是否启用 NVIDIA 开源内核模块 (nvidia-open)。Turing (RTX 20 系列) 及更新架构支持。";
      };

      powerManagement = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "是否启用电源管理 (有助于系统休眠/挂起与恢复)。";
        };

        finegrained = mkOption {
          type = types.bool;
          default = false;
          description = "是否启用精细化电源管理 (非 hybrid 模式下手动控制)。";
        };
      };

      nvidiaSettings = mkOption {
        type = types.bool;
        default = true;
        description = "是否构建并安装 nvidia-settings GUI 图形化控制面板。";
      };

      vaapi = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "是否构建并安装 nvidia-vaapi-driver 库。";
        };

        forceGlobalEnv = mkOption {
          type = types.bool;
          default = false;
          description = "是否强制将 LIBVA_DRIVER_NAME=nvidia 注入全局环境变量。在纯 NVIDIA 模式下自动生效，在 hybrid 模式下默认且建议保持 false。";
        };
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "指定 NVIDIA 驱动包。若为 null，默认使用 config.boot.kernelPackages.nvidiaPackages.stable。";
      };

      extraPackages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "额外注入的 64 位 NVIDIA 图形/视频加速包。";
      };

      extraPackages32 = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "额外注入的 32 位 NVIDIA 图形/视频加速包。";
      };
    };

    custom = {
      amd.enable = mkOption {
        type = types.bool;
        default = false;
        description = "自定义模式下是否启用 AMD 显卡驱动。";
      };
      nvidia.enable = mkOption {
        type = types.bool;
        default = false;
        description = "自定义模式下是否启用 NVIDIA 显卡驱动。";
      };
      isHybrid = mkOption {
        type = types.bool;
        default = false;
        description = "自定义模式下是否视作混合双显卡。";
      };
    };
  };

  config = mkIf (cfg.enable && !(config.base.testMode or false)) (mkMerge [
    # 1. 基础图形支持
    {
      hardware.graphics = {
        enable = true;
        enable32Bit = cfg.enable32Bit;
      };
    }

    # 2. AMD 显卡驱动配置
    (mkIf isAmdActive {
      services.xserver.videoDrivers = [ "amdgpu" ];
      boot.initrd.kernelModules = mkIf cfg.amd.initrd [ "amdgpu" ];
      hardware.graphics = {
        extraPackages = [
          pkgs.libva-vdpau-driver
          pkgs.libvdpau-va-gl
        ] ++ (optional cfg.amd.opencl pkgs.rocmPackages.clr.icd)
          ++ cfg.amd.extraPackages;

        extraPackages32 = (optionals cfg.enable32Bit [
          pkgs.pkgsi686Linux.libva-vdpau-driver
          pkgs.pkgsi686Linux.libvdpau-va-gl
        ]) ++ cfg.amd.extraPackages32;
      };
    })

    # 3. NVIDIA 显卡驱动配置
    (mkIf isNvidiaActive {
      # 当非 compute-only 模式时才将 nvidia 驱动添加到 videoDrivers
      services.xserver.videoDrivers = mkIf (!isComputeOnly) [ "nvidia" ];

      boot.kernelModules = mkIf isComputeOnly [ "nvidia" "nvidia_uvm" ];

      hardware.nvidia = {
        modesetting.enable = if isComputeOnly then false else cfg.nvidia.modesetting.enable;
        powerManagement = {
          enable = cfg.nvidia.powerManagement.enable || dynamicD3Enabled;
          finegrained = dynamicD3Enabled;
        };
        open = cfg.nvidia.open;
        nvidiaSettings = if isComputeOnly then false else cfg.nvidia.nvidiaSettings;
        package = if cfg.nvidia.package != null
          then cfg.nvidia.package
          else config.boot.kernelPackages.nvidiaPackages.stable;

        prime = mkIf (isOffload || isSync) {
          offload = {
            enable = isOffload;
            enableOffloadCmd = isOffload;
          };
          sync.enable = isSync;
          intelBusId = mkIf (cfg.mode == "hybrid-intel-nvidia" && cfg.hybrid.integratedBusId != null) cfg.hybrid.integratedBusId;
          amdgpuBusId = mkIf (cfg.mode == "hybrid-amd-nvidia" && cfg.hybrid.integratedBusId != null) cfg.hybrid.integratedBusId;
          nvidiaBusId = mkIf (cfg.hybrid.discreteBusId != null) cfg.hybrid.discreteBusId;
        };
      };

      boot.extraModprobeConfig = mkIf dynamicD3Enabled ''
        options nvidia "NVreg_DynamicPowerManagement=0x02"
      '';

      services.udev.extraRules = mkIf dynamicD3Enabled ''
        ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", ATTR{power/control}="auto"
      '';

      hardware.graphics = {
        extraPackages = (optionals cfg.nvidia.vaapi.enable [
          pkgs.nvidia-vaapi-driver
          pkgs.libva-vdpau-driver
          pkgs.libvdpau-va-gl
        ]) ++ cfg.nvidia.extraPackages;

        extraPackages32 = cfg.nvidia.extraPackages32;
      };

      # 全局环境变量注入逻辑：仅在纯 NVIDIA 模式 (mode == "nvidia") 或显式 forceGlobalEnv 时才全局注入 LIBVA_DRIVER_NAME
      environment.sessionVariables = mkIf (cfg.nvidia.vaapi.enable && (cfg.mode == "nvidia" || cfg.nvidia.vaapi.forceGlobalEnv)) {
        LIBVA_DRIVER_NAME = "nvidia";
        NVD_BACKEND = "direct";
        MOZ_DISABLE_RDD_SANDBOX = "1";
      };

      # 双显卡 Offload 模式下提供增强的包装命令
      environment.systemPackages = mkIf isOffload [
        nvidiaOffloadPkg
        primeRunPkg
      ];

    })

    # 4. 拓扑与合法性断言
    {
      assertions = [
        {
          assertion = isHybrid -> (cfg.hybrid.discreteBusId != null || cfg.hybrid.strategy == "compute-only");
          message = "base.hardware.graphics: 混合双显卡模式 (hybrid) 下必须通过 base.hardware.graphics.hybrid.discreteBusId 指定独显 PCI Bus ID (例如 \"PCI:1:0:0\")。";
        }
        {
          assertion = (cfg.mode == "hybrid-amd-nvidia" && (isOffload || isSync)) -> (cfg.hybrid.integratedBusId != null);
          message = "base.hardware.graphics: AMD+NVIDIA 混合模式下必须通过 base.hardware.graphics.hybrid.integratedBusId 指定 AMD 核显 PCI Bus ID (例如 \"PCI:5:0:0\")。";
        }
        {
          assertion = (cfg.mode == "hybrid-intel-nvidia" && (isOffload || isSync)) -> (cfg.hybrid.integratedBusId != null);
          message = "base.hardware.graphics: Intel+NVIDIA 混合模式下必须通过 base.hardware.graphics.hybrid.integratedBusId 指定 Intel 核显 PCI Bus ID (例如 \"PCI:0:2:0\")。";
        }
      ];
    }
  ]);
}
