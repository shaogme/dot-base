{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.dns.smartdns;
in {
  options.base.dns.smartdns = {
    mode = mkOption {
      type = types.enum [ "oversea" "china" "none" ];
      default = "none";
      description = "Select SmartDNS mode: 'oversea' for optimized overseas routing, 'china' for split-horizon DNS.";
    };
    unlock = {
      servers = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of upstream DNS servers for unlocking.";
      };
      domains = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of domains to be resolved by the unlocking servers.";
      };
    };
  };

  config = mkIf (cfg.mode != "none") {
    # --- Common Configuration ---
    services.resolved.enable = false;
    networking.networkmanager.dns = "none";
    networking.dhcpcd.extraConfig = "nohook resolv.conf";
    networking.nameservers = [ "127.0.0.1" ];

    services.smartdns = {
      enable = true;
      settings = mkMerge [
        # Common Settings
        {
          bind = "127.0.0.1:53";
          log-level = "warn";
          cache-file = "/var/lib/smartdns/smartdns.cache";
          cache-persist = true;
          prefetch-domain = true;
          serve-expired = true;
          response-mode = "fastest-response";
        }

        # Mode: Oversea
        (mkIf (cfg.mode == "oversea") {
          cache-size = 65536;
          serve-expired-ttl = 259200;
          serve-expired-reply-ttl = 30;
          speed-check-mode = "ping,tcp:80,tcp:443";
          dualstack-ip-selection = true;

          server-tls = [
            "1.1.1.1" "1.0.0.1" "2606:4700:4700::1111" "2606:4700:4700::1001"
            "8.8.8.8" "8.8.4.4" "2001:4860:4860::8888" "2001:4860:4860::8844"
            "9.9.9.9" "149.112.112.112"
          ];
          server = map (s: "${s} -group unlock -exclude-default-group") cfg.unlock.servers;
          nameserver = map (d: "/${d}/unlock") cfg.unlock.domains;
        })

        # Mode: China
        (mkIf (cfg.mode == "china") {
          bind-tcp = "127.0.0.1:53";
          cache-size = 32768;
          serve-expired-ttl = 86400;
          speed-check-mode = "tcp:80,tcp:443,ping";

          # Group China
          server = [
            "119.29.29.29 -group china -exclude-default-group"
            "223.5.5.5    -group china -exclude-default-group"
            "180.76.76.76 -group china -exclude-default-group"
          ] ++ (map (s: "${s} -group unlock -exclude-default-group") cfg.unlock.servers);

          # Group Global
          server-tls = [
            "1.1.1.1 -group global -exclude-default-group"
            "1.0.0.1 -group global -exclude-default-group"
            "8.8.4.4 -group global -exclude-default-group"
            "9.9.9.9 -group global -exclude-default-group"
            "9.9.9.9" # Fallback
          ];

          nameserver = [
            "/cn/china"
            "/baidu.com/china" "/qq.com/china" "/taobao.com/china"
            "/jd.com/china" "/aliyun.com/china" "/163.com/china"
            "/bilibili.com/china"
            "/apple.com/china" "/icloud.com/china" "/cdn-apple.com/china"
          ] ++ (map (d: "/${d}/unlock") cfg.unlock.domains);
        })
      ];
    };
  };
}
