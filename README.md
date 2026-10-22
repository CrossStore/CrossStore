# CrossStore

CrossMux 的实验性应用商店。设备通过 HTTP/HTTPS 获取静态 JSON 目录，下载 `.csp` 安装包，再由固件内的 Lua 5.4 运行时执行。商店服务不需要数据库或动态后端。

**当前为开发预览，需要带 CrossStore 运行时的 CrossMux 分支固件。官方现有固件不能直接运行这些包。** ESP32-S3 是当前验证目标；其他架构需要先实现相同的宿主 API 和设备适配，不能据此认定已经支持。

目录地址：<https://crossstore.github.io/CrossStore/index.json>

## 当前可安装应用

| 应用 | 实现 |
| --- | --- |
| calculator / game2048 | 计算器独立显示区与键盘；2048 棋盘、滑动、撤销和存档 |
| gomoku / sudoku / minesweeper | 五子棋棋盘与人机/双人、数独笔记、扫雷长按插旗 |
| sokoban / chinese_chess | 155 关推箱子；中国象棋合法走子与轻量人机 |
| woodfish | 木鱼计数、蜂鸣器短音、独立静音开关 |
| buddy / reading_stats | 保留设备对应宠物；读取系统已有阅读统计 |
| rf_chat / wifi_chat / esp_chat | Lua 聊天页面、发现、气泡、重试、通知入口；使用固件通信服务 |
| library / file_transfer / opds | 核心书库、文件传输、OPDS 的快捷入口 |

以上 API 2 应用需要新版运行时固件。Apps 首页显示已安装应用，应用商店是其中一个入口；图标网格跟随用户设置，不再因 Mono 主题而强制使用列表。目录地址、硬件信息和应用权限集中在商店设置。

其他应用的原始 C++ 源码保存在各包 `native/`，`ORIGIN.json` 记录来源。avatar、standby、pixel_switch、airpage、weread 仍标记为 `porting`，不发布安装包；`chat_common` 是公共源码。原生代码仍供传统固件使用，尚未全部移除。原生游戏存档尚未迁移；聊天身份和历史继续使用原服务文件。Lua 中国象棋使用轻量 AI，数独当前提供固定难度的合法变换题库，不等同于原生应用的全部功能。

## 包与兼容性

每个包包含 `manifest.json`、UTF-8 `main.lua` 和 `LICENSE`。同一份 Lua 源码包可用于实现相同运行时/API 的设备，无须按 CPU 指令集重新编译。适配不同屏幕的绘制由固件处理；应用仍需在不同尺寸上验证交互。

元信息声明 `runtime`、`api`、`memory_bytes`、硬件依赖 `requires` 和权限 `permissions`。例如 `requires: ["wifi", "lora", "storage"]`。商店展示依赖，并在安装和启动时检查设备能力；未知依赖拒绝处理。当前能力名称见 [包协议](docs/protocol.md)。

安装包保存在卡上的 `/.crosspoint/apps/`，独立应用数据保存在 `/.crosspoint/appdata/<id>/`。卸载保留数据。SHA-256 用于完整性校验。目前没有发布者数字签名，而且预览固件沿用的下载接口尚未启用 HTTPS 服务端证书校验；摘要不能验证发布者或防止目录与包同时被替换。当前版本用于受控测试，发布前仍需完善下载信任机制。

## 构建与托管

需要 Python 3.9 或以上：

```sh
python3 -m unittest discover -s tests -v
python3 scripts/build.py
python3 -m http.server 8080 --directory dist
```

将整个 `dist/` 部署到任意静态 HTTP/HTTPS 服务即可。GitHub Actions 验证包并部署 GitHub Pages；目录分为每页最多 16 个应用的静态文件。

提交新应用请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。运行时 API 仍处于实验阶段，见 [Lua API](docs/lua-api.md)。

本项目沿用原始源码许可证，各应用保留各自的版权和许可证信息。目录中的 `status: ready` 表示可以打包安装，不代表所有设备都已通过实机验收。
