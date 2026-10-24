# QFRP

**QML-GUI-FRPC** —— 基于 Qt6 / QML 的 [SakuraFrp (natfrp)](https://www.natfrp.com/) 内网穿透隧道管理客户端,面向 Linux 桌面(重点适配 Wayland + 平铺合成器,兼容 Windows)。

> 名字来源:QML-GUI-FRPC 的缩写。

## 特性

### 隧道管理
- **多隧道管理** — 启动 / 停止 / 编辑 / 删除,实时日志输出
- **流量趋势图** — 每条隧道的小时级真实流量面积图(`/tunnel/traffic`)
- **后台保活** — 退出应用后 frpc 继续运行;重新打开自动"接管"
- **崩溃自愈** — frpc 意外退出时自动重启(线性退避,最多 5 次,稳定运行 60s 计数清零);手动停止不会误重启
- **隧道编辑** — 修改备注 / 本地 IP / 本地端口(`/tunnel/edit`)
- **运行时长** — 运行中的隧道实时显示持续运行时间
- **复制访问地址 / 启动命令** — 一键复制 `节点域名:端口` 或 `frpc -f token:id`
- **危险操作二次确认** — 删除隧道、退出登录均需确认

### 节点
- **分类筛选** — 全部 / 无限制 / VIP / PLUS(带数量统计),按名称即时搜索
- **负载显示** — 节点实时负载百分比(`/node/stats`)
- **门槛标记** — 当前账号不可用的节点自动置灰并标注所需用户组

### 创建隧道
- **全类型支持** — TCP / UDP / HTTP / HTTPS
- **域名绑定校验** — HTTP(S) 隧道的域名格式、数量(最多 3 个)、泛域名检查
- **固定远程端口** — 可选填写,留空由服务器随机分配
- **配额检测** — 隧道数达到账号上限时禁用创建
- **合规提示** — 公开游戏服务器节点限制说明

### 信息与更新
- **公告栏** — 平台公告横幅 + 全文查看(`/system/bulletin`)
- **流量历史** — 近 7 天每日用量柱状图(`/user/traffic_history`)
- **frpc 版本检查** — 内置版本与官方最新版对比,一键下载更新(`/system/clients`)
- **流量包配额** — 识别用户流量包并计算剩余配额(`/user/data_plans`)

### 界面
- **8 套配色主题** — 樱花粉 / 薰衣草紫 / 薄荷绿 / 天空蓝 / 蜜橘橙 / 雾灰蓝 / 夜来香(深色)/ 曜石(深色)
- **磨砂玻璃界面** — 壁纸高斯模糊 + 半透明玻璃卡片 + 点阵律动背景
- **弹簧动效** — 导航胶囊滑动跟随、页面切换、卡片 3D 倾斜、按钮回弹、列表级联入场
- **樱花彩蛋** — 点击卡片粒子爆发、连点 logo 触发全屏樱花雨、登录页花瓣飘落
- **自定义壁纸** — 设置页选择图片(复制进缓存,原图移动不影响),支持打包内置默认壁纸
- **无边框窗口** — 自绘窗口控制按钮,适配 niri 等平铺合成器
- **硬件加速** — 自动选择 Vulkan / OpenGL 渲染后端(启动脚本处理 NVIDIA 环境)

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

frpc 二进制在 CMake 配置阶段自动从 natfrp 官方源下载到 `third_party/`(需联网);也可手动放置 `third_party/frpc` 跳过下载。运行时若找不到 frpc,应用会自动下载。

NixOS 用户:仓库提供 `flake.nix` 开发环境,`tools/cmake-nix` / `tools/run-nix` 封装了构建与启动(含 NVIDIA Vulkan 渲染后端选择)。

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

启动参数:`--page=nodes|tunnels|log|settings` 可直达指定页面。

## 常见问题

- **登录超时 / 请求卡住** — 若你的网络环境 IPv6 不通(域名解析返回 AAAA 记录但无法连接),Qt 会优先尝试 IPv6 并长时间卡住。临时方案:禁用 IPv6
  `sudo sysctl net.ipv6.conf.all.disable_ipv6=1 net.ipv6.conf.default.disable_ipv6=1 net.ipv6.conf.wlo1.disable_ipv6=1`,或让系统优先解析 IPv4(`/etc/gai.conf` 加 `precedence ::ffff:0:0/96 100`)
- **窗口显示为空白** — 应用最小化到不可见工作区时,Wayland 合成器会暂停其渲染,切回工作区即可

## 目录结构

```
qml/        界面(QML):Main / LoginView / MainView / Theme(主题+动效令牌)等
src/        C++:main / ApiClient(natfrp API) / FrpcManager(进程管理) / AppSettings(壁纸设置)
include/    对应头文件
assets/     应用图标;可放 assets/wallpaper.* 作为内置默认壁纸
packaging/  PKGBUILD / .desktop / 本地安装脚本
tools/      nix 开发环境构建/启动脚本
```

## 许可

本项目基于 [MIT License](LICENSE) 开源。SakuraFrp / natfrp 是其服务提供商的商标,本项目与其无隶属关系,仅为第三方客户端。
