# MusicFox 迁移到 LuneOS：独立版本与真机验证

首次检查日期：2026-11-14。独立版本实现与部署验证：2026-11-15。
目标：`root@192.168.2.160`，已通过免密 SSH 连接。

## 结论

已新增独立的 `luneos/` Qt6 构建、测试、IPK 打包与部署入口，保留现有 Sailfish OS 版本。
现有 RPM 和 GUI 二进制不能直接使用：它们依赖 Qt5、SailfishApp 和 Silica，目标机提供的是 Qt6。
新版本复用 Go 后端、API、播放队列、歌词、封面缓存、频谱和原有 QtQuick 界面，已在目标机部署运行。

## 已完成版本（2026-11-15）

- 新入口与 Qt6 播放器位于 `luneos/src/`，使用 C++17、QMediaPlayer 与 QAudioOutput。
  LuneOS 需要的 QML/API/封面/频谱变体只生成到构建目录，不改写共享 `app/` 或原 RPM 脚本。
- 本机使用隔离在 `luneos/.sdk/` 的 Qt 6.4.2 原生开发依赖编译；产物在目标 Qt 6.12.0 上运行。
  不向设备复制本机 Qt 库，不依赖目标机安装编译器。
- IPK 内包名与应用 ID 为 `org.musicfox.touch`，文件为
  `luneos/dist/musicfox-touch-luneos_0.5.0-1_aarch64.ipk`。
  由 AppInstallService 安装到 `/media/cryptofs/apps/usr/palm/applications/org.musicfox.touch/`，
  SAM 已注册可见的 MusicFox 启动图标，系统启动请求成功。
- 本机 14 项 Python 测试与 2 项 CTest 通过，真机 C++ 测试 6 项通过；
  完整 QML 启动检查通过，实际搜索“海阔天空”返回 3 首歌曲。
- 真实歌曲 MP3 URL 在目标 GStreamer 1.28.2 后端静音播放，检查到 0.366 秒进度。
  原生 Wayland 卡片创建成功，1080×2160 真机截图确认 MusicFox 主界面正常显示。
- 清理了早期手工启动的测试实例与 `/usr/palm/applications` 中的原型包，
  保留用户应用分区内由系统管理的版本；未重启桌面或设备。

### 安装器适配

单独用 opkg 写入文件并调用旧的 `com.palm.applicationManager/rescan`，不能让 SAM 得知新应用。
部署改用 `com.webos.appInstallService/install` 的订阅通知，等待 `installed`，
再确认 `com.webos.applicationManager/getAppInfo` 与 `launch` 返回成功。
目标 `luna-send` 在非交互 SSH 下会因 stdin EOF 提前退出，辅助程序保持 stdin 打开并校验实际响应。

目标安装器配置缺少 `aarch64`，其独立 opkg 数据库又不包含系统 Qt 包。
部署先校验系统 Qt6/Wayland/PulseAudio 依赖，再按系统的架构列表补齐必要的 `arch aarch64 16`。
原配置已保存在 `/etc/palm/appinstalld/opkg.conf.musicfox-backup`，不修改全局音频路由。
具体构建、部署和诊断命令见 `luneos/README.md`。

### 尚未覆盖

Sailfish 的 Cover 和 Nemo MPRIS 不包含在 LuneOS 版本中，使用普通原生应用卡片。
系统锁屏媒体控制、耳机快捷键和完整音频焦点尚未适配。
扬声器实际出声、蓝牙路由、输入法与长时间后台播放仍需人工真机体验验证。

以下记录首次可行性检查时的环境、实测结果和适配差异。

## 目标环境

- 系统：LuneOS 1.0，设备名 `dumpling`，`aarch64`，Linux 6.1.192。
- 内存约 7.4 GiB，根分区剩余约 10.1 GiB。
- Qt 6.12.0；已有 QtQuick、QtQuick.Controls、LuneOS.Components、QtMultimedia。
- 音频：PulseAudio 17.0，FFmpeg 8.0.1，GStreamer 1.28.2；两个 QtMultimedia 后端均已安装。
- 已有 `qml`、`qmlscene`、`qml-runner`、`opkg`、`python3`、`node`、`parec` 和 `pactl`。
- 已有 `native` 和 `qml` 类型的应用，应用目录为 `/usr/palm/applications`。
- Wayland socket 为 `/tmp/xdg/wayland-0`；现有 QML 应用使用 webOS Wayland shell integration。
- 未发现 `gcc`、`g++`、`qmake`、`cmake` 或 Qt6 开发头文件，不能直接在设备上按现有脚本编译。
- 当前开发机的 `qmake` 对应 Qt 5.6.3，也不能直接生成目标所需的 Qt6 程序。

## 真机实测结果

1. 原 `daemon/musicfox-daemon` 二进制可直接运行，退出码为 0。
   JSON 协议错误处理正常；实际搜索“海阔天空”返回三首 Beyond 歌曲。
2. 原 `app/harbour-musicfox` 启动失败，退出码为 127，缺少 `libsailfishapp.so.1`。
   本地 ELF 依赖检查同时确认其依赖 `libsailfishsilica.so.1` 和多项 Qt5 库。
