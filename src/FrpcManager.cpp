#include "FrpcManager.h"
#include "ApiClient.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QPointer>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
#include <QTimer>
#include <utility>
#include <csignal>
#include <unistd.h>

namespace {

constexpr int kMaxRestartAttempts = 5;

const char kPathKey[] = "frpc/path";
const char kStateFile[] = "/state.json";
const char kClientsUrl[] = "https://api.natfrp.com/v4/system/clients";

QString binDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/bin";
    QDir().mkpath(dir);
    return dir;
}

QString logDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/logs";
    QDir().mkpath(dir);
    return dir;
}

QString logFilePath(const QString& tunnelId)
{
    return logDir() + "/" + tunnelId + ".log";
}

QString stateFilePath()
{
    return QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + kStateFile;
}

} // namespace

FrpcManager* FrpcManager::instance()
{
    static FrpcManager inst;
    return &inst;
}

FrpcManager::FrpcManager(QObject* parent)
    : QObject(parent)
{
    QSettings settings;
    m_frpcPath = settings.value(kPathKey).toString();
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &FrpcManager::pumpLogFile);
    //隧道启停时顺手刷新状态文件:即使应用被强杀,文件里也是最近一次的真实 pid
    connect(this, &FrpcManager::started, this, &FrpcManager::saveState);
    connect(this, &FrpcManager::stopped, this, &FrpcManager::saveState);
    //接管的进程没有 QProcess 句柄,轮询 pid 存活,意外死亡同样触发自动重启
    m_adoptedPoller.setInterval(3000);
    connect(&m_adoptedPoller, &QTimer::timeout, this, &FrpcManager::pollAdopted);
    m_adoptedPoller.start();
    adoptRunningTunnels();
}

QString FrpcManager::frpcPath() const
{
    return m_frpcPath;
}

void FrpcManager::setFrpcPath(const QString& path)
{
    if (m_frpcPath == path)
        return;
    m_frpcPath = path;
    QSettings settings;
    settings.setValue(kPathKey, path);
    emit frpcPathChanged();
}

QString FrpcManager::resolveBinary() const
{
    if (!m_frpcPath.isEmpty() && QFileInfo::exists(m_frpcPath))
        return m_frpcPath;
    const QString autoPath = binDir() + "/frpc";
    QFile bundled(QStringLiteral(":/frpc/frpc"));
    if (QFileInfo::exists(autoPath)) {
        if (bundled.exists() && bundled.size() != QFileInfo(autoPath).size()) {
            QFile::remove(autoPath);
        } else {
            return autoPath;
        }
    }
    if (bundled.exists()) {
        if (bundled.copy(autoPath)) {
            QFile extracted(autoPath);
            extracted.setPermissions(QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther
                                     | QFile::ReadUser | QFile::ReadGroup | QFile::ReadOther);
            qInfo().noquote() << "FrpcManager: extracted bundled frpc to" << autoPath;
            return autoPath;
        }
        qWarning() << "FrpcManager: failed to extract bundled frpc, falling back to download";
    }
    return QString();
}

QString FrpcManager::downloadArch() const
{
    QString os = QSysInfo::productType();
    if (os == QLatin1String("darwin") || os == QLatin1String("macos"))
        os = QStringLiteral("darwin");
    else if (os == QLatin1String("windows"))
        os = QStringLiteral("windows");
    else
        os = QStringLiteral("linux");
    const QString arch = QSysInfo::currentCpuArchitecture();
    QString a;
    if (arch == QLatin1String("x86_64"))       a = QStringLiteral("amd64");
    else if (arch == QLatin1String("i386"))    a = QStringLiteral("386");
    else if (arch == QLatin1String("arm"))     a = QStringLiteral("armv7");
    else if (arch == QLatin1String("arm64"))   a = QStringLiteral("arm64");
    else if (arch == QLatin1String("mips"))    a = QStringLiteral("mips");
    else if (arch == QLatin1String("mips64"))  a = QStringLiteral("mips64");
    else if (arch == QLatin1String("riscv64")) a = QStringLiteral("riscv64");
    else if (arch == QLatin1String("loongarch64")) a = QStringLiteral("loong64");
    else                                       a = arch;
    return os + "_" + a;
}

void FrpcManager::toggleTunnel(const QString& tunnelId)
{
    if (m_procs.contains(tunnelId)) {
        stopTunnel(tunnelId);
        return;
    }
    const QString binary = resolveBinary();
    if (!binary.isEmpty()) {
        startTunnel(tunnelId, binary);
        return;
    }
    if (m_downloading)
        return;
    m_pendingStartId = tunnelId;
    downloadFrpc();
}

