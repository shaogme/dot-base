# Dot Base

Dot Base 是一个基于 NixOS Flake 的模块化、高性能服务器基础配置框架。它旨在为个人服务器和 VPS 提供开箱即用的优化方案，涵盖了从内核调优、内存管理到自动化运维及常用应用部署的全方位需求。

## 核心特性

- **极致性能优化**：内置 XanMod 最新内核，集成 BBRv3 网络拥塞控制算法，并针对高吞吐网络进行系统级参数调优。
- **智能内存管理**：提供多种内存优化模式（Aggressive/Balanced/Conservative），完美适配从 512MB 到大内存的各类 VPS。
- **自动化运维**：支持基于 Git 的配置自动同步与系统自动升级，内置定期垃圾回收（GC）和存储空间优化。
- **全自动 Web 服务**：Nginx 原生集成 ACME 证书申请，支持 HTTP/3 (QUIC)，简化反向代理配置。
- **常用应用集成**：预置 Hysteria、OpenList、Vaultwarden、X-UI-YG 等常用服务的 NixOS 模块。
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
│   ├── proxy/            # 代理服务 (Hysteria 等)
│   ├── web/              # Web 服务 (Nginx, OpenList, Vaultwarden, X-UI)
│   └── default.nix
├── hardware/             # 硬件与网络适配
│   ├── network/          # 单网卡与静态 IP 配置
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
- **`base.performance.tuning`**: 基于 `tuned` 的系统调优。
  - 默认启用 `virtual-guest` 配置文件，针对虚拟化环境（VPS）优化 CPU、I/O 及吞吐量。

### 2. 内核调优 (`kernel`)
- **`base.kernel.xanmod`**: 默认启用。切换至 XanMod 内核，开启 BBRv3，优化 TCP 窗口、缓冲区及文件描述符限制，显著提升网络连接速度与稳定性。

### 3. 应用服务 (`app`)
- **Nginx (`base.app.web.nginx`)**: 自动处理端口开放、SSL 证书申请及续期，一键开启 HTTP/3。
- **Hysteria (`base.app.web.hysteria`)**: 完整的容器化部署方案，支持端口跳跃（Port Hopping）和自动证书分发。
- **Web 应用**: 提供 OpenList、Vaultwarden、X-UI-YG 的一键反代接入，只需指定 `domain` 即可完成部署。

### 4. 网络适配 (`hardware`)
- **`base.hardware.network.single-interface`**: 专为 VPS 设计，简化 eth0 网卡的配置，支持协议优先级设置（如优先使用 IPv4）。

## 快速开始

在你的 NixOS 配置中引入此 Flake：

```nix
# flake.nix
{
  inputs.dot-base.url = "github:shaogme/dot-base";

  outputs = { self, nixpkgs, dot-base }: {
    nixosConfigurations.my-vps = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        dot-base.nixosModules.default
        dot-base.nixosModules.kernel-xanmod
        ({ ... }: {
          base.enable = true;
          base.memory.mode = "balanced";
          base.auth.root.authorizedKeys = [ "ssh-ed25519 AAA..." ];
          
          # 部署应用示例
          base.app.web.openlist = {
            enable = true;
            domain = "openlist.example.com";
          };
        })
      ];
    };
  };
}
```

## 安全建议

- 建议保持 `base.auth.root.mode = "default"` 以禁用密码登录。
- 使用 `base.update` 功能时，请确保 Git 仓库的私密性（如果包含敏感信息）。

## 许可证

[MIT License](LICENSE)
