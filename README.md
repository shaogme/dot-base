# Dot Base

Dot Base 是一个基于 NixOS Flake 的模块化、高性能服务器基础配置框架。它旨在为个人服务器和 VPS 提供开箱即用的优化方案，涵盖了从内核调优、内存管理到自动化运维及常用应用部署的全方位需求。

## 核心特性

- **极致性能优化**：内置 XanMod 最新内核，集成 BBRv3 网络拥塞控制算法，并针对高吞吐网络进行系统级参数调优。
- **智能内存管理**：提供多种内存优化模式（Aggressive/Balanced/Conservative），完美适配从 512MB 到大内存的各类 VPS。
- **自动化运维**：支持基于 Git 的配置自动同步与系统自动升级，内置定期垃圾回收（GC）和存储空间优化。
- **全自动 Web 服务**：Nginx 原生集成 ACME 证书申请，支持 HTTP/3 (QUIC)，简化反向代理配置。
- **常用应用集成**：预置 Hysteria、OpenList、Vaultwarden、X-UI-YG、S-UI 等常用服务的 NixOS 模块。
- **VPS 友好**：简化单网卡网络配置，支持静态 IPv4/IPv6，内置 QEMU Guest Agent 支持。

## 项目结构

```text
.
├── flake.nix             # 项目入口，定义 Flake 输出
├── default.nix           # 模块总入口
├── core/                 # 核心系统配置
│   ├── auth.nix          # SSH 安全与用户认证
│   ├── container.nix     # Docker/Podman 容器后端
│   ├── dns/              # SmartDNS 优化 (国内/国外模式)
│   ├── memory.nix        # 内存优化 (Zram, MGLRU, Sysctl)
│   ├── performance/      # Tuned 性能 profile
│   └── update.nix        # Git 同步与自动更新
├── app/                  # 应用模块
│   ├── proxy/            # 代理服务 (Hysteria, X-UI-YG 等)
│   ├── web/              # Web 服务 (Nginx, OpenList, Vaultwarden)
│   └── default.nix
├── hardware/             # 硬件、显卡与网络适配
│   ├── graphics/         # 桌面环境显卡驱动与硬件加速 (AMD/NVIDIA)
│   ├── network/          # 单网卡/多网卡与静态 IP 配置
│   └── default.nix
└── kernel/               # 内核选择
    └── xanmod.nix        # XanMod 内核与 BBRv3 调优
```

## 模块详解

### 1. 核心系统 (`core`)
- **`base.enable`**: 基础环境初始化。包含以下配置：
  - 启用 Nix 实验性功能 (`nix-command`)。
  - 预装核心工具（如 `git`）。
  - 设置时区（`Asia/Shanghai`）与中文本地化环境。
  - 启用串口终端支持 (`ttyS0`)，方便 VPS 救援。
  - 启用 `nftables` 防火墙与自动存储优化。
- **`base.testMode`**: 测试模式。开启后会强制进入“沙盒”状态，禁用所有联网应用（Nginx, Hysteria, Docker等）、自动更新逻辑以及网络链路配置（IP/网关），用于离线调试或安全排查。
- **`base.auth`**: SSH 安全与用户认证管理。
  - **`root.mode`**: 默认为 `default`（仅允许密钥登录），可选 `permit_passwd`。
  - 支持配置初始 Hashed 密码与 `authorizedKeys`。
  - 内置安全加固，自动禁用空密码并根据模式调整 SSHD 配置。
- **`base.memory`**: 智能内存优化。所有模式均启用 **Zram (zstd)** 与 **MGLRU**。
  - **`aggressive`**: 针对 <1G 内存。100% Zram 占用，激进的 Swap 策略，限制 Nix 构建任务数为 1。
  - **`balanced`**: 针对 <2G 内存。80% Zram，中等 Swap 策略，优化脏数据刷盘阈值。
  - **`conservative`**: 针对 >=4G 内存。50% Zram，保持标准系统压力。
- **`base.dns.smartdns`**: 高性能 DNS 转发。支持持久化缓存、域名预取及过期服务。
  - **`oversea` 模式**: 针对海外 VPS。使用主流公共 DNS Over TLS (DoT) 以确保安全。
  - **`china` 模式**: 国内外分流。国内域名（如百度、阿里、苹果等）走本地解析，其余走加密 DNS。
  - **`unlock` 配置**: 支持自定义解锁服务器与指定域名的分流解析。
- **`base.update`**: 自动化维护体系。
  - **`sync`**: 自动从远程仓库同步配置。支持 `destructive` 模式（强制 hard reset）以确保环境一致性。
  - **`upgrade`**: 定时执行系统升级（`nixos-rebuild`），支持 Flake 自动路径推断与随机延迟。
  - **`gc`**: 定期清理旧版本，释放存储空间。
  - **`host`**: 显式指定 Flake 宿主名，简化跨机器配置同步。
