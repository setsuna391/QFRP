cmake_minimum_required(VERSION 3.16.0)
project(QML_FRPC VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Network)

qt_policy(SET QTP0001 NEW)
qt_policy(SET QTP0004 NEW)

include_directories(include)

file(GLOB SOURCES "src/*.cpp")

add_executable(QML_FRPC ${SOURCES})
set_target_properties(QML_FRPC PROPERTIES OUTPUT_NAME "QML_FRPC" RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    WIN32_EXECUTABLE TRUE)

#Theme.qml 是 QML 单例(必须在 qt_add_qml_module 之前设置)
set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(QML_FRPC
    URI QML_FRPC
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/LoginView.qml
        qml/MainView.qml
        qml/TunnelCard.qml
        qml/AppIcon.qml
        qml/Theme.qml
        qml/WindowControls.qml
    SOURCES
        src/ApiClient.cpp
        include/ApiClient.h
        src/AppSettings.cpp
        include/AppSettings.h
        src/FrpcManager.cpp
        include/FrpcManager.h
)

target_link_libraries(QML_FRPC PRIVATE
    Qt6::Quick
    Qt6::Network
)

# ===== 内置 frpc =====
# 配置阶段从 natfrp 官方下载一份 frpc 存到 third_party/,打包进 Qt 资源。
# 应用启动时若缓存目录里没有 frpc,会从资源里解包使用;
# 离线配置构建时跳过下载,运行时的自动下载逻辑兜底。
set(FRPC_BUNDLE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party")
set(FRPC_BUNDLED "${FRPC_BUNDLE_DIR}/frpc")

if(NOT EXISTS "${FRPC_BUNDLED}")
    set(FRPC_TARGET_ARCH "linux_amd64")
    if(WIN32)
        #Windows 本地构建或交叉编译:下载 Windows 版 frpc
        set(FRPC_TARGET_ARCH "windows_amd64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "aarch64|arm64")
        set(FRPC_TARGET_ARCH "linux_arm64")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^armv7")
        set(FRPC_TARGET_ARCH "linux_armv7")
    elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "riscv64")
        set(FRPC_TARGET_ARCH "linux_riscv64")
    endif()
    #与 src/ApiClient.cpp 的 FRPC_VERSION 对应的官方分发版本
    set(FRPC_VERSION "0.51.0-sakura-14")
    set(FRPC_URL "https://nya.globalslb.net/natfrp/client/frpc/${FRPC_VERSION}/frpc_${FRPC_TARGET_ARCH}")
    message(STATUS "Downloading bundled frpc (${FRPC_TARGET_ARCH}) ...")
    file(DOWNLOAD "${FRPC_URL}" "${FRPC_BUNDLED}" STATUS frpc_dl_status SHOW_PROGRESS TIMEOUT 300)
    list(GET frpc_dl_status 0 frpc_dl_err)
    if(NOT frpc_dl_err EQUAL 0)
        list(GET frpc_dl_status 1 frpc_dl_msg)
        message(WARNING "frpc 下载失败(${frpc_dl_msg}),应用将改用运行时自动下载。重新构建或手动放置文件到 ${FRPC_BUNDLED} 后重试。")
        file(REMOVE "${FRPC_BUNDLED}")
    else()
        message(STATUS "Bundled frpc ready: ${FRPC_BUNDLED}")
    endif()
else()
    message(STATUS "Using bundled frpc: ${FRPC_BUNDLED}")
endif()

if(EXISTS "${FRPC_BUNDLED}")
    set_source_files_properties("${FRPC_BUNDLED}" PROPERTIES QT_RESOURCE_ALIAS "frpc")
    qt_add_resources(QML_FRPC "frpc_binary"
        PREFIX "/frpc"
        FILES "${FRPC_BUNDLED}"
    )
endif()

#应用图标(窗口图标 + 桌面入口用)
set_source_files_properties("assets/icon.png" PROPERTIES QT_RESOURCE_ALIAS "icon.png")
qt_add_resources(QML_FRPC "app_icon"
    PREFIX "/assets"
    FILES "assets/icon.png"
)

# ===== 内置壁纸(可选) =====
#把图片命名为 assets/wallpaper.jpg(.png/.webp 也可)放进项目,构建时打包进应用,
#作为未自选壁纸时的默认背景;设置页自选的壁纸优先于内置壁纸。
#CONFIGURE_DEPENDS:放入或删除图片后,直接重新构建就能被发现
file(GLOB APP_WALLPAPER_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/assets/wallpaper.*")
if(APP_WALLPAPER_FILES)
    list(GET APP_WALLPAPER_FILES 0 APP_WALLPAPER)
    get_filename_component(APP_WALLPAPER_NAME "${APP_WALLPAPER}" NAME)
    set_source_files_properties("${APP_WALLPAPER}" PROPERTIES QT_RESOURCE_ALIAS "${APP_WALLPAPER_NAME}")
    qt_add_resources(QML_FRPC "app_wallpaper" PREFIX "/assets" FILES "${APP_WALLPAPER}")
    target_compile_definitions(QML_FRPC PRIVATE APP_BUILTIN_WALLPAPER="/assets/${APP_WALLPAPER_NAME}")
    message(STATUS "Bundled wallpaper: ${APP_WALLPAPER_NAME}")
endif()

# ===== 安装规则 =====
include(GNUInstallDirs)
install(TARGETS QML_FRPC RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES packaging/qml-frpc.desktop
        DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
install(FILES assets/icon.png
        DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/256x256/apps
        RENAME qml-frpc.png)

include(CTest)
enable_testing()

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)