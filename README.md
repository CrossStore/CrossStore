# CrossStore

CrossMux 的实验性应用商店。设备通过 HTTP/HTTPS 获取静态 JSON 目录，下载 `.csp` 安装包，再由固件内的 Lua 5.4 运行时执行。商店服务不需要数据库或动态后端。

**当前为开发预览，需要带 CrossStore 运行时的 CrossMux 分支固件。官方现有固件不能直接运行这些包。** ESP32-S3 是当前验证目标；其他架构需要先实现相同的宿主 API 和设备适配，不能据此认定已经支持。

目录地址：<https://crossstore.github.io/CrossStore/index.json>

## 当前可安装应用

| 应用 | 实现 |
| --- | --- |
| calculator | Lua 计算器 |
| game2048 | Lua 2048，保存棋盘和得分 |
| woodfish | Lua 木鱼计数器，保存计数 |
| library | 打开固件书库的快捷入口 |
| file_transfer | 打开固件文件传输的快捷入口 |
| opds | 打开固件 OPDS 的快捷入口 |

其他应用的原始 C++ 源码保存在各包的 `native/` 中，`ORIGIN.json` 记录来源和文件摘要。它们目前标记为 `porting`，不会进入可安装目录。`chat_common` 是聊天公共源码；rf_chat、wifi_chat、esp_chat 尚未完成 Lua 迁移。原固件中的全部原生应用尚未完成移除，原有存档的迁移也尚未实现。

## 包与兼容性

每个包包含 `manifest.json`、UTF-8 `main.lua` 和 `LICENSE`。同一份 Lua 源码包可用于实现相同运行时/API 的设备，无须按 CPU 指令集重新编译。适配不同屏幕的绘制由固件处理；应用仍需在不同尺寸上验证交互。

元信息声明 `runtime`、`api`、`memory_bytes` 和硬件依赖 `requires`。例如 `requires: ["wifi", "lora", "storage"]`。商店展示依赖，并在安装和启动时检查设备能力；未知依赖拒绝处理。当前能力名称见 [包协议](docs/protocol.md)。

安装包保存在卡上的 `/.crosspoint/apps/`，独立应用数据保存在 `/.crosspoint/appdata/<id>/`。卸载保留数据。SHA-256 用于完整性校验；目前没有发布者数字签名，安装源的可信性取决于用户选择的商店和 HTTPS 连接。

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
