#ifndef FRPCMANAGER_H
#define FRPCMANAGER_H

//frpc 进程管理器
//
//职责:
//- 按隧道 id 启动/停止 frpc 子进程(支持多条隧道同时运行,互不影响)
//- frpc 可执行文件解析顺序:设置里手动填写的路径 → 缓存目录里自动下载的副本 →
//  都没有时从 natfrp 官方接口(/v4/system/clients,公开无需认证)自动下载
//- 启动用 SakuraFrp frpc 的 -f 开关:`frpc -f <token>:<隧道ID>`,
//  frpc 自己向服务器拉取配置,避免本地维护配置文件和版本号
//- frpc 的输出重定向到日志文件(应用缓存目录),界面通过监视文件按行显示;
//  重定向到文件(而非管道)是关键——应用退出后 frpc 不会因为管道断开而死掉
//- 应用退出时 frpc 继续在后台运行;退出前把 pid 写入状态文件,
//  下次启动时检查存活并"接管",停止时直接向 pid 发 SIGTERM
//- frpc 意外退出(崩溃/网络原因)时自动重启:线性退避最多 5 次,
//  稳定运行 60 秒后计数清零;用户手动停止的不重启
//- 接管的进程没有 QProcess 句柄,用定时器轮询 pid 存活,死亡同样触发重启
//
//QML 通过上下文属性 frpc 访问:
//  frpc.toggleTunnel(id)        未运行则启动,运行中则停止(隧道卡片按钮用)
//  frpc.stopTunnel(id)          停止指定隧道
//  frpc.isRunning(id)           是否在运行
//  frpc.runningTunnelIds()      当前在跑的隧道 id 列表(界面恢复状态用)
//  frpc.frpcPath                frpc 可执行文件路径(Q_PROPERTY,改动自动持久化)
//
//信号 → QML:
//  started / stopped / startFailed  → 更新卡片运行状态、写日志
//  frpcOutput                       → frpc 输出按行进日志页
//  frpcDownloadStarted/Finished/Failed → frpc 自动下载进度进日志页

#include <QObject>
#include <QProcess>
#include <QHash>
#include <QSet>
#include <QFileSystemWatcher>
#include <QNetworkAccessManager>
#include <QTimer>
#include <QVariantList>

class FrpcManager : public QObject
{
    Q_OBJECT
    //frpc 可执行文件路径,留空表示优先使用自动下载的副本,都没有则自动下载
    Q_PROPERTY(QString frpcPath READ frpcPath WRITE setFrpcPath NOTIFY frpcPathChanged)

public:
    static FrpcManager* instance();

    QString frpcPath() const;
    void setFrpcPath(const QString& path);

    //未运行 → 确保二进制存在后启动;运行中 → 停止
    Q_INVOKABLE void toggleTunnel(const QString& tunnelId);
    Q_INVOKABLE void stopTunnel(const QString& tunnelId);
    Q_INVOKABLE bool isRunning(const QString& tunnelId) const;
    Q_INVOKABLE QVariantList runningTunnelIds() const;
    //手动触发 frpc 下载(设置页用)
    Q_INVOKABLE void downloadFrpc();

    //把当前存活的 frpc pid 写入状态文件;正常退出时由 main 调用,QML 也可手动调用
    Q_INVOKABLE void saveState() const;

public slots:
    //强制停止全部(含后台接管进程)。正常退出不会调用它——frpc 要继续在后台跑
    void stopAll();

signals:
    void started(const QString& tunnelId);
    void stopped(const QString& tunnelId, int exitCode);
    void startFailed(const QString& tunnelId, const QString& reason);
    void frpcOutput(const QString& tunnelId, const QString& line);
    void frpcPathChanged();
    void frpcDownloadStarted();
    void frpcDownloadFinished(const QString& path);
    void frpcDownloadFailed(const QString& error);

private:
    explicit FrpcManager(QObject* parent = nullptr);

    //一条被管理的 frpc:自启的带 QProcess 句柄;从后台接管下来的只有 pid
    struct ProcEntry {
        QProcess* proc = nullptr;
        qint64 pid = 0;
    };

    //解析可用的 frpc 路径:手动配置 → 缓存副本 → 内置资源解包;都没有返回空串
    QString resolveBinary() const;
    void startTunnel(const QString& tunnelId, const QString& binary);
    void stopSpawned(const QString& tunnelId);
    void stopAdopted(const QString& tunnelId);
    void cleanupProcess(const QString& tunnelId);
    void adoptRunningTunnels();
    void scheduleRestart(const QString& tunnelId, const QString& binary);
    void pollAdopted();
    void watchLogFile(const QString& tunnelId);
    void pumpLogFile(const QString& path);
    bool pidAlive(qint64 pid) const;
    //当前 CPU 架构在 natfrp 下载列表里的键(如 linux_amd64)
    QString downloadArch() const;

    QHash<QString, ProcEntry> m_procs;          //被管理的 frpc,按隧道 id 索引
    QFileSystemWatcher m_watcher;               //监视 frpc 日志文件
    QHash<QString, qint64> m_logOffsets;        //日志文件读到的偏移
    QHash<QString, QByteArray> m_lineBuffers;   //按行缓冲
    QNetworkAccessManager m_manager;            //下载 frpc 用
    bool m_downloading = false;                 //同一时间只允许一个下载
    QString m_pendingStartId;                   //下载完成后要启动的隧道
    QSet<QString> m_userStopped;                //用户主动停止的隧道,不参与自动重启
    QHash<QString, int> m_restartAttempts;      //连续自动重启计数,稳定运行 60s 后清零
    QTimer m_adoptedPoller;                     //轮询接管进程的 pid 存活
    QString m_frpcPath;
};

#endif // FRPCMANAGER_H
