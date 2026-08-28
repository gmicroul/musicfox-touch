# MusicFox — 真机部署与 Cover 测试清单

## 1. 把 RPM 传到真机

前提：真机已开启开发者模式（`Settings → Developer tools → Remote connection`），并能在开发机上 SSH 连接。

```bash
RPM=harbour-musicfox-0.1.0-9.aarch64.rpm
DEVICE=nemo@<真机IP>        # 例如 nemo@192.168.2.15
scp "$RPM" "$DEVICE:/tmp/"
ssh "$DEVICE" "devel-su rpm -i --force /tmp/$RPM"
```

> 手动 `--force` 是为了覆盖旧版本（非正式签名包）。
> 卸载旧版：`ssh "$DEVICE" "devel-su rpm -e harbour-musicfox"`

## 2. 启动并验证

```bash
ssh "$DEVICE" "devel-su /usr/bin/harbour-musicfox"
```

或直接从应用桌面图标启动。

若启动失败，读取日志：
```bash
ssh "$DEVICE" "cat /tmp/musicfox.log"
```

## 3. 验证 Cover（系统桌面卡片）

这是本次改造的核心目标，按顺序检查：

1. 在 MusicFox 里搜索并**播放一首歌**（确认有封面、正在播放）。
2. 按 **Home** 键回到主桌面 → **MusicFox 应立即变成一张卡片**（而不是普通窗口缩略图）。
3. 检查这张卡片是否显示：
   - **正在播放歌曲的封面图**
   - **歌名 / 歌手**
   - 下方 **播放控制快捷按钮**（上一首 / 播放·暂停 / 下一首 / 随机）
4. 直接点卡片上的 **播放/暂停** 按钮 → 音乐应暂停/恢复。
5. 点 **下一首** → 应切歌，卡片封面同步更新。

## 4. 成功 / 失败判定

| 现象 | 判定 |
|------|------|
| 桌面卡片显示封面 + 控制按钮，按钮可控制播放 | ✅ 成功 |
| 卡片还是旧版窗口缩略图（无封面、无按钮） | ❌ cover 未生效，看日志 |
| 应用启动即崩溃/闪退 | ❌ 看 `/tmp/musicfox.log` |

## 5. 排查要点

- 日志里若出现 `Failed to load QML` 或 Silica 相关报错 → 把 `/tmp/musicfox.log` 完整内容发给开发者。
- 若卡片无内容（空白），检查 daemon 是否在跑：`ssh "$DEVICE" "pgrep -a musicfox-daemon"`
- 确认桌面文件类型：`grep X-Nemo-Application-Type /usr/share/applications/harbour-musicfox.desktop` 应为 `silica-qt5`
