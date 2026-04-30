{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.base.performance.tuning;
in {
  options.base.performance.tuning = {
    enable = mkEnableOption "Tuned performance tuning profiles";
  };

  config = mkIf cfg.enable {
    services.tuned.enable = true;
    environment.systemPackages = [ pkgs.tuned ];
    # 针对 VPS 推荐 'virtual-guest' 或 'throughput-performance'
    environment.etc."tuned/active_profile".text = "virtual-guest";
  };
}
