{ config, lib, ... }:
with lib;
let
  cfg = config.base.proxy;
in {
  options.base.proxy = {
    enable = mkEnableOption "System proxy configuration";

    default = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "socks5://127.0.0.1:2080";
      description = "Default proxy URL for all protocols (e.g. socks5://127.0.0.1:2080 or http://127.0.0.1:2080).";
    };

    httpProxy = mkOption {
      type = types.nullOr types.str;
      default = cfg.default;
      example = "http://127.0.0.1:2080";
      description = "HTTP proxy URL.";
    };

    httpsProxy = mkOption {
      type = types.nullOr types.str;
      default = cfg.default;
      example = "http://127.0.0.1:2080";
      description = "HTTPS proxy URL.";
    };

    allProxy = mkOption {
      type = types.nullOr types.str;
      default = cfg.default;
      example = "socks5://127.0.0.1:2080";
      description = "ALL_PROXY URL.";
    };

    noProxy = mkOption {
      type = types.str;
      default = "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
      description = "Comma-separated list of domain extensions and IP addresses for which proxy should not be used.";
    };

    nixDaemon = mkOption {
      type = types.bool;
      default = true;
      description = "Explicitly inject proxy environment variables into nix-daemon for nix-shell, nixos-rebuild, etc.";
    };
  };

  config = mkIf (cfg.enable && !config.base.testMode) {
    networking.proxy = {
      default = cfg.default;
      httpProxy = cfg.httpProxy;
      httpsProxy = cfg.httpsProxy;
      allProxy = cfg.allProxy;
      noProxy = cfg.noProxy;
    };

    systemd.services.nix-daemon.environment = mkIf cfg.nixDaemon (lib.filterAttrs (_: v: v != null) {
      http_proxy = cfg.httpProxy;
      https_proxy = cfg.httpsProxy;
      all_proxy = cfg.allProxy;
      ALL_PROXY = cfg.allProxy;
      no_proxy = cfg.noProxy;
      HTTP_PROXY = cfg.httpProxy;
      HTTPS_PROXY = cfg.httpsProxy;
      NO_PROXY = cfg.noProxy;
    });
  };
}
