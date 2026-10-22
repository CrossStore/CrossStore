# 静态目录与安装包 v1

目录是 UTF-8 JSON：`schema: 1`、`api: 1`、`packages: [...]`、`next: ""`。超过一页时 `next` 指向同目录的 `page-2.json` 等文件。每页最多 16 项、24 KiB。

目录条目包含完整清单，加上 `artifact` 相对路径、包字节数 `bytes`、十六进制 `sha256`。设备只允许从同一目录基础 URL 解析相对包地址，不接受目录穿越或另一个 URL。

清单字段：

| 字段 | 当前约束 |
| --- | --- |
| schema / api | 均为 1 |
| id | `[a-z][a-z0-9_]{0,30}`，与包目录相同 |
| version | 三段数字版本号 |
| runtime | `crossmux-lua54` |
| entry | `main.lua` |
| memory_bytes | 16384–65536，Lua VM 的分配限额，不包含固件 UI 和传输开销 |
| name / description | 含 en、zh；各语言 UTF-8 字节数分别不超过 95 / 191 |
| requires | 必需能力名称数组，不允许重复或未知能力 |
| status | ready、porting、source-library；后两者不发布可安装包 |
| license | 许可证标识，包内必须包含 LICENSE |

能力名称：`wifi`、`lora`、`esp_now`、`tox`、`imu`、`touch`、`frontlight`、`rtc`、`psram`、`storage`。既包含硬件，也包含固件提供的接口。能力检查不等同于测试当前网络连通性。

`.csp` 是不压缩的 ZIP：清单不超过 4 KiB，Lua 源码不超过 32 KiB，整个包不超过 1 MiB、32 个文件。禁止预编译 Lua 字节码。可选资源必须列在 `assets` 并位于 `assets/` 子目录；目前固件尚未提供通用资源绘制 API。

下载写入临时文件，设备核对长度、SHA-256、内部清单和入口，才替换已安装包。替换期间保留 `.previous` 以恢复被中断的安装。此机制不能保证抵御存储介质损坏。
