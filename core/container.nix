{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.container;
in {
  options.base.container = {
    docker = {
      enable = mkEnableOption "Docker container engine";
    };
    podman = {
      enable = mkEnableOption "Podman container engine";
    };
  };

  config = mkMerge [
    # --- Docker Configuration ---
    (mkIf cfg.docker.enable {
      virtualisation.docker = {
        enable = true;
        daemon.settings = {
          experimental = true;
          default-address-pools = [{ base = "172.30.0.0/16"; size = 24; }];
        };
        rootless = {
          enable = true;
          setSocketVariable = true;
          daemon.settings = { dns = [ "1.1.1.1" "8.8.8.8" ]; };
        };
      };

      boot.kernel.sysctl = {
        "net.ipv4.conf.eth0.forwarding" = 1; # enable port forwarding
      };

      users.users.root.extraGroups = [ "docker" ];
    })

    # --- Podman Configuration ---
    (mkIf cfg.podman.enable {
      virtualisation.podman = {
        enable = true;
        # Docker 兼容模式 (若 Docker 同时也启用了，则禁用此兼容模式以避免冲突)
        dockerCompat = !cfg.docker.enable;
        # 启用容器间 DNS 解析 (支持容器名互访)
        defaultNetwork.settings.dns_enabled = true;
      };

      environment.systemPackages = with pkgs; [
        podman-compose
      ];
    })
  ];
}
