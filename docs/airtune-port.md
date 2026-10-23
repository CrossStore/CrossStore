# AirTune 迁移检查

> 当前进度：首版 Lua 包与原生 MP3 播放服务已完成，只有 PaperMono 实验固件启用。下文前半部分保留改造前的源码审计；最新行为以 [应用 README](../packages/airtune/README.md) 为准。音质与长时间播放仍待实机验收。

检查日期：2026-10-23。以下现状是审计时点的记录；后续开发进度见文末。尚未发布可用的 CrossStore AirTune 应用。

目标是让设备实际播放网络电台，并保留目录、搜索和收藏功能。只有目录列表、无法播放的版本不能标为 `ready`。迁移需要 Lua 应用和固件原生音频服务共同完成；不能把 C1Max 的 Linux 可执行文件直接装进 ESP32。

本文源码位置以两个本地仓库为准：`C1Max:` 表示 `~/Workspace/c1max/C1Max/`，`CrossMux:` 表示 `~/Workspace/crossmux/`。行号为本次检查时的位置。

## 可保留的应用逻辑

| 功能 | 当前实现 | 迁移方式 |
| --- | --- | --- |
| 电台目录 | 热门、国家、流派、心情、广播集团、收藏、搜索 | Lua 展示和交互，原生服务返回有限条目；按屏幕尺寸重做布局 |
| 静态分类 | 12 种心情、20 个广播集团；集团实际上按台名搜索 | 保留分类语义，不把名称匹配解释为官方集团归属 |
| 预置台 | 13 个蜻蜓 FM MP3 地址和 Radio Suara Kupang FM，共 14 个 | 保留名称和 URL，发布前逐一验证；本次未验证地址仍可播放 |
| 收藏 | 自定义名称、HTTP(S) URL、UUID、码率；支持新增、删除、本地搜索 | 保存到应用私有数据目录，保留已有收藏，不随应用更新覆盖 |
| 分类缓存 | 国家、流派缓存 6 小时，先显示旧数据再刷新；内容未变化时不重绘 | 保留缓存优先行为，增加明确的条目和字节上限 |
| 播放控制 | 连接中、播放、暂停、停止、错误、音量、默认关闭的后台开关 | 状态来自真实播放服务，不能靠计时器模拟“已播放” |

依据：`C1Max:apps/airtune/src/main.cpp:30–49`、`:222–240`、`:244–303`、`:408–436`。原界面使用固定坐标和 26/27 px 控件，不能直接用于 CrossMux 的触摸界面（`:308–395`）。

收藏文件为 `/storage/apps/data/airtune/saved-stations.json`，结构如下：

```json
{
  "version": 1,
  "stations": [
    {"name": "电台名称", "country_code": "CN", "url": "https://example.org/live.mp3", "uuid": "", "bitrate": 64}
  ],
  "legacy_ids": []
}
```

当前实现按 UUID 或 URL 去重，首次载入预置台，尝试解析旧 `favorites.json` 的 UUID；损坏的新文件另存为 `.recovery.json`。迁移可以兼容此结构，但不能照搬读取整份 256 KiB JSON 的方式。依据：`C1Max:apps/airtune/src/main.cpp:128–160`。

## 公开目录 API

当前源码先查询 `all.api.radio-browser.info`，通过反向 DNS 获得镜像名，再轮换 HTTPS 主机；每次请求设置应用 User-Agent，失败换主机，`de1.api.radio-browser.info` 只是兜底（`C1Max:apps/airtune/src/main.cpp:180–205`）。

| 用途 | 路径 |
| --- | --- |
| 热门、名称搜索、集团搜索 | `/json/stations/search?limit=16&hidebroken=true&order=clickcount&reverse=true`，需要时追加 `name` |
| 国家电台 | `/json/stations/bycountrycodeexact/<code>` |
| 流派、心情电台 | `/json/stations/bytagexact/<tag>` |
| 国家、流派分类 | `/json/countries`、`/json/tags`，按 `stationcount` 排序，限制 100 条 |
| 旧收藏解析 | `/json/stations/byuuid?uuids=<ids>` |
| 用户实际开播计数 | `/json/url/<stationuuid>` |

