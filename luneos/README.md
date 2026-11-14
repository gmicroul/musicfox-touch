# MusicFox for LuneOS

独立的 Qt6/LuneOS 版本，应用 ID 与 IPK 内的包名均为 `org.musicfox.touch`。
安装包文件名使用 `musicfox-touch-luneos`，与 Sailfish RPM 分开。
现有 Sailfish 的 `.pro`、程序入口、播放器、RPM 脚本和 QML 源文件保持不变。

## 结构

- `src/`：标准 Qt6 程序入口与 QMediaPlayer/QAudioOutput 播放器。
- `generate-sources.py`：从现有主界面生成 LuneOS 界面，移除 Silica 窗口、Sailfish Cover 和 Nemo MPRIS 集成。
  生成文件只写入构建目录，不改动 `app/`；保留搜索、排行榜、歌单、播放界面、歌词和六个视觉组件。
- API 协议、播放队列、歌词同步和封面缓存复用 `app/src/`；
  生成的 API 优先启动应用内的后端，封面请求改用 Qt6 的安全重定向策略。
- 频谱逻辑从共享源码生成，仅把监视源选择适配到 LuneOS 的 `pcm_output.monitor`。
- `packaging/`：原生应用清单与 Wayland/PulseAudio 启动脚本。
- `install.py`：通过 AppInstallService 安装，等待真正的完成事件并检查目标系统依赖。
- `tests/`：源码隔离、IPK 元数据、安装通知、架构配置、播放器、队列/歌词和静音 WAV 播放测试。

## 本机编译

需要原生 aarch64 Linux、C++17 编译器、CMake 3.21+、Python 3.11+、GNU tar 和 ar。
后端使用 aarch64 `daemon/musicfox-daemon`；编译后的二进制不纳入 Git。
从新克隆的仓库构建时，需要 Go 1.23+，先编译后端：

```bash
(cd daemon && GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags '-s -w' -o musicfox-daemon .)
```

如需使用其他已编译后端，设置 `MUSICFOX_DAEMON`。

首次构建可下载并解包 Debian bookworm 的原生 Qt6 开发依赖：

```bash
./luneos/build.sh --bootstrap
```

这些依赖位于 `luneos/.sdk/`，不安装进本机系统，也不复制到目标机。
使用的是 Qt6 公共 API；目标机仍加载其自身的 Qt6 库和插件。
依赖下载与生成目录已通过 `luneos/.gitignore` 排除。

后续构建：

```bash
./luneos/build.sh
```

也可使用已有、与编译器匹配的 Qt6 开发环境：

```bash
MUSICFOX_QT6_PREFIX=/path/to/qt6 ./luneos/build.sh
```

默认构建目录为 `luneos/build/`，可通过 `MUSICFOX_BUILD_DIR` 更换。
这套 bootstrap 是原生开发依赖，不是 x86 到 ARM 的交叉编译 SDK。
使用交叉 SDK 时应直接通过 CMake 设置对应 toolchain、Qt6 prefix 和 Qt host tools。

## 输出与部署

构建同时生成 IPK：

```text
luneos/dist/musicfox-touch-luneos_0.5.0-1_aarch64.ipk
luneos/dist/root/usr/palm/applications/org.musicfox.touch/
```

应用目录内的 `bin/musicfox-touch` 是 Qt6 程序，`libexec/musicfox-daemon` 是 Go 后端。
根目录的 `musicfox-touch` 启动脚本设置 webOS Wayland shell、输入法和每个进程的 PulseAudio 媒体路由。
应用配置使用独立的 `MusicFox.LuneOS` organization，不复用 Sailfish 的配置命名空间。
`dist/root/` 是打包用的暂存树；安装服务将其放到用户应用分区，真机安装路径是：

```text
/media/cryptofs/apps/usr/palm/applications/org.musicfox.touch/
```

```bash
./luneos/deploy.sh root@192.168.2.160
```

