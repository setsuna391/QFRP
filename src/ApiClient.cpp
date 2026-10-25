#include "ApiClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QSettings>
#include <QUrl>
#include <algorithm>
#include <utility>
#include <vector>

ApiClient* ApiClient::s_instance = nullptr;
//静态成员变量,用于存储 ApiClient 的单例实例,初始值为 nullptr,表示尚未创建实例

const QString BASE_URL = QStringLiteral("https://api.natfrp.com/v4");
//SakuraFrp 开放 API 的基础地址,所有请求路径都会拼接在后面

const QString FRPC_VERSION = QStringLiteral("0.51.0-sakura-7.2");
//获取隧道配置文件(/tunnel/config)时必须告诉服务器目标 frpc 的版本,
//服务器会按版本生成对应格式的配置。这里先用官方分发版本的默认值,
//以后打包了自己的 frpc 后改成实际版本号即可

const qint64 REQUEST_TIMEOUT_MS = 15000;
//所有请求的超时时间(毫秒),防止网络异常时请求永远挂起

ApiClient* ApiClient::instance()
{
    if (!s_instance) {
        s_instance = new ApiClient();
    }
    return s_instance;
}
//静态成员函数,返回 ApiClient 的单例实例

ApiClient::ApiClient(QObject* parent): QObject(parent) , m_ready(false)
{
    loadSavedToken();
}
//构造函数,初始化成员变量 m_ready 为 false,表示 ApiClient 尚未准备就绪

ApiClient::~ApiClient()
{
}
//析构函数,目前没有特殊的清理操作,只是定义了一个空的析构函数

bool ApiClient::isReady() const
{
    return m_ready;
}
//返回 ApiClient 是否准备就绪的函数,外部可以调用

QString ApiClient::token() const
{
    return m_token;
}
//返回当前登录的 token 的函数,外部可以调用

void ApiClient::login(const QString& token)
{
    const QString normalizedToken = token.trimmed();
    if (normalizedToken.isEmpty())
    {
        emit loginFailed(QStringLiteral("Token 不能为空"));
        //如果 token 为空,发射 loginFailed 信号通知登录失败,并返回
        return;
    }

    m_token = normalizedToken;
    //先记下 token,后面的 /user/info 请求要带上它来验证是否有效
    emit tokenChanged();
    //发射 tokenChanged 信号通知 token 发生变化

    QNetworkReply* reply = sendRequest("GET", "/user/info");
    //发送 GET 请求获取用户信息,以验证 token 是否有效

    handleReply(reply,
        [this, normalizedToken](const QJsonObject& info) {
            if (m_token != normalizedToken) return;
            //登录期间 token 被换掉或注销了(比如用户连点了两次登录),
            //这个过期响应直接丢弃,避免旧请求的结果覆盖新状态

            m_ready = true;
            //设置 ApiClient 为准备就绪状态
            emit readyChanged();
            //发射 readyChanged 信号通知准备状态发生变化
            saveToken();
            //保存 token 到本地设置中,以便下次启动时自动登录
            qInfo() << "[ApiClient] login success";
            emit loginSuccess();
            //发射 loginSuccess 信号通知登录成功
            emit userInfoReceived(info);
            ///user/info 直接返回用户对象,顺便发出去,QML 不用再单独请求一次
        },
        [this, normalizedToken](const QString& error) {
            if (m_token != normalizedToken) return;
            //同样丢弃过期的失败响应

            m_token.clear();
            //消除无效token
            emit tokenChanged();
            //发射 tokenChanged 信号通知 token 发生变化
            emit loginFailed(error);
            //发射 loginFailed 信号通知登录失败,error 里是友好的错误信息
        });
}

void ApiClient::logout()
{
    m_token.clear();
    m_ready = false;
    emit tokenChanged();
    emit readyChanged();
    //清除当前的 token,并发射 readyChanged 信号通知界面更新

    QSettings settings;
    settings.remove("api_token");
}

QNetworkRequest ApiClient::buildRequest(const QString& path)
{
    QUrl url(BASE_URL + path);
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setTransferTimeout(REQUEST_TIMEOUT_MS);
    //设置超时,超时后请求会以 QNetworkReply::OperationCanceledError 结束

    if (!m_token.isEmpty()) {
        request.setRawHeader("Authorization", ("Bearer " + m_token).toUtf8());
    }

    return request;
}