3. `FrostedBackground`、`GlassPanel`、`VinylDisc`、`BaguaDial`、`KtvLyrics`、`SpectrumBars`
   六个原组件与 QtQuick.Controls 在目标 Qt6 中离屏加载通过，保留原 `QtQuick 2.6` 导入。
   `VinylDisc` 的旧式 Connections 写法产生弃用警告，但没有阻止加载。
4. Qt6 MediaPlayer 使用 FFmpeg 和 GStreamer 两种后端，分别静音播放临时 WAV，
   均有播放进度并到达 `EndOfMedia`，退出码为 0。
5. 单独导入 `Sailfish.Silica 1.0` 和 `org.nemomobile.mpris 1.0` 均失败：模块未安装。

界面测试使用离屏软件渲染，没有验证实际桌面卡片、触摸、输入法或 GPU 渲染。
音频测试验证解码与静音播放进度，不代表已验证扬声器出声、在线歌曲流或系统音频焦点。
探针使用独立 `/tmp` 目录和临时 HOME；目标测试目录与进程均已清理。
首次可行性探针没有安装软件包、修改系统配置或覆盖已有应用；随后独立版本的部署见前面的完成记录。

## 原版与 LuneOS 的适配差异

### 1. 构建和程序入口

`app/harbour-musicfox.pro:1` 使用 Qt5/Silica，配置为 C++14，并链接 `libsailfishapp`。
新增使用 C++17 的 Qt6 构建配置，移除 LuneOS 构建中的 Sailfish 链接依赖。
`app/src/main.cpp:50` 和 `app/src/main.cpp:63` 使用 SailfishApp 创建应用及视图，
LuneOS 入口应改为标准 Qt6 应用/视图或 QML engine，并适配原生应用标识和 webOS 窗口环境。
使用与目标镜像兼容的 LuneOS/OpenEmbedded SDK 或 Yocto 构建环境，不复用当前 Qt5 开发机产物。

### 2. 播放器的 Qt6 API

实际编译的播放器是 `app/src/mpvcontroller.cpp:4`，使用 QMediaPlayer，并不依赖 libmpv。
保留对 QML 暴露的接口，内部迁移到 Qt6：

- `setMedia(QMediaContent(...))` 改为 `setSource(QUrl(...))`。
- 音量交给独立 `QAudioOutput`，换算原有整数音量到 0–1 范围。
- `state()` / `stateChanged` 改为 `playbackState()` / `playbackStateChanged`。
- `QMediaPlayer::State` 改为 `QMediaPlayer::PlaybackState`，错误处理使用 `errorOccurred`。
- 移除 `setNotifyInterval`，使用 Qt6 播放进度信号，必要时单独实现界面刷新定时器。

`app/src/playback.cpp:1` 是另一套旧播放器，不在当前 `.pro` 的编译列表中；
不要为了移植把未使用的旧实现一并引入。

### 3. 主窗口和系统集成

`app/qml/harbour-musicfox.qml:1` 需要替换 Silica ApplicationWindow，
移除 Sailfish 专属的 `allowedOrientations`、CoverBackground、CoverActionList 和 Theme 引用。
主界面大量使用纯 QtQuick，优先保留布局与组件，而不是重写整个 UI。
`app/qml/harbour-musicfox.qml:117` 的 Nemo MPRIS QML 模块不可用：
初版可先去掉这层集成，后续单独实现 MPRIS 或接入 LuneOS/Luna 系统服务。
Sailfish Cover 的播放按钮和 LuneOS 卡片/通知/锁屏控制不能按相同接口直接替换。

### 4. 音频路由与频谱

目标机存在 `pmedia.monitor`、`pdefaultapp.monitor` 和 `pcm_output.monitor` 等源，
但 `app/src/pulselevels.cpp:100` 只接受 `sink.*.monitor`，原逻辑会过滤掉目标机的这些源。
需要按 LuneOS 的实际播放路由选择监视源，不能仅复制原 Sailfish 名称规则。
同时验证播放流的媒体角色、扬声器/蓝牙路由，以及与其他应用的音频焦点行为。

### 5. 部署与后端路径

新增 LuneOS 的 `appinfo.json` 和 native 应用目录，先做可回滚的目录部署，后续再打 IPK。
现有 RPM、`.desktop` 和 `X-Nemo-Application-Type=silica-qt5` 不能替代 LuneOS 应用清单。
`app/src/neteaseapi.cpp:27` 的后端路径查找需要支持新安装布局：
优先查找应用目录内的 `musicfox-daemon`，避免依赖 Sailfish 的 `/usr/libexec` 路径。
现有 aarch64 Go 后端已验证可复用；如需要重新构建，再保留对应 Go 模块和本地 replace 依赖。

## 最初推荐的实施顺序

1. 准备目标兼容的 Qt6 SDK，新增独立构建入口和 LuneOS native 应用清单。
2. 保留现有 Go 后端，完成 Qt6 启动入口、播放器和主窗口适配。
3. 真机验证搜索、获取播放链接、在线播放、暂停/跳转、封面和歌词。
4. 验证实际窗口显示、卡片行为、触摸输入、后台播放与扬声器/蓝牙路由。
5. 最后适配频谱、系统媒体控制和 IPK 打包；不改动现有 Sailfish 部署方式。