void FrpcManager::downloadFrpc()
{
    if (m_downloading)
        return;
    m_downloading = true;
    emit frpcDownloadStarted();
    QNetworkReply* reply = m_manager.get(QNetworkRequest(QUrl(kClientsUrl)));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            m_downloading = false;
            const QString error = QStringLiteral("获取下载信息失败: %1").arg(reply->errorString());
            emit frpcDownloadFailed(error);
            if (!m_pendingStartId.isEmpty()) {
                emit startFailed(m_pendingStartId, error);
                m_pendingStartId.clear();
            }
            return;
        }
        const QJsonObject clients = QJsonDocument::fromJson(reply->readAll()).object();
        const QJsonObject frpc = clients.value("frpc").toObject();
        const QJsonObject archs = frpc.value("archs").toObject();
        const QJsonObject entry = archs.value(downloadArch()).toObject();
        const QString url = entry.value("url").toString();
        if (url.isEmpty()) {
            m_downloading = false;
            const QString error = QStringLiteral("下载列表里没有当前架构 (%1) 的 frpc").arg(downloadArch());
            emit frpcDownloadFailed(error);
            if (!m_pendingStartId.isEmpty()) {
                emit startFailed(m_pendingStartId, error);
                m_pendingStartId.clear();
            }
            return;
        }
        qInfo().noquote() << "FrpcManager: downloading frpc" << frpc.value("ver").toString() << "from" << url;
        QNetworkReply* dl = m_manager.get(QNetworkRequest(QUrl(url)));
        connect(dl, &QNetworkReply::downloadProgress, this, [this](qint64 received, qint64 total) {
            if (total > 0)
                emit frpcOutput(QStringLiteral("frpc-download"),
                                QStringLiteral("下载进度 %1%").arg(received * 100 / total));
        });
        connect(dl, &QNetworkReply::finished, this, [this, dl, url]() {
            dl->deleteLater();
            if (dl->error() != QNetworkReply::NoError) {
                m_downloading = false;
                const QString error = QStringLiteral("下载 frpc 失败: %1").arg(dl->errorString());
                emit frpcDownloadFailed(error);
                if (!m_pendingStartId.isEmpty()) {
                    emit startFailed(m_pendingStartId, error);
                    m_pendingStartId.clear();
                }
                return;
            }
            const QString path = binDir() + "/frpc";
            QFile file(path);
            if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
                m_downloading = false;
                const QString error = QStringLiteral("无法写入 %1: %2").arg(path, file.errorString());
                emit frpcDownloadFailed(error);
                if (!m_pendingStartId.isEmpty()) {
                    emit startFailed(m_pendingStartId, error);
                    m_pendingStartId.clear();
                }
                return;
            }
            file.write(dl->readAll());
            file.close();
            file.setPermissions(QFile::ExeUser | QFile::ExeGroup | QFile::ExeOther
                                | QFile::ReadUser | QFile::ReadGroup | QFile::ReadOther);
            m_downloading = false;
            emit frpcDownloadFinished(path);
            if (!m_pendingStartId.isEmpty()) {
                const QString id = m_pendingStartId;
                m_pendingStartId.clear();
                startTunnel(id, path);
            }
        });
    });
}

void FrpcManager::startTunnel(const QString& tunnelId, const QString& binary)
{
    if (m_procs.contains(tunnelId))
        return;
    //手动/自动启动都视为"不再处于用户停止状态"
    m_userStopped.remove(tunnelId);
    const QString token = ApiClient::instance()->token();
    if (token.isEmpty()) {
        emit startFailed(tunnelId, QStringLiteral("请先登录"));
        return;
    }
    QProcess* proc = new QProcess(this);
    const QString logPath = logFilePath(tunnelId);
    proc->setStandardOutputFile(logPath);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::started, this, [this, tunnelId, logPath, proc]() {
        emit started(tunnelId);
        watchLogFile(tunnelId);
        qInfo().noquote() << QStringLiteral("[FrpcManager] tunnel %1 started with pid").arg(tunnelId) << proc->processId();
        emit frpcOutput(tunnelId, QStringLiteral("frpc 已启动 (pid=%1),日志文件: %2").arg(proc->processId()).arg(logPath));
        //稳定运行 60 秒后清零重启计数,避免偶发崩溃累积到放弃阈值
        QPointer<QProcess> guard(proc);
        QTimer::singleShot(60000, this, [this, guard, tunnelId]() {
            if (guard && m_procs.value(tunnelId).proc == guard)
                m_restartAttempts.remove(tunnelId);
        });
    });
    connect(proc, &QProcess::errorOccurred, this,
            [this, tunnelId, binary](QProcess::ProcessError error) {
                if (error == QProcess::FailedToStart) {
                    emit startFailed(tunnelId,
                                     QStringLiteral("无法启动 frpc (%1),请检查设置里的路径或重新下载").arg(binary));
                    cleanupProcess(tunnelId);
                }
            });
    connect(proc, &QProcess::finished, this, [this, tunnelId, binary](int exitCode, QProcess::ExitStatus) {
        //先移除再发信号,stopped 触发的 saveState 才不会把刚退出的 pid 写回文件
        const bool userInitiated = m_userStopped.contains(tunnelId);
        cleanupProcess(tunnelId);
        emit stopped(tunnelId, exitCode);
        if (!userInitiated)
            scheduleRestart(tunnelId, binary);
    });
    m_procs.insert(tunnelId, {proc, 0});
    proc->start(binary, {QStringLiteral("-f"), token + ":" + tunnelId});
}