- **`base.container`**: 容器后端配置。
  - **`docker`**: 支持 Rootless 模式、实验性功能，并优化了桥接网络转发性能。
  - **`podman`**: 提供 Docker 兼容模式，并预装 `podman-compose`。
- **`base.performance.tuning`**: 基于 `tuned` 的系统性能调优模块。通过原生 `services.tuned` 配置体系实现，提供开箱即用的预设 Profile 并支持灵活透传底层配置。
  - **`profile`**: 调优预设方案，支持：
    - **`vps`**: 专为 VPS 和虚拟化环境优化。自动禁用 PPD（避免桌面电源管理和 UPower 开销），默认推荐 `virtual-guest` 配置文件（优化 I/O 调度与吞吐量）。
    - **`desktop`**: 桌面平衡模式。自动启用 `ppdSupport`（对接 GNOME/KDE Plasma 等桌面环境的电源管理 API），默认使用 `balanced`（对应 `desktop` 配置文件）。
    - **`desktop-performance`**: 桌面高性能模式。启用 `ppdSupport` 并默认设为 `performance`（对应 `throughput-performance` 配置文件），最大化 CPU 吞吐与响应能力。
    - **`desktop-powersave`**: 桌面/笔记本节能模式。启用 `ppdSupport` 并默认设为 `power-saver`（对应 `desktop-powersave` 配置文件），最大化电池续航与控温。
    - **`none`**: 默认值。不启用预设 profile。
  - **底层配置透传**（支持直接覆盖或扩展 TuneD 原生属性）：
    - **`package`**: 自定义 TuneD 软件包实例。
    - **`ppdSupport`**: 显式开关 `power-profiles-daemon` 兼容支持。
    - **`ppdSettings`**: 详细配置 PPD 映射表与默认行为。
    - **`profiles`**: 自定义 TuneD 配置文件定义（生成 `/etc/tuned/profiles/<name>/tuned.conf`）。
    - **`recommend`**: 自定义规则匹配（生成 `/etc/tuned/recommend.conf`）。
    - **`settings`**: TuneD 主守护进程配置（生成 `/etc/tuned/tuned-main.conf`）。

### 2. 内核调优 (`kernel`)
- **`base.kernel.xanmod`**: 默认启用。切换至 XanMod 内核，开启 BBRv3，优化 TCP 窗口、缓冲区及文件描述符限制，显著提升网络连接速度与稳定性。

### 3. 应用服务 (`app`)
- **Nginx (`base.app.web.nginx`)**: 自动处理端口开放、SSL 证书申请及续期，一键开启 HTTP/3。
- **Hysteria (`base.app.proxy.hysteria`)**: 完整的容器化部署方案，支持端口跳跃（Port Hopping）和自动证书分发。
- **X-UI-YG (`base.app.proxy.x-ui-yg`)**: 多协议代理管理面板，支持 Nginx 反代与端口范围放行。
- **S-UI (`base.app.proxy.s-ui`)**: Sing-Box 代理管理面板，支持 Nginx 反代与端口范围放行。
- **Web 应用**: 提供 OpenList、Vaultwarden 的一键反代接入，通过 `nginx = { enable = true; domain = "..."; }` 快速配置反向代理与证书。

### 4. 硬件、显卡与网络适配 (`hardware`)
- **`base.hardware.network`**: 统一网络配置抽象模块，支持 `systemd-networkd`（默认）、`networkmanager` 及 `scripted`（NixOS 传统脚本模式）三大后端。支持多网卡的 DHCP、静态 IPv4/IPv6、自定义路由、MAC 地址克隆、MTU 设置以及针对特定后端的属性扩展（如 NetworkManager keyfile profiles 与 systemd-networkd linkConfig/networkConfig）。启用后会默认禁用 Facter 自动 DHCP，避免其生成的 networkd 配置覆盖显式接口配置。
- **`base.hardware.graphics`**: 统一图形驱动与硬件加速抽象模块，专为桌面环境与工作站设计，分为 **AMD** 与 **NVIDIA** 两套完备配置：
  - **通用特性**：
    - **`enable`**: 图形硬件加速总开关（当 `amd.enable` 或 `nvidia.enable` 为 true 时自动联动启用）。
    - **`enable32Bit`**: 默认启用 32 位 OpenGL/Vulkan/VA-API 加速库，保障 Steam、Wine 及 32 位程序开箱即用。
  - **AMD 显卡 (`base.hardware.graphics.amd`)**:
    - **`enable`**: 一键启用 AMD 开源驱动栈（`amdgpu`、Mesa RADV、Vulkan）。
    - **`initrd.enable`**: 默认在 initrd 阶段加载 `amdgpu` 模块（Early KMS），消除启动画面闪烁与撕裂。
    - **`opencl.enable`**: 默认启用 ROCm / OpenCL ICD 计算运行时（`rocmPackages.clr.icd`），加速 Blender、DaVinci Resolve 等生产力软件。
    - 预置 `libva-vdpau-driver` 与 `libvdpau-va-gl`，提供全面的 VA-API / VDPAU 视频硬解。
  - **NVIDIA 显卡 (`base.hardware.graphics.nvidia`)**:
    - **`enable`**: 启用 NVIDIA 专有/开源驱动栈，自动注入专有驱动 unfree 许可过滤。
    - **`modesetting.enable`**: 默认启用 modesetting（Wayland 合成器如 Hyprland、Sway、GNOME、KDE Plasma 必需）。
    - **`open`**: 可选切换为 NVIDIA 官方开源内核模块（`nvidia-open`，推荐 Turing RTX 20 系列及以上架构开启）。
    - **`powerManagement`**: 提供 `enable`（基础电源管理/挂起恢复）与 `finegrained`（精细化动态电源管理，空闲彻底关断独显）。
    - **`nvidiaSettings`**: 默认构建并安装 `nvidia-settings` 图形化控制面板。
    - **`vaapi.enable`**: 默认集成 `nvidia-vaapi-driver` 并注入 Direct 模式环境变量（`LIBVA_DRIVER_NAME = "nvidia"`, `NVD_BACKEND = "direct"`），大幅优化浏览器与媒体播放器视频硬解。
    - **`package`**: 支持自定义指定特定版本或分支的 NVIDIA 驱动包。
    - **`prime`**: 专为双显卡笔记本设计，支持 `offload`（渲染卸载/按需调用独显）与 `sync`（独显同步直连）两种模式，支持便捷指定 `intelBusId` / `amdgpuBusId` / `nvidiaBusId`。

