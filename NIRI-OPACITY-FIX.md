# QFRP 修复记录：niri 半透明透底 + 冷启动磨砂烘焙失效

> 2026-11-21 · 环境：NixOS 26.11 + niri（平铺合成器）+ Qt 6.12 + NVIDIA(Vulkan)

## 一、问题现象

1. **每次冷启动**，窗口整体半透明 —— niri 桌面壁纸从窗口底下透出来，内容残缺
2. 部分场景下磨砂玻璃层失效（壁纸原图裸奔、无模糊无压暗），**要鼠标拖动窗口才恢复**
3. 每次启动日志里有 `Cannot open: ~/.cache/QML_FRPC/QML_FRPC/wallpaper/wallpaper.jpg` 警告

## 二、根因分析

### 1. niri 全局窗口规则 `opacity 0.85`（合成器层）

`~/.config/niri/config.kdl` 里有无 `match` 的全局窗口规则：

```kdl
window-rule {
    draw-border-with-background false
    geometry-corner-radius 10.000000 10.000000 10.000000 10.000000
    clip-to-geometry true
    opacity 0.850000
}
```

合成器把**整个窗口缓冲**按 85% 不透明度混合，桌面从底下透出 15%。这发生在合成器层面，
**应用侧无法对抗**，只能让 niri 按 app-id 放行。

- QFRP 的 Wayland app-id 是 `qml-frpc`（`main.cpp` 里 `setDesktopFileName("qml-frpc")`，注释即说明为 niri 窗口规则预留）

### 2. 磨砂烘焙时序竞态（应用层）

`MainView.qml` 的磨砂背景是"烘焙一次、逐帧零成本"的设计：
`frostRig`（壁纸 + MultiEffect 模糊 + 遮罩）→ `frostBg`（`ShaderEffectSource`，`live: false`）。

`Component.onCompleted` 里 `scheduleUpdate()` 只是把烘焙**排队**，真正执行要等场景图出帧。
niri 这类合成器可能在窗口首帧前暂停渲染 → 排队的烘焙永远不执行 →
窗口停在未烘焙的原始帧上，直到拖动窗口等事件触发重绘。

### 3. 壁纸设置悬空

设置里记录的壁纸路径指向 `~/.cache/QML_FRPC/.../wallpaper.jpg`，缓存目录被系统清理后
文件不存在，`effectiveSource` 仍非空 → Image 每次启动加载失败。

## 三、已应用的修复

### 1. niri 配置：QFRP 全不透明例外（本地已生效）

利用 niri 规则"后匹配覆盖前匹配"的语义，在全局规则后追加（只影响 QFRP，其余窗口保持半透明美学）：

```kdl
window-rule {
    match app-id="^qml-frpc$"
    opacity 1.0
}
```

本地已把 `~/.config/niri/config.kdl` 符号链接替换为实体文件（原内容 + 上述规则），
`niri validate` 通过，热重载生效。

### 2. 磨砂烘焙突发（`qml/MainView.qml`）

启动后 ~1.4s 内每 120ms 补一次 `scheduleUpdate()`（`live:false` 下无帧可渲染时只是标脏，
零成本），渲染一恢复烘焙就能落帧；窗口从隐藏工作区切回（`visible` 翻转）时同样补一轮。

新增：`frostBakeBurst` Timer、`root.rebakeFrostBurst()`、`frostBg` 上的 `Window.window.onVisibleChanged` 连接。

### 3. 壁纸设置自愈（`src/AppSettings.cpp`）

构造时校验：记录的壁纸文件不存在则清掉设置，回落到内置壁纸，消除每次启动的加载失败。

### 4. 移除内置默认壁纸（`assets/wallpaper.jpg` 删除）

CMake 按 `assets/wallpaper.*` 存在与否 GLOB 打包（`CONFIGURE_DEPENDS`），删掉文件即不打包，
未选壁纸时使用主题纯色背景。**机制保留**：以后想恢复内置壁纸，放一个 `assets/wallpaper.*` 重新构建即可。

## 四、持久化（防止 home-manager switch 覆盖）

本地实体文件会被 HM 生成的符号链接顶回，需把规则进 Nix 配置仓库（YWJnixOS）：

在 `home/programs/desktop/niri/override-config.nix` 的 `extraConfig` kdl 段里、
firefox `opacity 1.0` 规则旁，加：

```kdl
window-rule {
    match app-id="^qml-frpc$"
    opacity 1.0
}
```

然后重建：

```bash
nixos-rebuild switch --flake /etc/nixos
```

rebuild 后可删除本地实体文件恢复符号链接（HM 生成的配置已带规则）：

```bash
rm ~/.config/niri/config.kdl
home-manager switch
```

## 五、待办清单

- [ ] 把规则加进 YWJnixOS 仓库的 `override-config.nix` 并 rebuild（见上）
- [ ] `git rm --cached frp-six.com.crt frp-six.com.key` —— **TLS 私钥不要进版本库**（如已 push 远端需轮换证书），并加进 `.gitignore`
- [ ] commit 本次变更：`D assets/wallpaper.jpg`、`M qml/MainView.qml`、`M src/AppSettings.cpp`
- [ ] （可选）拆分 `MainView.qml`（4270 行）为四个 Page 组件 + Loader 按需加载
- [ ] （可选）给 `FrpcManager` 的退避/接管状态机补单元测试（`include(CTest)` 已挂但无测试）

## 六、验证方法

```bash
# 构建
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$HOME/.nix-profile" \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined"   # nix libproxy/curl workaround
cmake --build build -j"$(nproc)"

# 运行后检查:
# 1. 窗口全不透明(桌面壁纸不再透出)
# 2. 冷启动无"原图裸奔/内容残缺",无需拖动窗口
# 3. 日志(/tmp/qfrp-messages.log)无 "Cannot open wallpaper" 警告
```
