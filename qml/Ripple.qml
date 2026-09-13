import QtQuick

//按钮涟漪:点击时从中心扩散的圆形水波(Material 风格)
//用法: 在按钮里放一个 Ripple { anchors.fill: parent },点击事件里调 play()
//透明度在扩散中衰减到 0,越出圆角的部分几乎不可见,宿主无需裁剪
Rectangle {
    id: ripple

    property color rippleColor: "#1f7a7a85"
    property real maxScale: 1.3

    anchors.fill: parent
    radius: width / 2
    color: rippleColor
    opacity: 0
    visible: false
    scale: 0.3

    function play() {
        rippleAnim.restart()
    }

    SequentialAnimation {
        id: rippleAnim
        PropertyAction { target: ripple; property: "visible"; value: true }
        ParallelAnimation {
            NumberAnimation { target: ripple; property: "opacity"; from: 0.7; to: 0; duration: 400; easing.type: Easing.OutQuad }
            NumberAnimation { target: ripple; property: "scale"; from: 0.3; to: ripple.maxScale; duration: 400; easing.type: Easing.OutQuad }
        }
        PropertyAction { target: ripple; property: "visible"; value: false }
    }
}
