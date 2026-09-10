pragma Singleton
import QtQuick
import QtCore

//全局主题单例:所有界面颜色集中在这里,按 current 在多套配色间切换。
//QML 里直接用 Theme.cBg / Theme.cAccent ... 引用,切换主题时所有绑定自动刷新。
//选择通过 Settings 持久化到 ~/.config/QML_FRPC/QML_FRPC.conf
//
//加新配色只需往 palettes 数组里加一项(字段与现有项完全一致),
//所有颜色属性会自动跟随,设置页的配色选择器也会自动多出一枚。
QtObject {
    id: root

    //QtObject 没有默认属性,Settings 以属性方式声明
    readonly property Settings themeStore: Settings {
        property int theme: 0
    }

    //当前配色索引(持久化)
    property int current: themeStore.theme
    onCurrentChanged: themeStore.theme = current

    // ===== 调色板 =====
    //每项字段: name + 全部 c* 颜色。新加主题时整块复制一份改色值即可。
    readonly property var palettes: [
        // 樱花粉(默认)
        { name: "樱花粉",
          cBg: "#fff0f5", cSidebar: "#ffdcea", cCard: "#fffafd", cBorder: "#ffc2d9",
          cInputBg: "#fff0f5", cAccent: "#ff5c8a", cAccentHover: "#f04378",
          cText: "#4a2b3a", cTextSec: "#a86b85", cTextMuted: "#b98fa4",
          cSuccess: "#1fae70", cError: "#e63757", cWarning: "#d97706",
          cNavHover: "#ffc9dd", cNavActive: "#ffb3cf", cHoverBg: "#ffe4ee",
          cErrorBg: "#ffe1e8", cScrollbar: "#ff9ec0", cDotOff: "#d4a5b8",
          cCardHoverBorder: "#ff8fb8", cTcpTag: "#f0568f",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#ffeaf3", cGradMid: "#ffe0ed", cGradBottom: "#ffd3e3",
          cPetal: "#ff7fab", cDimOverlay: "#664a2b3a" },
        // 薰衣草紫
        { name: "薰衣草紫",
          cBg: "#f4f0fb", cSidebar: "#e3d8f7", cCard: "#fbf9fe", cBorder: "#cfbceb",
          cInputBg: "#f0eafb", cAccent: "#8b5cf6", cAccentHover: "#7444e0",
          cText: "#33254d", cTextSec: "#7a67a0", cTextMuted: "#a394c4",
          cSuccess: "#1fae70", cError: "#d93757", cWarning: "#d97706",
          cNavHover: "#d7c9f2", cNavActive: "#c5b0f0", cHoverBg: "#ece2f8",
          cErrorBg: "#f9e3ee", cScrollbar: "#bda6ea", cDotOff: "#b7a8d8",
          cCardHoverBorder: "#b79ae8", cTcpTag: "#8b5cf6",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#f0e9fc", cGradMid: "#e6dcf8", cGradBottom: "#d9cdf5",
          cPetal: "#a98ce8", cDimOverlay: "#662b2048" },
        // 薄荷绿
        { name: "薄荷绿",
          cBg: "#eefaf3", cSidebar: "#d2f0e2", cCard: "#f8fdfa", cBorder: "#b2e4cd",
          cInputBg: "#e6f6ee", cAccent: "#16a374", cAccentHover: "#0f8a5f",
          cText: "#1e3d30", cTextSec: "#5c8672", cTextMuted: "#8bb09d",
          cSuccess: "#1fae70", cError: "#e63757", cWarning: "#d97706",
          cNavHover: "#bfe9d6", cNavActive: "#a0dfc3", cHoverBg: "#dcf4e8",
          cErrorBg: "#ffe1e8", cScrollbar: "#7ccfa8", cDotOff: "#a2c4b2",
          cCardHoverBorder: "#4cc294", cTcpTag: "#16a374",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#e4f7ed", cGradMid: "#d6f2e4", cGradBottom: "#c5ebd8",
          cPetal: "#4dbd92", cDimOverlay: "#661e3d30" },
        // 天空蓝
        { name: "天空蓝",
          cBg: "#eef5fc", cSidebar: "#d6e8f8", cCard: "#f8fbfe", cBorder: "#b7d6ee",
          cInputBg: "#e5f0fa", cAccent: "#3e86f0", cAccentHover: "#2a6cd6",
          cText: "#22334d", cTextSec: "#647b99", cTextMuted: "#8fa4bf",
          cSuccess: "#1fae70", cError: "#e63757", cWarning: "#d97706",
          cNavHover: "#c3dcf4", cNavActive: "#a7cdf0", cHoverBg: "#dfeefa",
          cErrorBg: "#ffe1e8", cScrollbar: "#89b7e6", cDotOff: "#a2b5cb",
          cCardHoverBorder: "#67a5e8", cTcpTag: "#3e86f0",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#e6f1fc", cGradMid: "#daebfb", cGradBottom: "#cae2f9",
          cPetal: "#649fe8", cDimOverlay: "#6622334d" },
        // 蜜橘橙
        { name: "蜜橘橙",
          cBg: "#fff6eb", cSidebar: "#ffe6c9", cCard: "#fffcf6", cBorder: "#f2cf9f",
          cInputBg: "#fff1de", cAccent: "#ee8c2b", cAccentHover: "#d97a1a",
          cText: "#46311c", cTextSec: "#9d7c54", cTextMuted: "#c2a888",
          cSuccess: "#1fae70", cError: "#e63757", cWarning: "#d97706",
          cNavHover: "#fbdfb4", cNavActive: "#f8cf92", cHoverBg: "#fdeed6",
          cErrorBg: "#ffe1e8", cScrollbar: "#eeb269", cDotOff: "#d1bc9c",
          cCardHoverBorder: "#e8a03f", cTcpTag: "#ee8c2b",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#fff0da", cGradMid: "#ffe7c9", cGradBottom: "#ffdcb4",
          cPetal: "#f2a04a", cDimOverlay: "#66463118" },
        // 雾灰蓝
        { name: "雾灰蓝",
          cBg: "#f2f4f8", cSidebar: "#dde3ec", cCard: "#fafbfd", cBorder: "#c3ccd9",
          cInputBg: "#e9edf3", cAccent: "#64748b", cAccentHover: "#4b5c73",
          cText: "#26303f", cTextSec: "#6b7a90", cTextMuted: "#95a2b5",
          cSuccess: "#1fae70", cError: "#e63757", cWarning: "#d97706",
          cNavHover: "#cbd5e3", cNavActive: "#b3c2d6", cHoverBg: "#e5eaf1",
          cErrorBg: "#ffe1e8", cScrollbar: "#9fb0c6", cDotOff: "#adb9c9",
          cCardHoverBorder: "#8296ad", cTcpTag: "#64748b",
          cSuccessBg: "#eafaf3", cSuccessBgHover: "#d5f4e7",
          cGradTop: "#eceff5", cGradMid: "#e2e8f0", cGradBottom: "#d5dce7",
          cPetal: "#8296ad", cDimOverlay: "#6626303f" },
        // 夜来香(深色)
        { name: "夜来香",
          cBg: "#16131d", cSidebar: "#100e16", cCard: "#1e1a27", cBorder: "#2a2438",
          cInputBg: "#241f31", cAccent: "#ff7fab", cAccentHover: "#ff97bd",
          cText: "#f0eaf4", cTextSec: "#a798c2", cTextMuted: "#6e6488",
          cSuccess: "#34d399", cError: "#f87171", cWarning: "#fbbf24",
          cNavHover: "#282234", cNavActive: "#3a2f4d", cHoverBg: "#282234",
          cErrorBg: "#43222e", cScrollbar: "#4a4160", cDotOff: "#544a6b",
          cCardHoverBorder: "#ff7fab", cTcpTag: "#ff7fab",
          cSuccessBg: "#12332a", cSuccessBgHover: "#1a4a3b",
          cGradTop: "#1c1725", cGradMid: "#151221", cGradBottom: "#100d19",
          cPetal: "#a86b95", cDimOverlay: "#aa0a0812" }
    ]

    //当前调色板(索引越界时回落到默认,防止旧配置越界闪退)
    readonly property var p: palettes[Math.min(Math.max(current, 0), palettes.length - 1)]
    readonly property string themeName: p.name
    readonly property int themeCount: palettes.length

    // ===== 颜色(跟随当前调色板,全应用只引用这些名字) =====
    readonly property color cBg:          p.cBg
    readonly property color cSidebar:     p.cSidebar
    readonly property color cCard:        p.cCard
    readonly property color cBorder:      p.cBorder
    readonly property color cInputBg:     p.cInputBg
    readonly property color cAccent:      p.cAccent
    readonly property color cAccentHover: p.cAccentHover
    readonly property color cText:        p.cText
    readonly property color cTextSec:     p.cTextSec
    readonly property color cTextMuted:   p.cTextMuted
    readonly property color cSuccess:     p.cSuccess
    readonly property color cSuccessBg:      p.cSuccessBg
    readonly property color cSuccessBgHover: p.cSuccessBgHover
    readonly property color cError:       p.cError
    readonly property color cWarning:     p.cWarning

    //导航/交互态
    readonly property color cNavHover:        p.cNavHover
    readonly property color cNavActive:       p.cNavActive
    readonly property color cHoverBg:         p.cHoverBg
    readonly property color cErrorBg:         p.cErrorBg
    readonly property color cScrollbar:       p.cScrollbar
    readonly property color cDotOff:          p.cDotOff
    readonly property color cCardHoverBorder: p.cCardHoverBorder
    readonly property color cTcpTag:          p.cTcpTag

    //登录页
    readonly property color cGradTop:     p.cGradTop
    readonly property color cGradMid:     p.cGradMid
    readonly property color cGradBottom:  p.cGradBottom
    readonly property color cPetal:       p.cPetal

    //模态遮罩
    readonly property color cDimOverlay:  p.cDimOverlay

    // ===== 动效 =====
    //全局统一的贝塞尔缓动曲线,配合 easing.type: Easing.Bezier 使用。
    //motionOut:出现/展开类——快速启动、丝滑减速收尾,等效 cubic-bezier(0.22, 1, 0.36, 1)
    //motionIn: 消失/收起类——缓慢启动、加速离场,等效 cubic-bezier(0.64, 0, 0.78, 0)
    //想全局调整动画手感,改这里的控制点即可。
    readonly property list<real> motionOut: [0.22, 1, 0.36, 1, 1, 1]
    readonly property list<real> motionIn: [0.64, 0, 0.78, 0, 1, 1]
}
