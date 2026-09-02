# Dot Base

Dot Base 是一个基于 NixOS Flake 的模块化、高性能服务器基础配置框架。它旨在为个人服务器和 VPS 提供开箱即用的优化方案，涵盖了从内核调优、内存管理到自动化运维及常用应用部署的全方位需求。

## 核心特性

- **极致性能优化**：内置 XanMod 最新内核，集成 BBRv3 网络拥塞控制算法，并针对高吞吐网络进行系统级参数调优。
- **智能内存管理**：提供多种内存优化模式（Aggressive/Balanced/Conservative），完美适配从 512MB 到大内存的各类 VPS。
- **自动化运维**：支持基于 Git 的配置自动同步与系统自动升级，内置定期垃圾回收（GC）和存储空间优化。
- **全自动 Web 服务**：Nginx 原生集成 ACME 证书申请，支持 HTTP/3 (QUIC)，简化反向代理配置。
- **常用应用集成**：预置 Hysteria、OpenList、Vaultwarden、X-UI-YG、S-UI、v2rayA 等常用服务的 NixOS 模块。
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
- **`base.update`**: 自动化运维与系统更新子系统。
  - **`upgrade.enable`**: 系统升级主开关（默认为 `true`）。控制是否启用系统升级能力与服务；若设为 `false`，则**完全关闭升级服务并从系统中移除 CLI 工具**。
  - **定时更新独立子配置 (`upgrade.timer`)**: `upgrade.timer.enable`（默认为 `false`）仅控制后台 Systemd Timer 定时器。关闭定时器时，CLI 工具与升级服务依然就绪，可随时手动触发单次更新。
  - **单次更新 CLI (`dot-update`)**: 内置系统级维护命令 `dot-update`（支持别名 `base-update` 与 `nixos-update`），一键执行当前系统的构建与切换。
  - **安全可控的 Pull 策略**: 默认**不拉取远程 Git**（仅构建本地工作区修改），方便本地配置调试；通过 `--pull`（或 `-p`）可在更新前自动同步远程最新代码。
  - **Git 仓库同步 (`sync`)**: 支持自动与远程 Git 仓库同步配置。支持 `destructive` 模式（`git reset --hard` 与 `clean`）以确保环境与远端严格一致。
  - **内核感知与自动重启**: 构建完成后自动比对运行中内核与新内核，支持提示或在配置 `allowReboot = true` 时自动重启。
  - **自动垃圾回收 (`gc`)**: 定期清理旧 Generation 并自动优化 Store 存储空间。
  - **Flake 宿主推断 (`host` / `path`)**: 自动推断 Flake URI 与 Legacy 配置文件路径。
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
- **v2rayA (`base.app.proxy.v2raya`)**: v2rayA 代理客户端与路由管理面板，支持 Nginx 反代与透明代理。
- **Web 应用**: 提供 OpenList、Vaultwarden 的一键反代接入，通过 `nginx = { enable = true; domain = "..."; }` 快速配置反向代理与证书。

### 4. 硬件、显卡与网络适配 (`hardware`)

