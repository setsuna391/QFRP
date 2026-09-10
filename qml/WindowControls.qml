import QtQuick

//窗口控制按钮组:最小化 + 关闭(应用是无边框窗口,niri 不提供标题栏按钮)
//win 传入所在窗口(通常用 Window.window 附加属性获取)
Row {
    id: root

    property var win: null
    spacing: 2

    signal minimizeClicked()
    signal closeClicked()

    component WBtn: Rectangle {
        id: btn
        property string iconType: "minimize"
        property bool danger: false

        width: 34
        height: 26
        radius: 6
        color: btnArea.containsMouse ? (danger ? Theme.cErrorBg : Theme.cHoverBg) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }

        AppIcon {
            anchors.centerIn: parent
            iconType: btn.iconType
            width: 14
            height: 14
            iconColor: btnArea.containsMouse ? (btn.danger ? Theme.cError : Theme.cText) : Theme.cTextSec
        }

        MouseArea {
            id: btnArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (!root.win)
                    return
                if (btn.danger)
                    root.closeClicked()
                else
                    root.minimizeClicked()
            }
        }
    }

    WBtn {
        iconType: "minimize"
    }
    WBtn {
        iconType: "close"
        danger: true
    }
}
