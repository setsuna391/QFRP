import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

//新版登录页:GLSL 流动渐变背景 + 玻璃拟态卡片(毛玻璃阴影) + 衬线标题
Item {
    id: root

    readonly property var appWindow: Window.window
    property bool loading: false

    function tryLogin() {
        if (loading)
            return
        var t = tokenInput.text.trim()
        if (t === "") {
            hintText.text = "请先输入 Token"
            hintText.visible = true
            return
        }
        loading = true
        hintText.visible = false
        apiClient.login(t)
    }

    Connections {
        target: apiClient
        function onLoginSuccess() { root.loading = false }
        function onLoginFailed(error) {
            root.loading = false
            hintText.text = error || "登录失败,请检查 Token"
            hintText.visible = true
        }
    }

    //流动渐变背景
    ModernBackground {}

    //顶部拖动 + 窗口控制
    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 44
        onPressed: root.appWindow.startSystemMove()
    }

    WindowControls {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        win: root.appWindow
        onMinimizeClicked: root.appWindow.showMinimized()
        onCloseClicked: root.appWindow.close()
    }

    //玻璃拟态登录卡片
    Rectangle {
        id: card
        width: 400
        height: 400
        anchors.centerIn: parent
        color: "#e6ffffff"
        radius: 24
        border.color: "#40ffffff"
        border.width: 1

        //入场:上浮 + 淡入
        opacity: 0
        scale: 0.96
        Component.onCompleted: entrance.restart()
        ParallelAnimation {
            id: entrance
            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: 420; easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "scale"; from: 0.95; to: 1; duration: 420; easing.type: Easing.OutCubic }
        }

        //柔和高斯阴影(GPU)
        MultiEffect {
            source: card
            anchors.fill: card
            shadowEnabled: true
            shadowColor: "#4b4f46e5"
            shadowBlur: 0.9
            shadowVerticalOffset: 14
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 36
            spacing: 0

            //标题(衬线体,呼应网站 font-serif)
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: "QFRP"
                color: "#4f46e5"
                font.family: "Noto Serif CJK SC"
                font.pixelSize: 30
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 6
                text: "SakuraFrp 隧道管理"
                color: "#8891a8"
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 28
                spacing: 6

                Text { text: "访问 Token"; color: "#5b6478"; font.pixelSize: 12 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 12
                    color: "#f4f5fb"
                    border.color: tokenInput.activeFocus ? "#4f46e5" : "#dde0ee"
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextField {
                        id: tokenInput
                        anchors.fill: parent
                        anchors.margins: 2
                        placeholderText: "粘贴你的 SakuraFrp Token"
                        placeholderTextColor: "#aab0c2"
                        color: "#2a2f45"
                        font.pixelSize: 13
                        background: null
                        verticalAlignment: TextInput.AlignVCenter
                        leftPadding: 12
                        selectByMouse: true
                        onAccepted: root.tryLogin()
                    }
                }

                Text {
                    id: hintText
                    visible: false
                    color: "#e0556e"
                    font.pixelSize: 12
                }
            }

            Rectangle {
                id: loginBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 18
                radius: 14
                color: area.containsMouse ? "#5b52ea" : "#4f46e5"
                Behavior on color { ColorAnimation { duration: 150 } }
                scale: area.pressed ? 0.97 : 1.0
                Behavior on scale { SpringAnimation { spring: 4; damping: 0.3; epsilon: 0.006 } }

                Text {
                    anchors.centerIn: parent
                    text: root.loading ? "登录中…" : "登 录"
                    color: "#ffffff"
                    font.pixelSize: 14
                    font.bold: true
                }

                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.tryLogin()
                }
            }

            Item { Layout.fillHeight: true }

            Text {
                Layout.fillWidth: true
                text: "Token 仅保存在本机 · SakuraFrp"
                color: "#aab0c2"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }

    }
}