- **`base.hardware.network`**: 统一网络配置抽象模块，支持 `systemd-networkd`（默认）、`networkmanager` 及 `scripted`（NixOS 传统脚本模式）三大后端。支持多网卡的 DHCP、静态 IPv4/IPv6、自定义路由、MAC 地址克隆、MTU 设置以及针对特定后端的属性扩展（如 NetworkManager keyfile profiles 与 systemd-networkd linkConfig/networkConfig）。启用后会默认禁用 Facter 自动 DHCP，避免其生成的 networkd 配置覆盖显式接口配置。
- **`base.hardware.graphics`**: 统一图形驱动与硬件加速抽象模块，基于**拓扑驱动架构 (Topology-Driven)** 设计，完美支持单显卡与多显卡混合协同：
  - **通用特性**：
    - **`mode`**: 图形硬件拓扑模式，支持 `"amd"`（纯 AMD 卡）、`"nvidia"`（纯 NVIDIA 独显）、`"hybrid-amd-nvidia"`（AMD 核显 + NVIDIA 独显笔记本）、`"hybrid-intel-nvidia"`（Intel 核显 + NVIDIA 独显笔记本）及 `"custom"`。
    - **`enable32Bit`**: 默认启用 32 位 OpenGL/Vulkan/VA-API 加速库，保障 Steam、Wine 及 32 位程序开箱即用。
  - **混合双显卡子系统 (`hybrid`)**：
    - **`strategy`**: 支持 `"offload"`（PRIME 渲染卸载，默认）、`"sync"`（独显同步直连）与 `"compute-only"`（纯 CUDA/AI 算力模式，NVIDIA 独显不参与桌面显示与显存占用）。
    - **`integratedBusId` / `discreteBusId`**: 显式声明集显与独显的 PCI Bus ID（如 `"PCI:5:0:0"` 与 `"PCI:1:0:0"`）。
    - **精细化动态电源管理 (`powerManagement.dynamicD3`)**: 在 offload 模式下默认自动开启 Turing+ 架构的 Runtime D3cold 深度休眠（0W 待机功耗）。
    - **零污染 VA-API 隔离与增强包装器**: 彻底解决双显卡笔记本全局 VA-API 污染问题。日常桌面在核显上享有原生超低功耗硬件硬解，独显加速通过内置的 `nvidia-offload` / `prime-run` 包装器按需局部注入。
  - **AMD 显卡微调 (`base.hardware.graphics.amd`)**:
    - **`initrd`**: 默认在 initrd 阶段加载 `amdgpu` 模块（Early KMS），消除启动画面闪烁。
    - **`opencl`**: 默认启用 ROCm / OpenCL ICD 计算运行时（`rocmPackages.clr.icd`），加速 Blender、DaVinci Resolve 等生产力软件。
  - **NVIDIA 显卡微调 (`base.hardware.graphics.nvidia`)**:
    - **`open`**: 可选切换为 NVIDIA 官方开源内核模块（`nvidia-open`，推荐 Turing RTX 20 系列及以上架构开启）。
    - **`modesetting.enable`**: 默认启用 modesetting（Wayland 合成器必需）。
    - **`package`**: 支持自定义指定特定版本或分支的 NVIDIA 驱动包。

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
          
          # --- AMD 显卡桌面配置 (模式一) ---
          base.hardware.graphics.mode = "amd";
          
          # --- NVIDIA 显卡桌面配置 (模式二) ---
          # base.hardware.graphics = {
          #   mode = "nvidia";
          #   nvidia.open = true;
          # };

          # --- AMD 核显 + NVIDIA 独显双显卡笔记本配置 (模式三) ---
          # base.hardware.graphics = {
          #   mode = "hybrid-amd-nvidia";
          #   hybrid = {
          #     strategy = "offload"; # 开启双显卡按需渲染与动态电源管理
          #     integratedBusId = "PCI:5:0:0";
          #     discreteBusId = "PCI:1:0:0";
          #   };
          #   nvidia.open = true; # RTX 20 系列及以上架构推荐
          # };
        })
      ];
    };
  };
}
```

### 示例 3: 自动化维护与系统更新配置 (`base.update`)

`base.update` 模块提供了一体化的 Git 配置同步、系统构建切换（Rebuild）与存储垃圾回收（GC）体系：

```nix
base.update = {
  enable = true;          # 启用更新子系统（生成 CLI 工具与系统升级服务）
  host = "my-host";       # 指定主机名（默认读取 networking.hostName）
  path = "hosts/my-host"; # 仓库中该主机的子路径（可选）

  # 1. Git 同步配置
  sync = {
    enable = true;
    url = "https://github.com/your-name/your-dotfiles";
    branch = "main";
    targetPath = "/etc/nixos";
    destructive = true;   # 是否在 pull 时使用 reset --hard 保持与远程严格一致
  };

  # 2. 系统升级与定时任务
  upgrade = {
    enable = true;            # 是否启用升级子系统（设为 false 时完全关闭升级服务并移除 dot-update CLI）
    type = "flake";           # 升级模式：flake 或 legacy
    pullBeforeUpdate = false; # 默认是否在更新前拉取远程（默认 false）
    allowReboot = true;       # 内核更新后是否允许自动重启

    # 定时自动更新独立子配置
    timer = {
      enable = false;         # 是否开启定时自动升级（默认 false，关闭不影响手动运行 dot-update）
      dates = "04:00";        # 自动更新触发时间
      randomizedDelaySec = "1h";
    };
  };

  # 3. 垃圾回收
  gc = {
    enable = true;
    dates = "weekly";
    olderThan = "7d";
  };
};
```

#### CLI 更新命令速查 (`dot-update`)

系统提供 `dot-update`（同时包含 `base-update` 与 `nixos-update` 别名）命令行工具：

```bash
# 1. 基础单次更新（使用当前本地配置直接 rebuild switch，不拉取远程）
dot-update

# 2. 更新前先从远程 Git 拉取最新提交
dot-update --pull
# 或使用简写
dot-update -p

# 3. 仅构建为下次启动项（不立即切换当前运行系统）
dot-update --boot

# 4. 临时测试构建（不写入 bootloader 启动项）
dot-update --test

# 5. 仅同步 Git 仓库，不执行系统构建
dot-update --sync-only

# 6. 委托给后台 systemd 服务运行并实时查看日志
dot-update --service
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
