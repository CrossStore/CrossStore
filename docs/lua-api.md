# Lua API 5（实验）

`main.lua` 返回回调表。API 5 保留 API 1–4 接口，增加阅读日期/成就与微信读书本地章节的只读查询。API 4 增加退出前的 `on_stop` 回调；API 3 提供点阵、图片呈现、文件导出和前台网络服务。应用需声明它实际使用的最低 API 版本。

```lua
return {
  on_start = function()
    app.clear()
    app.title(app.tr("Hello", "你好"))
    app.canvas()
    local width, height = app.size()
    app.text(0, 20, width, 60, app.tr("Welcome", "欢迎"), 2, 1)
    app.button(1, 0, height - 60, width, 52, app.tr("Close", "关闭"), 0)
  end,
  on_select = function(action, gesture, x, y)
    if action == 1 then app.exit() end
  end,
}
```

## 生命周期与输入

回调包括 `on_start()`、`on_resize()`、`on_tick()`、`on_select(action, gesture, x, y)`、`on_input(_, text)`、`on_swipe(_, direction)`、`on_network(success)`、`on_back()`。`on_tick` 约每 500 毫秒调用；没有后台 Lua VM。系统休眠时不接收聊天消息。

API 4 的可选 `on_stop()` 在正常退出、返回主页、进入系统休眠或活动栈清理时，关闭仍正常运行的 VM 之前调用一次。用于补存内存里的修改；遵守同样的执行限额。它不能取消系统休眠，失败会记入串口日志。断电、重启或已发生脚本错误时无法保证调用，因此仍应定期保存。

2048 0.3.0 只在内存里更新棋盘：停止操作 2 秒后保存；连续操作每 10 秒检查点保存；退出/休眠前补存。失败保留待保存状态并显示标题提示，2 秒后重试；最高分仅在提高时写入。突然断电可能丢失最近尚未保存的操作。

触摸坐标以画布左上角为原点；长按的 gesture 为 `long`。实体按键选择同一交互控件，此时坐标为 -1。画布应用必须处理 `on_resize`，不得假定设备尺寸。`on_back` 未定义时由系统返回；自己处理时使用 `app.exit()` 结束应用。

## 基础接口

| 接口 | 说明 |
| --- | --- |
| `app.title(text)` / `app.clear()` | 设置标题；清空画面、交互区域和说明文本 |
| `app.row(label, value)` / `app.grid(columns)` | API 1 列表或 1–6 列网格，最多 32 项 |
| `app.caption(text)` | API 1 说明或数值 |
| `app.tr(en, zh)` | 跟随系统语言 |
| `app.has(capability)` | 查询设备/固件能力，不表示已授权 |
| `app.allowed(permission)` | 同时检查清单声明与用户授权 |
| `app.millis()` | 开机时间计数 |
| `app.read(key)` / `app.write(key, value)` | 应用私有文本，单值最多 2 KiB、最多 32 键；写入返回成功与否 |
| `app.asset(path, offset, length)` | 读取包内 `assets/` 资源；资源最多 32 KiB，每次最多 2048 字节；失败返回 nil |
| `app.input(title, initial)` | 系统键盘；结果进入 `on_input`，最多 191 UTF-8 字节 |
| `app.notify(text)` | 需要 notifications 权限；点击系统通知可回到应用 |
| `app.open(route)` | 打开 library、file_transfer 或 opds 核心入口；opds 需要 network 权限 |
| `app.context()` | 通知打开应用时的会话 ID，普通启动为空 |
| `app.sound(cue)` | 需要 sound 权限；固定 `woodfish` / `click` 短音，返回是否播放；无蜂鸣器时返回 false。支持的 S3 蜂鸣器使用固件内置木鱼 PCM 采样，其他蜂鸣器保留提示音；此接口不接收任意 WAV/MP3 路径 |
| `app.exit()` | 返回上一级 |

## 画布

`app.canvas()` 启用画布，`app.size()` 返回可用宽高。标题和系统返回区域由宿主负责。画布灰度参数 0 表示黑，15 表示白；当前基本图形映射为主题的四级灰度，设备不支持灰度时按宿主方式退化。应用图标另有 2/4/16 灰阶资源。

