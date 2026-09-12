import QtQuick
import QtQuick.Controls

//根窗口:根据登录状态在登录页和主界面之间切换
ApplicationWindow {
    id: window
    visible: true
    width: 1000
    height: 680
    //固定窗口大小(最大=最小):窗口不可被拉伸,
    //niri 这类平铺合成器会自动把不可调整大小的窗口设为浮动,布局也不会被挤变形
    minimumWidth: 1000
    minimumHeight: 680
    maximumWidth: 1000
    maximumHeight: 680
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
        initialItem: apiClient.ready ? (UiStyle.modern ? modernMainComponent : mainViewComponent) : (UiStyle.modern ? modernLoginComponent : loginViewComponent)
        //启动时整体淡入,窗口内容不会突兀地直接出现
        opacity: 0.0
        Component.onCompleted: stackView.opacity = 1.0
        Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut } }

        //登录页/主界面切换:淡入淡出 + 轻微缩放
        replaceEnter: Transition {
            OpacityAnimator { from: 0; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
            ScaleAnimator { from: 0.98; to: 1; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
        }
        replaceExit: Transition {
            OpacityAnimator { from: 1; to: 0; duration: 300; easing.type: Easing.Bezier; easing.bezierCurve: Theme.motionOut }
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

    Component {
        id: modernLoginComponent
        ModernLoginView {}
    }

    Component {
        id: modernMainComponent
        ModernMainView {}
    }

    function currentViewComponent() {
        if (!apiClient.ready)
            return UiStyle.modern ? modernLoginComponent : loginViewComponent
        return UiStyle.modern ? modernMainComponent : mainViewComponent
    }

    //登录状态变化时切换视图
    Connections {
        target: apiClient
        function onReadyChanged() {
            stackView.replace(currentViewComponent())
        }
    }

    //界面风格切换(新版/经典)
    Connections {
        target: UiStyle
        function onModernChanged() {
            stackView.replace(currentViewComponent())
        }
    }
}
