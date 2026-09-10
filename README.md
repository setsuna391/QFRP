# QFRP

**QML-GUI-FRPC** —— 基于 Qt6 / QML 的 [SakuraFrp (natfrp)](https://www.natfrp.com/) 内网穿透隧道管理客户端,面向 Linux 桌面(重点适配 Wayland + 平铺合成器)。

> 名字来源:QML-GUI-FRPC 的缩写。

## 特性

- **多隧道管理** — 启动 / 停止 / 删除隧道,实时日志输出
- **后台保活** — 退出应用后 frpc 继续运行;重新打开自动"接管"后台进程
- **崩溃自愈** — frpc 意外退出时自动重启(线性退避,最多 5 次,稳定运行 60s 计数清零);手动停止不会误重启
- **危险操作二次确认** — 删除隧道、退出登录均需确认
- **7 套配色主题** — 樱花粉 / 薰衣草紫 / 薄荷绿 / 天空蓝 / 蜜橘橙 / 雾灰蓝 / 夜来香(深色)
- **自定义壁纸** — 设置页选择图片(复制进缓存,原图移动不影响),支持打包内置默认壁纸
- **无边框窗口** — 自绘窗口控制按钮,顶栏拖动,适配 niri 等平铺合成器
- **细节动效** — 全局贝塞尔缓动、悬停缩放、列表级联入场,零常驻开销

## 构建

依赖(Arch / CachyOS):

```bash
sudo pacman -S --needed cmake qt6-base qt6-declarative qt6-wayland
```

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j"$(nproc)"
./build/bin/QML_FRPC
```

frpc 二进制在 CMake 配置阶段自动从 natfrp 官方源下载到 `third_party/`(需联网);
也可手动放置 `third_party/frpc` 跳过下载。运行时若找不到 frpc,应用会自动下载。

## 安装

本地打包安装到 `~/.local`:

```bash
./packaging/install-local.sh
```

或使用 AUR 风格的 `packaging/PKGBUILD`。

## 使用

1. 登录:粘贴 SakuraFrp 的访问 Token(仅保存在本机 `~/.config/QML_FRPC/`)
2. 隧道页选择隧道启动;日志页实时查看 frpc 输出
3. **关闭应用不会停止隧道**——frpc 转入后台,下次启动应用自动接管

## 目录结构

```
qml/        界面(QML):Main / LoginView / MainView / TunnelCard / Theme(主题+动效令牌)
src/        C++:main / ApiClient(natfrp API) / FrpcManager(进程管理) / AppSettings(壁纸设置)
include/    对应头文件
packaging/  PKGBUILD / .desktop / 本地安装脚本
assets/     应用图标;可放 assets/wallpaper.* 作为内置默认壁纸
```

## 许可

尚未选择许可证,如需使用请先联系作者。
