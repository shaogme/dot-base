{
  description = "Dot Base";

  outputs = { self }:
    let
      base = import ./default.nix { };
    in
    {
      inherit (base) nixosModules;

      # 暴露一个库函数，允许外部用户显式注入特定的 pkgs
      lib = {
        withPkgs = pkgs: import ./default.nix { inherit pkgs; };
      };
    };
}
