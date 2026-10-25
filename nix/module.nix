# NixOS / home-manager 模块:programs.qml-frpc.enable = true
self: { config, lib, pkgs, ... }:
with lib; let
  cfg = config.programs.qml-frpc;
in {
  options.programs.qml-frpc = {
    enable = mkEnableOption "QFRP (SakuraFrp 隧道管理客户端)";

    package = mkOption {
      type = types.package;
      default = self.packages.${pkgs.system}.qml-frpc;
      defaultText = literalExpression "packages.qml-frpc";
      description = "QFRP 包";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
