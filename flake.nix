{
  description = "Dot Base";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      lib = import ./default.nix { pkgs = { }; };
    in
    {
      inherit (lib) nixosModules;
    };
}
