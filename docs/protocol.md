# 静态目录与安装包 v1

目录是 UTF-8 JSON：`schema: 1`、`api: 1`、`packages: [...]`、`next: ""`。超过一页时 `next` 指向同目录的 `page-2.json` 等文件。每页最多 16 项、24 KiB。

构建器还输出 `page`（从 1 开始）、`pages`、`total` 和 `previous`。第一页的 previous、最后一页的 next 为空；第二页的 previous 指向 `index.json`。三个计数字段必须一起提供。API 5 配套商店据此显示页码/总数与双向翻页，只缓存当前页；仍兼容只提供 next 的旧目录。旧固件会忽略新增字段。

目录条目包含完整清单，加上 `artifact` 相对路径、包字节数 `bytes`、十六进制 `sha256`。设备只允许从同一目录基础 URL 解析相对包地址，不接受目录穿越或另一个 URL。

清单字段：

| 字段 | 当前约束 |
| --- | --- |
| schema / api | schema=1，应用 api 为 1–5；目录外层 api=1 保持静态格式兼容 |
| id | `[a-z][a-z0-9_]{0,30}`，与包目录相同 |
| version | 三段数字版本号 |
| runtime | `crossmux-lua54` |
| entry | `main.lua` |
| memory_bytes | 16384–131072，Lua VM 的分配限额，不包含固件 UI 和传输开销 |
| name / description | 含 en、zh；各语言 UTF-8 字节数分别不超过 95 / 191 |
| requires | 必需能力名称数组，不允许重复或未知能力 |
| permissions | 应用声明的权限；安装时明确授权，商店设置可逐项撤销 |
| status | ready、porting、source-library；后两者不发布可安装包 |
| license | 许可证标识，包内必须包含 LICENSE |

能力名称：`wifi`、`lora`、`esp_now`、`tox`、`imu`、`touch`、`frontlight`、`rtc`、`psram`、`storage`、`buzzer`、`audio`。既包含硬件，也包含固件提供的接口。能力检查不等同于测试当前网络连通性。

`.csp` 是不压缩的 ZIP：清单不超过 4 KiB，Lua 源码不超过 32 KiB，整个包不超过 1 MiB、32 个文件。禁止预编译 Lua 字节码。可选资源必须列在 `assets` 并位于 `assets/` 子目录；API 2 可读取有界资源，图标按约定文件名加载。

权限名称为 `network`、`radio`、`notifications`、`background`、`reading_data`、`wallpaper`、`sound`、`device_info`、`files_export`、`keep_awake`。能力表示设备提供什么，权限表示用户允许应用做什么；两者分别展示。API 3 的 AirPage 服务需要 wallpaper 才能设置休眠壁纸；files_export 允许在 `/CrossStore/<应用ID>/` 导出 SVG；keep_awake 允许前台应用阻止自动休眠，退出时失效。内存声明超过 64 KiB 必须同时要求 psram。每台设备由商店最多安装 64 个包，更新已有包不计入新增。

图标源文件在各包 `icons/` 中，包含彩色母版和不同分辨率的预处理 PNG。安装资源为 32/64 px 的 2/4 灰阶和 32/96 px 的 16 灰阶 `.bin`，低灰阶大图采用预处理抖动。启动器选择设备所需版本；没有图标则使用通用图形。

下载写入临时文件，设备核对长度、SHA-256、内部清单和入口，才替换已安装包。替换期间保留 `.previous` 以恢复被中断的安装。此机制不能保证抵御存储介质损坏。

API 5 配套商店展示格式有效但要求更高运行时 API 的条目，并提示更新固件；安装和启动仍严格检查兼容性。若设备已装有可运行的旧版，详情页继续提供「打开」。旧固件会跳过不支持的条目，仍可更新同页其他兼容应用、访问下一页。

API 4 增加退出/休眠前 `on_stop()` 回调，2048、五子棋、数独 0.3.0 的合并保存依赖此回调。API 5 增加只读的阅读日期/成就和微信读书本地章节查询。固件版本与应用包分别更新。

安装数量与应用列表只统计合法 `<id>.csp` 文件；macOS 的 `._` 元数据、临时文件不计入 64 个安装包的上限。
