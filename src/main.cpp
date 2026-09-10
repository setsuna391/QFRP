#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QSocketNotifier>
#include <QIcon>
#include "ApiClient.h"
#include "AppSettings.h"
#include "FrpcManager.h"

//POSIX 信号处理仅类 Unix 平台使用;Windows 的 GUI 程序点关闭/系统注销
//走 WM_CLOSE/WM_QUERYENDSESSION,Qt 会正常触发 aboutToQuit,无需处理信号
#ifndef Q_OS_WIN
#include <csignal>
#include <sys/socket.h>
#include <unistd.h>
#endif

#ifndef Q_OS_WIN
namespace {

//SIGTERM/SIGINT 的默认行为是立即终止进程,不会执行任何退出钩子
//(aboutToQuit / 析构 / atexit 全都不跑),frpc 状态就存不下来了。
//标准做法:信号处理函数只往管道写一个字节(异步信号安全),
//由 QSocketNotifier 把它转成 Qt 事件,在事件循环里安全地 quit
int g_signalFds[2];

void signalHandler(int)
{
    const char b = 1;
    ::write(g_signalFds[0], &b, 1);
}

void installSignalHandlers(QCoreApplication* app)
{
    if (::socketpair(AF_UNIX, SOCK_STREAM, 0, g_signalFds) != 0)
        return;
    struct sigaction sa {};
    sa.sa_handler = signalHandler;
    sigemptyset(&sa.sa_mask);
    for (int sig : {SIGTERM, SIGINT})
        sigaction(sig, &sa, nullptr);

    auto* notifier = new QSocketNotifier(g_signalFds[1], QSocketNotifier::Read, app);
    QObject::connect(notifier, &QSocketNotifier::activated, app, [notifier] {
        notifier->setEnabled(false);
        char b = 0;
        ::read(g_signalFds[1], &b, 1);
        QCoreApplication::quit();
    });
}

} // namespace
#endif // !Q_OS_WIN

//程序入口:创建 Qt 应用、QML 引擎,把 ApiClient/FrpcManager 单例注册给 QML,然后加载主界面
int main(int argc, char *argv[])
{
    //分数缩放(1.2x)下 fontconfig 默认的 hintslight 会让笔画落在半像素上显得发虚,
    //强制 full hinting 让笔画对齐物理像素网格(仅本进程生效,不改系统字体配置)
    qputenv("QT_FREETYPE_PROPERTIES", "Noto Sans CJK SC:hintstyle=hintfull:hinting=true");

    //资源(图标/内置壁纸/frpc)由 qt_add_resources 注册进本目标,
    //其构造函数会在 main 之前自动初始化,无需手动 Q_INIT_RESOURCE
    //(MSVC 下该符号不导出,手动 extern 声明会导致链接失败)

    QGuiApplication app(argc, argv);
    QGuiApplication::setOrganizationName("QML_FRPC");
    QGuiApplication::setApplicationName("QML_FRPC");
    //组织名和应用名要一起设置,QSettings 靠它们确定配置文件的位置,
    //不设置组织名的话 token 会存到 ~/.config/Unknown Organization/ 下面
    //窗口图标(内嵌资源,Wayland 下任务栏/启动器图标由 .desktop 提供)
    app.setWindowIcon(QIcon(":/assets/icon.png"));

#ifndef Q_OS_WIN
    installSignalHandlers(&app);
#endif

    //Qt Quick 默认用距离场渲染文本,在 1.2x 这类分数缩放的屏幕上边缘会发虚;
    //NativeTextRendering 直接按真实 devicePixelRatio 走 FreeType 光栅化,最锐利
    QQuickWindow::setTextRenderType(QQuickWindow::NativeTextRendering);

    //任何形式的正常退出(界面退出按钮/窗口关闭/SIGTERM)都会触发 aboutToQuit,
    //在这里把还活着的 frpc pid 写入状态文件,下次启动时接管
    QObject::connect(&app, &QGuiApplication::aboutToQuit, [] {
        FrpcManager::instance()->saveState();
    });

    QQmlApplicationEngine engine;
    //把单例作为上下文属性暴露给 QML,QML 里直接用 apiClient.xxx / frpc.xxx 调用
    engine.rootContext()->setContextProperty("apiClient", ApiClient::instance());
    engine.rootContext()->setContextProperty("frpc", FrpcManager::instance());
    engine.rootContext()->setContextProperty("appSettings", AppSettings::instance());

    engine.loadFromModule("QML_FRPC", "Main");

    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
