{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.base.hardware;
in
{
  imports = [
    ./network/single-interface.nix
  ];

  options.base.hardware = {
    type = lib.mkOption {
      type = lib.types.enum [ "physical" "vps" ];
      default = "physical";
      description = "Type of the hardware: physical or vps";
    };
  };

  config = lib.mkIf (cfg.type == "vps") (import "${modulesPath}/profiles/qemu-guest.nix" { inherit config lib pkgs; });
}
