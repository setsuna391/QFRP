import QtQuick

//可复用的 Canvas 线条图标,通过 iconType 选择形状,iconColor 控制颜色
//支持的图标: tunnel(隧道) / node(节点) / log(日志) / settings(设置) / user(用户) / logout(注销) / plus(加号) / refresh(刷新) / delete(删除) / close(关闭) / play(启动) / stop(停止)
//
//所有图形都按 20x20 的"设计坐标"绘制,onPaint 里会统一缩放到实际尺寸。
//
//注意:画布必须用逻辑尺寸!之前这里用 canvasSize = 尺寸 × devicePixelRatio 想做物理像素级清晰,
//但 Qt 在分数/整数缩放下把画布缓冲映射回图元时坐标会错位,实测 1.25x/1.5x/2x 下
//笔画都会缺失、错位(加号变 T、刷新图标断弧)。逻辑尺寸画布在所有缩放下结构都正确,
//高 DPI 上会有一点点发软,对 14~18px 的线条图标来说看不出来。
Canvas {
    id: root

    property string iconType: "tunnel"
    property color iconColor: "#a86b85"

    //设计坐标系的大小,下面所有 case 里的坐标都不超过它
    readonly property real designSize: 20

    width: 20
    height: 20

    onIconTypeChanged: requestPaint()
    onIconColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Component.onCompleted: requestPaint()

    onPaint: {
        var ctx = getContext("2d")
        ctx.reset()

        //把 20x20 的设计坐标整体缩放到实际画布,
        //先 scale 再画,任何尺寸下都能显示完整图形,线宽也按比例缩放
        var s = Math.min(width, height) / designSize
        ctx.scale(s, s)

        ctx.strokeStyle = iconColor
        ctx.fillStyle = iconColor
        ctx.lineWidth = 1.5
        ctx.lineCap = "round"
        ctx.lineJoin = "round"

        switch (iconType) {
        case "tunnel":
            //I 型钢截面,代表隧道/管道
            ctx.beginPath()
            ctx.moveTo(4, 6)
            ctx.lineTo(16, 6)
            ctx.moveTo(4, 14)
            ctx.lineTo(16, 14)
            ctx.moveTo(6, 6)
            ctx.lineTo(6, 14)
            ctx.moveTo(14, 6)
            ctx.lineTo(14, 14)
            ctx.stroke()
            break

        case "node":
            //三个相连的节点
            ctx.beginPath()
            ctx.arc(6, 7, 2.5, 0, 2 * Math.PI)
            ctx.arc(14, 7, 2.5, 0, 2 * Math.PI)
            ctx.arc(10, 15, 2.5, 0, 2 * Math.PI)
            ctx.fill()
            ctx.beginPath()
            ctx.moveTo(6, 7)
            ctx.lineTo(14, 7)
            ctx.moveTo(6, 7)
            ctx.lineTo(10, 15)
            ctx.moveTo(14, 7)
            ctx.lineTo(10, 15)
            ctx.stroke()
            break

        case "log":
            //三条横线,代表文本/日志
            ctx.beginPath()
            ctx.moveTo(4, 7)
            ctx.lineTo(16, 7)
            ctx.moveTo(4, 11)
            ctx.lineTo(13, 11)
            ctx.moveTo(4, 15)
            ctx.lineTo(15, 15)
            ctx.stroke()
            break

        case "settings":
            //简化的齿轮
            ctx.beginPath()
            ctx.arc(10, 10, 6, 0, 2 * Math.PI)
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(10, 10, 3, 0, 2 * Math.PI)
            ctx.stroke()
            for (var i = 0; i < 8; i++) {
                var a = i * Math.PI / 4
                ctx.beginPath()
                ctx.moveTo(10 + Math.cos(a) * 6, 10 + Math.sin(a) * 6)
                ctx.lineTo(10 + Math.cos(a) * 8, 10 + Math.sin(a) * 8)
                ctx.stroke()
            }
            break

        case "user":
            //人形图标
            ctx.beginPath()
            ctx.arc(10, 7, 3, 0, 2 * Math.PI)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(4, 17)
            ctx.quadraticCurveTo(4, 11, 10, 11)
            ctx.quadraticCurveTo(16, 11, 16, 17)
            ctx.stroke()
            break

        case "logout":
            //向右箭头 + 右侧竖线
            ctx.beginPath()
            ctx.moveTo(4, 10)
            ctx.lineTo(13, 10)
            ctx.moveTo(10, 6)
            ctx.lineTo(13, 10)
            ctx.lineTo(10, 14)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(16, 5)
            ctx.lineTo(16, 15)
            ctx.stroke()
            break

        case "plus":
            //加号
            ctx.beginPath()
            ctx.moveTo(10, 4)
            ctx.lineTo(10, 16)
            ctx.moveTo(4, 10)
            ctx.lineTo(16, 10)
            ctx.stroke()
            break

        case "refresh":
            //圆形箭头:约 300° 的圆弧,缺口留在顶部
            var r = 6.5
            var endAngle = Math.PI * 4 / 3
            ctx.beginPath()
            ctx.arc(10, 10, r, -Math.PI / 3, endAngle)
            ctx.stroke()

            //箭头画在圆弧终点,是一个沿切线方向的实心三角
            //(箭头必须顺着圆弧的方向,否则看起来像漂在圆圈上的随机折线)
            var ex = 10 + Math.cos(endAngle) * r
            var ey = 10 + Math.sin(endAngle) * r
            var tx = -Math.sin(endAngle)
            var ty = Math.cos(endAngle)
            ctx.beginPath()
            ctx.moveTo(ex + tx * 3.2, ey + ty * 3.2)
            ctx.lineTo(ex - ty * 2.2, ey + tx * 2.2)
            ctx.lineTo(ex + ty * 2.2, ey - tx * 2.2)
            ctx.closePath()
            ctx.fill()
            break

        case "delete":
            //垃圾桶
            ctx.beginPath()
            ctx.moveTo(5, 7)
            ctx.lineTo(5, 16)
            ctx.quadraticCurveTo(5, 18, 7, 18)
            ctx.lineTo(13, 18)
            ctx.quadraticCurveTo(15, 18, 15, 16)
            ctx.lineTo(15, 7)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(4, 7)
            ctx.lineTo(16, 7)
            ctx.stroke()
            ctx.beginPath()
            ctx.moveTo(8, 7)
            ctx.lineTo(8, 5)
            ctx.quadraticCurveTo(8, 4, 9, 4)
            ctx.lineTo(11, 4)
            ctx.quadraticCurveTo(12, 4, 12, 5)
            ctx.lineTo(12, 7)
            ctx.stroke()
            break

        case "close":
            //叉号
            ctx.beginPath()
            ctx.moveTo(5, 5)
            ctx.lineTo(15, 15)
            ctx.moveTo(15, 5)
            ctx.lineTo(5, 15)
            ctx.stroke()
            break

        case "minimize":
            //最小化:短横线
            ctx.beginPath()
            ctx.moveTo(5, 10)
            ctx.lineTo(15, 10)
            ctx.stroke()
            break

        case "play":
            //播放/启动三角
            ctx.beginPath()
            ctx.moveTo(7, 5)
            ctx.lineTo(15, 10)
            ctx.lineTo(7, 15)
            ctx.closePath()
            ctx.fill()
            break

        case "stop":
            //停止方块
            ctx.beginPath()
            ctx.rect(6, 6, 8, 8)
            ctx.fill()
            break
        }
    }
}
