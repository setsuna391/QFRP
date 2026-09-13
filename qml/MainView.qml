import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
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

    // ===== 背景 =====
    Rectangle {
        anchors.fill: parent
        color: cBg
    }

    // ===== 自定义壁纸 =====
    //优先级:设置页自选的图片 > 构建时内置的壁纸(assets/wallpaper.*) > 纯色主题背景。
    //透明度固定 0.35:叠在浅色主题上文字依然清晰,已按此值调校
    Image {
        anchors.fill: parent
        property string userSource: appSettings.wallpaperFile === ""
                                    ? "" : "file://" + appSettings.wallpaperFile
        property string effectiveSource: userSource !== "" ? userSource
                                         : (appSettings.builtinWallpaper !== ""
                                            ? "qrc:" + appSettings.builtinWallpaper : "")
        visible: effectiveSource !== ""
        source: effectiveSource
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        mipmap: true
        opacity: 0.35
    }

    // ===== 信号处理 =====
    Connections {
        target: apiClient

        function onTunnelsReceived(tunnels) {
            var arr = []
            for (var i = 0; i < tunnels.length; i++)
                arr.push(tunnels[i])
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
            addLog("隧道创建成功: " + (tunnel.name || tunnel.id), "success")
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
    }

    // ===== frpc 进程事件 =====
    Connections {
        target: frpc

        function onStarted(tunnelId) {
            var s = new Set(root.runningIds)
            s.add(String(tunnelId))
            root.runningIds = s
            addLog("frpc 已启动 (隧道 " + tunnelId + ")", "success")
        }
        function onStopped(tunnelId, exitCode) {
            var s = new Set(root.runningIds)
            s.delete(String(tunnelId))
            root.runningIds = s
            addLog("frpc 已退出 (隧道 " + tunnelId + ", 退出码 " + exitCode + ")",
                   exitCode === 0 ? "info" : "warning")
        }
        function onStartFailed(tunnelId, reason) {
            addLog("启动失败 (隧道 " + tunnelId + "): " + reason, "error")
        }
        //frpc 的 stdout/stderr 按行进日志页
        function onFrpcOutput(tunnelId, line) {
            addLog("frpc:" + tunnelId + " " + line, "info")
        }
        //frpc 二进制自动下载
        function onFrpcDownloadStarted() {
            addLog("未找到 frpc,正在从 natfrp 官方源自动下载...", "info")
        }
        function onFrpcDownloadFinished(path) {
            addLog("frpc 下载完成: " + path, "success")
        }
        function onFrpcDownloadFailed(error) {
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
    }

    // ===== 主布局 =====
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ========== 侧边栏 ==========
        Rectangle {
            id: sidebar
            Layout.fillHeight: true
            Layout.preferredWidth: 200
            color: cSidebar

            // 右边框
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: 1
                color: cBorder
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // Logo
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 56

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "QFRP"
                            color: cAccent
                            font.pixelSize: 16
                            font.bold: true
                            font.letterSpacing: 0.5
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                // (logo 下不再画分隔线:它和内容区顶栏的下边框在分数缩放下
                //  会差 1px 对不齐;横线只保留内容区那条,交界处是干净的直角)

                // 导航项
                Repeater {
                    model: root.navItems

                    delegate: Rectangle {
                        id: navItem
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        //项与项留出间隙,选中胶囊不再上下贴在一起(侧栏 spacing 为 0,只能逐项加 margin)
                        Layout.topMargin: index === 0 ? 4 : 6
                        radius: 8
                        color: navItem.isActive ? Theme.cNavActive
                             : navArea.containsMouse ? Theme.cNavHover
                             : "#00000000"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: navArea.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                        readonly property bool isActive: root.currentPage === modelData.name

                        // 选中指示条:切换时弹出/收回
                        Rectangle {
                            width: 3
                            height: 20
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: cAccent
                            radius: 2
                            scale: navItem.isActive ? 1 : 0
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            spacing: 12

                            AppIcon {
                                iconType: modelData.icon
                                iconColor: navItem.isActive ? cAccent : cTextSec
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.label
                                color: navItem.isActive ? cText : cTextSec
                                font.pixelSize: 14
                                font.bold: navItem.isActive
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: navArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: root.currentPage = modelData.name
                        }
                    }
                }

                // 弹性间距
                Item { Layout.fillHeight: true }

                // 用户信息区
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: "#00000000"

                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: cBorder
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 16
                            color: cAccent

                            Text {
                                anchors.centerIn: parent
                                text: (root.userInfo.name || "U").charAt(0).toUpperCase()
                                color: "#ffffff"
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.userInfo.name || "未登录"
                            color: cText
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            radius: 6
                            color: logoutArea.containsMouse ? Theme.cErrorBg : "#00000000"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            scale: logoutArea.containsMouse ? 1.1 : 1.0
                            Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                            AppIcon {
                                anchors.centerIn: parent
                                iconType: "logout"
                                iconColor: logoutArea.containsMouse ? cError : cTextSec
                                width: 16
                                height: 16
                            }

                            MouseArea {
                                id: logoutArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: logoutPopup.open()
                            }
                        }
                    }
                }
            }
        }

        // ========== 内容区 ==========
        ColumnLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            spacing: 0

            // 顶栏
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "#00000000"

                //顶栏空白处拖动移动窗口(niri 无标题栏)
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.appWindow.startSystemMove()
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: cBorder
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 24
                    anchors.rightMargin: 24

                    Text {
                        text: root.pageTitle
                        color: cText
                        font.pixelSize: 18
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // 新建隧道按钮
                    Rectangle {
                        visible: root.currentPage === "tunnels"
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 104
                        radius: 8
                        color: createActionArea.containsMouse ? cAccentHover : cAccent
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: createActionArea.pressed ? 0.94 : (createActionArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

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
                                text: "新建隧道"
                                color: "#ffffff"
                                font.pixelSize: 13
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: createActionArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: createPopup.open()
                        }
                    }

                    // 刷新按钮
                    Rectangle {
                        visible: root.currentPage === "tunnels" || root.currentPage === "nodes"
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 80
                        radius: 8
                        color: refreshArea.containsMouse ? Theme.cHoverBg : cCard
                        border.color: cBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: refreshArea.pressed ? 0.94 : (refreshArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

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
                                    duration: 450
                                    easing.type: Easing.Bezier
                                    easing.bezierCurve: Theme.motionOut
                                }
                            }

                            Text {
                                text: "刷新"
                                color: cText
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: {
                                refreshSpin.restart()
                                if (root.currentPage === "tunnels") apiClient.getTunnels()
                                else if (root.currentPage === "nodes") apiClient.getNodes()
                            }
                        }
                    }

                    // 清空日志按钮
                    Rectangle {
                        visible: root.currentPage === "log"
                        Layout.preferredHeight: 34
                        Layout.preferredWidth: 80
                        radius: 8
                        color: clearLogArea.containsMouse ? Theme.cErrorBg : cCard
                        border.color: cBorder
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 120 } }
                        scale: clearLogArea.pressed ? 0.94 : (clearLogArea.containsMouse ? 1.04 : 1.0)
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                        Text {
                            anchors.centerIn: parent
                            text: "清空"
                            color: clearLogArea.containsMouse ? cError : cText
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: clearLogArea
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onClicked: logModel.clear()
                        }
                    }

                    //与功能按钮留出间隔
                    Item { Layout.preferredWidth: 10 }

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

            // ===== 页面内容 =====
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ----- 隧道页面(方形卡片网格,隧道少时自动放大) -----
                GridView {
                    id: tunnelsGrid
                    visible: root.currentPage === "tunnels"
                    anchors.fill: parent
                    anchors.margins: 16
                    clip: true
                    //≤2 条隧道时两列大卡片,更多时三列;高度同步调整
                    cellWidth: root.tunnels.length <= 2 ? (width - 24) / 2 : (width - 36) / 3
                    cellHeight: root.tunnels.length <= 2 ? 240 : 206

                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    //刷新时卡片级联入场
                    populate: Transition {
                        id: tunnelsPop
                        SequentialAnimation {
                            PauseAnimation { duration: Math.min(tunnelsPop.ViewTransition.index * 40, 400) }
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                            NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                        }
                    }

                    delegate: Rectangle {
                        width: tunnelsGrid.cellWidth - 14
                        height: tunnelsGrid.cellHeight - 14
                        radius: 16
                        color: cCard
                        border.color: cardArea.containsMouse ? Theme.cCardHoverBorder : cBorder
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                        scale: cardArea.containsMouse ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

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

                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

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
                                    border.color: parent.parent.parent.tagColor
                                    border.width: 1

                                    Text {
                                        id: typeLabel
                                        anchors.centerIn: parent
                                        text: String(t.type || "tcp").toUpperCase()
                                        color: parent.parent.parent.tagColor
                                        font.pixelSize: 10
                                        font.bold: true
                                    }
                                }

                                Item { Layout.fillWidth: true }

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

                                    MouseArea {
                                        id: delArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
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
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: "节点 #" + (t.node || "?") + "   ·   ID " + (t.id || "?")
                                color: cTextSec
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                text: (t.local_ip || "127.0.0.1") + ":" + (t.local_port || "?") + "  →  :" + (t.remote || "?")
                                color: cTextSec
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillHeight: true }

                            // 启停按钮(通栏)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 10
                                color: runArea.containsMouse
                                       ? (running ? Theme.cErrorBg : Theme.cSuccessBgHover)
                                       : (running ? Theme.cInputBg : Theme.cSuccessBg)
                                border.color: running ? cError : cSuccess
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 140 } }
                                scale: runArea.pressed ? 0.97 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

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

                                MouseArea {
                                    id: runArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: frpc.toggleTunnel(String(t.id))
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

                // ----- 节点页面 -----
                GridView {
                    id: nodesView
                    visible: root.currentPage === "nodes"
                    anchors.fill: parent
                    anchors.margins: 16
                    model: root.nodes
                    clip: true
                    cellWidth: 230
                    cellHeight: 110

                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.98
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    populate: Transition {
                        id: nodesPop
                        SequentialAnimation {
                            PauseAnimation { duration: Math.min(nodesPop.ViewTransition.index * 20, 400) }
                            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                            NumberAnimation { property: "scale"; from: 0.96; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                        }
                    }

                    ScrollBar.vertical: PinkScrollBar {}

                    delegate: Item {
                        id: nodeCell
                        width: nodesView.cellWidth
                        height: nodesView.cellHeight

                        Rectangle {
                            id: nodeCard
                            width: nodeCell.width - 10
                            height: nodeCell.height - 10
                            anchors.centerIn: parent
                            radius: 10
                            color: cCard
                            border.color: nodeHover.hovered ? Theme.cCardHoverBorder : cBorder
                            border.width: 1
                            scale: nodeHover.hovered ? 1.03 : 1.0
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                            HoverHandler { id: nodeHover }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6

                            RowLayout {
                                spacing: 8

                                AppIcon {
                                    iconType: "node"
                                    iconColor: cAccent
                                    width: 16
                                    height: 16
                                }

                                Text {
                                    text: modelData.name || ("节点 #" + (modelData.id || "?"))
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                                Text {
                                    text: "位置: " + (modelData.host || modelData.description || "未知")
                                    color: cTextSec
                                    font.pixelSize: 12
                                }

                                Text {
                                    text: "ID: " + (modelData.id || "?")
                                    color: cTextMuted
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.nodes.length === 0
                        text: "暂无节点数据"
                        color: cTextMuted
                        font.pixelSize: 14
                    }
                }

                // ----- 日志页面 -----
                ListView {
                    id: logView
                    visible: root.currentPage === "log"
                    anchors.fill: parent
                    anchors.margins: 16
                    model: logModel
                    clip: true
                    spacing: 2

                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.98
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    //新日志条目渐显;超过上限移除旧行时,其余行平滑上移而不是突跳
                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 180 }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                    }

                    ScrollBar.vertical: PinkScrollBar {}

                    delegate: RowLayout {
                        width: logView.width
                        spacing: 8

                        Text {
                            text: "[" + model.time + "]"
                            color: cTextMuted
                            font.family: "monospace"
                            font.pixelSize: 12
                        }

                        Text {
                            Layout.fillWidth: true
                            text: model.msg
                            color: model.level === "error" ? cError :
                                   model.level === "success" ? cSuccess :
                                   model.level === "warning" ? cWarning : cText
                            font.family: "monospace"
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }
                    }

                    onCountChanged: {
                        if (count > 0)
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

                // ----- 设置页面 -----
                Flickable {
                    visible: root.currentPage === "settings"
                    anchors.fill: parent
                    anchors.margins: 16
                    contentWidth: width
                    contentHeight: settingsCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    opacity: visible ? 1 : 0
                    scale: visible ? 1 : 0.98
                    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }
                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    ScrollBar.vertical: PinkScrollBar {}

                    ColumnLayout {
                        id: settingsCol
                        width: parent.width
                        spacing: 16

                        // 主题卡
                        Rectangle {
                            Layout.fillWidth: true
                            //高度跟随内容:配色多到换行时卡片自动长高
                            implicitHeight: themeCardCol.implicitHeight + 32
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            ColumnLayout {
                                id: themeCardCol
                                anchors.fill: parent
                                anchors.margins: 16
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
                                            color: Theme.current === index ? Theme.cAccent : cCard
                                            border.color: Theme.current === index ? Theme.cAccent : cBorder
                                            border.width: 1
                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            scale: chipArea.pressed ? 0.96 : (chipArea.containsMouse ? 1.04 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

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

                                            MouseArea {
                                                id: chipArea
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Theme.current = index
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
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
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
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 16
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
                                    radius: 8
                                    color: Theme.cInputBg
                                    border.color: frpcPathInput.activeFocus ? cAccent : cBorder
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

                                    Rectangle {
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 6
                                        color: dlFrpcArea.containsMouse ? Theme.cHoverBg : cCard
                                        border.color: cBorder
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: dlFrpcArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "重新下载"
                                            color: cText
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: dlFrpcArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: frpc.downloadFrpc()
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
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            ColumnLayout {
                                id: wpCardCol
                                anchors.fill: parent
                                anchors.margins: 16
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
                                        radius: 6
                                        color: wpPickArea.containsMouse ? Theme.cHoverBg : cCard
                                        border.color: cBorder
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: wpPickArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "选择图片"
                                            color: cText
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: wpPickArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: wallpaperDialog.open()
                                        }
                                    }

                                    Rectangle {
                                        visible: appSettings.wallpaperFile !== ""
                                        Layout.preferredWidth: 88
                                        Layout.preferredHeight: 28
                                        radius: 6
                                        color: wpClearArea.containsMouse ? Theme.cErrorBg : cCard
                                        border.color: cBorder
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        scale: wpClearArea.containsMouse ? 1.05 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                        Text {
                                            anchors.centerIn: parent
                                            text: "恢复默认"
                                            color: wpClearArea.containsMouse ? cError : cText
                                            font.pixelSize: 12
                                        }

                                        MouseArea {
                                            id: wpClearArea
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            hoverEnabled: true
                                            onClicked: appSettings.clearWallpaper()
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
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            ColumnLayout {
                                id: aboutCol
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 6

                                Text {
                                    text: "关于"
                                    color: cText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: "QFRP 客户端 v0.1.0"
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

                                    Text {
                                        id: qqValue
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

                                    MouseArea {
                                        id: qqArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            appSettings.copyText("1537403715")
                                            qqValue.copied = true
                                            qqCopyReset.restart()
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

                                    Text {
                                        text: "setsuna391/QFRP"
                                        color: ghArea.containsMouse ? Theme.cAccentHover : Theme.cAccent
                                        font.pixelSize: 12
                                        font.bold: true
                                        font.underline: ghArea.containsMouse
                                    }

                                    MouseArea {
                                        id: ghArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Qt.openUrlExternally("https://github.com/setsuna391/QFRP")
                                    }
                                }

                                Text {
                                    text: "基于 Qt6 + QML 开发"
                                    color: cTextMuted
                                    font.pixelSize: 11
                                }
                            }
                        }

                        // 新版界面入口
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: newUiCol.implicitHeight + 32
                            radius: 10
                            color: cCard
                            border.color: cBorder
                            border.width: 1

                            ColumnLayout {
                                id: newUiCol
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 6

                                Text { text: "界面风格"; color: cText; font.pixelSize: 14; font.bold: true }
                                Text { text: "体验新版界面:流动渐变背景 + 玻璃拟态卡片"; color: cTextSec; font.pixelSize: 12 }

                                Rectangle {
                                    Layout.preferredWidth: 170
                                    Layout.preferredHeight: 34
                                    radius: 10
                                    color: newUiArea.containsMouse ? cAccentHover : cAccent
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    scale: newUiArea.pressed ? 0.96 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "切换到新版界面"
                                        color: "#ffffff"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }

                                    MouseArea {
                                        id: newUiArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: UiStyle.modern = true
                                    }
                                }
                            }
                        }

                        // 退出登录按钮
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            radius: 10
                            color: logoutBtnArea.containsMouse ? Theme.cErrorBg : cCard
                            border.color: cError
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                            scale: logoutBtnArea.pressed ? 0.97 : (logoutBtnArea.containsMouse ? 1.04 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                            Text {
                                anchors.centerIn: parent
                                text: "退出登录"
                                color: cError
                                font.pixelSize: 14
                                font.bold: true
                            }

                            MouseArea {
                                id: logoutBtnArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: logoutPopup.open()
                            }
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 220; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            color: cCard
            radius: 16
            border.color: cBorder
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
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
                    radius: 8
                    color: quitCancelArea.containsMouse ? Theme.cHoverBg : cCard
                    border.color: cBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: quitCancelArea.pressed ? 0.96 : (quitCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: quitCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: quitPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: quitConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: quitConfirmArea.pressed ? 0.96 : (quitConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "退出"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: quitConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.appWindow.close()
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 220; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            color: cCard
            radius: 16
            border.color: cBorder
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
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
                    radius: 8
                    color: delCancelArea.containsMouse ? Theme.cHoverBg : cCard
                    border.color: cBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: delCancelArea.pressed ? 0.96 : (delCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: delCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            root.pendingDeleteId = ""
                            deletePopup.close()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: delConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: delConfirmArea.pressed ? 0.96 : (delConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "确认删除"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: delConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
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
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 220; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            color: cCard
            radius: 16
            border.color: cBorder
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
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
                    radius: 8
                    color: logoutCancelArea.containsMouse ? Theme.cHoverBg : cCard
                    border.color: cBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: logoutCancelArea.pressed ? 0.96 : (logoutCancelArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: logoutCancelArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: logoutPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: logoutConfirmArea.containsMouse ? Theme.cAccentHover : Theme.cError
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: logoutConfirmArea.pressed ? 0.96 : (logoutConfirmArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "退出登录"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: logoutConfirmArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
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
        width: 400
        height: 480
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        //重新打开时清掉上一次的错误提示(在 aboutToShow 里清,
        //这样打开过程中到达的创建失败信号不会被覆盖)
        onAboutToShow: createErrorText.visible = false

        //弹出/关闭动画:淡入 + 从略小弹出
        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 220; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 220; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
            NumberAnimation { property: "scale"; from: 1; to: 0.95; duration: 160; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        background: Rectangle {
            color: cCard
            radius: 16
            border.color: cBorder
            border.width: 1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 12

            Text {
                text: "新建隧道"
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
                    radius: 8
                    color: Theme.cInputBg
                    border.color: createName.activeFocus ? cAccent : cBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: createName
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "我的隧道"
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
                    model: root.nodes
                    textRole: "name"
                    valueRole: "id"

                    background: Rectangle {
                        radius: 8
                        color: Theme.cInputBg
                        border.color: createNode.pressed || createNode.popup.visible ? cAccent : cBorder
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
                            radius: 8
                            color: cCard
                            border.color: cBorder
                            border.width: 1
                        }

                        contentItem: ListView {
                            clip: true
                            //限制最大高度:节点多时下拉可滚动(否则高度永远等于
                            //全部内容,滚轮滚不动,列表还会超出屏幕)
                            implicitHeight: Math.min(contentHeight, 240)
                            boundsBehavior: Flickable.StopAtBounds
                            model: createNode.popup.visible ? createNode.delegateModel : null

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

                                width: createNode.width - 8
                                height: 32
                                hoverEnabled: true
                                highlighted: createNode.highlightedIndex === nodeItem.index

                                //自定义 popup 下 ComboBox 内部的点击选中接线不可靠,
                                //这里显式设置选中并关闭弹窗
                                onClicked: {
                                    createNode.currentIndex = nodeItem.index
                                    createNode.popup.close()
                                }

                                contentItem: Text {
                                    text: nodeItem.model[createNode.textRole] !== undefined ? nodeItem.model[createNode.textRole] : ""
                                    color: nodeItem.hovered || nodeItem.highlighted ? "#ffffff" : cText
                                    font.pixelSize: 13
                                    verticalAlignment: Text.AlignVCenter
                                    leftPadding: 6
                                    elide: Text.ElideRight
                                }

                                background: Rectangle {
                                    radius: 6
                                    color: nodeItem.hovered || nodeItem.highlighted ? cAccent : "transparent"
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
                    model: ["TCP", "UDP"]
                    currentIndex: 0

                    background: Rectangle {
                        radius: 8
                        color: Theme.cInputBg
                        border.color: createType.pressed || createType.popup.visible ? cAccent : cBorder
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
                            radius: 8
                            color: cCard
                            border.color: cBorder
                            border.width: 1
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
                        radius: 8
                        color: Theme.cInputBg
                        border.color: createLocalIp.activeFocus ? cAccent : cBorder
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
                        radius: 8
                        color: Theme.cInputBg
                        border.color: createLocalPort.activeFocus ? cAccent : cBorder
                        border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextField {
                            id: createLocalPort
                            anchors.fill: parent
                            anchors.margins: 2
                            placeholderText: "8080"
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
                    radius: 8
                    color: cancelCreateArea.containsMouse ? Theme.cHoverBg : cCard
                    border.color: cBorder
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: cancelCreateArea.pressed ? 0.96 : (cancelCreateArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        color: cText
                        font.pixelSize: 14
                    }

                    MouseArea {
                        id: cancelCreateArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: createPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 40
                    radius: 8
                    color: confirmCreateArea.containsMouse ? cAccentHover : cAccent
                    Behavior on color { ColorAnimation { duration: 120 } }
                    scale: confirmCreateArea.pressed ? 0.96 : (confirmCreateArea.containsMouse ? 1.04 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Text {
                        anchors.centerIn: parent
                        text: "创建"
                        color: "#ffffff"
                        font.pixelSize: 14
                        font.bold: true
                    }

                    MouseArea {
                        id: confirmCreateArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: {
                            //客户端先校验一遍必填项,避免把不完整参数发给服务器
                            var port = parseInt(createLocalPort.text)
                            if (createNode.currentIndex < 0 || createNode.currentValue === undefined) {
                                createErrorText.text = "请选择节点"
                                createErrorText.visible = true
                                return
                            }
                            if (createType.currentText !== "TCP" && createType.currentText !== "UDP") {
                                createErrorText.text = "请选择协议"
                                createErrorText.visible = true
                                return
                            }
                            if (!createLocalPort.text || !(port >= 1 && port <= 65535)) {
                                createErrorText.text = "本地端口必须是 1~65535 的数字"
                                createErrorText.visible = true
                                return
                            }
                            createErrorText.visible = false
                            var params = {
                                name: createName.text.trim() || "未命名隧道",
                                node: createNode.currentValue,
                                type: createType.currentText.toLowerCase(),
                                local_ip: createLocalIp.text.trim() || "127.0.0.1",
                                local_port: port
                            }
                            apiClient.createTunnel(params)
                        }
                    }
                }
            }
        }
    }
}