void FrpcManager::stopTunnel(const QString& tunnelId)
{
    const ProcEntry& entry = m_procs.value(tunnelId);
    if (!entry.proc && !entry.pid)
        return;
    if (entry.proc) {
        qInfo().noquote() << QStringLiteral("[FrpcManager] stopping spawned tunnel %1 (pid=%2)").arg(tunnelId).arg(entry.proc->processId());
        stopSpawned(tunnelId);
    }
    else if (entry.pid) {
        qInfo().noquote() << QStringLiteral("[FrpcManager] stopping adopted tunnel %1 (pid=%2)").arg(tunnelId).arg(entry.pid);
        stopAdopted(tunnelId);
    }
}

void FrpcManager::stopSpawned(const QString& tunnelId)
{
    ProcEntry& entry = m_procs[tunnelId];
    if (!entry.proc)
        return;
    m_userStopped.insert(tunnelId);
    entry.proc->terminate();
    QPointer<QProcess> guard(entry.proc);
    QTimer::singleShot(3000, this, [guard]() {
        if (guard && guard->state() != QProcess::NotRunning)
            guard->kill();
    });
}

void FrpcManager::stopAdopted(const QString& tunnelId)
{
    ProcEntry& entry = m_procs[tunnelId];
    if (!entry.pid)
        return;
    m_userStopped.insert(tunnelId);
    qInfo().noquote() << QStringLiteral("[FrpcManager] sending SIGTERM to adopted pid").arg(entry.pid);
    if (::kill(static_cast<pid_t>(entry.pid), SIGTERM) == 0) {
        QTimer::singleShot(3000, this, [this, tunnelId, pid = entry.pid]() {
            if (pidAlive(pid)) {
                qWarning() << "[FrpcManager] adopted process still alive, sending SIGKILL to" << pid;
                ::kill(static_cast<pid_t>(pid), SIGKILL);
            }
            cleanupProcess(tunnelId);
            emit stopped(tunnelId, 0);
        });
    } else {
        qWarning() << "[FrpcManager] failed to send SIGTERM to pid" << entry.pid;
        cleanupProcess(tunnelId);
        emit stopped(tunnelId, -1);
    }
}

void FrpcManager::cleanupProcess(const QString& tunnelId)
{
    ProcEntry entry = m_procs.take(tunnelId);
    if (entry.proc) {
        qInfo().noquote() << QStringLiteral("[FrpcManager] cleaning up spawned tunnel %1").arg(tunnelId);
        entry.proc->deleteLater();
    } else if (entry.pid) {
        qInfo().noquote() << QStringLiteral("[FrpcManager] cleaning up adopted tunnel %1 (pid=%2)").arg(tunnelId).arg(entry.pid);
    }
    m_watcher.removePath(logFilePath(tunnelId));
    m_logOffsets.remove(tunnelId);
    m_lineBuffers.remove(tunnelId);
}

bool FrpcManager::isRunning(const QString& tunnelId) const
{
    return m_procs.contains(tunnelId);
}

void FrpcManager::pollAdopted()
{
    //先收集再处理,避免处理过程中修改容器;
    //用户正在停止的(stopAdopted 自己的定时器负责收尾)跳过
    QList<QString> dead;
    for (auto it = m_procs.constBegin(); it != m_procs.constEnd(); ++it) {
        if (!it.value().proc && it.value().pid > 0
            && !m_userStopped.contains(it.key()) && !pidAlive(it.value().pid))
            dead.append(it.key());
    }
    for (const QString& id : dead) {
        cleanupProcess(id);
        emit stopped(id, 0);
        scheduleRestart(id, QString());
    }
}

