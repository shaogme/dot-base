{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.hardware.network.single-interface;
in {
  options.base.hardware.network.single-interface = {
    enable = mkEnableOption "Single interface networking";
    
    nameservers = mkOption {
      type = types.listOf types.str;
      default = [ 
        "1.1.1.1" 
        "8.8.8.8" 
        "2606:4700:4700::1111" 
        "2001:4860:4860::8888" 
      ];
      description = "List of nameservers";
    };

    dhcp.enable = mkEnableOption "DHCP";

    ipv4 = {
      enable = mkEnableOption "Static IPv4";
      address = mkOption { type = types.str; description = "IPv4 Address"; };
      prefixLength = mkOption { type = types.int; description = "Subnet Mask / Prefix Length"; };
      gateway = mkOption { type = types.nullOr types.str; default = null; description = "IPv4 Gateway"; };
    };

    ipv6 = {
      enable = mkEnableOption "Static IPv6";
      address = mkOption { type = types.str; description = "IPv6 Address"; };
      prefixLength = mkOption { type = types.int; description = "Prefix Length"; };
      gateway = mkOption { type = types.nullOr types.str; default = null; description = "IPv6 Gateway"; };
    };

    preference = mkOption {
      type = types.enum [ "ipv4" "ipv6" ];
      default = "ipv4";
      description = "Network protocol preference. Default is ipv4, which modifies /etc/gai.conf to prefer IPv4.";
    };
  };

  config = mkIf cfg.enable {
    networking = {
      nameservers = mkDefault cfg.nameservers;
      networkmanager.enable = false;
      
      # true (默认值)：启用 "Predictable Network Interface Names"。系统会根据网卡的物理位置（PCI插槽）命名，如 ens18, enp3s0。
      # false：禁用该功能。内核会按照枚举顺序命名网卡，对于单网卡的 VPS，这几乎 100% 会是 eth0。
      usePredictableInterfaceNames = false;
      
      interfaces.eth0 = {
        # 默认逻辑：只有v4和v6同时为静态时才默认为关闭dhcp
        # 否则（例如只有v4静态，或都没有静态）默认为开启dhcp
        # 如果显式启用了 DHCP 模块 (cfg.dhcp.enable)，则强制开启
        useDHCP = if cfg.dhcp.enable then true else (!(cfg.ipv4.enable && cfg.ipv6.enable));
        
        ipv4.addresses = mkIf cfg.ipv4.enable [{
          address = cfg.ipv4.address;
          prefixLength = cfg.ipv4.prefixLength;
        }];
        
        ipv6.addresses = mkIf cfg.ipv6.enable [{
          address = cfg.ipv6.address;
          prefixLength = cfg.ipv6.prefixLength;
        }];
      };

      defaultGateway = mkIf (cfg.ipv4.enable && cfg.ipv4.gateway != null) cfg.ipv4.gateway;
      
      defaultGateway6 = mkIf (cfg.ipv6.enable && cfg.ipv6.gateway != null) {
        address = cfg.ipv6.gateway;
        interface = "eth0";
      };
    };

    environment.etc."gai.conf".text = mkIf (cfg.preference == "ipv4") ''
      label ::1/128       0
      label ::/0          1
      label 2002::/16     2
      label ::/96         3
      label ::ffff:0:0/96 4
      precedence ::1/128       50
      precedence ::/0          40
      precedence 2002::/16     30
      precedence ::/96         20
      precedence ::ffff:0:0/96 100
    '';
  };
}
