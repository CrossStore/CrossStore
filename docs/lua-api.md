# Lua API 2（实验）

`main.lua` 返回回调表。API 2 保留 API 1 的列表接口，并增加画布、权限检查与系统服务。

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
| `app.sound(cue)` | 需要 sound 权限；固定 `woodfish` / `click` 短音，返回是否播放；无蜂鸣器时返回 false |
| `app.exit()` | 返回上一级 |

## 画布

`app.canvas()` 启用画布，`app.size()` 返回可用宽高。标题和系统返回区域由宿主负责。画布灰度参数 0 表示黑，15 表示白；当前基本图形映射为主题的四级灰度，设备不支持灰度时按宿主方式退化。应用图标另有 2/4/16 灰阶资源。

| 接口 | 参数 |
| --- | --- |
| `app.box(x,y,w,h,gray=0,radius=0,stroke=0)` | stroke=0 填充，否则绘制边框 |
| `app.circle(x,y,w,h,gray=0,stroke=0)` | 圆形/圆角胶囊；用相同宽高画圆 |
| `app.line(x,y,w,h,gray=0,reverse=0,stroke=1)` | 正宽高包围盒的对角线；reverse=1 从左下到右上 |
| `app.text(x,y,w,h,text,font=1,align=0,gray=0)` | font：0 小字、1 正文、2 标题、3 大数字；align：0 左、1 中、2 右 |
| `app.measure(text,maxWidth,font=1)` | 返回实际主题字体的排版宽高；text 最多 255 UTF-8 字节 |
| `app.button(id,x,y,w,h,label,style=0)` | style：0 描边、1 平面、2 浅灰、3 黑底 |
| `app.hit(id,x,y,w,h)` | 不绘制的交互区域，常用于棋盘 |
| `app.qr(x,y,size,text)` | 一帧一个二维码；固定版本 5/M、最多 96 字节，包含四模块留白 |

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

## 运行限制

仅开放基础库、table、string、math、utf8 的受限子集。没有 io、os、package、debug、coroutine；禁用动态加载、pcall/xpcall、collectgarbage、string.dump 和模式匹配系列函数。不能使用套接字或访问任意存储路径。

每个回调最多 100000 条 Lua 指令或约 100 毫秒。VM 配额为 16–128 KiB；超过 64 KiB 必须声明 psram。具备 PSRAM 的宿主将 VM 分配放到 PSRAM，失败不自动挤占内部堆。配额不含宿主画布、图标、协议服务与网络缓冲；这些各有独立上限。超限停止应用并报告错误。这是开发预览的故障隔离措施，尚未完成安全审计。
