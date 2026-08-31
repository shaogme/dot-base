{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.base.hardware.graphics;
in
{
  options.base.hardware.graphics = {
    enable = mkOption {
      type = types.bool;
      default = cfg.amd.enable || cfg.nvidia.enable;
      description = "是否启用图形驱动与硬件加速支持。当 amd.enable 或 nvidia.enable 为 true 时自动启用。";
    };

    enable32Bit = mkOption {
      type = types.bool;
      default = true;
      description = "是否启用 32 位图形支持与加速库 (对 Steam、Wine 及 32 位应用必需)。";
    };

    amd = {
      enable = mkEnableOption "AMD 显卡驱动与硬件加速支持";

      initrd = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "是否在 initrd (早期内核启动阶段) 加载 amdgpu 模块 (Early KMS)，可消除启动阶段画面闪烁与撕裂。";
        };
      };

      opencl = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "是否启用 ROCm/OpenCL 运行时支持 (用于 Blender、DaVinci Resolve 等图形与计算软件加速)。";
        };
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
      enable = mkEnableOption "NVIDIA 显卡驱动与硬件加速支持";

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
        description = "是否启用 NVIDIA 开源内核模块 (nvidia-open)。Turing (RTX 20 系列) 及更新架构支持；旧架构或需要特定专有功能建议保持 false。";
      };

      powerManagement = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "是否启用电源管理 (有助于系统休眠/挂起与恢复)。";
        };

        finegrained = mkOption {
          type = types.bool;
          default = false;
          description = "是否启用精细化电源管理 (适用于 Turing+ 架构双显卡笔记本，可在空闲时完全关闭独显电源)。";
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
          description = "是否启用 nvidia-vaapi-driver 及相关环境变量 (Direct 后端)，提升浏览器 (Firefox/Chrome) 与媒体播放器的硬件视频解码性能。";
        };
      };

      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        description = "指定 NVIDIA 驱动包。若为 null，默认使用 config.boot.kernelPackages.nvidiaPackages.stable。";
      };

      prime = {
        offload = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "是否启用 PRIME 渲染卸载模式 (适用于双显卡笔记本，默认使用集显，按需通过 prime-run / nvidia-offload 运行独显)。";
          };
        };

        sync = {
          enable = mkOption {
            type = types.bool;
            default = false;
            description = "是否启用 PRIME 同步模式 (独显始终工作以换取最高性能)。";
          };
        };

        intelBusId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Intel 集显 PCI Bus ID (例如 \"PCI:0:2:0\")。";
        };

        amdgpuBusId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "AMD 集显 PCI Bus ID (例如 \"PCI:5:0:0\")。";
        };

        nvidiaBusId = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "NVIDIA 独显 PCI Bus ID (例如 \"PCI:1:0:0\")。";
        };
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
  };

  config = mkIf (cfg.enable && !(config.base.testMode or false)) (mkMerge [
    {
      services.xserver.enable = mkDefault true;
      hardware.graphics = {
        enable = true;
        enable32Bit = cfg.enable32Bit;
      };
    }

    (mkIf cfg.amd.enable {
      services.xserver.videoDrivers = [ "amdgpu" ];
      boot.initrd.kernelModules = mkIf cfg.amd.initrd.enable [ "amdgpu" ];
      hardware.graphics = {
        extraPackages = [
          pkgs.libva-vdpau-driver
          pkgs.libvdpau-va-gl
        ] ++ (optional cfg.amd.opencl.enable pkgs.rocmPackages.clr.icd)
          ++ cfg.amd.extraPackages;

        extraPackages32 = (optionals cfg.enable32Bit [
          pkgs.pkgsi686Linux.libva-vdpau-driver
          pkgs.pkgsi686Linux.libvdpau-va-gl
        ]) ++ cfg.amd.extraPackages32;
      };
    })

    (mkIf cfg.nvidia.enable {
      services.xserver.videoDrivers = [ "nvidia" ];
      hardware.nvidia = {
        modesetting.enable = cfg.nvidia.modesetting.enable;
        powerManagement = {
          enable = cfg.nvidia.powerManagement.enable;
          finegrained = cfg.nvidia.powerManagement.finegrained;
        };
        open = cfg.nvidia.open;
        nvidiaSettings = cfg.nvidia.nvidiaSettings;
        package = if cfg.nvidia.package != null
          then cfg.nvidia.package
          else config.boot.kernelPackages.nvidiaPackages.stable;

        prime = mkIf (cfg.nvidia.prime.offload.enable || cfg.nvidia.prime.sync.enable) {
          offload = {
            enable = cfg.nvidia.prime.offload.enable;
            enableOffloadCmd = cfg.nvidia.prime.offload.enable;
          };
          sync.enable = cfg.nvidia.prime.sync.enable;
          intelBusId = mkIf (cfg.nvidia.prime.intelBusId != null) cfg.nvidia.prime.intelBusId;
          amdgpuBusId = mkIf (cfg.nvidia.prime.amdgpuBusId != null) cfg.nvidia.prime.amdgpuBusId;
          nvidiaBusId = mkIf (cfg.nvidia.prime.nvidiaBusId != null) cfg.nvidia.prime.nvidiaBusId;
        };
      };

      hardware.graphics = {
        extraPackages = (optionals cfg.nvidia.vaapi.enable [
          pkgs.nvidia-vaapi-driver
          pkgs.libva-vdpau-driver
          pkgs.libvdpau-va-gl
        ]) ++ cfg.nvidia.extraPackages;

        extraPackages32 = cfg.nvidia.extraPackages32;
      };

      environment.sessionVariables = mkIf cfg.nvidia.vaapi.enable {
        LIBVA_DRIVER_NAME = "nvidia";
        NVD_BACKEND = "direct";
        MOZ_DISABLE_RDD_SANDBOX = "1";
      };

      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
        "nvidia-x11"
        "nvidia-settings"
      ];
    })
  ]);
}
