{
  lib,
  stdenv,
  cmake,
  ninja,
  wrapQtAppsHook,
  qtbase,
  qtdeclarative,
  src,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "qml-frpc";
  version = "0.3.0";

  #src 由 flake 传入(= flake 源,git 跟踪文件);third_party/frpc 不在其中,
  #构建期联网下载也被关掉,frpc 由应用首次运行时自动下载到用户缓存目录
  inherit src;

  #nix 构建沙箱无网络:CMake 配置期跳过 frpc 下载,运行时应用自会下载
  cmakeFlags = [
    "-DQFRP_BUNDLE_FRPC=OFF"
    "-DCMAKE_BUILD_TYPE=Release"
  ];

  nativeBuildInputs = [
    cmake
    ninja
    wrapQtAppsHook
  ];

  buildInputs = [
    qtbase
    qtdeclarative
  ];

  #nixpkgs 的 Mesa/glvnd 找不到系统 NVIDIA EGL vendor 时,Qt 会静默回退 llvmpipe
  #软渲染。launcher 在运行时探测系统 NVIDIA Vulkan ICD,存在则强制 Vulkan 后端
  #绕开 EGL(本机已验证);其他环境保持 Qt 默认。:- 默认值写法保留用户覆盖能力。
  #Qt 环境由 wrapQtAppsHook 包在 QML_FRPC.bin 上,launcher 只做探测和转发
  postInstall = ''
    mv $out/bin/QML_FRPC $out/bin/QML_FRPC.bin
    cat > $out/bin/QML_FRPC <<'LAUNCH'
    #!/bin/sh
    if [ -f /run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json ]; then
        export QSG_RHI_BACKEND="''${QSG_RHI_BACKEND:-vulkan}"
        export VK_ICD_FILENAMES="''${VK_ICD_FILENAMES:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}"
    fi
    exec "$(dirname "$0")/QML_FRPC.bin" "$@"
    LAUNCH
    chmod +x $out/bin/QML_FRPC
    substituteInPlace $out/share/applications/qml-frpc.desktop \
      --replace-fail "Exec=QML_FRPC" "Exec=qml-frpc"
    ln -sf QML_FRPC $out/bin/qml-frpc
  '';

  strictDeps = true;

  meta = {
    description = "QFRP — SakuraFrp tunnel manager built with Qt6/QML";
    homepage = "https://github.com/setsuna391/QFRP";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "QML_FRPC";
  };
})
