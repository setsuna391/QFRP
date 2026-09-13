import QtQuick

//新版界面背景:GLSL 流动渐变(上层) + 无着色器平台的渐变回退(下层)
//ShaderTools 缺席的平台(如 Windows CI)编不出 .qsb,着色器渲染为空,
//下层的普通渐变自动兜底,背景不会空白
Item {
    id: root

    //回退层:普通四色渐变(与着色器同款配色)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: "#a18cd1" }
            GradientStop { position: 0.4; color: "#fbc2eb" }
            GradientStop { position: 0.7; color: "#a1c4fd" }
            GradientStop { position: 1.0; color: "#c2e9fb" }
        }
    }

    //液态玻璃着色器背景
    ShaderEffect {
        anchors.fill: parent

        //着色器里 uTime 会自动绑定到这个属性
        property real uTime: 0

        NumberAnimation on uTime {
            from: 0
            to: 864000
            duration: 864000000
            loops: Animation.Infinite
        }

        vertexShader: "qrc:/qml/modern/shaders/flow.vert.qsb"
        fragmentShader: "qrc:/qml/modern/shaders/flow.frag.qsb"
    }
}
