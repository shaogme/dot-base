{ pkgs, library }:
pkgs.testers.runNixOSTest {
  name = "network-facter-static";
  requiredFeatures.kvm = false;

  nodes = {
    router = { ... }: {
      virtualisation.interfaces.eth1.vlan = 1;
      networking = {
        firewall.enable = false;
        useDHCP = false;
        useNetworkd = true;
      };
      systemd.network = {
        enable = true;
        networks."10-eth1" = {
          matchConfig.Name = "eth1";
          address = [ "192.0.2.1/24" ];
        };
      };
    };

    client = { ... }: {
      imports = [ library.nixosModules.default ];

      virtualisation.interfaces.eth1.vlan = 1;
      networking.firewall.enable = false;
      hardware.facter.report = {
        hardware.network_interface = [
          {
            sub_class.name = "Ethernet";
            unix_device_names = [ "eth1" ];
          }
        ];
      };

      base = {
        enable = true;
        auth.root.authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... dummy@test" ];
        hardware.network = {
          enable = true;
          usePredictableInterfaceNames = false;
          interfaces.eth1 = {
            dhcp = "no";
            ipv4 = {
              addresses = [ { address = "192.0.2.2"; prefixLength = 24; } ];
              gateway = "192.0.2.1";
            };
          };
        };
      };
    };
  };

  testScript = ''
    start_all()
    router.wait_for_unit("network.target")
    client.wait_for_unit("network.target")

    client.succeed("test ! -e /etc/systemd/network/40-eth1.network")
    client.succeed("grep -qx 'Address=192.0.2.2/24' /etc/systemd/network/10-eth1.network")
    client.succeed("ip -4 addr show dev eth1 | grep -q '192.0.2.2/24'")
    client.succeed("ip -4 route show default | grep -q 'via 192.0.2.1 dev eth1'")
    client.wait_until_succeeds("ping -c 1 192.0.2.1")
  '';
}
