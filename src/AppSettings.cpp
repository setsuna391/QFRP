#include "AppSettings.h"
#include "ApiClient.h"

#include <QClipboard>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QSettings>
#include <QSaveFile>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QtGlobal>
#if defined(Q_OS_LINUX)
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#endif

namespace {

const char kWpKey[] = "ui/wallpaperFile";

QString cacheDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + "/wallpaper";
    QDir().mkpath(dir);
    return dir;
}

} // namespace

AppSettings* AppSettings::instance()
{
    static AppSettings inst;
    return &inst;
}

AppSettings::AppSettings(QObject* parent)
    : QObject(parent)
{
}

QString AppSettings::wallpaperFile() const
{
    QSettings settings;
    return settings.value(kWpKey).toString();
}

void AppSettings::setWallpaperFile(const QString& path)
{
    QSettings settings;
    if (settings.value(kWpKey).toString() == path)
        return;
    settings.setValue(kWpKey, path);
    emit wallpaperFileChanged();
}

QString AppSettings::builtinWallpaper() const
{
#ifdef APP_BUILTIN_WALLPAPER
    return QString::fromUtf8(APP_BUILTIN_WALLPAPER);
#else
    return QString();
#endif
}

QString AppSettings::pickWallpaper(const QString& source)
{
    //QML FileDialog 传来的通常是 file:// URL,也兼容直接给本地路径
    const QUrl url(source);
    const QString srcPath = url.isLocalFile() ? url.toLocalFile() : source;
    const QFileInfo fi(srcPath);
    if (!fi.exists() || !fi.isFile())
        return QString();

    //保留扩展名,Image 靠它识别格式;清掉旧格式残留,避免缓存目录堆积
    QString ext = fi.suffix().isEmpty() ? QStringLiteral("jpg") : fi.suffix().toLower();
    const QString dest = cacheDir() + QStringLiteral("/wallpaper.") + ext;
    QDir dir(cacheDir());
    const auto olds = dir.entryInfoList({ QStringLiteral("wallpaper.*") });
    for (const QFileInfo& old : olds) {
        if (old.absoluteFilePath() != dest)
            QFile::remove(old.absoluteFilePath());
    }
    QFile::remove(dest);
    if (!QFile::copy(srcPath, dest))
        return QString();

    setWallpaperFile(dest);
    return dest;
}

void AppSettings::clearWallpaper()
{
    setWallpaperFile(QString());
}

void AppSettings::copyText(const QString& text)
{
    QGuiApplication::clipboard()->setText(text);
}

QString AppSettings::exportLog(const QString& destination, const QString& text)
{
    const QUrl url(destination);
    if (!url.isLocalFile())
        return QStringLiteral("请选择本地文件。");
    QString safe = text;
    const QString token = ApiClient::instance()->token();
    if (!token.isEmpty())
        safe.replace(token, QStringLiteral("[已隐藏 Token]"), Qt::CaseSensitive);
    safe.replace(QRegularExpression(QStringLiteral("(Bearer\\s+)[^\\s]+"), QRegularExpression::CaseInsensitiveOption),
                 QStringLiteral("\\1[已隐藏]"));
    QSaveFile file(url.toLocalFile());
    if (!file.open(QIODevice::WriteOnly))
        return file.errorString();
    const QByteArray data = safe.toUtf8();
    if (file.write(data) != data.size() || !file.commit())
        return file.errorString();
    return QString();
}

void AppSettings::notify(const QString& title, const QString& message)
{
#if defined(Q_OS_LINUX)
    QDBusMessage call = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
    call << QStringLiteral("QFRP") << quint32(0) << QStringLiteral("qml-frpc") << title << message
         << QStringList() << QVariantMap() << int(-1);
    QDBusConnection::sessionBus().asyncCall(call);
#else
    Q_UNUSED(title);
    Q_UNUSED(message);
#endif
}