QNetworkReply* ApiClient::sendRequest(const QString& method, const QString& path, const QJsonObject& body)
{
    QNetworkRequest request = buildRequest(path);

    QNetworkReply* reply = nullptr;

    if (method == "GET") {
        reply = m_manager.get(request);
    } else if (method == "POST") {
        QJsonDocument doc(body);
        reply = m_manager.post(request, doc.toJson());
    } else if (method == "PUT") {
        QJsonDocument doc(body);
        reply = m_manager.put(request, doc.toJson());
    } else if (method == "DELETE") {
        if (body.isEmpty()) {
            reply = m_manager.deleteResource(request);
        } else {
            //deleteResource 不支持带请求体,带 body 的 DELETE 要用 sendCustomRequest
            reply = m_manager.sendCustomRequest(request, "DELETE", QJsonDocument(body).toJson());
        }
    }

    return reply;
    //注意:method 不认识时返回 nullptr,由 handleRawReply 统一判空报错
}

QString ApiClient::errorText(QNetworkReply* reply)
{
    //樱花API出错时,body 里是 {"code":403,"msg":"无权访问"} 这样的格式
    //优先把服务器给的 msg 展示给用户,比 Qt 原生的 errorString 友好得多
    QJsonDocument doc = QJsonDocument::fromJson(reply->readAll());
    if (doc.isObject()) {
        const QString msg = doc.object().value("msg").toString();
        if (!msg.isEmpty()) {
            return msg;
        }
    }
    return reply->errorString();
}

void ApiClient::reportError(const QString& error, const std::function<void(const QString&)>& onError)
{
    if (onError) {
        onError(error);
        //调用方自己处理错误(比如登录流程要发 loginFailed)
    } else {
        emit errorOccurred(error);
        //没人接管就发通用错误信号,QML 日志里能看到
    }
}

void ApiClient::handleRawReply(QNetworkReply* reply, std::function<void(QNetworkReply*)> onSuccess, const std::function<void(const QString&)>& onError)
{
    if (!reply) {
        //sendRequest 遇到不认识的请求方式时会返回空指针
        reportError(QStringLiteral("请求创建失败"), onError);
        return;
    }

    connect(reply, &QNetworkReply::finished, this, [this, reply, onSuccess, onError]() {
        reply->deleteLater();
        //用完释放内存

        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError || statusCode >= 400) {
            //网络错误,或服务器返回了 4xx/5xx 错误状态码
            //原始错误写入应用日志(/tmp/qfrp-messages.log),便于排查网络问题
            qWarning().noquote() << "[ApiClient]" << reply->url().toString()
                                 << "failed:" << reply->errorString()
                                 << "(HTTP" << statusCode << ")"
                                 << "body:" << QString::fromUtf8(reply->peek(300));
            reportError(errorText(reply), onError);
            return;
        }

        if (onSuccess) {
            onSuccess(reply);
            //把原始 reply 交给具体的解析函数(下面三个 handleXxxReply)
        }
    });
}

void ApiClient::handleReply(QNetworkReply* reply, std::function<void(const QJsonObject&)> onSuccess, std::function<void(const QString&)> onError)
{
    //响应是单个 JSON 对象的接口走这里(如 /user/info、/nodes、/tunnel/delete)
    handleRawReply(reply, [this, onSuccess, onError](QNetworkReply* r) {
        QJsonDocument doc = QJsonDocument::fromJson(r->readAll());
        if (!doc.isObject()) {
            //响应不是合法的 JSON 对象(比如网关返回了 HTML 错误页),不能当成成功
            reportError(QStringLiteral("服务器返回了无法解析的数据"), onError);
            return;
        }
        if (onSuccess) {
            onSuccess(doc.object());
        }
    }, onError);
}

void ApiClient::handleArrayReply(QNetworkReply* reply, std::function<void(const QJsonArray&)> onSuccess, std::function<void(const QString&)> onError)
{
    //响应是 JSON 数组的接口走这里(如 /tunnels,直接返回隧道数组本身)
    handleRawReply(reply, [this, onSuccess, onError](QNetworkReply* r) {
        QJsonDocument doc = QJsonDocument::fromJson(r->readAll());
        if (!doc.isArray()) {
            reportError(QStringLiteral("服务器返回了无法解析的数据"), onError);
            return;
        }
        if (onSuccess) {
            onSuccess(doc.array());
        }
    }, onError);
}

