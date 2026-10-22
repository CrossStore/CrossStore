# Lua API 1（实验）

`main.lua` 返回一个回调表：

```lua
return {
  on_start = function()
    app.clear()
    app.title(app.tr("Hello", "你好"))
    app.row(app.tr("Tap me", "点一下"))
  end,
  on_select = function(index)
    -- index 从 1 开始。
    app.notify(app.tr("Hello!", "你好！"))
  end,
  on_input = function(_, text) end,
  on_tick = function() end,
}
```

回调由前台应用调度；`on_tick` 约每 500 毫秒调用，不保证精确周期。当前没有后台 Lua 常驻服务或休眠接收能力。

| API | 用途 |
| --- | --- |
| app.title(text) | 设置标题 |
| app.clear() | 清空行、网格设置和说明文本 |
| app.row(label, value) | 添加一行；最多 32 行 |
| app.grid(columns) | 将行显示为网格，1–6 列，由设备适配可用宽度 |
| app.caption(text) | 显示说明或数值 |
| app.tr(en, zh) | 根据系统语言选择文本 |
| app.has(capability) | 查询宿主能力 |
| app.millis() | 宿主时间计数 |
| app.read(key) | 读取应用私有文本；不存在返回 nil |
| app.write(key, value) | 保存文本，返回成功与否；单值最多 2 KiB、最多 32 个键 |
| app.input(title, initial) | 打开系统键盘，结果送入 on_input |
| app.notify(text) | 投递系统通知；点击可回到此应用 |
| app.open(route) | 打开 library、file_transfer 或 opds 核心入口 |

VM 仅加载基础库、table、string、math、utf8 的受限子集。没有 io、os、package、debug、coroutine；禁用动态代码加载、pcall/xpcall、collectgarbage、string.dump 和模式匹配系列函数。不能使用网络套接字或访问任意存储路径。

每次回调最多 100000 条指令或约 100 毫秒，Lua 分配受清单预算限制。超限会停止应用并显示错误。此限制是故障隔离措施，并非已经完成安全审计的运行时承诺。
