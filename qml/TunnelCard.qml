import QtQuick
import QtQuick.Layouts

//单个隧道卡片,展示隧道信息 + 启动/停止按钮 + 删除按钮
//属性: tunnelData (JS对象,包含 id/name/node/type/local_ip/local_port/remote)
//信号: deleteRequested(tunnelId) — 用户点击删除时发出
Rectangle {
    id: card

    property var tunnelData: ({})
    property bool isRunning: false

    signal deleteRequested(string tunnelId)
    //启动/停止点击时发出,由外部持有运行状态
    //(卡片会随列表刷新重建,状态放内部会在刷新时丢失)
    signal toggleRequested(string tunnelId)

    readonly property color cBg: Theme.cCard
    readonly property color cBorder: Theme.cBorder
    readonly property color cAccent: Theme.cAccent
    readonly property color cText: Theme.cText
    readonly property color cTextSec: Theme.cTextSec
    readonly property color cSuccess: Theme.cSuccess
    readonly property color cError: Theme.cError

    //从 tunnelData 安全取值
    function field(name, fallback) {
        var v = tunnelData[name]
        return v !== undefined && v !== null ? v : fallback
    }

    color: cBg
    radius: 10
    //卡片固有高度:ListView 依赖它给每个卡片正确布局,否则所有卡片会叠在一起
    implicitHeight: 68
    border.color: hoverArea.containsMouse ? Theme.cCardHoverBorder : cBorder
    border.width: 1

    //hover 时边框高亮。不做整体缩放:卡片较宽,缩放会让右侧按钮横移数像素,
    //鼠标移入的瞬间按钮位置漂移,容易造成点击落空
    Behavior on border.color { ColorAnimation { duration: 120 } }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        propagateComposedEvents: true
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 12
        spacing: 14

        //状态圆点
        Rectangle {
            Layout.preferredWidth: 10
            Layout.preferredHeight: 10
            Layout.alignment: Qt.AlignVCenter
            radius: 5
            color: isRunning ? cSuccess : Theme.cDotOff
            Behavior on color { ColorAnimation { duration: 200 } }

            //运行时向外扩散的呼吸光圈
            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: 5
                color: "transparent"
                border.color: cSuccess
                border.width: 1
                visible: isRunning

                NumberAnimation on scale {
                    running: isRunning
                    loops: Animation.Infinite
                    from: 1
                    to: 2.4
                    duration: 1200
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.motionOut
                }
                NumberAnimation on opacity {
                    running: isRunning
                    loops: Animation.Infinite
                    from: 0.7
                    to: 0
                    duration: 1200
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Theme.motionOut
                }
            }
        }

        //中间信息区
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4

            RowLayout {
                spacing: 8

                //隧道名
                Text {
                    text: field("name", "未命名隧道")
                    color: cText
                    font.pixelSize: 15
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                //协议标签
                Rectangle {
                    Layout.preferredHeight: 20
                    radius: 4
                    color: "#00000000"
                    border.color: {
                        var t = field("type", "tcp").toString().toLowerCase()
                        if (t === "udp") return "#3b82f6"
                        if (t === "http") return "#d97706"
                        if (t === "https") return "#1fae70"
                        return Theme.cTcpTag
                    }
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        anchors.margins: 6
                        text: field("type", "tcp").toString().toUpperCase()
                        color: parent.border.color
                        font.pixelSize: 10
                        font.bold: true
                        leftPadding: 4
                        rightPadding: 4
                    }
                }
            }

            //第二行: 节点 · 本地地址 → 远程端口 · ID
            Text {
                Layout.fillWidth: true
                text: {
                    var nodeId = field("node", "?")
                    var localIp = field("local_ip", "127.0.0.1")
                    var localPort = field("local_port", "?")
                    var remotePort = field("remote", "?")
                    var tid = field("id", "?")
                    return "节点 #" + nodeId + "  ·  " + localIp + ":" + localPort + " → :" + remotePort + "  ·  ID:" + tid
                }
                color: cTextSec
                font.pixelSize: 12
                elide: Text.ElideRight
            }
        }

        //启动/停止按钮
        Rectangle {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: runBtnArea.containsMouse
                ? (isRunning ? Theme.cErrorBg : Theme.cSuccessBgHover)
                : (isRunning ? Theme.cInputBg : Theme.cSuccessBg)
            border.color: isRunning ? cError : cSuccess
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: runBtnArea.pressed ? 0.94 : (runBtnArea.containsMouse ? 1.04 : 1.0)
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

            RowLayout {
                anchors.centerIn: parent
                spacing: 6

                AppIcon {
                    iconType: isRunning ? "stop" : "play"
                    iconColor: isRunning ? cError : cSuccess
                    width: 14
                    height: 14
                }

                Text {
                    text: isRunning ? "停止" : "启动"
                    color: isRunning ? cError : cSuccess
                    font.pixelSize: 13
                    font.bold: true
                }
            }

            MouseArea {
                id: runBtnArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: card.toggleRequested(card.field("id", "").toString())
            }
        }

        //删除按钮
        Rectangle {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            Layout.alignment: Qt.AlignVCenter
            radius: 8
            color: delArea.containsMouse ? Theme.cErrorBg : "#00000000"
            border.color: delArea.containsMouse ? cError : "#00000000"
            border.width: 1
            Behavior on color { ColorAnimation { duration: 120 } }
            scale: delArea.pressed ? 0.9 : (delArea.containsMouse ? 1.06 : 1.0)
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

            AppIcon {
                anchors.centerIn: parent
                iconType: "delete"
                iconColor: delArea.containsMouse ? cError : cTextSec
                width: 16
                height: 16
            }

            MouseArea {
                id: delArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true
                onClicked: card.deleteRequested(field("id", "").toString())
            }
        }
    }
}
