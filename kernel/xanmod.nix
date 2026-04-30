{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.kernel.xanmod;
in {
  options.base.kernel.xanmod = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "XanMod kernel with BBRv3 network optimization";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;

    # 确保加载 BBR 模块
    boot.kernelModules = [ "tcp_bbr" ];

    # 网络栈参数调优
    boot.kernel.sysctl = {
      # --- 核心算法 ---
      
      # 启用 BBR (XanMod 内核中 tcp_bbr 即为 BBRv3)
      "net.ipv4.tcp_congestion_control" = "bbr";
      
      # 队列管理算法: fq (Fair Queueing)
      # 对于 XanMod + BBRv3，Google 官方推荐配合 fq 使用，
      # 因为 fq 能够最完美地执行 BBR 要求的 pacing (发包节奏控制)。
      "net.core.default_qdisc" = "fq";

      # --- 缓冲区与吞吐量优化 (10G/40G 网络就绪) ---
      
      # 增加接收/发送缓冲区上限 (32MB)
      # 相比 CachyOS 的通用配置，这里针对 XanMod 的高吞吐特性稍微激进一点
      "net.core.rmem_max" = 33554432;
      "net.core.wmem_max" = 33554432;
      "net.ipv4.tcp_rmem" = "4096 87380 33554432";
      "net.ipv4.tcp_wmem" = "4096 65536 33554432";
      "net.ipv4.udp_rmem_min" = 8192;
      "net.ipv4.udp_wmem_min" = 8192;

      # --- BBRv3 专属优化 ---
      
      # 降低未发送数据的低水位线
      # 这是一个对 BBR 至关重要的参数。
      # 它控制 TCP 栈在 socket buffer 中保留多少未发送数据。
      # 设置为 16KB 可以减少 bufferbloat，让 BBR 的 pacing 更加精准，大幅降低延迟。
      "net.ipv4.tcp_notsent_lowat" = 16384;
      
      # 开启 ECN (Explicit Congestion Notification)
      # BBRv3 对 ECN 有优秀的 L4S (Low Latency, Low Loss, Scalable Throughput) 支持
      # 允许在丢包发生前就进行速率调整
      "net.ipv4.tcp_ecn" = 1;
      "net.ipv4.tcp_ecn_fallback" = 1;

      # --- 连接管理与安全 ---
      
      # 禁用慢启动重启
      # 保持空闲连接的窗口大小，对 HTTP/2, gRPC 等长连接应用至关重要
      "net.ipv4.tcp_slow_start_after_idle" = 0;
      
      # 启用 MTU 探测
      # 对于巨型帧或复杂路由路径（如穿透 VPN/隧道），这能避免黑洞问题
      "net.ipv4.tcp_mtu_probing" = 1;
      
      # 快速打开 (TFO)
      "net.ipv4.tcp_fastopen" = 3;
      
      # 增加连接追踪上限 (防止高并发丢包)
      "net.netfilter.nf_conntrack_max" = 1048576;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = 7200; # 默认通常是 5 天，改为 2 小时更利于回收
    };

    # 增加文件描述符限制
    # 高吞吐网络通常伴随着大量的 socket 连接，需要提高文件句柄限制
    security.pam.loginLimits = [
      { domain = "*"; item = "nofile"; type = "soft"; value = "1048576"; }
      { domain = "*"; item = "nofile"; type = "hard"; value = "1048576"; }
    ];
  };
}
