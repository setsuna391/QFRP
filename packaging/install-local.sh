#!/usr/bin/env bash
#本地打包安装:构建 Release 并安装到 ~/.local(二进制/图标/桌面入口)
#用法: ./packaging/install-local.sh
set -euo pipefail
cd "$(dirname "$0")/.."

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build build -j"$(nproc)"
cmake --install build

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo
echo "已安装到 ~/.local/bin/QML_FRPC"
echo "在应用菜单搜索「QFRP」即可启动"
