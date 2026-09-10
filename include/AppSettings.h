#ifndef APPSETTINGS_H
#define APPSETTINGS_H

//应用外观设置(界面壁纸),QSettings 持久化
//
//壁纸图片会被复制到应用缓存目录后再使用:
//用户之后移动/删除原图,壁纸也不会失效。
//
//QML 通过上下文属性 appSettings 访问:
//  appSettings.wallpaperFile     壁纸图片路径(空串 = 未设置,回退到内置壁纸)
//  appSettings.builtinWallpaper  构建时打包的默认壁纸路径(可能为空)
//  appSettings.pickWallpaper(url)   复制图片进缓存并设为壁纸,失败返回空串
//  appSettings.clearWallpaper()     恢复默认(回退到内置壁纸)
//壁纸透明度固定为 0.35,写死在 MainView 的壁纸 Image 上

#include <QObject>
#include <QString>

class AppSettings : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString wallpaperFile READ wallpaperFile WRITE setWallpaperFile NOTIFY wallpaperFileChanged)
    //构建时打包进资源的默认壁纸(assets/wallpaper.*),没有则为空串
    Q_PROPERTY(QString builtinWallpaper READ builtinWallpaper CONSTANT)

public:
    static AppSettings* instance();

    QString wallpaperFile() const;
    void setWallpaperFile(const QString& path);
    QString builtinWallpaper() const;

    //参数可以是本地路径或 file:// URL(QML FileDialog 给的是 URL)
    Q_INVOKABLE QString pickWallpaper(const QString& source);
    Q_INVOKABLE void clearWallpaper();

signals:
    void wallpaperFileChanged();

private:
    explicit AppSettings(QObject* parent = nullptr);
};

#endif // APPSETTINGS_H
