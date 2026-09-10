#ifndef APICLIENT_H
#define APICLIENT_H


//QML 界面层
//   ↓ 调用方法
//ApiClient (C++)
//   ↓ HTTP 请求
//樱花API服务器
//   ↓ 返回数据
//ApiClient 处理响应
//   ↓ 发射信号
// QML 接收信号更新界面

//整个模块就是一个中间层：QML 不直接碰网络，
//ApiClient 帮它处理所有 HTTP 通信


//整体架构：
//- 单例模式 — 全局只有一个实例，保证登录状态统一
//- QML ↔ C++ 桥梁 — Q_INVOKABLE 让 QML 能调用，信号让 QML 能接收数据
//- 异步网络请求 — 发请求 → 信号通知结果，不阻塞


//数据流：
//QML 调用 login("token")
//  → ApiClient 发 HTTP 请求
//    → 服务器返回
//      → handleReply 处理响应
//        → emit loginSuccess()
//          → QML 收到信号更新界面




#include <QObject> //Qt对象模型基类，提供信号槽机制
#include <QNetworkAccessManager> //用于发送网络请求和接收响应的类
#include <QNetworkReply> //用于处理网络响应的类
#include <QJsonObject>  //用于表示 JSON 对象的类
#include <QJsonArray>  //用于表示 JSON 数组的类
#include <QSettings>  //用于存储和读取设置的类
#include <QNetworkRequest> //用于构建网络请求(设置 URL、请求头)的类
#include <functional> //用于函数对象的类

class ApiClient : public QObject
{
    Q_OBJECT    
    //Qt 元对象系统的宏,启用信号槽机制和其他元对象特性
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged) 
    //Qt 属性系统的宏,定义一个名为 ready 的属性,类型为 bool,
    //提供读取方法 isReady() 和通知信号 readyChanged()
    Q_PROPERTY(QString token READ token NOTIFY tokenChanged) 
    //定义一个名为 token 的属性,类型为 QString,
    //提供读取方法 token() 和通知信号 tokenChanged()

private:
    explicit ApiClient(QObject* parent = nullptr);
    //私有构造函数,防止外部直接创建实例,只能通过 instance() 方法获取单例对象
    // explicit 关键字用于防止构造函数被隐式调用,确保只能通过显式调用来创建对象,避免意外的类型转换和对象创建
    ApiClient(const ApiClient&) = delete;
    //删除拷贝构造函数,防止复制 ApiClient 实例,保证单例模式的唯一性
    ApiClient& operator=(const ApiClient&) = delete;
    //删除赋值运算符,防止复制 ApiClient 实例,保证单例模式的唯一性

    QNetworkRequest buildRequest(const QString& path);
    //工具函数,外部无法调用(拼接完整的请求地址)
    //构建网络请求对象,设置请求的 URL、头部信息等(负责拼接完整的请求地址)
    QNetworkReply* sendRequest(const QString& method, const QString& path, const QJsonObject& body = QJsonObject());
    //工具函数,外部无法调用(发送 HTTP 请求的核心方法)
    //发送网络请求,根据指定的 HTTP 方法、路径和请求体发送请求

    // 三个参数
    //sendRequest("GET", "/tunnels", QJsonObject());   // GET 请求，不需要 body
    //sendRequest("POST", "/tunnels", params);          // POST 请求，带 body
    //sendRequest("DELETE", "/xxx", body);              // DELETE 请求，也可以带 body
    //参数	       含义	      例子
    //method	请求方式	"GET"、"POST"、"PUT"、"DELETE"
    //path	接口路径	    "/user/info"、"/tunnels"
    //body	发送的数据   	{"ids": "123"}，GET 时可以不传
    //详细内容请学习http报文

    //返回 QNetworkReply*，就是服务器的响应，交给 handleReply 系列函数处理
    QString errorText(QNetworkReply* reply);
    //工具函数,外部无法调用
    //从失败的响应里提取用户友好的错误信息:
    //樱花API出错时 body 是 {"code":403,"msg":"无权访问"} 这样的格式,优先取 msg,
    //取不到再退回 Qt 原生的 errorString
    void reportError(const QString& error, const std::function<void(const QString&)>& onError);
    //工具函数,外部无法调用
    //统一处理错误:如果调用方提供了 onError(比如登录流程要发 loginFailed)就交给它,
    //否则发射通用的 errorOccurred 信号
    void handleRawReply(QNetworkReply* reply, std::function<void(QNetworkReply*)> onSuccess, const std::function<void(const QString&)>& onError = nullptr);
    //工具函数,外部无法调用
    //所有响应处理的公共部分:空指针检查、连接 finished 信号、释放 reply、网络/HTTP 错误检查
    //成功时把 reply 原样交给 onSuccess,由下面三个包装函数负责解析具体格式
    void handleReply(QNetworkReply* reply, std::function<void(const QJsonObject&)> onSuccess, std::function<void(const QString&)> onError = nullptr);
    //处理"响应是 JSON 对象"的请求(如 /user/info、/nodes、/tunnel/delete)
    //成功后把 JSON 对象交给 onSuccess;解析失败会按错误流程处理
    void handleArrayReply(QNetworkReply* reply, std::function<void(const QJsonArray&)> onSuccess, std::function<void(const QString&)> onError = nullptr);
    //处理"响应是 JSON 数组"的请求(如 /tunnels,它直接返回隧道数组本身,没有外层包装)
    void handleTextReply(QNetworkReply* reply, std::function<void(const QString&)> onSuccess, std::function<void(const QString&)> onError = nullptr);
    //处理"响应是纯文本"的请求(如 /tunnel/config,返回的是 frpc 配置文件内容,不是 JSON)
    void saveToken();
    //保存 token 到本地设置的函数,外部无法调用
    //将当前的 token 保存到本地设置中,以便下次启动时自动登录    
    
    void loadSavedToken();
    //加载本地保存的 token 的函数,外部无法调用
    //从本地设置中加载保存的 token,如果存在则设置为当前 token   

    static ApiClient* s_instance;
    //静态成员变量,用于存储 ApiClient 的单例实例

    QNetworkAccessManager m_manager;
    //用于发送网络请求和接收响应的类,是 Qt 网络模块的核心类,负责管理网络连接和请求
    QString m_token;
    //用于存储当前登录的 token 的成员变量,用于身份验证和授权
    bool m_ready;
    //用于表示 ApiClient 是否准备就绪的成员变量,在登录成功后设置为 true,在注销或登录失败后设置为 false

