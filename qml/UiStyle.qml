pragma Singleton
import QtCore
import QtQuick

//界面风格状态:modern(新版仿网站风) / classic(经典版),QSettings 持久化。
//切换单例的 modern 属性,Main.qml 会自动替换整个视图栈。
QtObject {
    id: root

    readonly property Settings store: Settings {
        property string style: "modern"
    }

    property bool modern: store.style !== "classic"
    onModernChanged: store.style = modern ? "modern" : "classic"
}
