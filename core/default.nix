{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base;
in {
  imports = [
    ./auth.nix
    ./container.nix
    ./dns/smartdns.nix
    ./memory.nix
    ./performance/tuning.nix
    ./update.nix
  ];

  options.base = {
    enable = mkEnableOption "Base system configuration";
    testMode = mkEnableOption "Test mode (force shutdown all networked services)";
  };

  config = mkIf cfg.enable {
    # 启用实验性功能 (nix-command)
    nix.settings.experimental-features = [ "nix-command" ];
    
    # 内核参数 (启用串口终端，通常用于 VPS 调试)
    boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];
    
    # --- SSH 服务 ---
    services.openssh.enable = true;

    # 每次构建时自动去重存储池以节省空间
    nix.settings.auto-optimise-store = true;

    # 安装系统级常用工具
    environment.systemPackages = with pkgs; [
      git        
    ];

    # 设置时区
    time.timeZone = "Asia/Shanghai";

    # 国际化设置：默认使用中文
    i18n.defaultLocale = "zh_CN.UTF-8";
    
    # 显式添加支持的 Locale，防止部分程序报错
    i18n.supportedLocales = [ "zh_CN.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];

    # 控制台字体设置
    console = {
      font = "Lat2-Terminus16";
      keyMap = "us";
    };

    # --- 图形界面 (X11) ---
    services.xserver.enable = false; # VPS 不需要图形界面

    # --- Firewall ---
    networking.nftables.enable = true;
  };
}
