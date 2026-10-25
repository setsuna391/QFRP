import QtQuick
import QtQuick.Controls

//根窗口:根据登录状态在登录页和主界面之间切换
ApplicationWindow {
    id: window
    visible: true
    width: 1080
    height: 720
    //固定窗口大小(最大=最小):窗口不可被拉伸,
    //niri 这类平铺合成器会自动把不可调整大小的窗口设为浮动,布局也不会被挤变形
    minimumWidth: 1080
    minimumHeight: 720
    maximumWidth: 1080
    maximumHeight: 720
    title: "QFRP"
    color: Theme.cBg
    //无边框窗口:窗口控制按钮(最小化/退出)由界面顶栏提供,顶栏可拖动移动窗口
    flags: Qt.Window | Qt.FramelessWindowHint

    //退出时的状态保存在 C++ 侧完成(main.cpp 监听 aboutToQuit 并写入 frpc 状态文件)

    //模态弹窗的遮罩:半透明主题色,带淡入淡出
    Overlay.modal: Rectangle {
        color: Theme.cDimOverlay
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    StackView {
        id: stackView
        anchors.fill: parent
        //初始视图在 onCompleted 里显式装入。
        //不能用 initialItem 绑定:它是响应式的,之后每次登录状态/界面风格变化
        //都会重新求值并把视图压入栈,新旧界面就会叠在一起(重影的根源)。
        //不做整体淡入:磨砂壁纸首帧即就绪,从黑屏淡入反而像"开窗黑一下"
        Component.onCompleted: stackView.replace(currentViewComponent())
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

        //登录页/主界面切换:淡入淡出 + 轻微缩放
        //注意:这里用 PropertyAnimation(走 GUI 线程的动画驱动)而非 OpacityAnimator/ScaleAnimator。
        //Animator 系在部分平台/合成器(如 niri + NVIDIA 的 basic render loop)下不会推进,
        //会让新页面停在 opacity 0 / scale 0.98,表现为窗口一片空白。
        replaceEnter: Transition {
            PropertyAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            PropertyAnimation { property: "scale"; from: 0.96; to: 1; duration: 420; easing.type: Easing.OutBack }
        }
        replaceExit: Transition {
            PropertyAnimation { property: "opacity"; from: 1; to: 0; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
        }
    }

    Component {
        id: loginViewComponent
        LoginView {}
    }

    Component {
        id: mainViewComponent
        MainView {}
    }

    function currentViewComponent() {
        return apiClient.ready ? mainViewComponent : loginViewComponent
    }

    //登录状态变化时切换视图
    Connections {
        target: apiClient
        function onReadyChanged() {
            stackView.replace(currentViewComponent())
        }
    }
}
