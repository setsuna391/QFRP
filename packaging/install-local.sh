#!/usr/bin/env bash
#本地打包安装:构建 Release 并安装到 ~/.local(二进制/图标/桌面入口)
#用法: ./packaging/install-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

#CMAKE_INSTALL_RPATH_USE_LINK_PATH: 安装时保留链接期 RPATH。NixOS 下 Qt 在
#/nix/store 的非标准路径里,CMake 默认会在 install 时剥掉构建期 RPATH,
#装到 ~/.local 后动态链接器就找不到 Qt,报 "cannot open shared object file"
#(传统发行版的系统 Qt 在 /usr/lib 默认搜索路径里,此开关无副作用)
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
    -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON
cmake --build build -j"$(nproc)"
cmake --install build

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo
echo "已安装到 ~/.local/bin/QML_FRPC"
echo "在应用菜单搜索「QFRP」即可启动"