void ApiClient::handleTextReply(QNetworkReply* reply, std::function<void(const QString&)> onSuccess, std::function<void(const QString&)> onError)
{
    //响应是纯文本的接口走这里(如 /tunnel/config,返回的是配置文件内容,不要做 JSON 解析)
    handleRawReply(reply, [this, onSuccess](QNetworkReply* r) {
        if (onSuccess) {
            onSuccess(QString::fromUtf8(r->readAll()));
        }
    }, onError);
}

void ApiClient::getTunnels()
{
    QNetworkReply* reply = sendRequest("GET", "/tunnels");

    ///tunnels 返回的就是隧道数组,不套任何包装
    handleArrayReply(reply, [this](const QJsonArray& tunnels) {
        emit tunnelsReceived(tunnels);
    });
}

void ApiClient::createTunnel(const QJsonObject& params)
{
    QNetworkReply* reply = sendRequest("POST", "/tunnels", params);

    //成功返回 201 + {id, name, remote};失败(缺参数/无权限)走 tunnelCreateFailed,
    //让创建弹窗能把服务器的原因直接显示出来,而不是只写进日志页
    handleReply(reply, [this](const QJsonObject& response) {
        emit tunnelCreated(response);
    }, [this](const QString& error) {
        emit tunnelCreateFailed(error);
    });
}

void ApiClient::deleteTunnel(const QString& tunnelId)
{
    //删除接口的参数名是 ids(逗号分隔的隧道 ID 列表),单个删除也走它,不是 id
    QJsonObject body;
    body["ids"] = tunnelId;

    QNetworkReply* reply = sendRequest("POST", "/tunnel/delete", body);

    handleReply(reply, [this, tunnelId](const QJsonObject& response) {
        //返回 {"deleted":[...], "failed":[...]}
        //deleted 是删除成功的;failed 是已删除但没踢下线的(也算删除成功)
        auto idInList = [&tunnelId](const QJsonArray& list) {
            for (const QJsonValue& v : list) {
                if (QString::number(v.toInt()) == tunnelId) {
                    return true;
                }
            }
            return false;
        };

        if (idInList(response["deleted"].toArray()) || idInList(response["failed"].toArray())) {
            emit tunnelDeleted(tunnelId);
        } else {
            emit errorOccurred(QStringLiteral("删除隧道 %1 失败: 服务器未确认删除").arg(tunnelId));
        }
    });
}

void ApiClient::getUserInfo()
{
    QNetworkReply* reply = sendRequest("GET", "/user/info");

    ///user/info 直接返回用户对象,没有外层包装
    handleReply(reply, [this](const QJsonObject& info) {
        emit userInfoReceived(info);
    });
}

void ApiClient::getNodes()
{
    QNetworkReply* reply = sendRequest("GET", "/nodes");

    handleReply(reply, [this](const QJsonObject& response) {
        ///nodes 返回的是 {"节点ID": {节点信息...}} 这样的对象(map),不是数组,
        //而 QML 那边(下拉框、节点卡片)按数组处理,所以这里转成数组,
        //并把节点 ID 作为 id 字段塞进每个节点对象,下拉框才能拿到 id 去创建隧道
        std::vector<std::pair<int, QJsonObject>> nodeList;
        for (auto it = response.constBegin(); it != response.constEnd(); ++it) {
            const int id = it.key().toInt();
            QJsonObject node = it.value().toObject();
            node.insert("id", id);
            nodeList.push_back({id, node});
        }

        //map 的遍历顺序是按 key 字符串排的("1","10","11","2"...),按数字重排一下
        //注意不能直接对 QJsonArray 的迭代器 std::sort,QJsonValueRef 不支持 swap
        std::sort(nodeList.begin(), nodeList.end(),
                  [](const std::pair<int, QJsonObject>& a, const std::pair<int, QJsonObject>& b) {
                      return a.first < b.first;
                  });

        QJsonArray nodes;
        for (const auto& item : nodeList) {
            nodes.append(item.second);
        }

        emit nodesReceived(nodes);
    });
}

void ApiClient::getTunnelConfig(const QString& tunnelId)
{
    //这个接口需要两个必填参数:
    //query — 隧道 ID(也可以是 n 前缀的节点 ID,如 "n233")
    //frpc  — 目标 frpc 版本号,见文件顶部的 FRPC_VERSION 常量
    QJsonObject body;
    body["query"] = tunnelId;
    body["frpc"] = FRPC_VERSION;

    QNetworkReply* reply = sendRequest("POST", "/tunnel/config", body);

    //注意:返回的是 frpc 可直接加载的 ini/toml 配置文本,不是 JSON。
    //信号带上隧道 id,失败单独走 tunnelConfigFailed(FrpcManager 靠它清掉 pending 状态)
    handleTextReply(reply, [this, tunnelId](const QString& config) {
        emit tunnelConfigReceived(tunnelId, config);
    }, [this, tunnelId](const QString& error) {
        emit tunnelConfigFailed(tunnelId, error);
    });
}

