{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.base.app.web.nginx;
  
  # 定义公共的 ACME Webroot 目录
  acmeWebRoot = "/var/lib/acme/acme-challenge";

  siteSubmodule = types.submodule {
    options = {
      locations = mkOption {
        type = types.attrs;
        default = {};
        description = "Nginx location configurations";
      };
      
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Nginx configuration";
      };

      enableForceSSL = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to force SSL redirection";
      };

      http3 = mkOption {
        type = types.bool;
        default = false;
        description = "Enable HTTP3 for this site";
      };

      quic = mkOption {
        type = types.bool;
        default = false;
        description = "Enable QUIC listener for this site";
      };

      # 保留此高级配置，用于 Hysteria 等服务的证书分发
      acmePostRun = mkOption {
        type = types.lines;
        default = "";
        description = "Shell commands to run after certificate renewal";
      };
    };
  };

in {
  options.base.app.web.nginx = {
    enable = mkEnableOption "Nginx Web Server with Native ACME Integration";
    
    email = mkOption {
      type = types.str;
      description = "Email address for ACME registration and renewal notifications";
    };

    sites = mkOption {
      type = types.attrsOf siteSubmodule;
      default = {};
    };
  };

  config = mkIf cfg.enable {
    # 开放端口
    networking.firewall.allowedTCPPorts = [ 80 443 ];
    networking.firewall.allowedUDPPorts = [ 443 ];

    # 1. 目录权限管理
    # 确保 acme 用户可写，nginx 用户可读 (Group 'nginx' 权限为 r-x)
    systemd.tmpfiles.rules = [
      "d ${acmeWebRoot} 0755 acme nginx -"
    ];

    # 2. ACME 证书配置 (混合模式)
    # 我们利用 NixOS 的合并特性：
    # - default.nix 会根据 useACMEHost 自动生成一部分基础配置（如 reloadServices）
    # - 我们在这里补充 webroot 和 postRun 钩子
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = cfg.email;
        group = "nginx";
      };

      certs = mapAttrs (domain: siteCfg: {
        # 强制指定 webroot 模式
        webroot = acmeWebRoot;
        
        # 注入用户定义的 Hook (如复制证书给 Hysteria)
        postRun = siteCfg.acmePostRun;
        
        # 显式允许 nginx 组读取（关键）
        group = "nginx";
        
        # 虽然 default.nix 也会设置这个，但显式声明更安全，确保合并正确
        reloadServices = [ "nginx" ];
      }) cfg.sites;
    };

    # 3. Nginx 配置
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts = 
        let
          userSites = mapAttrs (domain: siteCfg: {
            # --- 核心修正 ---
            
            # 1. 启用原生 ACME 集成
            # 这会触发 default.nix 中的逻辑，自动处理 snakeoil 证书和依赖关系
            useACMEHost = domain;

            # 2. 移除手动指定的 sslCertificate / sslCertificateKey
            # default.nix 会根据 useACMEHost 自动填充路径

            # 3. 正确的 SSL 开关逻辑
            # 如果强制 SSL，则 forceSSL=true (会自动生成 80->443 跳转)
            # 如果不强制但支持 SSL，则 addSSL=true
            forceSSL = siteCfg.enableForceSSL;
            addSSL = !siteCfg.enableForceSSL;

            # 4. 传递 HTTP3/QUIC 参数
            http3 = siteCfg.http3;
            quic = siteCfg.quic;
            
            # 5. 使用 acmeRoot 参数替代手写的 location
            # default.nix 检测到 useACMEHost + acmeRoot 后，
            # 会自动生成 /.well-known/acme-challenge/ 块，且配置正确
            acmeRoot = acmeWebRoot;

            # 注入用户定义的 locations
            locations = siteCfg.locations;

            extraConfig = siteCfg.extraConfig;
          }) cfg.sites;

          defaultSite = {
            "_" = {
              default = true;
              rejectSSL = true;
              locations."/" = { return = "444"; };
            };
          };
        in
          userSites // defaultSite;
    };
  };
}