{
  description = "Dot Base";

  outputs = { self }:
    let
      lib = import ./default.nix { pkgs = { }; };
    in
    {
      inherit (lib) nixosModules;
    };
}
