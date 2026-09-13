import QtQuick

//液态玻璃面板:对流动渐变背景做磨砂模糊 + 圆角 + 边缘液态高光 + 轻微折射
//用法: GlassPanel { anchors.fill: parent; bgItem: modernBg; radiusPx: 18 }
//bgItem 传背景 ShaderEffect 的 id;几何变化时映射自动重算
ShaderEffect {
    id: root

    property var bgItem
    property real radiusPx: 18
    property real blurPx: 14
    property real glow: 0.55

    readonly property real bgW: bgItem ? bgItem.width : 1
    readonly property real bgH: bgItem ? bgItem.height : 1

    property real uTime: bgItem ? bgItem.uTime : 0

    //面板区域映射到背景 uv(引用宽高属性,窗口缩放时绑定自动重算)
    readonly property real uOffX: bgItem ? mapToItem(bgItem, 0, 0).x / bgW : 0
    readonly property real uOffY: bgItem ? mapToItem(bgItem, 0, 0).y / bgH : 0
    readonly property real uScaleX: bgW ? width / bgW : 1
    readonly property real uScaleY: bgH ? height / bgH : 1
    readonly property real uAspect: bgH ? bgW / bgH : 1.78
    readonly property real uRadius: height ? radiusPx / height : 0.05
    readonly property real uBlur: bgH ? blurPx / bgH : 0.02
    property real uGlow: 0.55

    vertexShader: "qrc:/qml/modern/shaders/flow.vert.qsb"
    fragmentShader: "qrc:/qml/modern/shaders/frost.frag.qsb"
}
