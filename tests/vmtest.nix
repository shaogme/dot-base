{ pkgs, library }:
pkgs.testers.nixosTest {
  name = "library-runtime-test";
  
  nodes.machine = { config, pkgs, ... }: {
    imports = [ library.nixosModules.default ];
    
    base = {
      enable = true;
      auth.root.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... dummy@test" ];
      memory.mode = "aggressive";
      dns.smartdns.mode = "china";
      container.podman.enable = true;
      performance.tuning.enable = true;
    };
    
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
    
    # 4. 检查内存优化 (zram)
    machine.succeed("zramctl")
    machine.succeed("swapon --show | grep zram")
    
    # 5. 检查 SmartDNS
    machine.wait_for_unit("smartdns.service")
    machine.succeed("systemctl is-active smartdns")
    machine.succeed("nc -z -u 127.0.0.1 53") # 检查 DNS 端口
    
    # 6. 检查 Podman 容器服务
    machine.succeed("podman --version")
    machine.succeed("podman info")
    
    # 7. 检查性能调优 (Tuned)
    machine.wait_for_unit("tuned.service")
    machine.succeed("systemctl is-active tuned")
    
    # 8. 检查防火墙 (nftables)
    machine.succeed("nft list ruleset")
    
    # 9. 检查时区
    output = machine.succeed("date +%Z")
    assert "CST" in output or "UTC" in output
  '';
}