void FrpcManager::scheduleRestart(const QString& tunnelId, const QString& binary)
{
    //用户手动停止过,或期间已被重新启动的,不再重启
    if (m_userStopped.contains(tunnelId) || m_procs.contains(tunnelId))
        return;
    const int attempts = m_restartAttempts.value(tunnelId, 0) + 1;
    if (attempts > kMaxRestartAttempts) {
        m_restartAttempts.remove(tunnelId);
        emit frpcOutput(tunnelId, QStringLiteral("frpc 反复退出,已放弃自动重启;请排查后手动启动"));
        return;
    }
    m_restartAttempts[tunnelId] = attempts;
    //线性退避:3s, 6s, 9s ... 封顶 30s
    const int delaySec = qMin(3 * attempts, 30);
    emit frpcOutput(tunnelId, QStringLiteral("frpc 意外退出,%1 秒后自动重启(第 %2/%3 次)")
                        .arg(delaySec).arg(attempts).arg(kMaxRestartAttempts));
    QTimer::singleShot(delaySec * 1000, this, [this, tunnelId, binary]() {
        if (m_userStopped.contains(tunnelId) || m_procs.contains(tunnelId))
            return;
        QString bin = binary;
        if (bin.isEmpty())
            bin = resolveBinary();
        if (bin.isEmpty()) {
            m_restartAttempts.remove(tunnelId);
            emit frpcOutput(tunnelId, QStringLiteral("自动重启失败: 找不到可用的 frpc 可执行文件"));
            return;
        }
        startTunnel(tunnelId, bin);
    });
}

QVariantList FrpcManager::runningTunnelIds() const
{
    QVariantList ids;
    for (auto it = m_procs.constBegin(); it != m_procs.constEnd(); ++it)
        ids.append(it.key());
    return ids;
}

void FrpcManager::stopAll()
{
    //强制停止全部(含后台接管进程)。正常退出不会调用它——frpc 要继续在后台跑
    const QList<QString> ids = m_procs.keys();
    for (const QString& id : ids)
        stopTunnel(id);
}

void FrpcManager::adoptRunningTunnels()
{
    const QString path = stateFilePath();
    if (!QFile::exists(path)) {
        qInfo() << "[FrpcManager] no state file found, nothing to adopt";
        return;
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[FrpcManager] failed to open state file:" << file.errorString();
        return;
    }
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    const QJsonObject obj = doc.object();
    int adopted = 0;
    for (auto it = obj.constBegin(); it != obj.constEnd(); ++it) {
        const QString tunnelId = it.key();
        const qint64 pid = it.value().toVariant().toLongLong();
        if (pidAlive(pid)) {
            m_procs.insert(tunnelId, {nullptr, pid});
            watchLogFile(tunnelId);
            emit started(tunnelId);
            emit frpcOutput(tunnelId, QStringLiteral("接管后台 frpc 进程 (pid=%1)").arg(pid));
            qInfo().noquote() << QStringLiteral("[FrpcManager] adopted %1 (pid=%2)").arg(tunnelId).arg(pid);
            adopted++;
        } else {
            qInfo().noquote() << QStringLiteral("[FrpcManager] dead process %1 (pid=%2), skipped").arg(tunnelId).arg(pid);
        }
    }
    file.close();
    qInfo() << "[FrpcManager] adoption done," << adopted << "tunnel(s) adopted";
}

void FrpcManager::saveState() const
{
    QJsonObject obj;
    for (auto it = m_procs.constBegin(); it != m_procs.constEnd(); ++it) {
        const ProcEntry& entry = it.value();
        const qint64 pid = entry.proc ? entry.proc->processId() : entry.pid;
        if (pid > 0)
            obj.insert(it.key(), pid);
    }
    QDir().mkpath(QFileInfo(stateFilePath()).path());
    QFile file(stateFilePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[FrpcManager] failed to save state:" << file.errorString();
        return;
    }
    const QByteArray json = QJsonDocument(obj).toJson(QJsonDocument::Compact);
    file.write(json);
    file.close();
    qInfo().noquote() << "[FrpcManager] state saved:" << json;
}

void FrpcManager::watchLogFile(const QString& tunnelId)
{
    const QString path = logFilePath(tunnelId);
    m_watcher.addPath(path);
    m_logOffsets[tunnelId] = 0;
    m_lineBuffers[tunnelId] = QByteArray();
    QTimer::singleShot(100, this, [this, path]() { pumpLogFile(path); });
}

void FrpcManager::pumpLogFile(const QString& path)
{
    const QString tunnelId = QFileInfo(path).baseName();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return;
    qint64& offset = m_logOffsets[tunnelId];
    file.seek(offset);
    QByteArray& buffer = m_lineBuffers[tunnelId];
    while (!file.atEnd()) {
        QByteArray data = file.read(4096);
        buffer += data;
        int idx;
        while ((idx = buffer.indexOf('\n')) >= 0) {
            QByteArray line = buffer.left(idx);
            buffer.remove(0, idx + 1);
            if (line.endsWith('\r'))
                line.chop(1);
            if (!line.isEmpty())
                emit frpcOutput(tunnelId, QString::fromLocal8Bit(line));
        }
    }
    offset = file.pos();
    m_lineBuffers[tunnelId] = buffer;
    file.close();
}

bool FrpcManager::pidAlive(qint64 pid) const
{
    return ::kill(static_cast<pid_t>(pid), 0) == 0;
}