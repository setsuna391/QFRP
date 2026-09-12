import QtQuick

//新版界面背景:GLSL 着色器实现的四色粉彩流动渐变
//整块 quad 全 GPU 渲染,唯一的常驻动画,CPU 开销接近零
ShaderEffect {
    id: root

    //着色器里 uTime 会自动绑定到这个属性
    property real uTime: 0

    //时间驱动(线性循环,数值保持有限避免精度问题)
    NumberAnimation on uTime {
        from: 0
        to: 864000
        duration: 864000000
        loops: Animation.Infinite
    }

    vertexShader: "qrc:/qml/modern/shaders/flow.vert.qsb"
    fragmentShader: "qrc:/qml/modern/shaders/flow.frag.qsb"
}