部署脚本上传到临时目录，通过 `com.webos.appInstallService/install` 安装/重新安装这一个包，
等待 `installed` 事件，确认 SAM 的应用注册，再执行离屏启动检查并请求系统启动应用。
只拿到 `returnValue: true` 的请求受理响应不算安装成功。
安装服务会通知 SAM（`com.webos.applicationManager`）注册图标；不需要重启桌面。
旧的 `com.palm.applicationManager/rescan` 不能替代这个通知。
SSH 使用免交互认证并拒绝已知主机密钥变化。
可通过 `MUSICFOX_KNOWN_HOSTS` 指定 known_hosts 文件。
包内的 `luna-call` 保持调用期间 stdin 打开，避免目标机的 `luna-send` 在非交互 SSH 下因 EOF 提前退出，
并检查服务返回的 `returnValue`，不把“没有响应但退出码为 0”当作部署成功。

### 目标系统要求

部署需要目标机的 `python3`、`ar`、`tar`、`opkg` 和 `luna-send`。
程序加载设备自身的 Qt6（最低 6.4），不附带或升级系统 Qt 库。
安装前检查这些系统包：`qtbase`、`qtbase-plugins`、`qtdeclarative`、`qtdeclarative-qmlplugins`、
`qtmultimedia`、`qtmultimedia-plugins`、`qtwayland-plugins`、`qtwayland-webos` 和 `pulseaudio-misc`。
用户分区的 opkg 数据库不包含系统包，因此用户 IPK 不声明这些系统级 `Depends`，
由部署程序明确检查，避免安装器尝试把系统依赖安装到用户分区。

目标镜像的 `/etc/palm/appinstalld/opkg.conf` 最初缺少 `aarch64` 架构项，
使用该配置的 opkg 只接受 `all`、`noarch` 和默认 `x86_64`，会拒绝正确的 ARM64 原生包。
部署程序只在缺失时，从系统 opkg 的架构列表补入对应原生架构及优先级；
首次修改前保留 `/etc/palm/appinstalld/opkg.conf.musicfox-backup`。
包的架构必须与设备匹配，不把含 ARM64 二进制的包伪装成 `all`。
除这个必要的架构项外，不改桌面配置或全局 PulseAudio 路由。

## 验证与日志

在已安装应用的目标机上：

```bash
APP=/media/cryptofs/apps/usr/palm/applications/org.musicfox.touch/bin/musicfox-touch
PULSE_SERVER=unix:/run/pulse/native "$APP" --smoke-test
PULSE_SERVER=unix:/run/pulse/native "$APP" --test-search 海阔天空
PULSE_SERVER=unix:/run/pulse/native "$APP" --test-audio file:///tmp/test.wav
cat /tmp/musicfox-luneos.log
```

诊断参数使用离屏软件渲染，`--test-audio` 静音播放并检查进度，有超时保护。
正常从系统图标启动时使用设备的 Wayland/GPU 渲染。
测试脚本为 CTest 设置 Qt6 SDK 的库、plugins 和 qml 路径。

```bash
./luneos/test.sh
```

2026-11-15 在 `root@192.168.2.160` 的 LuneOS 1.0、Qt 6.12.0 上验证：

- 本机 14 项 Python 测试、2 项 CTest 通过；真机 C++ 测试 6 项通过。
- 完整 QML 启动与 API 搜索“海阔天空”通过，返回 3 首歌曲。
- 取到真实歌曲的 MP3 URL，经目标机 GStreamer 1.28.2 静音播放，检测到 0.366 秒进度。
- SAM 安装注册和系统启动请求成功；真机 1080×2160 截图确认 MusicFox 主界面正常显示。

`PULSE_SINK` 默认是 LuneOS 的 `pmedia`，`MUSICFOX_PULSE_MONITOR` 默认是 `pcm_output.monitor`。
其他设备或蓝牙路由不同的情况下，可在启动环境中覆盖这两个值；不改全局音频默认值。

## 当前范围

Sailfish 的自定义 Cover 与 Nemo MPRIS QML 插件不包含在 LuneOS 版本中，
LuneOS 使用正常的原生应用卡片。系统锁屏媒体控制、耳机快捷键及完整音频焦点集成需要另行适配。
离屏/静音诊断通过不代表扬声器、蓝牙或输入法已经经过人工体验验证。
