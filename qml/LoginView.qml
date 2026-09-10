import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

    //登录页面:主题渐变背景 + 飘落花瓣 + 居中登录卡片
Item {
    id: root

    //所在窗口(无边框窗口的控制按钮/拖动用)
    readonly property var appWindow: Window.window

    //渐变背景
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.cGradTop }
            GradientStop { position: 0.5; color: Theme.cGradMid }
            GradientStop { position: 1.0; color: Theme.cGradBottom }
        }
    }

    //顶部拖动区(无边框窗口移动) + 窗口控制按钮
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

    //装饰性樱花花瓣:从顶部飘落,边落边左右摇摆、自身旋转
    Repeater {
        model: 14
        delegate: Item {
            id: petal

            property real startX: Math.random() * root.width
            property real swayRange: 12 + Math.random() * 18
            property real fallDuration: 7000 + Math.random() * 6000
            property real spinDuration: 2000 + Math.random() * 2500
            property real sz: 6 + Math.random() * 8

            x: startX
            y: -24
            width: sz
            height: sz * 1.5

            //花瓣本体:胶囊形,旋转起来有花瓣感
            Rectangle {
                anchors.fill: parent
                radius: parent.sz / 2
                color: Theme.cPetal
                opacity: 0.4 + Math.random() * 0.3
            }

            //从顶部落到底部,循环
            NumberAnimation on y {
                loops: Animation.Infinite
                from: -24
                to: root.height + 24
                duration: petal.fallDuration
                easing.type: Easing.InQuad
            }

            //左右摇摆
            SequentialAnimation on x {
                loops: Animation.Infinite
                NumberAnimation {
                    from: petal.startX - petal.swayRange
                    to: petal.startX + petal.swayRange
                    duration: petal.fallDuration / 3
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    from: petal.startX + petal.swayRange
                    to: petal.startX - petal.swayRange
                    duration: petal.fallDuration / 3
                    easing.type: Easing.InOutSine
                }
            }

            //自转
            NumberAnimation on rotation {
                loops: Animation.Infinite
                from: 0
                to: 360
                duration: petal.spinDuration
            }
        }
    }

    //登录卡片
    Rectangle {
        id: card
        width: 380
        height: 440
        anchors.centerIn: parent
        color: Theme.cCard
        radius: 20
        border.color: Theme.cBorder
        border.width: 1

        //入场动画:从略小、透明轻轻弹出
        scale: 0.9
        opacity: 0
        Component.onCompleted: {
            scaleAnim.start()
            fadeAnim.start()
        }
        NumberAnimation on scale {
            id: scaleAnim
            from: 0.9
            to: 1.0
            duration: 450
            easing.type: Easing.OutBack
        }
        NumberAnimation on opacity {
            id: fadeAnim
            from: 0
            to: 1
            duration: 300
            easing.type: Easing.Bezier
            easing.bezierCurve: Theme.motionOut
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 36
            spacing: 0

            //标题
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 24
                text: "QFRP"
                color: Theme.cText
                font.pixelSize: 26
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
            }

            //副标题
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 4
                text: "请输入 Token 以登录"
                color: Theme.cTextSec
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
            }

            //间距
            Item {
                Layout.fillHeight: true
                Layout.preferredHeight: 20
            }

            //Token 输入框
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                radius: 10
                color: Theme.cInputBg
                border.color: tokenInput.activeFocus ? Theme.cAccent : Theme.cBorder
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 150 } }

                TextField {
                    id: tokenInput
                    anchors.fill: parent
                    anchors.margins: 2
                    placeholderText: "Token"
                    placeholderTextColor: Theme.cTextMuted
                    color: Theme.cText
                    font.pixelSize: 14
                    selectByMouse: true
                    verticalAlignment: TextInput.AlignVCenter
                    leftPadding: 12
                    passwordCharacter: "*"
                    echoMode: TextInput.Password
                    background: null

                    Keys.onReturnPressed: loginBtn.mouseClicked()
                    onTextChanged: errorText.visible = false
                }
            }

            //错误提示
            Text {
                id: errorText
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.preferredHeight: 16
                color: Theme.cError
                font.pixelSize: 12
                visible: false
                wrapMode: Text.WordWrap
            }

            //登录按钮
            Rectangle {
                id: loginBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 12
                radius: 10
                color: loginArea.containsMouse ? Theme.cAccentHover : Theme.cAccent
                Behavior on color { ColorAnimation { duration: 150 } }

                //按下时轻微缩小,松开弹回
                scale: loginArea.pressed ? 0.96 : (loginArea.containsMouse ? 1.03 : 1.0)
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

                property bool loading: false

                function mouseClicked() {
                    if (loading)
                        return
                    var t = tokenInput.text.trim()
                    if (t === "") {
                        errorText.text = "Token 不能为空"
                        errorText.visible = true
                        return
                    }
                    loading = true
                    errorText.visible = false
                    apiClient.login(t)
                }

                Text {
                    anchors.centerIn: parent
                    text: "登录"
                    color: "#ffffff"
                    font.pixelSize: 15
                    font.bold: true
                    visible: !loginBtn.loading
                }

                //自定义旋转小加载圈(配色比默认 BusyIndicator 更搭)
                Item {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    visible: loginBtn.loading

                    RotationAnimation on rotation {
                        running: loginBtn.loading
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 11
                        color: "transparent"
                        border.color: Theme.cBorder
                        border.width: 2
                    }

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: "#ffffff"
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.topMargin: -2
                    }
                }

                MouseArea {
                    id: loginArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: loginBtn.mouseClicked()
                }

                Connections {
                    target: apiClient
                    function onLoginSuccess() { loginBtn.loading = false }
                    function onLoginFailed(error) {
                        loginBtn.loading = false
                        errorText.text = error
                        errorText.visible = true
                    }
                }
            }

            //底部链接
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 4
                text: "没有账号？前往 SakuraFrp 获取 Token →"
                color: Theme.cTextMuted
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onEntered: parent.color = Theme.cAccentHover
                    onExited: parent.color = Theme.cTextMuted
                    onClicked: Qt.openUrlExternally("https://www.natfrp.com/")
                }
            }
        }
    }
}