## 快速开始

Dot Base 采用“纯模块库”架构，不强制锁定 `nixpkgs` 版本。这意味着你可以将其无缝集成到任何 NixOS 项目中，并自动使用你项目中指定的 `nixpkgs` 版本。

### 示例 1: VPS / 服务器环境
在你的 NixOS 配置中引入此 Flake：

```nix
# flake.nix (VPS / Server 示例)
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    dot-base.url = "github:shaogme/dot-base";
  };

  outputs = { self, nixpkgs, dot-base }: {
    nixosConfigurations.my-vps = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # 引入基础模块
        dot-base.nixosModules.default
        # 引入可选的 XanMod 内核优化
        dot-base.nixosModules.kernel-xanmod
        
        ({ ... }: {
          base.enable = true;
          base.performance.tuning.profile = "vps"; # 针对 VPS 虚拟化环境调优
          base.memory.mode = "balanced";
          base.auth.root.authorizedKeys = [ "ssh-ed25519 AAA..." ];
          
          # 部署应用示例
          base.app.web.openlist = {
            enable = true;
            nginx = {
              enable = true;
              domain = "openlist.example.com";
            };
          };
        })
      ];
    };
  };
}
```

### 示例 2: 个人桌面 / 工作站环境 (AMD 或 NVIDIA 显卡)

```nix
# flake.nix (Desktop 示例)
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    dot-base.url = "github:shaogme/dot-base";
  };

  outputs = { self, nixpkgs, dot-base }: {
    nixosConfigurations.my-desktop = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        dot-base.nixosModules.default
        
        ({ ... }: {
          base.enable = true;
          base.performance.tuning.profile = "desktop"; # 桌面平衡模式 (可选 desktop-performance / desktop-powersave)
          base.memory.mode = "conservative"; # 桌面大内存保守模式
          
          # --- AMD 显卡桌面配置 (二选一) ---
          base.hardware.graphics.amd.enable = true;
          
          # --- NVIDIA 显卡 / 双显卡笔记本配置 (二选一) ---
          # base.hardware.graphics.nvidia = {
          #   enable = true;
          #   open = true; # RTX 20 系列及以上架构推荐
          #   prime = {
          #     offload.enable = true; # 开启双显卡按需渲染
          #     amdgpuBusId = "PCI:5:0:0";
          #     nvidiaBusId = "PCI:1:0:0";
          #   };
          # };
        })
      ];
    };
  };
}
```

## 进阶用法：显式注入特定 pkgs

虽然在 Flake 环境下 `nixosSystem` 会自动处理 `pkgs` 注入，但在某些特殊场景（如自动化测试、传统 `configuration.nix` 调用、或需要强制指定特定 `nixpkgs` 实例时），你可以使用 `lib.withPkgs` 函数：

```nix
let
  # 假设你有一个特定的 pkgs 实例
  myPkgs = import nixpkgs { system = "x86_64-linux"; };
  
  # 显式注入该 pkgs 并获取配置好的库/模块
  dotBase = dot-base.lib.withPkgs myPkgs;
in
{
  imports = [
    # 使用注入后的模块
    dotBase.nixosModules.default
  ];
}
```

> [!TIP]
> 大多数普通用户只需遵循“快速开始”中的标准 Flake 用法即可，`nixosSystem` 会自动确保版本一致性。

## 安全建议

- 建议保持 `base.auth.root.mode = "default"` 以禁用密码登录。
- 使用 `base.update` 功能时，请确保 Git 仓库的私密性（如果包含敏感信息）。

## 许可证

[MIT License](LICENSE)
