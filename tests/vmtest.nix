{ pkgs, library }:
pkgs.testers.nixosTest {
  name = "library-runtime-test";
  
  nodes.machine = { config, pkgs, lib, ... }:
  let
    baseUpgradeProbe = pkgs.writeShellScript "base-upgrade-probe" ''
      echo original >> /run/base-upgrade-invocations
    '';
    changedBaseUpgradeProbe = pkgs.writeShellScript "base-upgrade-probe-changed" ''
      echo changed >> /run/base-upgrade-invocations
    '';
  in {
    imports = [
      library.nixosModules.default
      library.nixosModules.kernel-xanmod
    ];
    
    base = {
      enable = true;
      auth.root.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... dummy@test" ];
      memory.mode = "aggressive";
      dns.smartdns.mode = "china";
      container.podman.enable = true;
      performance.tuning.profile = "vps";
      update.enable = true;
    };

    # Keep the updater service harmless while testing how a live oneshot unit
    # behaves when switch-to-configuration sees a changed ExecStart.
    systemd.services.base-upgrade.serviceConfig = {
      ExecStart = lib.mkOverride 60 "${baseUpgradeProbe}";
      RemainAfterExit = true;
    };
    specialisation.changedBaseUpgrade.configuration.systemd.services.base-upgrade.serviceConfig.ExecStart =
      lib.mkForce "${changedBaseUpgradeProbe}";
    
    # 虚拟机测试所需的最小硬件配置
    virtualisation.memorySize = 1024; # 增加内存以支持更多服务
  };

  testScript = ''
    # 1. 等待基础系统启动
    machine.wait_for_unit("multi-user.target")
    
    # 2. 检查 SSH 服务
    machine.wait_for_unit("sshd.service")
    machine.succeed("systemctl is-active sshd")
    
    # 3. 检查基本工具 (git)
    machine.succeed("git --version")

    # 4. Verify the independently pinned XanMod kernel booted successfully
    uname_r = machine.succeed("uname -r").strip()
    print(f"Running kernel: {uname_r}")
    assert "xanmod1" in uname_r
    
    # 5. 检查内存优化 (zram)
    machine.succeed("zramctl")
    machine.succeed("swapon --show | grep zram")
    
    # 6. 检查 SmartDNS
    machine.wait_for_unit("smartdns.service")
    machine.succeed("systemctl is-active smartdns")
    machine.succeed("nc -z -u 127.0.0.1 53") # 检查 DNS 端口
    
    # 7. 检查 Podman 容器服务
    machine.succeed("podman --version")
    machine.succeed("podman info")
    
    # 8. 检查性能调优 (Tuned)
    machine.wait_for_unit("tuned.service")
    machine.succeed("systemctl is-active tuned")
    
    # 9. 检查防火墙 (nftables)
    machine.succeed("nft list ruleset")
    
    # 10. 检查时区
    output = machine.succeed("date +%Z")
    assert "CST" in output or "UTC" in output

    # 11. 检查更新子系统 (CLI 工具与升级服务)
    help_output = machine.succeed("dot-update --help")
    assert "Usage: dot-update" in help_output
    assert "Default Pull:       No" in help_output
    machine.succeed("base-update --help")
    machine.succeed("nixos-update --help")
    service_cat = machine.succeed("systemctl cat base-upgrade.service")
    assert "ExecStart=" in service_cat
    assert "base-upgrade-probe" in service_cat
    assert "X-RestartIfChanged=false" in service_cat
    _, status_output = machine.execute("systemctl status base-upgrade.service")
    assert "Loaded: loaded" in status_output
    assert "Active: inactive (dead)" in status_output

    # A NixOS switch must not restart the updater while it is already running.
    machine.succeed("systemctl start base-upgrade.service")
    machine.succeed("test $(wc -l < /run/base-upgrade-invocations) -eq 1")
    machine.succeed("/run/current-system/specialisation/changedBaseUpgrade/bin/switch-to-configuration test")
    machine.succeed("test $(wc -l < /run/base-upgrade-invocations) -eq 1")
    machine.succeed("systemctl stop base-upgrade.service")
  '';
}