官方要求镜像发现、可识别的 User-Agent，以及用户开播时的计数请求；不能把一次浏览算成开播。现有 README 声称已发送计数，但 `play()` 只调用 c1audio，本次未在应用或共享音频代码找到 `/json/url` 实现，迁移时应补齐。依据：`C1Max:apps/airtune/README.md:13`、`C1Max:apps/airtune/src/main.cpp:430–436`；[官方接入说明](https://api.radio-browser.info/)、[API 参考](https://docs.radio-browser.info/#station-click-counter)。

## 必须替换的 Linux 依赖

- `c1audio` 通过 Unix `SOCK_SEQPACKET` 连接独立守护进程，使用 `fork/exec` 和进程身份维护后台生命周期：`C1Max:apps/shared/audio_client.c:17–43`。
- `c1max-audio` 启动 `/usr/bin/mplayer`，采用 slave 控制、128 KiB 启动缓存和 5% 起播阈值；解码、流格式和输出由 MPlayer 处理：`C1Max:apps/shared/audio_service.cpp:82–110`。暂停、退出、后台保留等在 `:123–175`。
- 目录 HTTP 调用会生成临时文件并启动 `wget`，响应可累计到 1 MiB；不能移入 ESP32：`C1Max:apps/shared/net.cpp:54–84`。
- 音量读取依赖 tinyalsa mixer；界面依赖 LVGL/Linux framebuffer：`C1Max:apps/airtune/src/main.cpp:102–107`、`C1Max:apps/CMakeLists.txt:197–199`。
- Google Cast/DLNA 是独立的接收器服务和协议栈，不能视为现有 CrossMux 能力。它也不是“本机播放失败后的自动回退”：`C1Max:apps/shared/audio_service.cpp:87–94`、`C1Max:apps/airtune/README.md:25–39`。

## CrossMux 已有能力与缺口

SDK `AudioManager` 已有连续 PCM/WAV 回调播放：16-bit little-endian，单/双声道，8–48 kHz。部分 ES8311 外部时钟配置仅接受 16 kHz，需要解码后重采样。依据：`CrossMux:freeink-sdk/libs/hardware/AudioManager/include/AudioManager.h:32–63`、`src/AudioManager.cpp:249–253`（后者位于同一 AudioManager 库）。

`HalAudioOutput` 已封装 PCM 回调，但仅在 `CROSSPOINT_CAP_SOUND_FEEDBACK` 目标编译；不能由此认定所有有声音的机型都能播电台。Lua 的 `sound(cue)` 目前调用短音效 `HalBuzzer::play()`，没有音频文件或网络流播放 API。依据：`CrossMux:lib/hal/HalAudioOutput.cpp:3–53`、`CrossMux:src/activities/apps/appstore/LuaAppActivity.cpp:436–440`、`CrossMux:platformio.ini:769–781`。

本次检查未找到可直接复用的 MP3/AAC 解码器、HTTP/ICY 播流器或网络收音机服务。现有 `NativeService` 提供前台适配器模式，可参考它把阻塞网络操作放在 Lua 回调之外；持续后台播放还需要独立服务生命周期，不能持有已销毁 Activity 的指针。依据：`CrossMux:src/activities/apps/appstore/LuaNativeService.h:9–23`。

### Mono 需要单独补连续输出

Mono 板级配置是 GPIO42、无 codec 的蜂鸣器输出；当前短 PCM 路径允许 24 kHz、最长 200 ms，并有 400 ms 阻塞期限。它可以播放木鱼短音效，但没有接通 `AudioManager` 的持续 PCM 输出。依据：`CrossMux:freeink-sdk/libs/hardware/BoardConfig/include/BoardConfig.h:1129–1142`、`CrossMux:freeink-sdk/libs/hardware/Buzzer/src/Buzzer.cpp:74–84`、`:111–145`。

若将 Mono 列为支持机型，必须实现并验证连续输出，检查音质、断流恢复、功耗与长时间播放稳定性。不能把官方 Speaker 类名或当前 `audio` 标记等同于经过验证的高保真扬声器。本次没有播放电台或实测音质。

## MP3 首版契约

1. **完整闭环**：安装后可浏览或搜索、选择电台、实际听到声音、调节音量、暂停/恢复和停止；收藏与自定义 URL 可持久化。启动应用不自动播放。
2. **格式边界**：首版支持 HTTP/HTTPS MP3 直播流。解析 `codec`、`hls` 等目录字段并检查实际流，遇到 AAC、HLS、未知或损坏格式明确报错；不把所有 HTTP URL 标成可播放。现有 AirTune 没有保存 `codec/hls`，需要补充（`C1Max:apps/airtune/src/main.cpp:207–215`；[官方 Station 字段](https://docs.radio-browser.info/#station)）。
3. **原生播放链路**：有界 HTTP/HTTPS 读取 → 重定向和 ICY 元数据处理 → 压缩数据环形缓冲 → MP3 解码 → 必要的采样率转换 → HAL 连续 PCM。音频字节不穿 Lua，不把直播音频持续写入 TF 卡。解码库尚未选定，需核对许可证、当前 ESP-IDF 兼容性与实际预算。
4. **真实状态与取消**：连接、缓冲、播放、暂停、停止、失败可区分；断网、证书错误、无效格式和超时可退出或重试。底层 PCM 回调返回 0 表示结束，临时缺数据不能误报 EOF；网络等待也不能无限阻塞停止。依据：`CrossMux:freeink-sdk/libs/hardware/AudioManager/include/AudioManager.h:40–46`、`src/AudioManager.cpp:520–527`。
5. **后台与电源**：后台默认关；关闭时退出应用停止。允许后台后可返回阅读，并在重新打开时恢复真实状态；休眠、卸载及权限撤销要停止流并释放资源。保持唤醒必须单独获授权，不能让目录刷新永久唤醒设备。暂停后的直播恢复应定义为重新接入直播，不承诺保留全部暂停内容。

### 首版本机播放不支持的协议

首版限定使用 HTTP 状态行的 HTTP/HTTPS MP3 流，不支持 AAC、HLS 或播放列表解析。`icy-metaint` 音频间插元数据可以在 HTTP 响应中处理，但旧 SHOUTcast 的 `ICY 200 OK` 状态行不在首版范围：现有 `SecureHttpClient` 按 `HTTP/1.x 200 OK` 的固定位置取状态码，不能据此解析 ICY 状态。此类地址会失败，不应在应用中宣称已支持。

依据：`CrossMux:src/services/radio/Player.cpp:107–119`、`CrossMux:src/services/radio/StreamFormat.cpp:38–76`、`CrossMux:freeink-sdk/libs/network/SecureNet/include/SecureHttpClient.h:229–230`。本次不扩大共享 HTTP 解析器的协议范围。

## 能力与权限分别声明

能力回答“固件和硬件是否能完成此功能”，权限回答“用户是否允许本应用使用它”。两者不能互相代替。

- 建议首版支持条件：Wi-Fi、PSRAM、应用存储，以及已实现且通过验收的连续 PCM 和 MP3 播流服务。后两项尚无正式能力键/API 版本，须先在固件与打包校验器中定义，再写入 manifest。
- 不能仅依赖现有 `audio`：当前代码也将 `HalBuzzer::supportsPcm()` 算为 `audio`，会误放行 Mono 短音效路径。依据：`CrossMux:src/crossstore/Package.cpp:41–46`。
- 播放需要用户授权 `network` 和 `sound`；后台保留、保持唤醒分别使用 `background`、`keep_awake`。拒绝后台权限仍应允许前台播放；拒绝播放权限可以浏览本地收藏，但不得偷偷播音或联网。
- `radio` 权限用于现有无线射频接口，不表示网络收音机。AirTune 是收听应用，不需要麦克风权限。不能为迁移预授予权限。

现有权限表：`CrossMux:src/crossstore/Permissions.h:13–23`。未知能力名会被拒绝，内存声明超过 64 KiB 必须要求 PSRAM：`CrossMux:src/crossstore/PackageManifest.cpp:69–88`。

## 内存、Flash 与验收记录

现有上限和成本不能当作新增服务的可用余量：

| 项目 | 已核对的事实 / 后续测量 |
| --- | --- |
| Lua | 源码上限 32 KiB，VM 上限 128 KiB；只装界面状态与当前页元数据，不装解码器、整流或整份大 JSON。`CrossMux:lib/CrossStoreRuntime/CrossStoreRuntime.h:15–16` |
| PCM 任务 | 当前任务栈 8 KiB；其中包含 1 KiB 输入和 2 KiB 输出数组，不能重复计为栈外缓冲；另有 SDK DMA、任务控制块。`CrossMux:freeink-sdk/libs/hardware/AudioManager/src/AudioManager.cpp:19`、`:376–378`、`:438–442` |
| 压缩缓冲 | 可从 32 KiB 环形缓冲评估；128 kbps 时约容纳 2 秒，仅为容量计算，不代表已验证的抗抖动表现 |
| 原生服务 | 实测解码器、TLS、连接、环形缓冲、元数据解析的峰值；区分内部堆、PSRAM 和 DMA 内存，记录最小剩余内部堆、最大连续块、任务栈余量和播放中断次数 |
| OTA Flash | 当前分区单槽 `0x640000`，即 6.25 MiB；新增库后按目标记录固件大小和剩余量，不能引用旧构建的余量保证可用。`CrossMux:partitions.csv:4–5` |

建议分三步实施：先完成单路 MP3 播流和一个目标的连续输出验证，再接目录/收藏 Lua 界面，最后接后台与跨机型能力检查。验收至少包括连续播放、切台、暂停/恢复、断网重连、拒绝权限、退出、休眠和更新后收藏保留；录下实测资源数据。Mono 额外验收连续输出质量。有完整播放闭环且目标验收通过后，才发布 `ready` 包；阶段性目录原型留在开发状态。

## 许可与本次检查边界

Radio-Browser 官方允许自由及非自由软件调用 API，站点声明目录数据为 public domain；目录许可不等于其指向广播音频的授权，也不代表服务可用性承诺。[官方使用说明](https://api.radio-browser.info/)、[站点数据许可说明](https://www.radio-browser.info/?lang=en)。

本次在 AirTune 目录及 C1Max 顶层未找到该应用自身的 `LICENSE` 或明确授权声明；第三方目录中的许可证不能替代应用许可。公开迁移源码前应明确其许可证，并逐项保留所选音频库的许可说明，不能直接宣称 AirTune 是 MIT。

本次只审计源码与官方文档，未新增固件依赖、应用包或权限；未连接音频流、录音或测量实际音质、功耗、解码性能及新增固件体积。

## 后续实施进度：Mono 本机输出基础

2026-10-23，用户选择优先本机收听后，已在工作区新增 `HalRadioAudio` 与 SDK `Buzzer` 的连续 PCM 基础。该项不代表 MP3、网络服务、完整应用或实机验收已经完成。

- `CrossMux:lib/hal/HalRadioAudio.h` 提供 `supports/begin/write/setVolume/end`。当前只对 Mono S3 提供输出；固定 24 kHz、16-bit 单声道，解码服务负责必要的采样率转换。
- 与短音效共用一个 Buzzer 实例，播放时短音效和通用 shutdown 不抢占；开始、写入、结束由同一个 worker 调用，前台只通过原子值调音量。每次写入最多 1024 samples，DMA 等待预算 100 ms，单次等待至多 20 ms；结束淡出与排空的 DMA 等待预算 40 ms，随后清理驱动和拉低引脚。
- DMA 数据仍为 `3 × 64 × 4 = 768` 字节，另有 SDK 控制结构；没有新建音频任务或源数据缓存，每次编码使用 256 字节栈缓冲。失败保留必要句柄用于清理重试，不把仍被驱动持有的引脚交给短音效。
- `MAX_STREAM_GAIN_PERCENT = 25` 是尚未实测校准的临时电平上限：UI 音量 100 对应 25% PCM 增益，UI 音量 25 对应 6.25%。首次本机测试从 UI 音量 25 开始；这不是音质、功率或温升验证结论。
- `CrossMux:test/buzzer_pcm/test_stream.py` 编译真实驱动和 HAL，覆盖长于短音效上限的连续写入、跨块编码连续性、静音/音量、占用拒绝、超时、失败清理以及 Mono/其他 S3/无蜂鸣器/模拟目标；原短音效回归由 `test_buzzer.py` 保留。主机测试通过，尚未验证实际电台声音。

## 首版整合结果

已完成新写的 `packages/airtune` Lua 应用（未复制 C1Max 未明确授权的源码）、固定版本 minimp3/CC0 解码器、HTTP MP3 播放服务与 Mono 连续 PCM。6 个预设、自定义 URL、12 收藏、五档音量及横竖界面已经通过真实 Lua VM 测试，峰值 86236 B / 128 KiB。网络字节不进入 Lua、不落盘；仅收藏与设置写入应用数据区。

MP3 解码/分片、ICY 元数据、24 kHz 时间轴与997 Hz音高、线程失败/取消/回收测试以及 ASan/UBSan 均通过。每个播放会话使用32KiB PSRAM任务栈，decoder state 6668B，另有有界压缩输入、PCM与重采样缓存。工作区在流结束时释放，已挂起任务的栈在下一次stop/start/退出时回收；不是每帧分配。DNS取消仍受Arduino/lwIP重试时间限制。共享HTTP响应头另限制16KiB和64字段，避免无限增长。

API 6的 `radio_audio` 与普通短音效 `audio` 分开，当前只在 `papermono_store` 中启用；PaperS3/C3仍编译验证，但不提供本机电台播放。6.25MiB OTA槽继续沿用，无需改分区。构建结果与实机验收状态保存在 CrossMux `build/crossstore-validation/` 的相应manifest中。