QString ApiClient::frpcVersion() const
{
    return FRPC_VERSION;
}

void ApiClient::getTunnelTraffic(const QString& tunnelId)
{
    //返回 {时间戳: 字节} 的桶状数据,转成数组交给 QML
    handleReply(sendRequest("GET", "/tunnel/traffic?id=" + tunnelId),
        [this, tunnelId](const QJsonObject& resp) {
            QVariantMap traffic;
            for (auto it = resp.constBegin(); it != resp.constEnd(); ++it)
                traffic.insert(it.key(), it.value().toVariant());
            emit tunnelTrafficReceived(tunnelId, traffic);
        });
}

void ApiClient::getUserTrafficHistory()
{
    //type=day:条目为 [日期, 上期累计, 本期累计],差分即当日用量
    handleArrayReply(sendRequest("GET", "/user/traffic_history?type=day"),
        [this](const QJsonArray& arr) {
            QVariantList history;
            for (const auto& e : arr)
                history.append(e.toVariant());
            emit trafficHistoryReceived(history);
        });
}

void ApiClient::getDataPlans()
{
    handleArrayReply(sendRequest("GET", "/user/data_plans?status=valid"),
        [this](const QJsonArray& arr) { emit dataPlansReceived(arr); });
}

void ApiClient::getNodeStats()
{
    handleReply(sendRequest("GET", "/node/stats"),
        [this](const QJsonObject& stats) { emit nodeStatsReceived(stats); });
}

void ApiClient::getSystemClients()
{
    handleReply(sendRequest("GET", "/system/clients"),
        [this](const QJsonObject& info) { emit systemClientsReceived(info); });
}

void ApiClient::editTunnel(const QJsonObject& params)
{
    //编辑接口支持:备注/本地 IP/本地端口/类型/extra(不支持名称与节点)
    handleRawReply(sendRequest("POST", "/tunnel/edit", params),
        [this, params](QNetworkReply*) {
            emit tunnelEdited(QString::number(params.value("id").toInt()));
        },
        [this](const QString& error) { emit tunnelEditFailed(error); });
}

void ApiClient::getBulletin()
{
    handleArrayReply(sendRequest("GET", "/system/bulletin"),
        [this](const QJsonArray& arr) { emit bulletinReceived(arr); });
}

void ApiClient::saveToken()
{
    QSettings settings;
    settings.setValue("api_token", m_token);
}

void ApiClient::loadSavedToken()
{
    QSettings settings;
    const QString savedToken = settings.value("api_token").toString().trimmed();
    if (savedToken.isEmpty())
        return;

    // 本地已有 token 时直接恢复登录界面,验证放到后台做。
    // 不能因为启动时网络慢/超时就退回登录页,否则用户会以为 token 没被记住。
    m_token = savedToken;
    m_ready = true;
    emit tokenChanged();
    emit readyChanged();

    QNetworkReply* reply = sendRequest("GET", "/user/info");
    if (!reply)
        return;

    connect(reply, &QNetworkReply::finished, this, [this, reply, savedToken]() {
        reply->deleteLater();
        if (m_token != savedToken)
            return;

        const int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QJsonObject body = QJsonDocument::fromJson(reply->readAll()).object();
        const int code = body.value("code").toInt();

        if (reply->error() == QNetworkReply::NoError && statusCode < 400) {
            saveToken();
            emit userInfoReceived(body);
            emit loginSuccess();
            qInfo() << "[ApiClient] restored saved token";
            return;
        }

        // 服务器明确拒绝 token 才清除本地凭据并回到登录页
        if (statusCode == 401 || statusCode == 403 || code == 401 || code == 403) {
            m_token.clear();
            m_ready = false;
            QSettings settings;
            settings.remove("api_token");
            emit tokenChanged();
            emit readyChanged();
            emit loginFailed(body.value("msg").toString(QStringLiteral("Token 已失效")));
            return;
        }

        // 网络错误时保留 token 和主界面,不要要求用户重新输入
        emit errorOccurred(QStringLiteral("暂时无法验证登录状态: %1").arg(reply->errorString()));
    });
}
