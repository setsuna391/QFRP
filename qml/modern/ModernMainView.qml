import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs

//新版主界面:仿 xinghuisama.top —— 流动渐变背景 + 玻璃拟态卡片 + indigo 强调
//数据流与经典版完全一致(apiClient/frpc/appSettings),仅视觉不同
Item {
    id: root

    readonly property var appWindow: Window.window
    property var tunnels: []
    property var nodes: []
    property var runningIds: new Set()
    property string currentPage: "tunnels"
    property string nodeFilter: "all"

    //新版界面配色(独立于经典主题系统)
    readonly property color cGlass: "#ccffffff"
    readonly property color cGlassBorder: "#3dffffff"
    readonly property color cText: "#2a2f45"
    readonly property color cTextSec: "#5b6478"
    readonly property color cTextMuted: "#9aa0b5"
    readonly property color cAccent: "#4f46e5"
    readonly property color cAccentSoft: "#eceafd"
    readonly property color cAccentHover: "#5b52ea"
    readonly property color cSuccess: "#10b981"
    readonly property color cError: "#ef4444"

    function syncRunning() {
        var s = new Set()
        var ids = frpc.runningTunnelIds()
        for (var i = 0; i < ids.length; i++)
            s.add(String(ids[i]))
        runningIds = s
    }

    //档位从节点名判断: 含 VIP → VIP 专属, 含 PLUS → PLUS, 其余普通
    function nodeTier(name) {
        var n = String(name)
        if (n.indexOf("VIP") >= 0) return "VIP"
        if (n.indexOf("PLUS") >= 0) return "PLUS"
        return ""
    }

    readonly property var filteredNodes: {
        var out = []
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            var tier = nodeTier(String(n.name || ""))
            if (nodeFilter === "all"
                || (nodeFilter === "vip" && tier === "VIP")
                || (nodeFilter === "plus" && tier === "PLUS")
                || (nodeFilter === "normal" && tier === ""))
                out.push(n)
        }
        return out
    }

    function tunnelName(id) {
        for (var i = 0; i < tunnels.length; i++) {
            if (String(tunnels[i].id) === String(id))
                return tunnels[i].name || String(id)
        }
        return String(id)
    }

    function addLog(msg, level) {
        logModel.append({ time: Qt.formatDateTime(new Date(), "hh:mm:ss"), msg: msg, level: level || "info" })
        if (logModel.count > 400)
            logModel.remove(0)
    }

    //支持 --page=nodes|tunnels|log|settings 直达页面、--create 启动时打开新建弹窗
    Component.onCompleted: {
        var args = Qt.application.arguments || []
        for (var i = 0; i < args.length; i++) {
            if (args[i].indexOf("--page=") === 0)
                currentPage = args[i].substring(7)
            if (args[i] === "--create")
                createTimer.start()
        }
        apiClient.getTunnels()
        apiClient.getNodes()
        addLog("新版界面已加载", "info")
        syncRunning()
    }

    Timer {
        id: createTimer
        interval: 400
        onTriggered: createPopup.open()
    }

    Connections {
        target: apiClient
        function onTunnelsReceived(t) {
            var arr = []
            for (var i = 0; i < t.length; i++) arr.push(t[i])
            root.tunnels = arr
        }
        function onNodesReceived(n) {
            var arr = []
            for (var i = 0; i < n.length; i++) arr.push(n[i])
            root.nodes = arr
            if (createNode.currentIndex < 0 && createNode.count > 0)
                createNode.currentIndex = 0
        }
        function onTunnelCreated(t) {
            var arr = root.tunnels.slice()
            arr.push(t)
            root.tunnels = arr
            addLog("隧道创建成功: " + (t.name || t.id), "success")
            createPopup.close()
        }
        function onTunnelDeleted(tunnelId) {
            for (var i = 0; i < root.tunnels.length; i++) {
                if (String(root.tunnels[i].id) === String(tunnelId)) {
                    root.tunnels.splice(i, 1)
                    root.tunnels = root.tunnels.slice()
                    break
                }
            }
            frpc.stopTunnel(String(tunnelId))
        }
    }

    Connections {
        target: frpc
        function onStarted(tunnelId) { root.syncRunning(); addLog("frpc 已启动 (隧道 " + tunnelId + ")", "success") }
        function onStopped(tunnelId, exitCode) { root.syncRunning(); addLog("frpc 已退出 (隧道 " + tunnelId + ", 退出码 " + exitCode + ")", exitCode === 0 ? "info" : "error") }
        function onStartFailed(tunnelId, reason) { root.syncRunning(); addLog("启动失败: " + reason, "error") }
        function onFrpcOutput(tunnelId, line) { addLog("[" + tunnelId + "] " + line, "info") }
    }

    // ===== 流动渐变背景 =====
    ModernBackground {}

    // ===== 布局:玻璃侧栏 + 内容区 =====
    RowLayout {
        anchors.fill: parent
        spacing: 12

        // 侧栏
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 224
            Layout.margins: 12
            radius: 18
            color: "#a8ffffff"
            border.color: "#40ffffff"
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64

                    Text {
                        anchors.centerIn: parent
                        text: "QFRP"
                        color: cAccent
                        font.family: "Noto Serif CJK SC"
                        font.pixelSize: 18
                        font.bold: true
                        font.letterSpacing: 1
                    }
                }

                // 导航
                Repeater {
                    model: [
                        { name: "tunnels", label: "隧道", icon: "tunnel" },
                        { name: "nodes", label: "节点", icon: "node" },
                        { name: "log", label: "日志", icon: "log" },
                        { name: "settings", label: "设置", icon: "settings" }
                    ]

                    delegate: Rectangle {
                        id: navItem
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        Layout.topMargin: index === 0 ? 6 : 4
                        radius: 12
                        readonly property bool isActive: root.currentPage === modelData.name
                        color: isActive ? cAccentSoft : navArea.containsMouse ? "#66ffffff" : "#00000000"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        scale: navArea.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                        Rectangle {
                            width: 3
                            height: 18
                            radius: 1.5
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: cAccent
                            scale: navItem.isActive ? 1 : 0
                            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            spacing: 10

                            AppIcon {
                                iconType: modelData.icon
                                iconColor: navItem.isActive ? cAccent : cTextSec
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData.label
                                color: navItem.isActive ? cAccent : cTextSec
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

                Item { Layout.fillHeight: true }

                // 底部:开发者 + 返回经典
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.leftMargin: 14
                    Layout.rightMargin: 14
                    color: "#22dde0ee"
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    Layout.margins: 10
                    radius: 10
                    color: classicArea.containsMouse ? cAccentSoft : "#00000000"
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        AppIcon {
                            iconType: "settings"
                            iconColor: classicArea.containsMouse ? cAccent : cTextMuted
                            width: 14
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Text {
                            text: "返回经典界面"
                            color: classicArea.containsMouse ? cAccent : cTextMuted
                            font.pixelSize: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: classicArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: UiStyle.modern = false
                    }
                }
            }
        }

        // 内容区
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.rightMargin: 12
            Layout.topMargin: 12
            Layout.bottomMargin: 12
            spacing: 12

            // 顶栏
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Text {
                    text: root.currentPage === "tunnels" ? "隧道管理"
                        : root.currentPage === "nodes" ? "节点列表"
                        : root.currentPage === "log" ? "运行日志" : "设置"
                    color: cText
                    font.family: "Noto Serif CJK SC"
                    font.pixelSize: 20
                    font.bold: true
                }

                Item { Layout.fillWidth: true }

                // 新建隧道按钮
                Rectangle {
                    visible: root.currentPage === "tunnels"
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 36
                    radius: 12
                    color: createArea.containsMouse ? cAccentHover : cAccent
                    Behavior on color { ColorAnimation { duration: 140 } }
                    scale: createArea.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        AppIcon { iconType: "plus"; iconColor: "#ffffff"; width: 13; height: 13; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "新建"; color: "#ffffff"; font.pixelSize: 13; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: createArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: createPopup.open()
                    }
                }

                Item { Layout.preferredWidth: 8 }

                WindowControls {
                    win: root.appWindow
                    onMinimizeClicked: root.appWindow.showMinimized()
                    onCloseClicked: root.appWindow.close()
                }
            }

            // ===== 隧道页(方形卡片网格) =====
            GridView {
                id: tunnelsGrid
                visible: root.currentPage === "tunnels"
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: root.tunnels.length
                clip: true
                cellWidth: 216
                cellHeight: 196

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                //刷新时卡片级联入场
                populate: Transition {
                    id: tunnelsPop
                    SequentialAnimation {
                        PauseAnimation { duration: Math.min(tunnelsPop.ViewTransition.index * 30, 360) }
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                        NumberAnimation { property: "scale"; from: 0.95; to: 1; duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                    }
                }

                delegate: Rectangle {
                    width: tunnelsGrid.cellWidth - 12
                    height: tunnelsGrid.cellHeight - 12
                    radius: 18
                    color: cGlass
                    border.color: cardArea.containsMouse ? "#66818cf8" : cGlassBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    property var t: root.tunnels[index]
                    property bool running: root.runningIds.has(String(t.id))

                    //卡片级悬停层:声明在内容之前(下层),不挡按钮
                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 6

                        // 顶行: 状态点 + 协议 + 删除
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Rectangle {
                                width: 9; height: 9; radius: 4.5
                                Layout.alignment: Qt.AlignVCenter
                                color: running ? cSuccess : cTextMuted
                                Behavior on color { ColorAnimation { duration: 200 } }
                            }

                            Rectangle {
                                Layout.preferredHeight: 18
                                Layout.preferredWidth: typeLabel.implicitWidth + 12
                                radius: 9
                                color: cAccentSoft
                                border.color: "#55818cf8"
                                border.width: 1

                                Text {
                                    id: typeLabel
                                    anchors.centerIn: parent
                                    text: String(t.type || "tcp").toUpperCase()
                                    color: cAccent
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }

                            Item { Layout.fillWidth: true }

                            AppIcon {
                                iconType: "delete"
                                iconColor: delArea.containsMouse ? cError : cTextMuted
                                width: 14
                                height: 14
                                Layout.alignment: Qt.AlignVCenter

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
                            font.pixelSize: 15
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        // 端口信息(两行)
                        Text {
                            Layout.fillWidth: true
                            text: (t.local_ip || "127.0.0.1") + ":" + (t.local_port || "?")
                            color: cTextSec
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Text {
                            Layout.fillWidth: true
                            text: "→ :" + (t.remote || "?") + "   ·   ID " + (t.id || "?")
                            color: cTextMuted
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        // 启停按钮(通栏)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: 10
                            color: runArea.containsMouse
                                   ? (running ? "#33ef4444" : "#3310b981")
                                   : (running ? "#22ef4444" : "#2210b981")
                            Behavior on color { ColorAnimation { duration: 140 } }
                            scale: runArea.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                            Text {
                                anchors.centerIn: parent
                                text: running ? "停止" : "启动"
                                color: running ? cError : cSuccess
                                font.pixelSize: 13
                                font.bold: true
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
                    text: "还没有隧道,点右上角「新建」创建第一个"
                    color: cTextMuted
                    font.pixelSize: 13
                }
            }
            // ===== 节点页(小卡片网格 + 档位分类) =====
            Item {
                visible: root.currentPage === "nodes"
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    // 档位筛选
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                            model: [
                                { key: "all", label: "全部" },
                                { key: "vip", label: "VIP 专属" },
                                { key: "plus", label: "PLUS" },
                                { key: "normal", label: "普通" }
                            ]

                            delegate: Rectangle {
                                Layout.preferredHeight: 30
                                Layout.preferredWidth: chipLabel.implicitWidth + 24
                                radius: 15
                                readonly property bool on: root.nodeFilter === modelData.key
                                color: on ? cAccent : "#99ffffff"
                                border.color: on ? cAccent : cGlassBorder
                                border.width: 1
                                Behavior on color { ColorAnimation { duration: 140 } }
                                scale: chipArea.pressed ? 0.94 : (chipArea.containsMouse ? 1.05 : 1.0)
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: on ? "#ffffff" : cTextSec
                                    font.pixelSize: 12
                                    font.bold: on
                                }

                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.nodeFilter = modelData.key
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: root.filteredNodes.length + " 个节点"
                            color: cTextMuted
                            font.pixelSize: 12
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // 节点小卡片网格
                    GridView {
                        id: nodesGrid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cellWidth: 200
                        cellHeight: 88
                        model: root.filteredNodes.length

                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            width: nodesGrid.cellWidth - 10
                            height: nodesGrid.cellHeight - 10
                            radius: 14
                            color: cGlass
                            border.color: nodeArea.containsMouse ? "#66818cf8" : cGlassBorder
                            border.width: 1
                            Behavior on border.color { ColorAnimation { duration: 140 } }

                            property var node: root.filteredNodes[index]
                            readonly property string tier: root.nodeTier(String(node.name || ""))

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Text {
                                        text: node.name || ("节点 #" + (node.id || "?"))
                                        color: cText
                                        font.pixelSize: 12
                                        font.bold: true
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        visible: tier !== ""
                                        Layout.preferredWidth: nodeTierLabel.implicitWidth + 10
                                        Layout.preferredHeight: 16
                                        radius: 8
                                        color: tier === "VIP" ? "#33fbbf24" : "#33818cf8"
                                        border.color: tier === "VIP" ? "#fbbf24" : "#818cf8"
                                        border.width: 1

                                        Text {
                                            id: nodeTierLabel
                                            anchors.centerIn: parent
                                            text: tier
                                            color: parent.border.color
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                }

                                Text {
                                    text: node.host || node.description || "—"
                                    color: cTextSec
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: "ID " + (node.id || "?")
                                    color: cTextMuted
                                    font.pixelSize: 10
                                }
                            }

                            MouseArea {
                                id: nodeArea
                                anchors.fill: parent
                                hoverEnabled: true
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.filteredNodes.length === 0
                            text: "该分类下暂无节点"
                            color: cTextMuted
                            font.pixelSize: 13
                        }
                    }
                }
            }

            // ===== 日志页 =====
            Rectangle {
                visible: root.currentPage === "log"
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 16
                color: cGlass
                border.color: cGlassBorder
                border.width: 1
                clip: true

                ListView {
                    id: logView
                    anchors.fill: parent
                    anchors.margins: 14
                    model: logModel
                    clip: true
                    spacing: 2

                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160 }
                    }
                    displaced: Transition {
                        NumberAnimation { properties: "y"; duration: 140; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
                    }

                    delegate: RowLayout {
                        width: logView.width
                        spacing: 8

                        Text {
                            text: time
                            color: cTextMuted
                            font.pixelSize: 11
                            font.family: "monospace"
                        }

                        Text {
                            text: msg
                            color: level === "error" ? cError : level === "success" ? cSuccess : cTextSec
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }
                }
            }

            // ===== 设置页 =====
            Flickable {
                visible: root.currentPage === "settings"
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: settingsCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: settingsCol
                    width: parent.width
                    spacing: 12

                    // 外观卡
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: styleCol.implicitHeight + 32
                        radius: 16
                        color: cGlass
                        border.color: cGlassBorder
                        border.width: 1

                        ColumnLayout {
                            id: styleCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text { text: "界面"; color: cText; font.pixelSize: 14; font.bold: true }

                            Text {
                                text: "当前使用新版界面(流动渐变 + 玻璃拟态)。"
                                color: cTextSec
                                font.pixelSize: 12
                            }

                            Rectangle {
                                Layout.preferredWidth: 160
                                Layout.preferredHeight: 34
                                radius: 10
                                color: switchArea.containsMouse ? cAccentHover : cAccent
                                Behavior on color { ColorAnimation { duration: 140 } }
                                scale: switchArea.pressed ? 0.96 : 1.0
                                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                                Text {
                                    anchors.centerIn: parent
                                    text: "返回经典界面"
                                    color: "#ffffff"
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                MouseArea {
                                    id: switchArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: UiStyle.modern = false
                                }
                            }
                        }
                    }

                    // 壁纸卡
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: wpCol.implicitHeight + 32
                        radius: 16
                        color: cGlass
                        border.color: cGlassBorder
                        border.width: 1

                        ColumnLayout {
                            id: wpCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 8

                            Text { text: "壁纸"; color: cText; font.pixelSize: 14; font.bold: true }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.preferredWidth: 88
                                    Layout.preferredHeight: 30
                                    radius: 10
                                    color: wpPickArea.containsMouse ? cAccentSoft : "#00000000"
                                    border.color: cBorder2
                                    border.width: 1
                                    Behavior on color { ColorAnimation { duration: 140 } }

                                    Text { anchors.centerIn: parent; text: "选择图片"; color: cText; font.pixelSize: 12 }
                                    MouseArea {
                                        id: wpPickArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: wallpaperDialog.open()
                                    }
                                }

                                Rectangle {
                                    visible: appSettings.wallpaperFile !== ""
                                    Layout.preferredWidth: 88
                                    Layout.preferredHeight: 30
                                    radius: 10
                                    color: wpClearArea.containsMouse ? "#33ef4444" : "#00000000"
                                    border.color: cBorder2
                                    border.width: 1

                                    Text { anchors.centerIn: parent; text: "恢复默认"; color: wpClearArea.containsMouse ? cError : cText; font.pixelSize: 12 }
                                    MouseArea {
                                        id: wpClearArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: appSettings.clearWallpaper()
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: appSettings.wallpaperFile !== ""
                                          ? "已自选: " + appSettings.wallpaperFile.split("/").pop()
                                          : "未设置壁纸,使用流动渐变背景"
                                    color: cTextMuted
                                    font.pixelSize: 11
                                    elide: Text.ElideMiddle
                                    Layout.maximumWidth: 220
                                }
                            }
                        }
                    }

                    // 关于卡
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: aboutCol.implicitHeight + 32
                        radius: 16
                        color: cGlass
                        border.color: cGlassBorder
                        border.width: 1

                        ColumnLayout {
                            id: aboutCol
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 6

                            Text { text: "关于"; color: cText; font.pixelSize: 14; font.bold: true }
                            Text { text: "QFRP 客户端 v0.1.0"; color: cTextSec; font.pixelSize: 12 }

                            RowLayout {
                                spacing: 8
                                Text { text: "开发者"; color: cTextMuted; font.pixelSize: 12 }
                                Rectangle { width: 3; height: 3; radius: 1.5; color: cTextMuted; Layout.alignment: Qt.AlignVCenter }
                                Text { text: "setsuna"; color: cText; font.pixelSize: 12; font.bold: true }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: "QQ"; color: cTextMuted; font.pixelSize: 12 }
                                Rectangle { width: 3; height: 3; radius: 1.5; color: cTextMuted; Layout.alignment: Qt.AlignVCenter }

                                Text {
                                    id: qqValue
                                    property bool copied: false
                                    text: copied ? "已复制 ✓" : "1537403715"
                                    color: qqArea.containsMouse || copied ? cAccentHover : cAccent
                                    font.pixelSize: 12
                                    font.bold: true

                                    Timer { id: qqReset; interval: 1500; onTriggered: qqValue.copied = false }
                                }

                                MouseArea {
                                    id: qqArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        appSettings.copyText("1537403715")
                                        qqValue.copied = true
                                        qqReset.restart()
                                    }
                                }
                            }

                            RowLayout {
                                spacing: 8
                                Text { text: "GitHub"; color: cTextMuted; font.pixelSize: 12 }
                                Rectangle { width: 3; height: 3; radius: 1.5; color: cTextMuted; Layout.alignment: Qt.AlignVCenter }

                                Text {
                                    text: "setsuna391/QFRP"
                                    color: ghArea.containsMouse ? cAccentHover : cAccent
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

                            Text { text: "基于 Qt6 + QML 开发"; color: cTextMuted; font.pixelSize: 11 }
                        }
                    }
                }
            }
        }
    }

    // 壁纸选择
    FileDialog {
        id: wallpaperDialog
        title: "选择壁纸图片"
        nameFilters: ["图片文件 (*.jpg *.jpeg *.png *.webp *.bmp)"]
        onAccepted: appSettings.pickWallpaper(selectedFile)
    }

    // 删除确认
    Popup {
        id: deletePopup
        width: 360
        height: 180
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#f7f8fc"; radius: 18; border.color: cGlassBorder; border.width: 1 }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.93; to: 1; duration: 200; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 150; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 10

            Text { text: "删除隧道"; color: cText; font.pixelSize: 17; font.bold: true }
            Text {
                Layout.fillWidth: true
                text: "确定要删除「" + root.tunnelName(root.pendingDeleteId) + "」吗? 会同步删除服务器上的隧道,无法撤销。"
                color: cTextSec; font.pixelSize: 13; wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 10
                    color: dCancel.containsMouse ? "#66ffffff" : "#00000000"
                    border.color: cBorder2; border.width: 1
                    Text { anchors.centerIn: parent; text: "取消"; color: cText; font.pixelSize: 13 }
                    MouseArea {
                        id: dCancel; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { root.pendingDeleteId = ""; deletePopup.close() }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 10
                    color: dConfirm.containsMouse ? cAccentHover : cError
                    Text { anchors.centerIn: parent; text: "确认删除"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                    MouseArea {
                        id: dConfirm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
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

    // 新建隧道
    Popup {
        id: createPopup
        width: 380
        height: 420
        anchors.centerIn: parent
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: "#f7f8fc"; radius: 18; border.color: cGlassBorder; border.width: 1 }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 200; easing.type: Easing.OutBack }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; to: 0; duration: 140; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionIn }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 10

            Text { text: "新建隧道"; color: cText; font.pixelSize: 17; font.bold: true }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: "隧道名称"; color: cTextSec; font.pixelSize: 12 }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 10; color: "#ffffff"
                    border.color: createName.activeFocus ? cAccent : cBorder2; border.width: 1
                    TextField {
                        id: createName
                        anchors.fill: parent; anchors.margins: 2
                        placeholderText: "我的隧道"; placeholderTextColor: cTextMuted
                        color: cText; font.pixelSize: 13; background: null
                        verticalAlignment: TextInput.AlignVCenter; leftPadding: 10
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true; spacing: 4
                Text { text: "节点"; color: cTextSec; font.pixelSize: 12 }
                ComboBox {
                    id: createNode
                    Layout.fillWidth: true; Layout.preferredHeight: 38
                    model: root.nodes
                    textRole: "name"
                    valueRole: "id"

                    background: Rectangle {
                        radius: 10; color: "#ffffff"
                        border.color: createNode.popup.visible ? cAccent : cBorder2; border.width: 1
                        Behavior on border.color { ColorAnimation { duration: 140 } }
                    }
                    contentItem: Text {
                        text: createNode.displayText || "请选择节点"
                        color: cText; font.pixelSize: 13
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10; rightPadding: 26
                        elide: Text.ElideRight
                    }
                    indicator: Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right; anchors.rightMargin: 10
                        text: createNode.popup.visible ? "▴" : "▾"
                        color: cTextSec; font.pixelSize: 12
                    }

                    //玻璃风弹窗(默认是深色系统样式,与浅色界面不协调)
                    popup: Popup {
                        y: createNode.height - 1
                        width: createNode.width
                        padding: 6
                        background: Rectangle {
                            color: "#ffffff"; radius: 12
                            border.color: cGlassBorder; border.width: 1
                        }
                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.min(contentHeight, 300)
                            model: createNode.delegateModel
                            currentIndex: createNode.highlightedIndex
                            spacing: 2
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }

                    delegate: ItemDelegate {
                        id: nodeDelegate
                        width: createNode.width - 10
                        height: 42
                        highlighted: createNode.highlightedIndex === index

                        contentItem: RowLayout {
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Text {
                                    text: (modelData && modelData.name) || ("节点 #" + ((modelData && modelData.id) || "?"))
                                    color: cText
                                    font.pixelSize: 12
                                    font.bold: nodeDelegate.hovered || nodeDelegate.highlighted
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Text {
                                    text: (modelData && (modelData.host || modelData.description)) || ""
                                    color: cTextMuted
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                }
                            }

                            Rectangle {
                                readonly property string tier: root.nodeTier(String((modelData && modelData.name) || ""))
                                visible: tier !== ""
                                width: tierLabel.implicitWidth + 10; height: 16; radius: 8
                                color: tier === "VIP" ? "#33fbbf24" : "#33818cf8"
                                border.color: tier === "VIP" ? "#fbbf24" : "#818cf8"
                                border.width: 1

                                Text {
                                    id: tierLabel
                                    anchors.centerIn: parent
                                    text: parent.tier
                                    color: parent.border.color
                                    font.pixelSize: 9
                                    font.bold: true
                                }
                            }
                        }

                        background: Rectangle {
                            radius: 8
                            color: nodeDelegate.highlighted ? cAccentSoft : nodeDelegate.hovered ? "#f4f5fb" : "transparent"
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 4
                    Text { text: "本地端口"; color: cTextSec; font.pixelSize: 12 }
                    Rectangle {
                        Layout.fillWidth: true; Layout.preferredHeight: 38; radius: 10; color: "#ffffff"
                        border.color: createPort.activeFocus ? cAccent : cBorder2; border.width: 1
                        TextField {
                            id: createPort
                            anchors.fill: parent; anchors.margins: 2
                            placeholderText: "8080"; placeholderTextColor: cTextMuted
                            color: cText; font.pixelSize: 13; background: null
                            verticalAlignment: TextInput.AlignVCenter; leftPadding: 10
                        }
                    }
                }
                ColumnLayout {
                    Layout.preferredWidth: 110; spacing: 4
                    Text { text: "协议"; color: cTextSec; font.pixelSize: 12 }
                    ComboBox {
                        id: createType
                        Layout.fillWidth: true; Layout.preferredHeight: 38
                        model: ["tcp", "udp", "http"]
                        background: Rectangle { radius: 10; color: "#ffffff"; border.color: cBorder2; border.width: 1 }
                        contentItem: Text {
                            text: createType.displayText
                            color: cText; font.pixelSize: 13; verticalAlignment: Text.AlignVCenter; leftPadding: 10
                        }
                    }
                }
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: 8

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 12
                    color: cCancel2.containsMouse ? "#66ffffff" : "#00000000"
                    border.color: cBorder2; border.width: 1
                    Text { anchors.centerIn: parent; text: "取消"; color: cText; font.pixelSize: 13 }
                    MouseArea {
                        id: cCancel2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: createPopup.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 40; radius: 12
                    color: cConfirm2.containsMouse ? cAccentHover : cAccent
                    Text { anchors.centerIn: parent; text: "创建隧道"; color: "#ffffff"; font.pixelSize: 13; font.bold: true }
                    MouseArea {
                        id: cConfirm2; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var node = createNode.currentValue
                            if (!createName.text.trim() || node === undefined || !createPort.text.trim())
                                return
                            apiClient.createTunnel({
                                name: createName.text.trim(),
                                node_id: node,
                                protocol: createType.currentText,
                                local_port: createPort.text.trim()
                            })
                            createPopup.close()
                            createName.text = ""
                            createPort.text = ""
                        }
                    }
                }
            }
        }
    }

    // 新版界面内部没有的边框色便捷别名(与玻璃边框区分)
    readonly property color cBorder2: "#dde0ee"
    property string pendingDeleteId: ""

    ListModel { id: logModel }
}