public:
    static ApiClient* instance(); 
    //懒汉式,首次调用 instance() 时创建 ApiClient 实例,之后的调用返回同一个实例
    //静态成员函数，返回 ApiClient 的单例实例
    //全局共用一个,保证了登录状态的唯一,也就是只有一个ApiClient实例在运行,避免了多次登录和状态混乱的问题
    ~ApiClient();

    bool isReady() const;
    //返回 ApiClient 是否准备就绪的函数,外部可以调用
    //如果准备就绪,说明已经登录成功,可以进行后续的 API 调用,否则需要先登录
    QString token() const;
    //返回当前登录的 token 的函数,外部可以调用
    //如果已经登录成功,返回有效的 token,否则返回空字符串
    

    //Q_INVOKABLE 宏
    //作用： 让这些函数能从 QML（前端界面） 里直接调用

    Q_INVOKABLE void login(const QString& token);
    //登录函数,外部可以调用
    //使用提供的 token 进行登录,如果登录成功,会发射 loginSuccess
    Q_INVOKABLE void logout();
    //注销函数,外部可以调用
    //清除当前的 token,并发射 readyChanged 信号通知界面更新

    Q_INVOKABLE void getTunnels();
    //获取隧道列表函数,外部可以调用
    //发送 GET 请求获取隧道列表,如果成功,会发射 tunnelsReceived
    Q_INVOKABLE void createTunnel(const QJsonObject& params);
    //创建隧道函数,外部可以调用
    //发送 POST 请求创建隧道,如果成功,会发射 tunnelCreated
    Q_INVOKABLE void deleteTunnel(const QString& tunnelId);
    //删除隧道函数,外部可以调用
    //发送 POST /tunnel/delete 请求删除隧道(参数是 ids,不是 id),成功后发射 tunnelDeleted
    Q_INVOKABLE void getUserInfo();
    //获取用户信息函数,外部可以调用
    //发送 GET 请求获取用户信息,如果成功,会发射 userInfoReceived
    Q_INVOKABLE void getNodes();
    //获取节点列表函数,外部可以调用
    //发送 GET 请求获取节点列表,如果成功,会发射 nodesReceived
    Q_INVOKABLE void getTunnelConfig(const QString& tunnelId);
    //获取隧道配置函数,外部可以调用
    //发送 POST /tunnel/config 请求获取 frpc 配置文件(纯文本),成功后发射 tunnelConfigReceived
signals:
    void readyChanged();
    //信号,当 ApiClient 的准备状态发生变化时发射,外部可以连接该信号以更新界面
    void tokenChanged();
    //信号,当 ApiClient 的 token 发生变化时发射,外部可以连接该信号以更新界面
    void loginSuccess();
    //信号,当登录成功时发射,外部可以连接该信号以更新界面
    void loginFailed(const QString& error);
    //信号,当登录失败时发射,外部可以连接该信号以更新界面

    void userInfoReceived(const QJsonObject& info);
    //信号,当用户信息获取成功时发射,外部可以连接该信号以更新界面
    void tunnelsReceived(const QJsonArray& tunnels);
    //信号,当隧道列表获取成功时发射,外部可以连接该信号以更新界面
    void tunnelCreated(const QJsonObject& tunnel);
    //信号,当隧道创建成功时发射,外部可以连接该信号以更新界面
    void tunnelCreateFailed(const QString& error);
    //信号,当隧道创建失败时发射(缺必填参数/无权限/服务器拒绝),创建弹窗靠它显示内联错误
    void tunnelDeleted(const QString& tunnelId);
    //信号,当隧道删除成功时发射,外部可以连接该信号以更新界面
    void tunnelConfigReceived(const QString& tunnelId, const QString& config);
    //信号,当隧道配置获取成功时发射,tunnelId 标识响应属于哪条隧道
    //(同时拉多条隧道的配置时靠它区分),config 是 frpc 可直接加载的 ini/toml 配置文本
    void tunnelConfigFailed(const QString& tunnelId, const QString& error);
    //信号,当隧道配置获取失败时发射(无 token/网络错误/服务器拒绝)
    void nodesReceived(const QJsonArray& nodes);
    //信号,当节点列表获取成功时发射,外部可以连接该信号以更新界面

    void errorOccurred(const QString& error);
    //信号,当发生任何请求错误时发射(网络错误、服务器错误、数据解析失败)
    //错误信息优先用服务器返回的 msg,外部可以连接该信号以更新界面

};

#endif // APICLIENT_H
