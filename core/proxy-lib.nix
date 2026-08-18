{ lib ? (import <nixpkgs> {}).lib }:
with lib;
rec {
  # 统一的空代理环境变量集合，供明确无需代理的容器/服务使用（清空代理继承）
  emptyProxyEnv =
    let
      keys = [ "http_proxy" "https_proxy" "ftp_proxy" "all_proxy" "no_proxy" ];
    in
    genAttrs (keys ++ map toUpper keys) (_: "");

  # 将代理 URL 中的 127.0.0.1 和 localhost 转换为指定的 hostDomain（如 host.docker.internal）
  replaceLoopback = { url, hostDomain ? "host.docker.internal", enable ? true }:
    if url == null then null
    else if enable then
      builtins.replaceStrings
        [ "127.0.0.1" "localhost" ]
        [ hostDomain hostDomain ]
        url
    else
      url;

  # 通用代理配置项 Option 构造器
  mkProxyOptions = {
    description ? "service",
    defaultMode ? "auto",
    autoReplaceLoopback ? true,
    hostDomain ? "host.docker.internal",
  }:
    let
      mkProxyStrOpt = example: desc: mkOption {
        type = types.nullOr types.str;
        default = null;
        inherit example;
        description = "${desc} for ${description} when mode is 'overwrite'.";
      };
    in {
      mode = mkOption {
        type = types.enum [ "auto" "disable" "overwrite" ];
        default = defaultMode;
        description = "Proxy configuration mode for ${description}: 'auto' (follow global proxy), 'disable' (explicitly disable/unset proxy env), or 'overwrite' (use custom proxy URLs).";
      };

      default = mkProxyStrOpt "http://127.0.0.1:2080" "Default fallback proxy URL";
      httpProxy = mkProxyStrOpt "http://127.0.0.1:2080" "HTTP proxy URL";
      httpsProxy = mkProxyStrOpt "http://127.0.0.1:2080" "HTTPS proxy URL";
      allProxy = mkProxyStrOpt "socks5://127.0.0.1:2080" "ALL_PROXY URL";
      noProxy = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";
        description = "NO_PROXY list for ${description} when mode is 'overwrite'.";
      };

      autoReplaceLoopback = mkOption {
        type = types.bool;
        default = autoReplaceLoopback;
        description = "Automatically replace 127.0.0.1 and localhost in proxy URLs with hostDomain.";
      };

      hostDomain = mkOption {
        type = types.str;
        default = hostDomain;
        description = "Host gateway domain name for ${description}.";
      };
    };

  # 统一代理环境变量解析函数
  resolveProxyEnv = { proxyCfg, baseProxy }:
    if proxyCfg.mode == "disable" then
      emptyProxyEnv
    else if proxyCfg.mode == "auto" then
      if baseProxy.enable then
        let
          doReplace = url: replaceLoopback {
            inherit url;
            inherit (proxyCfg) hostDomain;
            enable = proxyCfg.autoReplaceLoopback;
          };

          httpP = doReplace baseProxy.httpProxy;
          httpsP = doReplace baseProxy.httpsProxy;
          allP = doReplace baseProxy.allProxy;
          noP = baseProxy.noProxy;

          proxyVars = {
            http_proxy = httpP;
            https_proxy = httpsP;
            all_proxy = allP;
            no_proxy = noP;
          };
        in
        filterAttrs (_: v: v != null) (
          proxyVars // mapAttrs' (k: v: nameValuePair (toUpper k) v) proxyVars
        )
      else
        {}
    else if proxyCfg.mode == "overwrite" then
      let
        doReplace = url: replaceLoopback {
          inherit url;
          inherit (proxyCfg) hostDomain;
          enable = proxyCfg.autoReplaceLoopback;
        };

        resolveUrl = key: doReplace (
          if proxyCfg.${key} != null then proxyCfg.${key}
          else proxyCfg.default
        );

        httpP = resolveUrl "httpProxy";
        httpsP = resolveUrl "httpsProxy";
        allP = resolveUrl "allProxy";
        noP =
          if proxyCfg.noProxy != null then proxyCfg.noProxy
          else if baseProxy.noProxy != null && baseProxy.noProxy != "" then baseProxy.noProxy
          else "127.0.0.1,localhost,192.168.0.0/16,10.0.0.0/8,172.16.0.0/12";

        proxyVars = {
          http_proxy = httpP;
          https_proxy = httpsP;
          all_proxy = allP;
          no_proxy = noP;
        };
      in
      filterAttrs (_: v: v != null) (
        proxyVars // mapAttrs' (k: v: nameValuePair (toUpper k) v) proxyVars
      )
    else
      throw "Unknown proxy mode '${proxyCfg.mode}'";
}
