import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtQuick.Effects
import QtCore

//主界面:左侧导航栏 + 右侧内容区(隧道/节点/日志/设置四个页面)
Item {
    id: root

    // ===== 属性 =====
    property string currentPage: "tunnels"
    property string pageTitle: "隧道管理"
    property var tunnels: []
    property var nodes: []
    property var userInfo: ({})
    //所在窗口(无边框窗口的控制按钮/拖动用)
    readonly property var appWindow: Window.window
    //处于"已启动"状态的隧道 id 集合:卡片会随列表刷新重建,
    //启动/停止状态必须放在这里,否则一刷新所有卡片都会变回"启动"。
    //真实状态由 frpc(FrpcManager)通过信号驱动更新
    property var runningIds: new Set()

    //待删除的隧道 id,删除确认弹窗用
    property string pendingDeleteId: ""

    //运行状态:每条隧道的启动时刻(接管的从接管起算)+ 每秒心跳驱动时长刷新
    property var startedAt: ({})
    property real nowMs: 0
    Timer {
        interval: 1000
        running: root.runningIds.size > 0
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    function uptimeStr(id) {
        var t0 = (root.startedAt || {})[id]
        if (!t0) return ""
        var sec = Math.max(0, Math.floor((root.nowMs - t0) / 1000))
        if (sec < 60) return sec + " 秒"
        if (sec < 3600) return Math.floor(sec / 60) + " 分钟"
        if (sec < 86400) return Math.floor(sec / 3600) + " 小时 " + Math.floor((sec % 3600) / 60) + " 分"
        return Math.floor(sec / 86400) + " 天 " + Math.floor((sec % 86400) / 3600) + " 小时"
    }

    //公告(最新一条置顶展示,标题一致则视为已读)
    property var bulletins: []
    property string dismissedBulletin: ""

    function openBulletin(b) {
        bulletinPopup.itemData = b
        bulletinPopup.open()
    }

        //扩展 API 数据:逐隧道流量/节点负载/流量历史/最新 frpc 版本/公告
    property var tunnelTraffic: ({})
    property var nodeLoad: ({})
    property var trafficHistory: []
    property string frpcLatest: ""
    property var dataPlans: []
    property bool frpcUpdating: false

        //节点页筛选:分类 + 关键词
    property string nodeFilter: "all"
    property string nodeSearch: ""

    //按分类与关键词过滤后的节点列表。
    //vip = 节点要求的用户等级(0 无限制 / 3 VIP / 4 PLUS),
    //与 /user/info 里 group.level 比较,低于要求的节点标记为不可用
    readonly property var filteredNodes: {
        var out = []
        var level = root.userInfo.group && root.userInfo.group.level !== undefined ? root.userInfo.group.level : 0
        for (var i = 0; i < root.nodes.length; i++) {
            var n = root.nodes[i]
            var v = n.vip || 0
            if (root.nodeFilter === "free" && v !== 0) continue
            if (root.nodeFilter === "vip" && v !== 3) continue
            if (root.nodeFilter === "plus" && v !== 4) continue
            var kw = root.nodeSearch.toLowerCase()
            if (kw !== "" && String(n.name || "").toLowerCase().indexOf(kw) < 0) continue
            out.push(n)
        }
        return out
    }

    //分类芯片模型(带数量)
    readonly property var nodeFilterModel: {
        var counts = { all: root.nodes.length, free: 0, vip: 0, plus: 0 }
        for (var i = 0; i < root.nodes.length; i++) {
            var v = root.nodes[i].vip || 0
            if (v === 0) counts.free++
            else if (v === 3) counts.vip++
            else counts.plus++
        }
        return [
            { key: "all", label: "全部", count: counts.all },
            { key: "free", label: "无限制", count: counts.free },
            { key: "vip", label: "VIP", count: counts.vip },
            { key: "plus", label: "PLUS", count: counts.plus }
        ]
    }

    //创建弹窗专用节点列表:当前账号可用的排前面(按名称排序),
    //不可用的排后面并置灰;sectionKey 供 ListView 分组头使用
    readonly property var createableNodes: {
        var level = root.userInfo.group && root.userInfo.group.level !== undefined ? root.userInfo.group.level : 0
        var usable = [], locked = []
        for (var i = 0; i < root.nodes.length; i++) {
            var n = root.nodes[i]
            var v = n.vip || 0
            var item = { name: n.name, id: n.id, vip: v, usable: v <= level,
                         sectionKey: v <= level ? "当前账号可用" : "需要更高用户组" }
            if (item.usable) usable.push(item)
            else locked.push(item)
        }
        var byName = function(a, b) { return String(a.name).localeCompare(String(b.name), "zh") }
        usable.sort(byName)
        locked.sort(byName)
        return usable.concat(locked)
    }

    //节点 ID → 接入域名(隧道卡的"访问地址"用它拼);查不到返回空
    function nodeHost(nodeId) {
        for (var i = 0; i < root.nodes.length; i++) {
            if (String(root.nodes[i].id) === String(nodeId))
                return String(root.nodes[i].host || "")
        }
        return ""
    }

    //隧道的对外访问地址:http(s) 隧道 remote 本身就是域名,其余是 节点域名:远程端口
    function tunnelAccessAddr(t) {
        var type = String(t.type || "tcp").toLowerCase()
        if (type === "http" || type === "https")
            return String(t.remote || "")
        var host = root.nodeHost(t.node)
        return host !== "" ? host + ":" + (t.remote || "?") : ":" + (t.remote || "?")
    }

    function nodeTierLabel(vip) {
        if (vip === 3) return "VIP"
        if (vip === 4) return "PLUS"
        if (vip === 0) return "无限制"
        return "等级 " + vip
    }

    function nodeTierColor(vip) {
        if (vip === 3) return cWarning
        if (vip === 4) return cAccent
        if (vip === 0) return cSuccess
        return cError
    }

    function openNodeDetail(n) {
        nodeDetailPopup.nodeData = n
        nodeDetailPopup.open()
    }

    // ===== 配色(跟随全局主题,见 Theme.qml) =====
    readonly property color cBg: Theme.cBg
    readonly property color cSidebar: Theme.cSidebar
    readonly property color cCard: Theme.cCard
    readonly property color cBorder: Theme.cBorder
    readonly property color cAccent: Theme.cAccent
    readonly property color cAccentHover: Theme.cAccentHover
    readonly property color cText: Theme.cText
    readonly property color cTextSec: Theme.cTextSec
    readonly property color cTextMuted: Theme.cTextMuted
    readonly property color cSuccess: Theme.cSuccess
    readonly property color cError: Theme.cError
    readonly property color cWarning: Theme.cWarning

    // ===== 导航项 =====
    property var navItems: [
        { name: "tunnels", label: "隧道管理", icon: "tunnel" },
        { name: "nodes", label: "节点列表", icon: "node" },
        { name: "log", label: "运行日志", icon: "log" },
        { name: "settings", label: "设置", icon: "settings" }
    ]

    // ===== 日志模型 =====
    ListModel { id: logModel }

    //粉色细滚动条,供各列表复用
    //自定义了 contentItem 会失去 Basic 样式自带的"内容不满一屏时隐藏"逻辑,
    //因此这里手动按 size < 1(内容可滚动)且 active/hovered(正在滚动或鼠标在条上)
    //来控制淡入淡出;淡出时条仍在原位,鼠标移过去会重新出现,可以拖拽
    component PinkScrollBar: ScrollBar {
        id: sb
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 6
            radius: 3
            color: Theme.cScrollbar
            opacity: sb.policy === ScrollBar.AlwaysOn || ((sb.active || sb.hovered) && sb.size < 1.0) ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
        }
    }

    //平滑滚轮:Flickable 系默认滚轮是一格一格跳,这里把每次滚动
    //变成短促的平滑动画(位置插值),手感顺滑。放在 Flickable 内即可生效
    component SmoothWheel : WheelHandler {
        id: smoothWheel
        property real speed: 2.6
        property Flickable flick: parent
        //WheelHandler 不是 Item,不能带子对象;动画用属性内联声明
        property NumberAnimation anim: NumberAnimation {
            target: smoothWheel.flick
            property: "contentY"
            duration: 320
            easing.type: Easing.OutQuint
        }
        onWheel: function(ev) {
            var max = smoothWheel.flick.contentHeight - smoothWheel.flick.height
            var to = Math.max(0, Math.min(max, smoothWheel.flick.contentY - ev.angleDelta.y * smoothWheel.speed))
            if (to !== smoothWheel.anim.to || !smoothWheel.anim.running) {
                smoothWheel.anim.stop()
                smoothWheel.anim.to = to
                smoothWheel.anim.restart()
            }
        }
    }

    //bento 统计卡容器:进入隧道页时按 enterDelay 阶梯式上滑淡入,离场静默复位。
    //内容通过 default 属性放进内部 ColumnLayout;sheenEnabled 打开后有缓缓扫过的高光。
    //全部用 PropertyAnimation(而非 Animator):niri + NVIDIA 下 Animator 不推进
    component StatReveal : Rectangle {
        id: revealRoot
        default property alias content: revealCol.data
        property int enterDelay: 0
        property bool sheenEnabled: false
        radius: 18
        clip: true
        color: Theme.cCard
        opacity: 0
        transform: Translate { id: revealT; y: 22 }

        SequentialAnimation {
            running: tunnelsPageCol.visible
            PauseAnimation { duration: revealRoot.enterDelay }
            ParallelAnimation {
                NumberAnimation { target: revealRoot; property: "opacity"; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                NumberAnimation { target: revealT; property: "y"; from: 28; to: 0; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            }
        }
        ParallelAnimation {
            running: !tunnelsPageCol.visible
            NumberAnimation { target: revealRoot; property: "opacity"; to: 0; duration: 100 }
            NumberAnimation { target: revealT; property: "y"; to: 22; duration: 1 }
        }

        //扫过的高光(仅渐变卡开启)
        Rectangle {
            visible: revealRoot.sheenEnabled
            width: 54
            height: parent.height * 1.5
            y: -parent.height * 0.25
            rotation: 14
            x: -170
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#00ffffff" }
                GradientStop { position: 0.5; color: "#38ffffff" }
                GradientStop { position: 1.0; color: "#00ffffff" }
            }
            SequentialAnimation on x {
                running: revealRoot.visible && revealRoot.sheenEnabled
                loops: Animation.Infinite
                PauseAnimation { duration: 3800 }
                NumberAnimation { from: -170; to: 240; duration: 1200; easing.type: Easing.InOutQuad }
            }
        }

        ColumnLayout {
            id: revealCol
            anchors.fill: parent
            anchors.margins: 20
            spacing: 4
        }
    }

    //卡片内的真实流量趋势图:来自 /tunnel/traffic 的小时桶数据,面积图 + 折线;
    //无数据时显示待机均衡器(纯装饰律动,由 root.waveTime 驱动)。
    //点阵拆成静态层(只在尺寸变化时重绘),律动层每帧只画柱/线,绘制成本最低
    component TrafficChart : Item {
        id: tc
        property var samples: []
        property real beat: 0

        //静态点阵层
        Canvas {
            anchors.fill: parent
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                ctx.fillStyle = Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.10)
                for (var gx = 10; gx < w; gx += 18)
                    for (var gy = 10; gy < h; gy += 16) {
                        ctx.beginPath()
                        ctx.arc(gx, gy, 1, 0, 2 * Math.PI)
                        ctx.fill()
                    }
            }
        }

        //律动层:均衡器 + 数据面积图
        Canvas {
            id: waveCanvas
            anchors.fill: parent
            antialiasing: true

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var w = width, h = height

            //待机均衡器:常驻背景律动——无数据时是主角(30%),有数据时退为衬托(12%)
            var arr = samples || []
            var n = arr.length
            var nb = 22
            var bw2 = (w - (nb - 1) * 3) / nb
            var t = tc.beat
            for (var b = 0; b < nb; b++) {
                var hgt = (0.16 + 0.34 * (0.5 + 0.5 * Math.sin(t * 1.9 + b * 0.55))
                           + 0.16 * (0.5 + 0.5 * Math.sin(t * 3.1 + b * 1.7))) * h
                ctx.fillStyle = Qt.rgba(cAccent.r, cAccent.g, cAccent.b, n === 0 ? 0.30 : 0.12)
                ctx.fillRect(b * (bw2 + 3), h - hgt, bw2, hgt)
            }

            if (n === 0) return

            var maxV = 1
            for (var i = 0; i < n; i++)
                if (arr[i].v > maxV) maxV = arr[i].v
            var pad = 6
            var xv = function(i) { return n === 1 ? w / 2 : pad + i * (w - 2 * pad) / (n - 1) }
            var yv = function(v) { return h - 5 - (v / maxV) * (h - 20) }

            //面积(渐变填充)
            ctx.beginPath()
            ctx.moveTo(xv(0), h - 5)
            for (i = 0; i < n; i++) {
                if (i === 0) { ctx.lineTo(xv(0), yv(arr[0].v)); continue }
                var mx = (xv(i - 1) + xv(i)) / 2
                ctx.quadraticCurveTo(xv(i - 1), yv(arr[i - 1].v), mx, (yv(arr[i - 1].v) + yv(arr[i].v)) / 2)
            }
            ctx.lineTo(xv(n - 1), yv(arr[n - 1].v))
            ctx.lineTo(xv(n - 1), h - 5)
            ctx.lineTo(xv(0), h - 5)
            ctx.closePath()
            var g = ctx.createLinearGradient(0, 0, 0, h)
            g.addColorStop(0, Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.30))
            g.addColorStop(1, Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.03))
            ctx.fillStyle = g
            ctx.fill()

            //折线
            ctx.beginPath()
            ctx.moveTo(xv(0), yv(arr[0].v))
            for (i = 1; i < n; i++) {
                mx = (xv(i - 1) + xv(i)) / 2
                ctx.quadraticCurveTo(xv(i - 1), yv(arr[i - 1].v), mx, (yv(arr[i - 1].v) + yv(arr[i].v)) / 2)
            }
            ctx.lineTo(xv(n - 1), yv(arr[n - 1].v))
            ctx.strokeStyle = cAccent
            ctx.lineWidth = 1.5
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()

            //末点圆点
            ctx.fillStyle = cAccent
            ctx.beginPath()
            ctx.arc(xv(n - 1), yv(arr[n - 1].v), 2.4, 0, 2 * Math.PI)
            ctx.fill()
            }
        }

        Connections {
            target: tc
            function onSamplesChanged() { waveCanvas.requestPaint() }
            function onBeatChanged() { waveCanvas.requestPaint() }
        }
    }

    // ===== 背景 =====
    Rectangle {
        anchors.fill: parent
        color: cBg
    }

    // ===== 自定义壁纸(macOS 式磨砂玻璃背景) =====
    //优先级:设置页自选的图片 > 构建时内置的壁纸(assets/wallpaper.*) > 纯色主题背景。
    //渲染链(壁纸→模糊→遮罩)藏在 visible:false 的 rig 里,用 live:false 的
    //ShaderEffectSource 一次性烘焙成静态纹理——MultiEffect 的全窗口多 pass 模糊
    //每帧重跑在 240Hz 屏上是纯浪费,烘焙后逐帧成本归零,仅在换壁纸/换主题时重烘。
    //壁纸故意放大 15%:模糊会把边缘外的透明像素卷进来导致四周发暗,放大可避免
    Item {
        id: frostRig
        //必须保持 visible:true——不在场景里的元素 ShaderEffectSource 捕获不到;
        //不在屏上直接显示由 frostBg 的 hideSource: true 负责
        width: root.width
        height: root.height

        Image {
            id: wallpaperImage
            anchors.centerIn: parent
            width: parent.width * 1.15
            height: parent.height * 1.15
            property string userSource: appSettings.wallpaperFile === ""
                                        ? "" : "file://" + appSettings.wallpaperFile
            property string effectiveSource: userSource !== ""
                                             ? userSource
                                             : (appSettings.builtinWallpaper !== ""
                                                ? "qrc:" + appSettings.builtinWallpaper : "")
            visible: effectiveSource !== ""
            source: effectiveSource
            fillMode: Image.PreserveAspectCrop
            //同步加载:异步会在首帧后才出图,磨砂层晚到造成"开窗黑一下"
            asynchronous: false
            mipmap: true
            opacity: 0.9
            onStatusChanged: if (status === Image.Ready) frostBg.scheduleUpdate()
            onSourceChanged: frostBg.scheduleUpdate()
        }

        MultiEffect {
            anchors.fill: parent
            source: wallpaperImage
            blurEnabled: true
            blurMax: 16
            blur: 1.0
            saturation: -0.15
            visible: wallpaperImage.effectiveSource !== ""
        }

        //暗色/亮色遮罩:轻微压一层保证文字对比度,过重会显得雾蒙蒙
        Rectangle {
            anchors.fill: parent
            color: Theme.cBg
            opacity: {
                    //遮罩按背景亮度自适应:深色主题压暗 28% 提对比;
                    //浅色主题的白遮罩会把全窗洗成雾,只上 10%
                    var c = Theme.cBg
                    var lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
                    return wallpaperImage.effectiveSource !== "" ? (lum > 0.5 ? 0.10 : 0.20) : 0
                }
        }
    }

    //烘焙出的静态磨砂背景。
    //注意必须全分辨率烘焙:纹理若降采样,铺回窗口时模糊半径被等比放大,
    //64px 的磨砂会变成 ~128px 的"看不清"(半分辨率省的那点带宽完全不值)
    ShaderEffectSource {
        id: frostBg
        anchors.fill: parent
        sourceItem: frostRig
        hideSource: true
        live: false
        smooth: true
        visible: wallpaperImage.effectiveSource !== ""
        Component.onCompleted: frostBg.scheduleUpdate()
        onWidthChanged: scheduleUpdate()
        Connections {
            target: Theme
            //主题切换会改遮罩色,重烘一次
            function onCurrentChanged() { frostBg.scheduleUpdate() }
        }
    }

    // ===== 信号处理 =====
    Connections {
        target: apiClient

        function onTunnelsReceived(tunnels) {
            var arr = []
            for (var i = 0; i < tunnels.length; i++) {
                arr.push(tunnels[i])
                apiClient.getTunnelTraffic(String(arr[i].id))
            }
            root.tunnels = arr
        }
        function onNodesReceived(nodes) {
            var arr = []
            for (var i = 0; i < nodes.length; i++)
                arr.push(nodes[i])
            root.nodes = arr
            //模型重置后 ComboBox 的选中可能变回 -1,默认选中第一个节点
            if (createNode.currentIndex < 0 && createNode.count > 0)
                createNode.currentIndex = 0
        }
        function onUserInfoReceived(info) { root.userInfo = info }
        function onTunnelCreated(tunnel) {
            var arr = root.tunnels.slice()
            arr.push(tunnel)
            root.tunnels = arr
            //服务器返回的 remote 是分配结果:tcp/udp 为端口号,http/https 为域名
            addLog("隧道创建成功: " + (tunnel.name || tunnel.id)
                   + (tunnel.remote !== undefined ? " → 远程 " + tunnel.remote : ""), "success")
            createErrorText.visible = false
            createPopup.close()
            createName.text = ""
            createLocalPort.text = ""
        }
        function onTunnelCreateFailed(error) {
            //创建失败:弹窗保持打开,把服务器的原因直接显示在表单里
            createErrorText.text = error
            createErrorText.visible = true
            addLog("隧道创建失败: " + error, "error")
        }
        function onTunnelDeleted(tunnelId) {
            var arr = []
            for (var i = 0; i < root.tunnels.length; i++) {
                if (root.tunnels[i].id.toString() !== tunnelId)
                    arr.push(root.tunnels[i])
            }
            root.tunnels = arr
            //删除运行中的隧道时同步停掉 frpc 进程
            if (root.runningIds.has(String(tunnelId)))
                frpc.stopTunnel(tunnelId)
            addLog("隧道已删除: " + tunnelId, "info")
        }
        function onLoginSuccess() {
            addLog("登录成功", "success")
            refreshData()
        }
        function onErrorOccurred(error) { addLog("请求失败: " + error, "error") }

        function onTunnelTrafficReceived(tunnelId, traffic) {
            var arr = []
            for (var k in traffic)
                arr.push({ ts: Number(k), v: Number(traffic[k]) })
            arr.sort(function(a, b) { return a.ts - b.ts })
            var nd = Object.assign({}, root.tunnelTraffic)
            nd[tunnelId] = arr
            root.tunnelTraffic = nd
        }

        function onNodeStatsReceived(stats) {
            var nd = {}
            var list = stats.nodes || []
            for (var i = 0; i < list.length; i++)
                nd[String(list[i].id)] = list[i]
            root.nodeLoad = nd
        }

        function onTrafficHistoryReceived(history) {
            //条目 [日期, 上期累计, 本期累计] → 差分出当日用量
            var out = []
            var prev = 0
            for (var i = 0; i < history.length; i++) {
                var e = history[i]
                var cum = Number(e[2] || 0)
                out.push({ day: String(e[0] || ""), usage: Math.max(0, cum - prev) })
                prev = cum
            }
            root.trafficHistory = out
        }

        function onDataPlansReceived(plans) { root.dataPlans = plans }

        function onSystemClientsReceived(info) {
            root.frpcLatest = info.frpc ? String(info.frpc.ver || "") : ""
        }

        function onBulletinReceived(bulletins) { root.bulletins = bulletins }

        function onTunnelEdited(tunnelId) {
            addLog("隧道 " + tunnelId + " 已更新", "success")
            refreshData()
        }

        function onTunnelEditFailed(error) {
            addLog("隧道编辑失败: " + error, "error")
        }
    }

    // ===== frpc 进程事件 =====
    Connections {
        target: frpc

        function onStarted(tunnelId) {
            var s = new Set(root.runningIds)
            s.add(String(tunnelId))
            root.runningIds = s
            var nd = Object.assign({}, root.startedAt)
            nd[String(tunnelId)] = Date.now()
            root.startedAt = nd
            addLog("frpc 已启动 (隧道 " + tunnelId + ")", "success")
        }
        function onStopped(tunnelId, exitCode) {
            var s = new Set(root.runningIds)
            s.delete(String(tunnelId))
            root.runningIds = s
            var nd = Object.assign({}, root.startedAt)
            delete nd[String(tunnelId)]
            root.startedAt = nd
            addLog("frpc 已退出 (隧道 " + tunnelId + ", 退出码 " + exitCode + ")",
                   exitCode === 0 ? "info" : "warning")
        }
        function onStartFailed(tunnelId, reason) {
            addLog("启动失败 (隧道 " + tunnelId + "): " + reason, "error")
        }
        //frpc 的 stdout/stderr 按行进日志页,同时累计到活动波形
        function onFrpcOutput(tunnelId, line) {
            addLog("frpc:" + tunnelId + " " + line, "info")
        }
        //frpc 二进制自动下载
        function onFrpcDownloadStarted() {
            addLog("未找到 frpc,正在从 natfrp 官方源自动下载...", "info")
        }
        function onFrpcDownloadFinished(path) {
            root.frpcUpdating = false
            addLog("frpc 下载完成: " + path + "(下次启动隧道生效)", "success")
        }
        function onFrpcDownloadFailed(error) {
            root.frpcUpdating = false
            addLog("frpc 下载失败: " + error + " (可在设置页手动填写 frpc 路径后点\"重新下载\"重试)", "error")
        }


    }

    // ===== 函数 =====
    function addLog(msg, level) {
        logModel.append({
            time: Qt.formatDateTime(new Date(), "hh:mm:ss"),
            msg: msg,
            level: level || "info"
        })
        if (logModel.count > 500)
            logModel.remove(0)
    }

    function refreshData() {
        apiClient.getTunnels()
        apiClient.getUserInfo()
        apiClient.getNodes()
        apiClient.getNodeStats()
        apiClient.getSystemClients()
        apiClient.getUserTrafficHistory()
        apiClient.getDataPlans()
        apiClient.getBulletin()
    }

    function tunnelName(id) {
        for (var i = 0; i < tunnels.length; i++) {
            if (String(tunnels[i].id) === String(id))
                return tunnels[i].name || String(id)
        }
        return String(id)
    }

    function toggleRunning(idStr) {
        //未运行则拉配置启动,运行中则停止——具体逻辑在 FrpcManager(C++)
        frpc.toggleTunnel(idStr)
    }

    // ===== 页面标题随切换更新 =====
    onCurrentPageChanged: {
        switch (currentPage) {
        case "tunnels": pageTitle = "隧道管理"; break
        case "nodes": pageTitle = "节点列表"; break
        case "log": pageTitle = "运行日志"; break
        case "settings": pageTitle = "设置"; break
        }
    }

    Component.onCompleted: {
        refreshData()
        addLog("程序已启动", "info")
        //恢复应用重启前仍在运行的隧道状态(进程由 FrpcManager 持有)
        var s = new Set(runningIds)
        var ids = frpc.runningTunnelIds()
        for (var i = 0; i < ids.length; i++)
            s.add(String(ids[i]))
        runningIds = s
        //支持 --page=nodes|tunnels|log|settings 启动直达指定页面
        var args = Qt.application.arguments || []
        for (var j = 0; j < args.length; j++) {
            if (args[j].indexOf("--page=") === 0)
                currentPage = args[j].substring(7)
        }
    }

    //均衡器律动节拍(40fps;240Hz 屏上低于 ~30fps 的动画肉眼可见顿挫)
    property real waveTime: 0
    Timer {
        interval: 25
        running: root.currentPage === "tunnels"
        repeat: true
        onTriggered: root.waveTime = Date.now() / 1000
    }

    // ===== 主布局:顶栏(logo + 导航胶囊 + 用户) + 全宽内容区,无侧栏 =====
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

            // 顶栏(带主题底色的衬底:导航文字不能直接压在壁纸上,
            // 浅色主题下深色文字会看不清;55% 保持玻璃层次感)
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: Qt.alpha(Theme.cBg, 0.55)

                //顶栏空白处拖动移动窗口(niri 无标题栏)
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.appWindow.startSystemMove()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 20
                    spacing: 6

                    // Logo(连点 5 次有彩蛋)
                    Text {
                        id: logoText
                        text: "QFRP"
                        color: cAccent
                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1.5
                        scale: 1.0
                        Behavior on scale { SpringAnimation { spring: 3.5; damping: 0.45; mass: 0.6 } }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: logoBounce.restart()
                        }

                        SequentialAnimation {
                            id: logoBounce
                            NumberAnimation { target: logoText; property: "scale"; to: 1.25; duration: 90; easing.type: Easing.OutQuad }
                            NumberAnimation { target: logoText; property: "scale"; to: 1.0; duration: 200; easing.type: Easing.OutBack }
                        }
                    }

                    Item { Layout.preferredWidth: 10 }

                    // 导航胶囊(选中的胶囊背景用弹簧动画滑向当前页)
                    Item {
                        id: navWrap
                        Layout.preferredWidth: navRow.implicitWidth
                        Layout.preferredHeight: 44

                        Rectangle {
                            id: navIndicator
                            readonly property int activeIndex: {
                                for (var i = 0; i < root.navItems.length; i++)
                                    if (root.navItems[i].name === root.currentPage) return i
                                return -1
                            }
                            anchors.verticalCenter: parent.verticalCenter
                            height: 38
                            width: navRepeater.itemAt(activeIndex) ? navRepeater.itemAt(activeIndex).width : 0
                            x: navRepeater.itemAt(activeIndex) ? navRepeater.itemAt(activeIndex).x : 0
                            radius: 19
                            color: Theme.cNavActive
                            opacity: activeIndex >= 0 ? 1 : 0

                            Behavior on x { SpringAnimation { spring: 2.5; damping: 0.6; mass: 1.2 } }
                            Behavior on width { SpringAnimation { spring: 2.5; damping: 0.6; mass: 1.2 } }
                        }

                        Row {
                            id: navRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                id: navRepeater
                                model: root.navItems

                                delegate: Rectangle {
                                    id: navPill
                                    readonly property bool isActive: root.currentPage === modelData.name
                                    width: pillRow.implicitWidth + 36
                                    height: 38
                                    radius: 19
                                    color: !isActive && pillArea.containsMouse ? Theme.cNavHover : "#00000000"
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Row {
                                        id: pillRow
                                        anchors.centerIn: parent
                                        spacing: 10

                                        AppIcon {
                                            iconType: modelData.icon
                                            iconColor: navPill.isActive ? cAccent : cTextSec
                                            width: 16
                                            height: 16
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Text {
                                            text: modelData.label
                                            color: navPill.isActive ? cText : cTextSec
                                            font.pixelSize: 13
                                            font.bold: navPill.isActive
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: pillArea
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: root.currentPage = modelData.name
                                    }
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // 新建隧道按钮(隧道数达到账号配额时禁用)
                    Rectangle {
                        visible: root.currentPage === "tunnels"
                        //配额来自 /user/info 的 tunnels 字段(普通用户 2 条)
                        readonly property bool quotaFull: root.tunnels.length >= (root.userInfo.tunnels !== undefined ? root.userInfo.tunnels : 2)
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: quotaFull ? 150 : 116
                        radius: 12
                        opacity: quotaFull ? 0.55 : 1.0
                        color: quotaFull ? Theme.cInputBg
                               : createActionArea.containsMouse ? cAccentHover : cAccent
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: !quotaFull && createActionArea.pressed ? 0.94 : (createActionArea.containsMouse && !quotaFull ? 1.04 : 1.0)
                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            AppIcon {
                                iconType: "plus"
                                iconColor: "#ffffff"
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: parent.parent.quotaFull ? "隧道已达上限" : "新建隧道"
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Ripple { id: createActionAreaRipple; anchors.fill: parent }
                        MouseArea {
                            id: createActionArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                if (parent.quotaFull) return
                                createActionAreaRipple.play()
                                createPopup.openCreate()
                            }
                        }
                    }

                    // 刷新按钮
                    Rectangle {
                        visible: root.currentPage === "tunnels" || root.currentPage === "nodes"
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: 86
                        radius: 12
                        color: refreshArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: refreshArea.pressed ? 0.94 : (refreshArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 6

                            AppIcon {
                                id: refreshIcon
                                iconType: "refresh"
                                iconColor: cAccent
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter

                                //点击刷新后图标旋转一周,给异步请求一个可视反馈
                                RotationAnimation {
                                    id: refreshSpin
                                    target: refreshIcon
                                    property: "rotation"
                                    from: 0
                                    to: 360
                                    duration: 620
                                    easing.type: Easing.OutBack
                                }
                            }

                            Text {
                                text: "刷新"
                                color: cText
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Ripple { id: refreshAreaRipple; anchors.fill: parent }
                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: { refreshAreaRipple.play(); { }
                                refreshSpin.restart()
                                if (root.currentPage === "tunnels") apiClient.getTunnels()
                                else if (root.currentPage === "nodes") apiClient.getNodes()
                            }
                        }
                    }

                    // 清空日志按钮
                    Rectangle {
                        visible: root.currentPage === "log"
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: 86
                        radius: 12
                        color: clearLogArea.containsMouse ? Theme.cErrorBg : Theme.cInputBg
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: clearLogArea.pressed ? 0.94 : (clearLogArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                        Text {
                            anchors.centerIn: parent
                            text: "清空"
                            color: clearLogArea.containsMouse ? cError : cText
                            font.pixelSize: 13
                        }

                        Ripple { id: clearLogAreaRipple; anchors.fill: parent }
                        MouseArea {
                            id: clearLogArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: { clearLogAreaRipple.play(); logModel.clear() }
                        }
                    }

                    //与功能按钮留出间隔
                    // 当前用户(点击打开退出登录确认)
                    Rectangle {
                        Layout.preferredHeight: 36
                        Layout.preferredWidth: userRow.implicitWidth + 28
                        radius: 18
                        color: userArea.containsMouse ? Theme.cNavHover : "#00000000"
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                            id: userRow
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                width: 24
                                height: 24
                                radius: 12
                                color: cAccent

                                Text {
                                    anchors.centerIn: parent
                                    text: (root.userInfo.name || "U").charAt(0).toUpperCase()
                                    color: "#ffffff"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            Text {
                                text: root.userInfo.name || "未登录"
                                color: cText
                                font.pixelSize: 13
                                font.bold: true
                            }
                        }

                        Ripple { id: userAreaRipple; anchors.fill: parent }
                        MouseArea {
                            id: userArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: { userAreaRipple.play(); logoutPopup.open() }
                        }
                    }

                    Item { Layout.preferredWidth: 6 }

                    //窗口控制:最小化 / 退出
                    WindowControls {
                        win: root.appWindow
                        onMinimizeClicked: root.appWindow.showMinimized()
                        onCloseClicked: {
                            if (root.runningIds.size > 0)
                                quitPopup.open()
                            else
                                root.appWindow.close()
                        }
                    }
                }
            }

            // ===== 公告横幅(有新公告时显示) =====
            Rectangle {
                visible: (root.bulletins || []).length > 0
                         && root.dismissedBulletin !== root.bulletins[0].title
                Layout.fillWidth: true
                Layout.preferredHeight: 34
                color: Qt.alpha(Theme.cWarning, 0.12)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 16
                    spacing: 10

                    Text {
                        text: "公告"
                        color: cWarning
                        font.pixelSize: 11
                        font.bold: true
                    }

                    Text {
                        Layout.fillWidth: true
                        text: (root.bulletins[0] || {}).title || ""
                        color: cText
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "查看"
                        color: cAccent
                        font.pixelSize: 12
                        font.bold: true

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openBulletin(root.bulletins[0])
                        }
                    }

                    Text {
                        text: "✕"
                        color: cTextMuted
                        font.pixelSize: 12

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissedBulletin = (root.bulletins[0] || {}).title || ""
                        }
                    }
                }
            }

            // ===== 页面内容 =====
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ----- 隧道页面:统计行 + 卡片网格 -----
                ColumnLayout {
                    id: tunnelsPageCol
                    anchors.fill: parent
                    visible: root.currentPage === "tunnels"
                    spacing: 0
                    //页面切换时整页内容从下方弹入
                    transform: Translate {
                        y: tunnelsPageCol.visible ? 0 : 26
                        Behavior on y { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }
                    }

                    // ===== bento 统计行(阶梯式入场) =====
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.topMargin: 24
                        Layout.bottomMargin: 6
                        spacing: 20

                        // 运行中(渐变主卡 + 扫过的高光)
                        StatReveal {
                            enterDelay: 0
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 116
                            //纯色半透明:跟随主题强调色,不用渐变
                            color: Qt.alpha(Theme.cAccent, 0.7)

                            Text {
                                Layout.fillWidth: true
                                text: "运行中"
                                color: "#f3e8ff"
                                font.pixelSize: 13
                                font.bold: true
                            }

                            Item { Layout.fillHeight: true }

                            Text {
                                id: runNum
                                text: root.runningIds.size
                                color: "#ffffff"
                                font.pixelSize: 42
                                font.bold: true
                                transform: Translate { id: runNumHop; y: 0 }
                                onTextChanged: runPop.restart()

                                SequentialAnimation {
                                    id: runPop
                                    NumberAnimation { target: runNumHop; property: "y"; from: -6; to: 0; duration: 170; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // 隧道总数
                        StatReveal {
                            enterDelay: 90
                            Layout.preferredWidth: 170
                            Layout.preferredHeight: 116

                            Text {
                                text: "隧道总数"
                                color: cTextSec
                                font.pixelSize: 13
                            }

                            Item { Layout.fillHeight: true }

                            Text {
                                id: totalNum
                                text: root.tunnels.length
                                color: cText
                                font.pixelSize: 42
                                font.bold: true
                                transform: Translate { id: totalNumHop; y: 0 }
                                onTextChanged: totalPop.restart()

                                SequentialAnimation {
                                    id: totalPop
                                    NumberAnimation { target: totalNumHop; property: "y"; from: -6; to: 0; duration: 170; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        // 用户与流量(填充剩余宽度)
                        StatReveal {
                            enterDelay: 180
                            Layout.fillWidth: true
                            Layout.preferredHeight: 116

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 14

                                Rectangle {
                                    Layout.preferredWidth: 52
                                    Layout.preferredHeight: 52
                                    radius: 26
                                    color: cAccent

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.userInfo.name || "U").charAt(0).toUpperCase()
                                        color: "#ffffff"
                                        font.pixelSize: 20
                                        font.bold: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: 3

                                    Text {
                                        text: root.userInfo.name || "未登录"
                                        color: cText
                                        font.pixelSize: 16
                                        font.bold: true
                                    }

                                    Text {
                                        text: "用户组: " + ((root.userInfo.group && root.userInfo.group.name) || "未知")
                                        color: cTextSec
                                        font.pixelSize: 12
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                //近 7 天每日用量迷你柱状(traffic_history 差分)
                                ColumnLayout {
                                    spacing: 3

                                    Text {
                                        text: "近 7 天"
                                        color: cTextMuted
                                        font.pixelSize: 10
                                    }

                                    Canvas {
                                        Layout.preferredWidth: 120
                                        Layout.preferredHeight: 38
                                        property var histData: root.trafficHistory
                                        onHistDataChanged: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.reset()
                                            var d = histData || []
                                            if (d.length === 0) return
                                            var last = d.slice(-7)
                                            var maxV = 1
                                            for (var i = 0; i < last.length; i++)
                                                maxV = Math.max(maxV, last[i].usage)
                                            var bw = (width - (last.length - 1) * 4) / last.length
                                            ctx.fillStyle = Qt.rgba(cAccent.r, cAccent.g, cAccent.b, 0.75)
                                            for (i = 0; i < last.length; i++) {
                                                var bh = Math.max(3, (last[i].usage / maxV) * (height - 3))
                                                ctx.fillRect(i * (bw + 4), height - bh, bw, bh)
                                            }
                                        }
                                    }
                                }

                                ColumnLayout {
                                    spacing: 3

                                    Text {
                                        text: "剩余流量"
                                        color: cTextSec
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        // API 返回 traffic: [本日消耗, 剩余] (字节)
                                        id: trafficNum
                                        text: {
                                            var t = root.userInfo.traffic
                                            if (!t || t.length < 2) return "—"
                                            return (t[1] / 1024 / 1024 / 1024).toFixed(2) + " GB"
                                        }
                                        color: cAccent
                                        font.pixelSize: 24
                                        font.bold: true
                                        transform: Translate { id: trafficNumHop; y: 0 }
                                        onTextChanged: trafficPop.restart()

                                        SequentialAnimation {
                                            id: trafficPop
                                            NumberAnimation { target: trafficNumHop; property: "y"; from: -5; to: 0; duration: 160; easing.type: Easing.OutCubic }
                                        }
                                    }
                                }
                            }
                        }
                    }

                GridView {
                    id: tunnelsGrid
                    visible: root.currentPage === "tunnels"
                    SmoothWheel { flick: tunnelsGrid }
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    Layout.bottomMargin: 24
                    model: root.tunnels
                    clip: true
                    //≤2 条隧道时两列大卡片,更多时三列;高度同步调整。
                    //cellWidth 正好整除宽度,delegate 在 cell 内居中并四周留 10px,
                    //这样卡片间距和页面边缘的距离完全对称。
                    //行数按隧道数自适应:1-2 条单行 hero 卡,3-6 条撑满两行,
                    //7 条以上固定高度滚动——任何数量下页面都不留大片空白
                    readonly property int gridRows: root.tunnels.length <= 2 ? 1
                                                   : Math.ceil(root.tunnels.length / 3)
                    cellWidth: root.tunnels.length <= 2 ? width / 2 : width / 3
                    cellHeight: gridRows === 1 ? height
                              : gridRows === 2 ? height / 2
                              : 220

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    //刷新时卡片级联入场
                    populate: Transition {
                        id: tunnelsPop
                        SequentialAnimation {
                            PauseAnimation { duration: Math.min(tunnelsPop.ViewTransition.index * 60, 480) }
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 340; easing.type: Easing.OutBack }
                        }
                    }

                    delegate: Item {
                        //delegate 根必须有尺寸(GridView 不会隐式撑大它),
                        //否则卡片 centerIn 到 0x0 的原点上,整体偏移半个卡片
                        width: tunnelsGrid.cellWidth
                        height: tunnelsGrid.cellHeight
                        //数据属性放在 delegate 根对象上:QML 非限定名解析只查组件根,
                        //子层绑定才能直接用 t / running / tagColor
                        property var t: modelData
                        property bool running: root.runningIds.has(String(t.id))
                        //协议→标签色
                        readonly property color tagColor: {
                            var tt = String(t.type || "tcp").toLowerCase()
                            if (tt === "udp") return "#3b82f6"
                            if (tt === "http") return "#d97706"
                            if (tt === "https") return "#1fae70"
                            return Theme.cTcpTag
                        }

                        Rectangle {
                            id: tcard
                            anchors.centerIn: parent
                            width: tunnelsGrid.cellWidth - 20
                            height: tunnelsGrid.cellHeight - 20
                            radius: 18
                        //悬停提亮,同时保留卡片本体的半透明度
                        color: cardArea.containsMouse ? Qt.alpha(Qt.lighter(cCard, 1.10), cCard.a) : cCard
                        Behavior on color { ColorAnimation { duration: 140 } }
                        //悬停弹簧上浮 + 跟随鼠标的 3D 倾斜(回弹用弹簧)
                        transform: [
                            Translate {
                                y: cardArea.containsMouse ? -6 : 0
                                Behavior on y { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }
                            },
                            Rotation {
                                id: tiltYaw
                                axis { x: 0; y: 1; z: 0 }
                                origin.x: tcard.width / 2; origin.y: tcard.height / 2
                                Behavior on angle { SpringAnimation { spring: 5; damping: 0.8; mass: 0.6 } }
                            },
                            Rotation {
                                id: tiltPitch
                                axis { x: 1; y: 0; z: 0 }
                                origin.x: tcard.width / 2; origin.y: tcard.height / 2
                                Behavior on angle { SpringAnimation { spring: 5; damping: 0.8; mass: 0.6 } }
                            }
                        ]

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: function(mouse) {
                                tiltYaw.angle = (mouse.x / tcard.width - 0.5) * 6
                                tiltPitch.angle = -(mouse.y / tcard.height - 0.5) * 6
                            }
                            onExited: { tiltYaw.angle = 0; tiltPitch.angle = 0 }

                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 10

                            // 顶行: 状态点(含呼吸光圈) + 协议标签 + 删除
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Item {
                                    width: 10; height: 10
                                    Layout.alignment: Qt.AlignVCenter

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 5
                                        color: running ? cSuccess : Theme.cDotOff
                                        Behavior on color { ColorAnimation { duration: 200 } }

                                        //运行时向外扩散的呼吸光圈
                                        Rectangle {
                                            visible: running
                                            anchors.centerIn: parent
                                            width: 10; height: 10; radius: 5
                                            color: "transparent"
                                            border.color: cSuccess
                                            border.width: 1
                                            NumberAnimation on scale {
                                                running: running
                                                loops: Animation.Infinite
                                                from: 1; to: 2.4
                                                duration: 1200
                                                easing.type: Easing.OutQuad
                                            }
                                            NumberAnimation on opacity {
                                                running: running
                                                loops: Animation.Infinite
                                                from: 0.7; to: 0
                                                duration: 1200
                                                easing.type: Easing.OutQuad
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: typeLabel.implicitWidth + 14
                                    radius: 10
                                    color: "transparent"
                                    border.color: tagColor
                                    border.width: 1

                                    Text {
                                        id: typeLabel
                                        anchors.centerIn: parent
                                        text: String(t.type || "tcp").toUpperCase()
                                         color: tagColor
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Item {
                                    id: cmdBtn
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    property bool cmdCopied: false

                                    AppIcon {
                                        anchors.centerIn: parent
                                        iconType: "copy"
                                        iconColor: cmdBtn.cmdCopied ? cSuccess : (cmdArea.containsMouse ? cAccent : cTextMuted)
                                        width: 15
                                        height: 15
                                    }

                                    Timer { id: cmdCopyReset; interval: 1600; onTriggered: cmdBtn.cmdCopied = false }
                                    Ripple { id: cmdAreaRipple; anchors.fill: parent }
                                    MouseArea {
                                        id: cmdArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            appSettings.copyText("frpc -f " + apiClient.token + ":" + t.id)
                                            cmdBtn.cmdCopied = true
                                            cmdCopyReset.restart()
                                        }
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20

                                    AppIcon {
                                        anchors.centerIn: parent
                                        iconType: "edit"
                                        iconColor: editArea.containsMouse ? cAccent : cTextMuted
                                        width: 15
                                        height: 15
                                    }

                                    Ripple { id: editAreaRipple; anchors.fill: parent }
                                    MouseArea {
                                        id: editArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { editAreaRipple.play(); createPopup.openEdit(t) }
                                    }
                                }

                                Item {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20

                                    AppIcon {
                                        anchors.centerIn: parent
                                        iconType: "delete"
                                        iconColor: delArea.containsMouse ? cError : cTextMuted
                                        width: 15
                                        height: 15
                                    }

                                    Ripple { id: delAreaRipple; anchors.fill: parent }
                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { delAreaRipple.play(); { }
                                            root.pendingDeleteId = String(t.id)
                                            deletePopup.open()
                                        }
                                    }
                                }
                            }

                            // 名称
                            Text {
                                Layout.fillWidth: true
                                text: t.name || String(t.id)
                                color: cText
                                font.pixelSize: 18
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            // 结构化信息行:标签 + 数值,卡片高时有内容撑起
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: "节点"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 34
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "#" + (t.node || "?") + "  ·  ID " + (t.id || "?")
                                        color: cText
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: "本地"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 34
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (t.local_ip || "127.0.0.1") + ":" + (t.local_port || "?")
                                        color: cText
                                        font.pixelSize: 13
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        text: "远程"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 34
                                    }

                                    //完整访问地址(节点域名:端口 / http 域名),点击复制
                                    Text {
                                        id: remoteAddrText
                                        Layout.fillWidth: true
                                        property bool copied: false
                                        text: copied ? "已复制 ✓" : root.tunnelAccessAddr(t)
                                        color: copied ? cSuccess : (remoteCopyArea.containsMouse ? cAccent : cText)
                                        font.pixelSize: 13
                                        elide: Text.ElideMiddle

                                        Timer {
                                            id: remoteCopyReset
                                            interval: 1500
                                            onTriggered: remoteAddrText.copied = false
                                        }

                                        MouseArea {
                                            id: remoteCopyArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                appSettings.copyText(root.tunnelAccessAddr(t))
                                                remoteAddrText.copied = true
                                                remoteCopyReset.restart()
                                            }
                                        }
                                    }
                                }
                            }

                            // 实时活动波形:吃掉卡片剩余高度
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "流量趋势"
                                    color: cTextMuted
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: {
                                        var arr = (root.tunnelTraffic || {})[String(t.id)] || []
                                        if (arr.length === 0)
                                            return running ? "运行中 · 暂无流量记录" : "暂无流量记录"
                                        var total = 0
                                        for (var i = 0; i < arr.length; i++) total += arr[i].v
                                        return total > 1073741824 ? (total / 1073741824).toFixed(2) + " GB"
                                             : total > 1048576 ? (total / 1048576).toFixed(1) + " MB"
                                             : (total / 1024).toFixed(1) + " KB"
                                    }
                                    color: cTextMuted
                                    font.pixelSize: 10
                                }
                            }

                            TrafficChart {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.minimumHeight: 64
                                samples: (root.tunnelTraffic || {})[String(t.id)] || []
                                beat: root.waveTime
                            }

                            // 启停按钮(通栏)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 12
                                color: runArea.containsMouse
                                       ? (running ? Theme.cErrorBg : Theme.cSuccessBgHover)
                                       : (running ? Theme.cInputBg : Theme.cSuccessBg)
                                Behavior on color { ColorAnimation { duration: 140 } }
                                scale: runArea.pressed ? 0.97 : 1.0
                                Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    AppIcon {
                                        iconType: running ? "stop" : "play"
                                        iconColor: running ? cError : cSuccess
                                        width: 13
                                        height: 13
                                        anchors.verticalCenter: parent.verticalCenter
                                    }

                                    Text {
                                        text: running ? "停止" : "启动"
                                        color: running ? cError : cSuccess
                                        font.pixelSize: 13
                                        font.bold: true
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Ripple { id: runAreaRipple; anchors.fill: parent }
                                MouseArea {
                                    id: runArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { runAreaRipple.play(); frpc.toggleTunnel(String(t.id)) }
                                }
                            }
                        }
                    }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.tunnels.length === 0
                        text: "暂无隧道，点击右上角「新建隧道」创建"
                        color: cTextMuted
                        font.pixelSize: 14
                    }
                }
                }

                // ----- 节点页面:分类筛选 + 搜索 + 网格 -----
                ColumnLayout {
                    id: nodesPage
                    anchors.fill: parent
                    visible: root.currentPage === "nodes"
                    spacing: 0
                    transform: Translate {
                        y: nodesPage.visible ? 0 : 26
                        Behavior on y { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }
                    }

                    // 筛选行:分类芯片 + 搜索框
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.topMargin: 24
                        spacing: 8

                        Repeater {
                            model: root.nodeFilterModel

                            delegate: Rectangle {
                                id: nodeFilterChip
                                readonly property bool isActive: root.nodeFilter === modelData.key
                                width: filterRow.implicitWidth + 32
                                height: 34
                                radius: 17
                                color: isActive ? cAccent : Theme.cInputBg
                                Behavior on color { ColorAnimation { duration: 150 } }
                                scale: filterArea.pressed ? 0.96 : 1.0
                                Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                Row {
                                    id: filterRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: modelData.label
                                        color: nodeFilterChip.isActive ? "#ffffff" : cText
                                        font.pixelSize: 13
                                        font.bold: nodeFilterChip.isActive
                                    }

                                    Text {
                                        text: modelData.count
                                        color: nodeFilterChip.isActive ? "#e8e0ff" : cTextMuted
                                        font.pixelSize: 12
                                    }
                                }

                                Ripple { id: filterRipple; anchors.fill: parent }
                                MouseArea {
                                    id: filterArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { filterRipple.play(); root.nodeFilter = modelData.key }
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // 搜索框
                        Rectangle {
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 34
                            radius: 10
                            color: Theme.cInputBg
                            border.color: nodeSearchInput.activeFocus ? cAccent : "transparent"
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            TextField {
                                id: nodeSearchInput
                                anchors.fill: parent
                                anchors.margins: 2
                                placeholderText: "搜索节点…"
                                placeholderTextColor: cTextMuted
                                color: cText
                                font.pixelSize: 13
                                background: null
                                verticalAlignment: TextInput.AlignVCenter
                                leftPadding: 12
                                selectByMouse: true
                                onTextChanged: root.nodeSearch = text
                            }
                        }
                    }

                    GridView {
                        id: nodesView
                        Layout.fillWidth: true
                        SmoothWheel { flick: nodesView }
                        Layout.fillHeight: true
                        Layout.leftMargin: 24
                        Layout.rightMargin: 24
                        Layout.bottomMargin: 24
                        Layout.topMargin: 12
                        model: root.filteredNodes
                        clip: true
                        cellWidth: width / 3
                        cellHeight: 132

                        opacity: nodesPage.visible ? 1 : 0
                        scale: nodesPage.visible ? 1 : 0.98
                        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
                        Behavior on scale { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }

                        populate: Transition {
                            id: nodesPop
                            SequentialAnimation {
                                PauseAnimation { duration: Math.min(nodesPop.ViewTransition.index * 40, 480) }
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 240; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                                NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 340; easing.type: Easing.OutBack }
                            }
                        }

                        ScrollBar.vertical: PinkScrollBar {}

                        delegate: Item {
                            id: nodeCell
                            width: nodesView.cellWidth
                            height: nodesView.cellHeight

                            readonly property var node: modelData
                            readonly property int tier: node.vip || 0
                            //当前账号等级不够用的节点
                            readonly property bool locked: tier > (root.userInfo.group && root.userInfo.group.level !== undefined ? root.userInfo.group.level : 0)

                            Rectangle {
                                id: nodeCard
                                anchors.centerIn: parent
                                width: nodeCell.width - 16
                                height: nodeCell.height - 16
                                radius: 14
                                color: cCard
                                opacity: nodeCell.locked ? 0.55 : 1.0
                                scale: nodeCardArea.containsMouse ? 1.02 : 1.0
                                Behavior on scale { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 6

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // 门槛徽章
                                        Rectangle {
                                            Layout.preferredHeight: 18
                                            Layout.preferredWidth: tierBadgeText.implicitWidth + 12
                                            radius: 9
                                            color: "transparent"
                                            border.color: nodeCell.locked ? cTextMuted : root.nodeTierColor(nodeCell.tier)
                                            border.width: 1

                                            Text {
                                                id: tierBadgeText
                                                anchors.centerIn: parent
                                                text: root.nodeTierLabel(nodeCell.tier)
                                                color: parent.border.color
                                                font.pixelSize: 10
                                                font.bold: true
                                            }
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: {
                                                var st = (root.nodeLoad || {})[String(nodeCell.node.id)]
                                                var base = "ID " + (nodeCell.node.id || "?")
                                                return st && st.load !== undefined ? base + "  ·  负载 " + st.load + "%" : base
                                            }
                                            color: cTextMuted
                                            font.pixelSize: 11
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: nodeCell.node.name || ("节点 #" + (nodeCell.node.id || "?"))
                                        color: nodeCell.locked ? cTextMuted : cText
                                        font.pixelSize: 14
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: nodeCell.node.host || "—"
                                        color: cTextSec
                                        font.pixelSize: 12
                                        elide: Text.ElideMiddle
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: nodeCell.node.description || ""
                                        color: cTextMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                        visible: text !== ""
                                    }
                                }

                                MouseArea {
                                    id: nodeCardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openNodeDetail(nodeCell.node)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.filteredNodes.length === 0
                            text: root.nodes.length === 0 ? "暂无节点数据" : "没有匹配的节点"
                            color: cTextMuted
                            font.pixelSize: 14
                        }
                    }
                }


                // ----- 日志页面:玻璃面板承载,文字不再直接压在壁纸上 -----
                ColumnLayout {
                    id: logPage
                    anchors.fill: parent
                    visible: root.currentPage === "log"
                    spacing: 0
                    transform: Translate {
                        y: logPage.visible ? 0 : 26
                        Behavior on y { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.margins: 24
                        radius: 14
                        color: cCard

                        ListView {
                            id: logView
                            anchors.fill: parent
                            anchors.margins: 16
                            SmoothWheel { flick: logView }
                            model: logModel
                            clip: true
                            spacing: 5

                            opacity: logPage.visible ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                            //新日志条目渐显;超过上限移除旧行时,其余行平滑上移而不是突跳
                            add: Transition {
                                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
                            }
                            displaced: Transition {
                                NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                            }

                            ScrollBar.vertical: PinkScrollBar {}

                            delegate: RowLayout {
                                width: logView.availableWidth
                                spacing: 10

                                Text {
                                    text: "[" + model.time + "]"
                                    color: cTextMuted
                                    font.family: "monospace"
                                    font.pixelSize: 15
                                    //CurveRendering:矢量路径,不做 hinting,小号 CJK 更不容易糊
                                    renderType: Text.CurveRendering
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.msg
                                    color: model.level === "error" ? cError :
                                           model.level === "success" ? cSuccess :
                                           model.level === "warning" ? cWarning : cText
                                    font.family: "monospace"
                                    font.pixelSize: 15
                                    renderType: Text.CurveRendering
                                    wrapMode: Text.Wrap
                                }
                            }

                            onCountChanged: {
                                //只在本来就贴着底部时才跟随:用户往上翻历史日志,
                                //新日志到达不应把视图强拉回底部
                                if (count > 0 && atYEnd)
                                    positionViewAtEnd()
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: logModel.count === 0
                                text: "暂无日志"
                                color: cTextMuted
                                font.pixelSize: 14
                            }
                        }
                    }
                }

                // ----- 设置页面 -----
                Flickable {
                    id: settingsPage
                    visible: root.currentPage === "settings"
                    SmoothWheel { flick: settingsPage }
                    anchors.fill: parent
                    anchors.margins: 20
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.98
                    transform: Translate {
                        y: settingsPage.visible ? 0 : 26
                        Behavior on y { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }
                    }
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
                    Behavior on scale { SpringAnimation { spring: 6; damping: 0.8; mass: 0.55 } }

                    ScrollBar.vertical: PinkScrollBar {}

                    ColumnLayout {
                        id: settingsCol
                        width: parent.width
                        spacing: 20

                        // 主题卡
                        Rectangle {
                            Layout.fillWidth: true
                            //高度跟随内容:配色多到换行时卡片自动长高
                            implicitHeight: themeCardCol.implicitHeight + 32
                            radius: 14
                            color: cCard

                            ColumnLayout {
                                id: themeCardCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 10

                                Text {
                                    text: "主题"
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                //配色选择器:Flow 自动换行,宽度随名字自适应,
                                //配色列表来自 Theme.palettes,加新配色无需改这里
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: Theme.palettes

                                        delegate: Rectangle {
                                            id: themeChip
                                            implicitWidth: chipRow.implicitWidth + 28
                                            height: 34
                                            radius: 17
                                            color: Theme.current === index ? Theme.cAccent : Theme.cInputBg
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            scale: chipArea.pressed ? 0.96 : (chipArea.containsMouse ? 1.04 : 1.0)
                                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                            Row {
                                                id: chipRow
                                                anchors.centerIn: parent
                                                spacing: 8

                                                Rectangle {
                                                    width: 12
                                                    height: 12
                                                    radius: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    color: modelData.cAccent
                                                    border.color: Theme.current === index ? "#ffffff" : cBorder
                                                    border.width: 1
                                                }

                                                Text {
                                                    text: modelData.name
                                                    color: Theme.current === index ? "#ffffff" : cText
                                                    font.pixelSize: 13
                                                    font.bold: Theme.current === index
                                                    anchors.verticalCenter: parent.verticalCenter
                                                }
                                            }

                                            Ripple { id: chipAreaRipple; anchors.fill: parent }
                                            MouseArea {
                                                id: chipArea
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: { chipAreaRipple.play(); Theme.current = index }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 用户信息卡
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            radius: 14
                            color: cCard

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 16

                                Rectangle {
                                    Layout.preferredWidth: 48
                                    Layout.preferredHeight: 48
                                    radius: 24
                                    color: cAccent

                                    Text {
                                        anchors.centerIn: parent
                                        text: (root.userInfo.name || "U").charAt(0).toUpperCase()
                                        color: "#ffffff"
                                        font.pixelSize: 20
                                        font.bold: true
                                    }
                                }

                                ColumnLayout {
                                    spacing: 4

                                    Text {
                                        text: root.userInfo.name || "未登录"
                                        color: cText
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    Text {
                                        text: "用户组: " + ((root.userInfo.group && root.userInfo.group.name) || "未知")
                                        color: cTextSec
                                        font.pixelSize: 12
                                    }

                                    Text {
                                        text: {
                                            // API 返回 traffic: [本日消耗, 剩余] (字节),展示剩余流量
                                            var t = root.userInfo.traffic
                                            if (!t || t.length < 2) return "剩余流量: —"
                                            return "剩余流量: " + (t[1] / 1024 / 1024 / 1024).toFixed(2) + " GB"
                                        }
                                        color: cTextSec
                                        font.pixelSize: 12
                                    }
                                }
                            }
                        }

                        // frpc 设置卡
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 130
                            radius: 14
                            color: cCard

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 8

                                Text {
                                    text: "frpc 程序路径"
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38
                                    radius: 10
                                    color: Theme.cInputBg
                                    border.color: frpcPathInput.activeFocus ? cAccent : "transparent"
                                    border.width: 1
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    TextField {
                                        id: frpcPathInput
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        text: frpc.frpcPath
                                        placeholderText: "/opt/frp/frpc"
                                        placeholderTextColor: cTextMuted
                                        color: cText
                                        font.pixelSize: 13
                                        background: null
                                        verticalAlignment: TextInput.AlignVCenter
                                        leftPadding: 10
                                        selectByMouse: true
                                        //失焦或回车即保存到 QSettings
                                        onEditingFinished: frpc.frpcPath = text
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true

                                    Text {
                                        Layout.fillWidth: true
                                        text: "留空使用应用内置的 frpc;也可手动指定路径"
                                        color: cTextMuted
                                        font.pixelSize: 11
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            var cur = apiClient.frpcVersion
                                            if (root.frpcLatest === "")
                                                return "内置 frpc 版本: " + cur
                                            return root.frpcLatest === cur
                                                ? "内置 frpc " + cur + "(已是最新版本)"
                                                : "内置 frpc " + cur + "  ·  官方最新 " + root.frpcLatest
                                        }
                                        color: root.frpcLatest !== "" && root.frpcLatest !== apiClient.frpcVersion ? cWarning : cTextMuted
                                        font.pixelSize: 11
                                    }

                                    Rectangle {
                                        visible: root.frpcLatest !== "" && root.frpcLatest !== apiClient.frpcVersion
                                        Layout.preferredWidth: 96
                                        Layout.preferredHeight: 26
                                        radius: 8
                                        color: frpcUpdArea.containsMouse ? cAccentHover : cAccent
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: root.frpcUpdating ? "下载中…" : "下载更新"
                                            color: "#ffffff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        Ripple { id: frpcUpdRipple; anchors.fill: parent }
                                        MouseArea {
                                            id: frpcUpdArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            enabled: !root.frpcUpdating
                                            onClicked: { frpcUpdRipple.play(); frpc.downloadFrpc() }
                                        }
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 8
                                        color: dlFrpcArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: dlFrpcArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "重新下载"
                                            color: cText
                                            font.pixelSize: 12
                                        }

                                        Ripple { id: dlFrpcAreaRipple; anchors.fill: parent }
                                        MouseArea {
                                            id: dlFrpcArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: { dlFrpcAreaRipple.play(); frpc.downloadFrpc() }
                                        }
                                    }
                                }
                            }
                        }

                        // 壁纸设置卡
                        Rectangle {
                            Layout.fillWidth: true
                            //高度跟随内容:透明度滑条只在设置了壁纸时出现
                            implicitHeight: wpCardCol.implicitHeight + 32
                            radius: 14
                            color: cCard

                            ColumnLayout {
                                id: wpCardCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 8

                                Text {
                                    text: "界面壁纸"
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 8
                                        color: wpPickArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: wpPickArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "选择图片"
                                            color: cText
                                            font.pixelSize: 12
                                        }

                                        Ripple { id: wpPickAreaRipple; anchors.fill: parent }
                                        MouseArea {
                                            id: wpPickArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: { wpPickAreaRipple.play(); wallpaperDialog.open() }
                                        }
                                    }

                                    Rectangle {
                                        visible: appSettings.wallpaperFile !== ""
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 8
                                        color: wpClearArea.containsMouse ? Theme.cErrorBg : Theme.cInputBg
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: wpClearArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "恢复默认"
                                            color: wpClearArea.containsMouse ? cError : cText
                                            font.pixelSize: 12
                                        }

                                        Ripple { id: wpClearAreaRipple; anchors.fill: parent }
                                        MouseArea {
                                            id: wpClearArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: { wpClearAreaRipple.play(); appSettings.clearWallpaper() }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: appSettings.wallpaperFile !== ""
                                              ? "已自选: " + appSettings.wallpaperFile.split("/").pop()
                                              : (appSettings.builtinWallpaper !== ""
                                                 ? "使用内置壁纸(" + appSettings.builtinWallpaper.split("/").pop() + ")"
                                                 : "未设置壁纸,使用纯色主题背景")
                                        color: cTextMuted
                                        font.pixelSize: 11
                                        elide: Text.ElideMiddle
                                        Layout.maximumWidth: 220
                                    }
                                }
                            }
                        }

                        // 关于卡片
                        Rectangle {
                            Layout.fillWidth: true
                            //高度跟随内容,开发者信息增删时卡片自动适应
                            implicitHeight: aboutCol.implicitHeight + 32
                            radius: 14
                            color: cCard

                            ColumnLayout {
                                id: aboutCol
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 6

                                Text {
                                    text: "关于"
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: "QFRP 客户端 v0.3.0"
                                    color: cTextSec
                                    font.pixelSize: 12
                                }

                                //开发者信息
                                RowLayout {
                                    spacing: 8

                                    Text {
                                        text: "开发者"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                    }

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: cTextMuted
                                    }

                                    Text {
                                        text: "setsuna"
                                        color: cText
                                        font.pixelSize: 12
                                        font.bold: true
                                    }
                                }

                                //QQ 号:点击复制到剪贴板
                                RowLayout {
                                    spacing: 8

                                    Text {
                                        text: "QQ"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                    }

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: cTextMuted
                                    }

                                     Item {
                                         Layout.preferredWidth: qqValue.implicitWidth
                                         Layout.preferredHeight: qqValue.implicitHeight

                                         Text {
                                             id: qqValue
                                             anchors.fill: parent
                                             property bool copied: false
                                             text: copied ? "已复制 ✓" : "1537403715"
                                             color: qqArea.containsMouse || copied ? Theme.cAccentHover : Theme.cAccent
                                             font.pixelSize: 12
                                             font.bold: true

                                             Timer {
                                                 id: qqCopyReset
                                                 interval: 1500
                                                 onTriggered: qqValue.copied = false
                                             }
                                         }

                                         Ripple { id: qqAreaRipple; anchors.fill: parent }
                                         MouseArea {
                                             id: qqArea
                                             anchors.fill: parent
                                             hoverEnabled: true
                                             cursorShape: Qt.PointingHandCursor
                                             onClicked: {
                                                 qqAreaRipple.play()
                                                 appSettings.copyText("1537403715")
                                                 qqValue.copied = true
                                                 qqCopyReset.restart()
                                             }
                                         }
                                     }
                                }

                                //GitHub 仓库:点击打开浏览器
                                RowLayout {
                                    spacing: 8

                                    Text {
                                        text: "GitHub"
                                        color: cTextMuted
                                        font.pixelSize: 12
                                    }

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        width: 3
                                        height: 3
                                        radius: 1.5
                                        color: cTextMuted
                                    }

                                     Item {
                                         Layout.preferredWidth: ghValue.implicitWidth
                                         Layout.preferredHeight: ghValue.implicitHeight

                                         Text {
                                             id: ghValue
                                             anchors.fill: parent
                                             text: "setsuna391/QFRP"
                                             color: ghArea.containsMouse ? Theme.cAccentHover : Theme.cAccent
                                             font.pixelSize: 12
                                             font.bold: true
                                             font.underline: ghArea.containsMouse
                                         }

                                         Ripple { id: ghAreaRipple; anchors.fill: parent }
                                         MouseArea {
                                             id: ghArea
                                             anchors.fill: parent
                                             hoverEnabled: true
                                             cursorShape: Qt.PointingHandCursor
                                             onClicked: {
                                                 ghAreaRipple.play()
                                                 Qt.openUrlExternally("https://github.com/setsuna391/QFRP")
                                             }
                                         }
                                     }
                                }

                                Text {
                                    text: "基于 Qt6 + QML 开发"
                                    color: cTextMuted
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // 退出登录按钮
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 12
                            color: logoutBtnArea.containsMouse ? Theme.cError : Theme.cErrorBg
                            Behavior on color { ColorAnimation { duration: 120 } }
                            scale: logoutBtnArea.pressed ? 0.97 : (logoutBtnArea.containsMouse ? 1.04 : 1.0)
                            Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                            Text {
                                anchors.centerIn: parent
                                text: "退出登录"
                                color: logoutBtnArea.containsMouse ? "#ffffff" : cError
                                font.pixelSize: 14
                                font.bold: true
                            }

                            Ripple { id: logoutBtnAreaRipple; anchors.fill: parent }
                            MouseArea {
                                id: logoutBtnArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: { logoutBtnAreaRipple.play(); logoutPopup.open() }
                            }
                        }
                    }
                }
            }
    }

    // ========== 退出确认弹窗 ==========
    //壁纸图片选择对话框(走系统/ portals 文件选择器)
    FileDialog {
        id: wallpaperDialog
        title: "选择壁纸图片"
        currentFolder: StandardPaths.standardLocations(StandardPaths.PicturesLocation)[0]
                     || StandardPaths.standardLocations(StandardPaths.HomeLocation)[0]
        nameFilters: ["图片文件 (*.jpg *.jpeg *.png *.webp *.bmp)"]
        onAccepted: appSettings.pickWallpaper(selectedFile)
    }

    Popup {
        id: quitPopup
        width: 380
        height: 200
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            //模态弹窗是最高层级,接近实心:底下透出的卡片+壁纸叠在一起就是"杂乱"的来源
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 12

            Text {
                text: "退出应用"
                color: cText
                font.pixelSize: 18
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "确定要退出 QFRP 吗? 所有隧道会在后台继续运行,下次打开应用时会自动接管。"
                color: cTextSec
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: quitCancelArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: quitCancelArea.pressed ? 0.96 : (quitCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    Ripple { id: quitCancelAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: quitCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { quitCancelAreaRipple.play(); quitPopup.close() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: quitConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: quitConfirmArea.pressed ? 0.96 : (quitConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "退出"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Ripple { id: quitConfirmAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: quitConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { quitConfirmAreaRipple.play(); root.appWindow.close() }
                    }
                }
            }
        }
    }

    // ========== 新建隧道弹窗 ==========
    // 删除隧道确认弹窗
    Popup {
        id: deletePopup
        width: 380
        height: 200
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            //模态弹窗是最高层级,接近实心:底下透出的卡片+壁纸叠在一起就是"杂乱"的来源
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 12

            Text {
                text: "删除隧道"
                color: cText
                font.pixelSize: 18
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "确定要删除隧道「" + root.tunnelName(root.pendingDeleteId) + "」吗? 该操作会同步删除服务器上的隧道,无法撤销。"
                color: cTextSec
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: delCancelArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: delCancelArea.pressed ? 0.96 : (delCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    Ripple { id: delCancelAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: delCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { delCancelAreaRipple.play(); { }
                            root.pendingDeleteId = ""
                            deletePopup.close()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: delConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: delConfirmArea.pressed ? 0.96 : (delConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "确认删除"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Ripple { id: delConfirmAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: delConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { delConfirmAreaRipple.play(); { }
                            var id = root.pendingDeleteId
                            root.pendingDeleteId = ""
                            deletePopup.close()
                            apiClient.deleteTunnel(id)
                        }
                    }
                }
            }
        }
    }

    // 退出登录确认弹窗
    Popup {
        id: logoutPopup
        width: 380
        height: 200
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            //模态弹窗是最高层级,接近实心:底下透出的卡片+壁纸叠在一起就是"杂乱"的来源
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 12

            Text {
                text: "退出登录"
                color: cText
                font.pixelSize: 18
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                text: "确定要退出登录吗? 本机保存的 Token 将被清除,需要重新输入;已启动的隧道会继续在后台运行。"
                color: cTextSec
                font.pixelSize: 13
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: logoutCancelArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: logoutCancelArea.pressed ? 0.96 : (logoutCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    Ripple { id: logoutCancelAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: logoutCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { logoutCancelAreaRipple.play(); logoutPopup.close() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: logoutConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: logoutConfirmArea.pressed ? 0.96 : (logoutConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "退出登录"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Ripple { id: logoutConfirmAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: logoutConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { logoutConfirmAreaRipple.play(); { }
                            logoutPopup.close()
                            apiClient.logout()
                        }
                    }
                }
            }
        }
    }

    Popup {
        id: createPopup
        width: 420
        height: 640
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        //重新打开时清掉上一次的错误提示(在 aboutToShow 里清,
        //这样打开过程中到达的创建失败信号不会被覆盖)
        onAboutToShow: createErrorText.visible = false

        //编辑模式:非空时弹窗变为编辑隧道(/tunnel/edit 仅支持 备注/本地IP/本地端口)
        property var editing: null

        function openCreate() {
            editing = null
            createName.text = ""
            createNote.text = ""
            createErrorText.visible = false
            open()
        }

        function openEdit(t) {
            editing = t
            createName.text = String(t.name || "")
            createNote.text = String(t.note || "")
            createLocalIp.text = String(t.local_ip || "127.0.0.1")
            createLocalPort.text = String(t.local_port || "")
            createErrorText.visible = false
            open()
        }

        //弹出/关闭动画:淡入 + 从略小弹出
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            //模态弹窗是最高层级,接近实心:底下透出的卡片+壁纸叠在一起就是"杂乱"的来源
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        Connections {
            target: apiClient
            function onTunnelEdited(tunnelId) { createPopup.close() }
            function onTunnelEditFailed(error) {
                createErrorText.text = error
                createErrorText.visible = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 10

            Text {
                text: createPopup.editing ? "编辑隧道" : "新建隧道"
                color: cText
                font.pixelSize: 18
                font.bold: true
                Layout.fillWidth: true
            }

            // 隧道名称
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: "隧道名称"; color: cTextSec; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.cInputBg
                    border.color: createName.activeFocus ? cAccent : "transparent"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: createName
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "我的隧道"
                        //编辑接口不支持修改名称
                        readOnly: createPopup.editing !== null
                        opacity: createPopup.editing !== null ? 0.55 : 1.0
                        Keys.onReturnPressed: confirmCreateArea.simulateClick()
                        placeholderTextColor: cTextMuted
                        color: cText
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        leftPadding: 10
                    }
                }
            }

            // 备注(创建/编辑均可)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: "备注(选填)"; color: cTextSec; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.cInputBg
                    border.color: createNote.activeFocus ? cAccent : "transparent"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: createNote
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "用途说明等"
                        placeholderTextColor: cTextMuted
                        color: cText
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        leftPadding: 10
                    }
                }
            }

            // 节点选择
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: "节点"; color: cTextSec; font.pixelSize: 12 }

                ComboBox {
                    id: createNode
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    //编辑模式不可迁移节点(/tunnel/migrate 才能改节点,端口会变)
                    enabled: createPopup.editing === null
                    opacity: createPopup.editing !== null ? 0.5 : 1.0
                    model: root.createableNodes
                    textRole: "name"
                    valueRole: "id"

                    background: Rectangle {
                        radius: 10
                        color: Theme.cInputBg
                        border.color: createNode.pressed || createNode.popup.visible ? cAccent : "transparent"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: createNode.displayText || "请选择节点"
                        color: cText
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                        rightPadding: 26
                    }
                    indicator: Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: "▾"
                        color: cTextSec
                        font.pixelSize: 13
                    }

                    popup: Popup {
                        id: nodePopup
                        y: createNode.height + 4
                        width: createNode.width
                        padding: 4

                        //Qt 6.11 下自定义 popup + 自定义 delegate 时,弹窗打开过程中
                        //ComboBox 会把 currentIndex 重置为 -1,当前选中值就直接丢了。
                        //这里在打开前记住、打开完成后恢复
                        property int restoreIndex: 0
                        onAboutToShow: nodePopup.restoreIndex = createNode.currentIndex
                        onOpened: createNode.currentIndex = nodePopup.restoreIndex

                        enter: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                        }

                        background: Rectangle {
                            radius: 10
                            color: Qt.alpha(Theme.cCard, 0.94)
                        }

                        contentItem: ListView {
                            clip: true
                            //限制最大高度:节点多时下拉可滚动(否则高度永远等于
                            //全部内容,滚轮滚不动,列表还会超出屏幕)
                            implicitHeight: Math.min(contentHeight, 320)
                            boundsBehavior: Flickable.StopAtBounds
                            model: createNode.popup.visible ? createNode.delegateModel : null

                            //分组头:当前账号可用 / 需要更高用户组
                            section.property: "sectionKey"
                            section.criteria: ViewSection.FullString
                            section.delegate: Rectangle {
                                width: ListView.view.width
                                height: 26
                                color: Qt.alpha(Theme.cBg, 0.6)

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    text: section
                                    color: section === "当前账号可用" ? cSuccess : cWarning
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }

                            //可拖拽的滚动条(ScrollIndicator 只能看不能拖)。
                            //内容不满一屏时 size==1,直接隐藏,不占右侧点击区
                            ScrollBar.vertical: ScrollBar {
                                interactive: true
                                visible: size < 1.0
                                contentItem: Rectangle {
                                    implicitWidth: 6
                                    radius: 3
                                    color: Theme.cScrollbar
                                }
                            }

                            delegate: ItemDelegate {
                                id: nodeItem
                                required property var model
                                required property int index
                                readonly property bool usable: model["usable"] !== false

                                width: createNode.width - 8
                                height: 32
                                opacity: usable ? 1.0 : 0.45
                                hoverEnabled: true
                                highlighted: createNode.highlightedIndex === nodeItem.index

                                //不可用的节点(账号等级不够)不响应点击
                                onClicked: {
                                    if (!nodeItem.usable)
                                        return
                                    createNode.currentIndex = nodeItem.index
                                    createNode.popup.close()
                                }

                                contentItem: RowLayout {
                                    spacing: 6

                                    Rectangle {
                                        Layout.leftMargin: 6
                                        Layout.preferredWidth: 6
                                        Layout.preferredHeight: 6
                                        radius: 3
                                        //门槛色点:绿=无限制 橙=VIP 紫=PLUS(与节点页一致)
                                        color: {
                                            var v = nodeItem.model["vip"] || 0
                                            return v === 3 ? cWarning : v === 4 ? cAccent : cSuccess
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: nodeItem.model[createNode.textRole] !== undefined ? nodeItem.model[createNode.textRole] : ""
                                        color: nodeItem.usable ? (nodeItem.hovered || nodeItem.highlighted ? "#ffffff" : cText) : cTextMuted
                                        font.pixelSize: 13
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        visible: !nodeItem.usable
                                        text: nodeItem.model["vip"] === 3 ? "需 VIP" : "需 PLUS"
                                        color: cTextMuted
                                        font.pixelSize: 10
                                    }
                                }

                                background: Rectangle {
                                    radius: 6
                                    color: nodeItem.usable && (nodeItem.hovered || nodeItem.highlighted) ? cAccent : "transparent"
                                }
                            }
                        }
                    }
                }
            }

            // 协议选择
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                Text { text: "协议"; color: cTextSec; font.pixelSize: 12 }

                ComboBox {
                    id: createType
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    model: ["TCP", "UDP", "HTTP", "HTTPS"]
                    currentIndex: 0

                    background: Rectangle {
                        radius: 10
                        color: Theme.cInputBg
                        border.color: createType.pressed || createType.popup.visible ? cAccent : "transparent"
                        border.width: 1
                    }
                    contentItem: Text {
                        text: createType.displayText
                        color: cText
                        font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                        rightPadding: 26
                    }
                    indicator: Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        text: "▾"
                        color: cTextSec
                        font.pixelSize: 13
                    }

                    popup: Popup {
                        id: typePopup
                        y: createType.height + 4
                        width: createType.width
                        padding: 4

                        property int restoreIndex: 0
                        onAboutToShow: typePopup.restoreIndex = createType.currentIndex
                        onOpened: createType.currentIndex = typePopup.restoreIndex

                        enter: Transition {
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 }
                        }

                        background: Rectangle {
                            radius: 10
                            color: Qt.alpha(Theme.cCard, 0.94)
                        }

                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.min(contentHeight, 240)
                            boundsBehavior: Flickable.StopAtBounds
                            model: createType.popup.visible ? createType.delegateModel : null

                            delegate: ItemDelegate {
                                id: typeItem
                                required property string modelData
                                required property int index

                                width: createType.width - 8
                                height: 32
                                hoverEnabled: true
                                highlighted: createType.highlightedIndex === typeItem.index

                                onClicked: {
                                    createType.currentIndex = typeItem.index
                                    createType.popup.close()
                                }

                                contentItem: Text {
                                    text: typeItem.modelData
                                    color: typeItem.hovered || typeItem.highlighted ? "#ffffff" : cText
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 6
                                }

                                background: Rectangle {
                                    radius: 6
                                    color: typeItem.hovered || typeItem.highlighted ? cAccent : "transparent"
                                }
                            }
                        }
                    }
                }
            }

            // 远程配置:tcp/udp = 远程端口(可选,留空随机);http/https = 绑定域名(必填)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: !createPopup.editing && (createType.currentText === "TCP" || createType.currentText === "UDP")

                Text { text: "远程端口(可选)"; color: cTextSec; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.cInputBg
                    border.color: createRemotePort.activeFocus ? cAccent : "transparent"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: createRemotePort
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "留空由服务器随机分配"
                        placeholderTextColor: cTextMuted
                        color: cText
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        leftPadding: 10
                        validator: IntValidator { bottom: 1; top: 65535 }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: !createPopup.editing && (createType.currentText === "HTTP" || createType.currentText === "HTTPS")

                Text { text: "绑定域名(必填)"; color: cTextSec; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 10
                    color: Theme.cInputBg
                    border.color: createRemoteDomain.activeFocus ? cAccent : "transparent"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: createRemoteDomain
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "example.natfrp.app 或自有域名"
                        placeholderTextColor: cTextMuted
                        color: cText
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        leftPadding: 10
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: "多个域名用英文逗号分隔,最多 3 个,不支持泛域名;内地节点要求域名已备案"
                    color: cTextMuted
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }

            // 公开游戏服务器合规提示(官方规则:只能用「多线」节点)
            Text {
                Layout.fillWidth: true
                visible: !createPopup.editing && (createType.currentText === "TCP" || createType.currentText === "UDP")
                text: "⚠ 公开游戏服务器只能用「多线」节点"
                color: cTextMuted
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            // 本地 IP + 端口
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text { text: "本地 IP"; color: cTextSec; font.pixelSize: 12 }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Theme.cInputBg
                        border.color: createLocalIp.activeFocus ? cAccent : "transparent"
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextField {
                            id: createLocalIp
                            anchors.fill: parent
                            anchors.margins: 2
                            text: "127.0.0.1"
                            color: cText
                            font.pixelSize: 13
                            background: null
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 10
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 100
                    spacing: 4

                    Text { text: "本地端口"; color: cTextSec; font.pixelSize: 12 }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Theme.cInputBg
                        border.color: createLocalPort.activeFocus ? cAccent : "transparent"
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextField {
                            id: createLocalPort
                            anchors.fill: parent
                            anchors.margins: 2
                            placeholderText: "8080"
                            Keys.onReturnPressed: confirmCreateArea.simulateClick()
                            placeholderTextColor: cTextMuted
                            color: cText
                            font.pixelSize: 13
                            background: null
                            verticalAlignment: TextInput.AlignVCenter
                            leftPadding: 10
                            validator: IntValidator { bottom: 1; top: 65535 }
                        }
                    }
                }
            }

            // 错误提示(创建失败时显示服务器原因/校验提示)
            Text {
                id: createErrorText
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? implicitHeight : 0
                color: cError
                font.pixelSize: 12
                visible: false
                wrapMode: Text.WordWrap
            }

            Item { Layout.fillHeight: true }

            // 按钮区
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: cancelCreateArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: cancelCreateArea.pressed ? 0.96 : (cancelCreateArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    Ripple { id: cancelCreateAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: cancelCreateArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { cancelCreateAreaRipple.play(); createPopup.close() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 10
                    color: confirmCreateArea.containsMouse ? cAccentHover : cAccent
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: confirmCreateArea.pressed ? 0.96 : (confirmCreateArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { SpringAnimation { spring: 5; damping: 0.75; mass: 0.6 } }

                    Text {
                        anchors.centerIn: parent
                        text: "创建"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    Ripple { id: confirmCreateAreaRipple; anchors.fill: parent }
                    MouseArea {
                        id: confirmCreateArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: { confirmCreateAreaRipple.play(); { }
                            //客户端先校验一遍必填项,避免把不完整参数发给服务器
                            var port = parseInt(createLocalPort.text)
                            var isHttp = createType.currentText === "HTTP" || createType.currentText === "HTTPS"
                            if (createNode.currentIndex < 0 || createNode.currentValue === undefined) {
                                createErrorText.text = "请选择节点"
                                createErrorText.visible = true
                                return
                            }
                            if (!createLocalPort.text || !(port >= 1 && port <= 65535)) {
                                createErrorText.text = "本地端口必须是 1~65535 的数字"
                                createErrorText.visible = true
                                return
                            }
                            if (isHttp) {
                                var domains = createRemoteDomain.text.trim()
                                if (domains === "") {
                                    createErrorText.text = "HTTP(S) 隧道必须填写绑定域名"
                                    createErrorText.visible = true
                                    return
                                }
                                //逗号分隔校验:最多 3 个,每个至少含一个点,不含通配符
                                var parts = domains.split(",").map(function(x){return x.trim()}).filter(function(x){return x !== ""})
                                if (parts.length === 0 || parts.length > 3) {
                                    createErrorText.text = "绑定域名须为 1~3 个,用英文逗号分隔"
                                    createErrorText.visible = true
                                    return
                                }
                                for (var di = 0; di < parts.length; di++) {
                                    if (parts[di].indexOf("*") >= 0 || parts[di].split(".").length < 2) {
                                        createErrorText.text = "域名格式不正确: " + parts[di]
                                        createErrorText.visible = true
                                        return
                                    }
                                }
                            } else {
                                var rp = parseInt(createRemotePort.text)
                                if (createRemotePort.text && !(rp >= 1 && rp <= 65535)) {
                                    createErrorText.text = "远程端口必须是 1~65535 的数字"
                                    createErrorText.visible = true
                                    return
                                }
                            }
                            createErrorText.visible = false
                            if (createPopup.editing) {
                                //编辑接口仅支持:备注/本地 IP/本地端口
                                apiClient.editTunnel({
                                    id: Number(createPopup.editing.id),
                                    note: createNote.text.trim(),
                                    local_ip: createLocalIp.text.trim() || "127.0.0.1",
                                    local_port: port
                                })
                                return
                            }
                            var params = {
                                name: createName.text.trim() || "未命名隧道",
                                note: createNote.text.trim(),
                                node: createNode.currentValue,
                                type: createType.currentText.toLowerCase(),
                                local_ip: createLocalIp.text.trim() || "127.0.0.1",
                                local_port: port
                            }
                            //remote:tcp/udp 是远程端口(空则不传,服务器随机);
                            //http/https 是绑定域名(必填)
                            if (isHttp)
                                params.remote = parts.join(",")
                            else if (createRemotePort.text)
                                params.remote = rp
                            apiClient.createTunnel(params)
                        }
                    }
                }
            }
        }
    }

    // 节点详情弹窗(仿 web 面板的节点详情)
    Popup {
        id: nodeDetailPopup
        width: 460
        height: 440
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property var nodeData: ({})

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            //模态弹窗是最高层级,接近实心:底下透出的卡片+壁纸叠在一起就是"杂乱"的来源
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    Layout.fillWidth: true
                    text: nodeDetailPopup.nodeData.name || "节点"
                    color: cText
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: detailTierText.implicitWidth + 14
                    radius: 10
                    color: "transparent"
                    border.color: root.nodeTierColor(nodeDetailPopup.nodeData.vip || 0)
                    border.width: 1

                    Text {
                        id: detailTierText
                        anchors.centerIn: parent
                        text: root.nodeTierLabel(nodeDetailPopup.nodeData.vip || 0)
                        color: parent.border.color
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text { text: "节点 ID"; color: cTextMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }
                    Text {
                        text: String(nodeDetailPopup.nodeData.id || "—")
                        color: cText
                        font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text { text: "使用限制"; color: cTextMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }
                    Text {
                        text: root.nodeTierLabel(nodeDetailPopup.nodeData.vip || 0)
                              + (nodeDetailPopup.nodeData.vip > 0 && nodeDetailPopup.nodeData.vip > (root.userInfo.group ? root.userInfo.group.level : 0) ? "(当前账号不可用)" : "")
                        color: cText
                        font.pixelSize: 13
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text { text: "接入地址"; color: cTextMuted; font.pixelSize: 12; Layout.preferredWidth: 60 }

                    Text {
                        Layout.fillWidth: true
                        text: String(nodeDetailPopup.nodeData.host || "—")
                        color: cText
                        font.pixelSize: 13
                        elide: Text.ElideMiddle
                    }

                    Item {
                        Layout.preferredWidth: copyText.implicitWidth + 20
                        Layout.preferredHeight: 26

                        Text {
                            id: copyText
                            anchors.centerIn: parent
                            property bool copied: false
                            text: copied ? "已复制 ✓" : "复制"
                            color: copyArea.containsMouse || copied ? Theme.cAccentHover : cTextSec
                            font.pixelSize: 12
                            font.bold: copied

                            Timer {
                                id: copyReset
                                interval: 1500
                                onTriggered: copyText.copied = false
                            }
                        }

                        MouseArea {
                            id: copyArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                appSettings.copyText(String(nodeDetailPopup.nodeData.host || ""))
                                copyText.copied = true
                                copyReset.restart()
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: String(nodeDetailPopup.nodeData.description || "") !== ""
                    spacing: 4

                    Text { text: "说明"; color: cTextMuted; font.pixelSize: 12 }

                    Text {
                        Layout.fillWidth: true
                        text: String(nodeDetailPopup.nodeData.description || "")
                        color: cTextSec
                        font.pixelSize: 13
                        wrapMode: Text.WordWrap
                    }
                }
            }

            Item { Layout.fillHeight: true }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 10
                color: closeArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "关闭"
                    color: cText
                    font.pixelSize: 14
                }

                Ripple { id: closeRipple; anchors.fill: parent }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: { closeRipple.play(); nodeDetailPopup.close() }
                }
            }
        }
    }

    // 公告详情弹窗
    Popup {
        id: bulletinPopup
        width: 500
        height: 480
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        property var itemData: ({})

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 180; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            color: Qt.alpha(Theme.cCard, 0.94)
            radius: 20
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.preferredHeight: 20
                    Layout.preferredWidth: noticeTag.implicitWidth + 14
                    radius: 10
                    color: "transparent"
                    border.color: cWarning
                    border.width: 1

                    Text {
                        id: noticeTag
                        anchors.centerIn: parent
                        text: "公告"
                        color: cWarning
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: bulletinPopup.itemData.title || "公告"
                    color: cText
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: noticeBody.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: PinkScrollBar {}

                Text {
                    id: noticeBody
                    width: bulletinPopup.width - 56
                    text: bulletinPopup.itemData.content || "无内容"
                    color: cTextSec
                    font.pixelSize: 13
                    wrapMode: Text.WordWrap
                    textFormat: Text.MarkdownText
                    lineHeight: 1.25
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                radius: 10
                color: noticeCloseArea.containsMouse ? Theme.cHoverBg : Theme.cInputBg
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "关闭"
                    color: cText
                    font.pixelSize: 14
                }

                Ripple { id: noticeCloseRipple; anchors.fill: parent }
                MouseArea {
                    id: noticeCloseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { noticeCloseRipple.play(); bulletinPopup.close() }
                }
            }
        }
    }
}