| 接口 | 参数 |
| --- | --- |
| `app.box(x,y,w,h,gray=0,radius=0,stroke=0)` | stroke=0 填充，否则绘制边框 |
| `app.circle(x,y,w,h,gray=0,reserved=0,stroke=0)` | 圆形/圆角胶囊；用相同宽高画圆 |
| `app.line(x,y,w,h,gray=0,reverse=0,stroke=1)` | 正宽高包围盒的对角线；reverse=1 从左下到右上 |
| `app.text(x,y,w,h,text,font=1,align=0,gray=0)` | font：0 小字、1 正文、2 标题、3 大数字；align：0 左、1 中、2 右 |
| `app.measure(text,maxWidth,font=1)` | 返回实际主题字体的排版宽高；text 最多 255 UTF-8 字节 |
| `app.button(id,x,y,w,h,label,style=0)` | style：0 描边、1 平面、2 浅灰、3 黑底 |
| `app.hit(id,x,y,w,h)` | 不绘制的交互区域，常用于棋盘 |
| `app.qr(x,y,size,text)` | 一帧一个二维码；固定版本 5/M、API 2 最多 96，API 3 最多 384 字节，包含四模块留白 |

每帧最多 512 条绘制命令、8192 字节文本、24 个交互区域。交互 ID 不重复，区域不得重叠或越界；相邻控件至少保留 6 px 间隔。棋盘使用一个区域，再在 Lua 中计算格子。画布命令保存在宿主约 20 KiB 的活动缓冲中，绘制任务不执行 Lua。

## 聊天服务

`app.chat(command, argument="", index=0, text="")` 返回 `ok, text, a, b, c, extra`。通信、消息存储和唤醒期间后台监听由固件服务负责；页面、气泡、导航、输入与状态提示在 Lua 中。

| command | 入参 / 返回 |
| --- | --- |
| start | argument 为 radio / wifi / esp_now；需要 radio 或 network 权限及 lora / tox / esp_now 能力；Wi-Fi 选择完成回调 on_network |
| snapshot | text=状态，a=修订号，b=好友数，c=消息数，extra=本机完整 ID |
| contact | index 从 1 开始；text=ID，a=在线，b=待接受请求 |
| nearby_count / nearby | 数量 a；nearby(index) 返回完整 ID |
| message | index 从 1 开始；text=内容，a=送达状态，b=32 位消息 ID，c=接收设备数，extra=会话 ID |
| add_result | a 为最近添加好友结果 |
| add / discover | argument=好友 ID / 无参数 |
| send | argument=会话 ID，text=消息；返回是否入队，不代表送达 |
| retry | argument=会话 ID，index=消息 ID |
| viewing | argument=正在阅读的会话，空串取消；清除对应未读通知 |
| background | argument=on/off/空串；a=是否开启，开启需要 background 权限 |

公共会话 ID 为 `*`。状态依次为 stopped、starting、online、connecting、failed、storage_error。送达状态：0 收到、1 发送中、2 广播已发出、3 已送达、4 失败。

当前三个原生传输服务的身份和后台通知归属固定为 `rf_chat`、`wifi_chat`、`esp_chat`；此桥接用于这三个官方包，尚不提供第三方聊天应用的独立账户隔离。关闭后台或撤销通信权限会停止对应后台监听；休眠统一停止，唤醒后按授权恢复。

## 系统数据

`app.system(command, argument="", index=0)` 同样返回 `ok,text,a,b,c,extra`。

| command | 返回与权限 |
| --- | --- |
| device.time | 已校准时钟：text=HH:MM，extra=YYYY-MM-DD，a=星期（0 周日），b=秒，c=Unix 时间；时钟无效返回 false |
| device.battery | a=电量百分比 |
| device.id | 需要 device_info；text=12 位小写十六进制设备标识 |
| reading.summary | 需要 reading_data；a=累计、b=今日、c=近七天阅读毫秒 |
| reading.counts | a=读过书籍数、b=读完数、c=连续天数 |
| reading.goal | a=每日目标毫秒、b=最长连续天数、c=阅读日期数 |
| reading.day | index 从 1 开始；a=日期序号、b=阅读毫秒 |
| reading.book | index 从 1 开始；text=书名、extra=作者、a=阅读毫秒、b=百分比、c=是否完成 |
| reading.open | index 为书籍序号；交给核心阅读器继续阅读 |

API 5 增加以下命令，均要求 `reading_data`，不写入或重建统计：

