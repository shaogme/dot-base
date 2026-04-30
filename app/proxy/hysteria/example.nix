{ config, lib, pkgs, ... }:

{
  # 示例配置：展示 Hysteria 模块的所有可用选项
  # Example Configuration: Shows all available options for the Hysteria module
  
  config = lib.mkIf false { # 默认禁用，仅作为参考 Disabled by default, for reference only
    base.app.hysteria = {
      enable = true;
      
      # 容器后端选择 (docker 或 podman)
      backend = "podman";
      
      # 镜像设置
      image = "tobyxdd/hysteria:latest";
      
      # 数据持久化目录
      dataDir = "/var/lib/hysteria";

      # 端口跳跃功能 (Port Hopping)
      # 需要配合 nftables 使用
      portHopping = {
        enable = true;
        range = "20000-50000"; # 监听端口范围
        interface = "eth0";    # 入站流量接口
      };

      # Hysteria 核心配置
      settings = {
        # 服务端监听地址
        # 如果启用了 portHopping，这个端口将作为目标端口，nftables 会将 range 流量转发到这里
        listen = ":443";

        # --- TLS 配置 (互斥：不能与 ACME 同时启用) ---
        # tls = {
        #   cert = "/path/to/cert.crt";
        #   key = "/path/to/private.key";
        #   sniGuard = "strict"; # strict / disable / dns-san
        #   clientCA = "/path/to/client_ca.crt";
        # };

        # --- ACME 自动证书配置 (互斥：不能与 TLS 同时启用) ---
        acme = {
          domains = [ "your.domain.com" "example.org" ];
          email = "your@email.com";
          ca = "letsencrypt"; # letsencrypt / zerossl / buypass ...
          listenHost = "0.0.0.0";
          dir = "/acme"; # 容器内路径
          type = "http"; # http / tls / dns

          # HTTP 验证模式配置
          http = {
            altPort = 80;
          };
          
          # TLS 验证模式配置
          # tls = {
          #   altPort = 443;
          # };

          # DNS 验证模式配置
          # dns = {
          #   name = "cloudflare";
          #   config = {
          #     CLOUDFLARE_DNS_API_TOKEN = "your_token";
          #   };
          # };
        };

        # --- 混淆配置 (Obfuscation) ---
        obfs = {
          type = "salamander";
          salamander = {
            password = "your_obfs_password"; # 留空则自动生成
          };
        };

        # --- QUIC 协议参数 ---
        quic = {
          initStreamReceiveWindow = 8388608;
          maxStreamReceiveWindow = 8388608;
          initConnReceiveWindow = 20971520;
          maxConnReceiveWindow = 20971520;
          maxIdleTimeout = "30s";
          maxIncomingStreams = 1024;
          disablePathMTUDiscovery = false;
        };

        # --- 带宽限制 ---
        bandwidth = {
          up = "1 gbps";
          down = "1 gbps";
        };
        ignoreClientBandwidth = false;

        # --- 其他功能开关 ---
        speedTest = true;
        disableUDP = false;
        udpIdleTimeout = "60s";

        # --- 认证配置 ---
        auth = {
          type = "password"; # password / userpass / http / command
          password = "your_auth_password"; # 留空则自动生成
          
          # userpass 模式示例
          # userpass = {
          #   user1 = "pass1";
          #   user2 = "pass2";
          # };
          
          # http 模式示例
          # http = {
          #   url = "http://your-auth-backend/api";
          #   insecure = false;
          # };
        };

        # --- DNS 解析器 ---
        resolver = {
          type = "udp"; # udp / tcp / tls / https
          udp = {
            addr = "8.8.8.8:53";
            timeout = "4s";
          };
          # tls = {
          #   addr = "1.1.1.1:853";
          #   timeout = "10s";
          #   sni = "cloudflare-dns.com";
          #   insecure = false;
          # };
        };

        # --- SNI 嗅探 ---
        sniff = {
          enable = true;
          timeout = "2s";
          rewriteDomain = true;
          tcpPorts = "80,443";
          udpPorts = "all";
        };

        # --- ACL 访问控制 ---
        acl = {
          file = "/path/to/acl.txt";
          geoip = "/path/to/geoip.dat";
          geosite = "/path/to/geosite.dat";
          geoUpdateInterval = "168h";
          inline = [
            "direct(all)"
          ];
        };

        # --- 出站代理链 (Outbounds) ---
        outbounds = [
          {
            name = "direct_out";
            type = "direct";
            direct = {
              mode = "auto";
            };
          }
          {
            name = "socks5_out";
            type = "socks5";
            socks5 = {
              addr = "192.168.1.1:1080";
              username = "user";
              password = "password";
            };
          }
        ];

        # --- 流量统计 API ---
        trafficStats = {
          listen = ":9999";
          secret = "stats_secret";
        };

        # --- 伪装设置 (Masquerade) ---
        masquerade = {
          type = "proxy"; # file / proxy / string
          proxy = {
            url = "https://www.bing.com";
            rewriteHost = true;
            insecure = false;
          };
          # file = {
          #   dir = "/var/www/html";
          # };
          listenHTTP = ":80";
          listenHTTPS = ":443";
          forceHTTPS = true;
        };
      };
    };
  };
}
