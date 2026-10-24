# AirTune

为墨水屏设计的轻量网络收音机。原创新代码，MIT 许可。`0.1.2` 增加实体上下键音量控制，面向实现 `radio_audio` 能力的固件，需要 CrossMux Lua API 8 与原生 MP3 播放服务。安装状态以 `manifest.json` 为准，运行时检查设备能力，不按机型名称限制安装。Waveshare 3.97 已能播放，实机反馈 100% 音量仍小、声音基本干净，响度验收尚未通过；PaperMono 仍偏小，当前不继续调整其蜂鸣器方案。长时间稳定性仍待实机验收，主机测试不能代替这一步。本次只改输入控制，不改音频处理或增益。

“正在播放”页显示电台、真实连接状态和音量，支持停止、重新收听与收藏。“选台”提供六个 MP3 直播预设；“收藏”最多保存 12 台，可移除或填写名称与 HTTP(S) 地址。横屏采用左右布局，竖屏采用上下布局；触控按钮至少 44 px，交互区域之间至少 6 px。

## 能力与边界

- 依赖 `wifi`、`psram`、`radio_audio`；请求 `network`、`sound`、`keep_awake` 权限。未授权时提示进入商店设置。
- 初始化不会自动播放或连接 Wi-Fi。点“收听”后由原生服务连接或打开网络选择；页面状态以 `radio.status` 为准。
- 首次使用默认音量 50，每次加减 10，范围 0–100；保留已有音量（包括静音 0），不主动改写存档。权限稍后获准时也恢复所存音量。配套新固件将 100 映射为源 PCM 的完整幅度，去掉原来的额外四倍衰减；实际听感还取决于电台和硬件。旧固件的输出上限不会随应用更新而改变。
- “正在播放”页按实体上键加 10、下键减 10；一次按下只调整一次，保持或松开不再重复调整。到达 0/100 边界不写卡。选台、收藏、编辑和删除确认页保留默认按键导航；触摸加减按钮仍可使用，两者共用权限检查和失败提示。
- 仅本机播放 MP3 HTTP(S) 直链，不解析 PLS、M3U、HLS、AAC，也没有搜索、分类、DLNA 或后台播放。旧式 SHOUTcast 的 `ICY 200 OK` 状态行暂不支持，需要普通 HTTP 状态行；HTTP 流里的 `icy-metaint` 元数据可被跳过。广播源不可暂停回到原位置；“重新收听”重新连接当前直播。
- 退出应用或休眠时停止，由原生服务释放音频、连接和保持唤醒资源。允许 `keep_awake` 时，服务仅在播放期间保持唤醒。
- 自定义名称最多 72 UTF-8 字节；键盘输入地址最多 191 字节。预设与持久化地址上限 511 字节。实际编码支持与 URL 校验最终由原生服务决定。

## 数据与内存

收藏使用 `favorite_01` 至 `favorite_12` 独立存储键，每条为 `名称\n地址`，最多 584 字节；另保存 `last_station` 和 `volume`。每次收藏、移除、选台或实际改变音量都检查 `app.write` 结果，写入失败时保留原记录并显示重试提示。音量先保存再送给原生服务；若已保存但硬件设置失败，界面显示扬声器错误和服务实际音量，已保存的值留待下次初始化恢复。撤销网络或声音权限后，按键和触摸均提示授权、不写音量或调用音量设置。取消键盘输入不会提交草稿，未完成的自定义表单不自动保存。

Lua VM 硬上限为 128 KiB，要求 PSRAM；双语界面、预设与函数编译时超过 64 KiB，故不能使用默认预算。主机真实 Runtime 用例测得峰值 87,911 字节（目标设备仍须验证）。没有逐帧网络、缓存或存档写入；状态轮询最多每 500 ms 一次，只有连接状态、错误或音量改变时重绘。接收字节数和服务 revision 改变不会使墨水屏持续刷新。

## 原生接口约定

`app.system` 的返回顺序为 `ok, text, a, b, c, extra`：

| 调用 | 约定 |
|---|---|
| `app.system('radio.start')` | 初始化，不连接 Wi-Fi |
| `app.system('radio.play', url)` | 返回请求是否已排队，不把 `ok` 当作已播放 |
| `app.system('radio.stop')` | 停止并释放播放资源 |
| `app.system('radio.volume', '', value)` | 设置 0–100 的逻辑音量 |
| `app.system('radio.status')` | `ok, state, volume, receivedBytes, revision, errorCode` |

状态为 `idle/connecting/buffering/playing/error`；错误为 `none/invalid_url/unsupported/network/timeout/no_memory/audio/offline/permission`。退出回调 `on_stop` 再次调用停止，允许重复清理。

## 来源与预设验证

选台、收藏、自定义地址与播放状态的功能设计参考本地 `c1max/C1Max/apps/airtune/README.md`；此 Lua 实现、布局、存储与测试均为新写代码，没有复制该项目的 C++ 源码。北京电台名称和蜻蜓地址仅作为公开台站元数据引用。

[SomaFM 官方收听页](https://somafm.com/listen/)提供 Groove Salad、Drone Zone、Secret Agent、Beat Blender 的 MP3 入口。预设地址见 `main.lua`。2026-10-23 逐个请求最多 1,024 字节：两条蜻蜓源返回 HTTP 200，四条 SomaFM 源返回 HTTP 206，均为 `audio/mpeg`。没有下载或打包广播内容。该检查只证明当时端点能返回音频数据，不证明所有网络环境可达，也没有替代固件上的解码与扬声器验收。

预设采用 HTTP 直链；本机 Python 对 SomaFM HTTPS 探测遇到证书链校验失败，没有关闭证书校验。应用仍接受 HTTPS 自定义地址，由固件服务执行实际连接。

`icons/master.png` 为本次项目生成并提供的原创彩色母图；`scripts/prepare_icons.py` 生成六套安装资产及不同尺寸的 2 / 4 / 16 灰阶预览，64 px 的 2 / 4 灰阶版本使用受限抖动。

## 验证

在 CrossStore 根目录运行：

```sh
python3 packages/airtune/tests/test_runtime.py
```

默认从同级 `crossmux` 目录编译真实沙箱 Runtime 与固定 Lua 源码；可用 `CROSSMUX_ROOT` 指向其他固件 checkout。测试覆盖中英文、五种横竖画布尺寸、44 px/6 px 触控约束、保存失败、取消输入、权限拒绝、12 条收藏限制、切台、音量、退出与静态刷新行为。API 8 用例还检查按键消费返回值、其他页面导航回退、0/100 边界、存储/音量服务失败、运行期间撤权及轮询不重复写入。原生收音服务使用有状态 Host 替身，测试不会连接或播放网络广播；实体保持/松开的单次分发由固件输入测试另行验证。

可选生成布局预览（字体近似，不模拟电子纸波形）：

```sh
mkdir -p /tmp/airtune-preview
AIRTUNE_PREVIEW_DIR=/tmp/airtune-preview python3 packages/airtune/tests/test_runtime.py
python3 packages/airtune/tests/render_preview.py /tmp/airtune-preview
```

集成后仍需实机验证六个预设的解码、双声道/音量、断网与取消连接、连续切台、退出/休眠停止，以及屏幕旋转后的字体与触控。