| command | 入参 / 返回 |
| --- | --- |
| reading.calendar | argument 为空或 YYYY-MM；text=月份、a=月初日期序号、b=月内天数、c=参考日期序号；无可信时间且无日期历史时，空参数请求返回 false |
| reading.date | index=日期序号；text=YYYY-MM-DD、a=日期序号、b=该日阅读毫秒 |
| reading.date_book | argument=十进制日期序号（前缀 `-` 表示倒序），index=从 1 开始的书籍游标；a=匹配的书籍序号或 0、b=该书当天毫秒、c=下一游标或 0；单次最多扫描 32 本书，a=0 且 c 非零时应继续分页查询 |
| reading.book_detail | index=书籍序号；text=章节名、a=阅读次数、b=上次阅读毫秒、c=章节进度百分比；extra 为首次/最近/完成日期，以 `\|` 分隔，未知日期留空 |
| reading.achievements | a=成就总数、b=已解锁数、c=系统是否启用成就；关闭时数量为零 |
| reading.achievement | index=从 1 开始的成就序号；text=本地化标题、a=系统指标类型、b=目标、c=是否解锁、extra=解锁日期；关闭成就时返回 false |

日期序号沿用核心统计的本地日序，支持 1970–2106 年；书籍游标指向系统书籍表，不是日期内的排名。成就指标值取自固件的 `AchievementMetric` 枚举，客户端可以使用本地化标题和目标，不应据此伪造当前进度。

## 运行限制

仅开放基础库、table、string、math、utf8 的受限子集。没有 io、os、package、debug、coroutine；禁用动态加载、pcall/xpcall、collectgarbage、string.dump 和模式匹配系列函数。不能使用套接字或访问任意存储路径。

每个回调最多 100000 条 Lua 指令或约 100 毫秒脚本执行时间。同步存储、资源读取、文字测量、系统/聊天服务和声音调用的宿主耗时单独累计，单回调最多 1500 毫秒，不挤占脚本的时间限额。这个累计检查发生在宿主函数返回后，无法中断正在阻塞的驱动；驱动仍须有自己的超时。

VM 配额为 16–128 KiB；超过 64 KiB 必须声明 psram。具备 PSRAM 的宿主将 VM 分配放到 PSRAM，失败不自动挤占内部堆。配额不含宿主画布、图标、协议服务与网络缓冲；这些各有独立上限。超限停止应用并报告错误。这是开发预览的故障隔离措施，尚未完成安全审计。

## API 3：绘图、时钟与文件

- `app.raster(x,y,w,h,sourceWidth,sourceHeight,shades)`：每个源像素一个大写十六进制字符 `0..F`，行优先。源宽高各 1–128，总字节最多 8191，并与其他文字共用画布 8192 字节额度。按设备主题灰阶显示；它不是额外的全屏缓冲区。
- `app.system("canvas.export", basename)`：需要 files_export。排队导出当前图形到 `/CrossStore/<id>/<basename>.svg`，单个应用最多 32 个文件。basename 遵循包 ID 字符规则。完成回调 `on_export(success, path)`。忽略按钮与点击区；暂不支持 QR 和 raster 导出。文本为 SVG 系统字体，布局不保证与设备字体逐像素一致。
- `app.system("power.keep_awake", "on"/"off")`：开启需要 keep_awake；仅在本应用前台有效。它不是低功耗休眠，也不启用后台 Lua。
- `app.system("device.sync")`：需要 network，异步校时。缺少连接时打开系统 Wi-Fi 选择器，返回 false/connecting；应用在 `on_network(1)` 后重新请求。`device.sync_status` 返回是否结束，text 为 success/failed，15 秒超时。释放应用自己开启的 Wi-Fi，并保留已获授权的聊天后台收听。
- QR 最多 384 UTF-8 字节；宿主按长度选择 QR 版本。必须预留至少每模块 2 像素及四模块静区。

## API 3：前台网络服务

以下命令通过 `app.system(command, argument, index)` 调用，返回仍为 `ok,text,a,b,c,extra`。每个应用同时只能持有一种前台服务。网络步骤在 Lua 回调之间执行，不计入 Lua 的 100 毫秒执行窗口；退出或脚本失败后释放服务。没有后台 Lua 定时器。`on_service()` 通知应用查询新状态；`on_tick` 可以轮询有界快照。图片显示时用 `on_image` 处理点击，`on_back` / `on_swipe` 仍由 Lua 决定。

### 公共像素画布

需要 network；首次 `pixel.start`，后续 `pixel.status` 返回连接状态、a=画面版本、b=待发点数、c=限速剩余毫秒。`pixel.row` 的 index 为 0–99，返回 60 个灰阶字符。`pixel.place` 的 argument 为 0–3（白到黑），index 为显示坐标 `y*60+x`。两秒合并发送、每十秒最多十点；断线回滚待发点，新快照会重放本地尚未发送的修改。数据使用原有公共 MQTT 协议；应用应清楚说明内容将公开共享。

