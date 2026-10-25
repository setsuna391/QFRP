{
  description = "QFRP — QML GUI FRPC (SakuraFrp tunnel manager)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/73e728ddb6b7a12d18808f510813a13ee1fe4cce";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
      # ===== 包 =====
      packages.${system} = rec {
        qml-frpc = pkgs.qt6Packages.callPackage ./nix/package.nix { src = self; };
        default = qml-frpc;
      };

      apps.${system}.default = {
        type = "app";
        program = "${self.packages.${system}.qml-frpc}/bin/QML_FRPC";
      };

      # ===== NixOS / home-manager 模块 =====
      nixosModules.default = import ./nix/module.nix self;
      nixosModules.qml-frpc = self.nixosModules.default;

      # ===== 开发环境(保留) =====
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          cmake
          gcc
          cmake-language-server
          qt6Packages.qtbase
          qt6Packages.qtdeclarative
          libglvnd
          vulkan-headers
        ];

        shellHook = ''
          export Qt6_DIR="${pkgs.qt6Packages.qtbase}/lib/cmake/Qt6"
          export CMAKE_PREFIX_PATH="${pkgs.qt6Packages.qtbase}:${pkgs.qt6Packages.qtdeclarative}:${pkgs.libglvnd}:${pkgs.vulkan-headers}''${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
          export QML2_IMPORT_PATH="${pkgs.qt6Packages.qtdeclarative}/lib/qt-6/qml''${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}"
        '';
      };
    };
}
