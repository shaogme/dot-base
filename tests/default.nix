{ ... }:
let
  # 导入 npins 锁定的源
  sources = import ./npins;

  # 强制使用锁定的 nixpkgs 版本
  pkgs = import sources.nixpkgs { };

  # 导入库实现，使用确定的 pkgs
  library = import ../default.nix { inherit pkgs; };
in
{
  # 静态评估检查
  static = import ./static.nix { inherit pkgs library; };

  # 虚拟机运行时测试
  vmtest = import ./vmtest.nix { inherit pkgs library; };
}