### AirPage

需要 network + device_info；`airpage.start` 初始化已有设备 ID 与缓存。`airpage.status`：text=状态，a=本页历史数，b=版本，c=当前是否显示全屏图片。`airpage.url` 返回上传链接；`airpage.fetch` 请求最新图片；`airpage.live` 的 on/off 控制前台实时接收，on 还需 keep_awake。

`airpage.history` 按本页 1 起始下标返回归档编号及宽高；`airpage.page` 的 first/next/previous 切换每页 20 条的历史。`airpage.show` 的 index=0 显示当前图片，1–20 显示历史；`airpage.hide` 回到 Lua 页面。图片完整解码并显示成功后才提交待定缓存，失败恢复旧图。此显示器复用固件的原生 16 灰阶或 4 灰阶图片通路。`airpage.wallpaper` 需要 wallpaper，使用当前选中图片设置休眠壁纸。

### 微信读书

需要 network + reading_data；`weread.start` 初始化本机已有账户与书架。服务不向 Lua 暴露 Cookie 或密钥。`weread.status`：text 为 idle/disclaimer/connecting/busy/qr/range/done/error，a=书籍数，b=版本，c=原生错误码。`weread.accept` 保存既有使用说明的接受状态。

`weread.sync` 同步书架并按需扫码登录；`weread.qr` 按 index=0/1/2 返回每段 192 字节的登录链接；`weread.book` 按 1 起始下标返回书名、a=已有本地书、extra=作者。`weread.fetch_detail` 获取详情，`weread.detail` 返回字数/评分/简介长度/出版社；`weread.intro` 按字节偏移读取最多 192 字节、保持 UTF-8 边界的简介。

`weread.download` 的 index=书籍，argument 使用 images/no_images，可附加 range。range 状态下 `weread.chapter_count`、`weread.chapter`（0 起始）读取目录，`weread.range` 以 `first:last` 选择闭区间。`weread.progress` 返回标题、已完成/总数/阶段。`weread.cancel` 取消；`weread.open` 打开已有本地书籍，阅读和进度同步仍属核心阅读器。`weread.logout` 退出账户，应用应先让用户确认。

API 5 新增 `weread.cache`（index=从 1 开始的书架序号）：text=ready/missing/invalid，a=是否已有 EPUB，b=有效本地目录的章节数，c=保存的图片选项（0 含图、1 纯文字、-1 未知）。随后 `weread.cached_chapter` 按从 0 开始的章节序号返回 text=标题、a=章节文件是否存在、b=付费标记、c=字数。这两项仍受 network + reading_data 权限约束，但查询本身不联网、不下载、不删除文件；前台下载任务运行时不读取本地目录。一个章节文件存在不等于 EPUB 已生成或正文完整。

这些适配器保留原有全局 AirPage 身份/微信读书账户，不提供多个第三方应用的独立账户空间。它们是受权限控制的现有服务桥接，不是通用 HTTP、MQTT 或任意文件访问接口。

## API 6：前台网络电台

AirTune 使用 `app.system` 的 `radio.*` 命令。需要 `network`、`sound` 授权及 `radio_audio`、`wifi`、`psram` 能力；保持唤醒另需 `keep_awake`。这些接口只在应用前台存活，退出/休眠同步停止音频和网络任务，不会启动后台 Lua。

- `radio.start`：创建服务，不自动播放或联网。权限/能力不满足时返回 false。
- `radio.play`, URL：排队收听直接 MP3 流，HTTP(S) URL 最多 511 字节。返回 true 仅表示接受请求；通过状态得知实际播放结果。未联网时打开系统 Wi-Fi 选择。
- `radio.stop`：排队停止。直播不缓存暂停位置，恢复是重新收听。
- `radio.volume`, `""`, 0–100：设置音量，初始 25。Mono 在板级输出设有保守增益上限。
- `radio.status`：返回 `ok, state, volume, receivedBytes, revision, error`。state 为 `idle/connecting/buffering/playing/error`；error 为 `none/invalid_url/unsupported/network/timeout/no_memory/audio/offline`。只在状态或音量变化时重画，避免随音频字节频繁刷新墨水屏。

首版只支持 MP3 直接流；AAC、HLS、M3U/PLS 播放列表不作为可播放流接受。音频不进入 Lua VM、不写 TF 卡。解码服务保持原始节目时长，将单/双声道自然采样转换到硬件的 24 kHz 单声道；不会通过改速调整节目长度。
