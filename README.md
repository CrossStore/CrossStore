# CrossStore

CrossMux 的实验性应用商店。设备通过 HTTP/HTTPS 获取静态 JSON 目录，下载 `.csp` 安装包，再由固件内的 Lua 5.4 运行时执行。商店服务不需要数据库或动态后端。

**当前为开发预览，需要带 CrossStore 运行时的 CrossMux 分支固件。官方现有固件不能直接运行这些包。** ESP32-S3 是当前验证目标；其他架构需要先实现相同的宿主 API 和设备适配，不能据此认定已经支持。

目录地址：<https://crossstore.github.io/CrossStore/index.json>

## 当前可安装应用

| 应用 | 实现 |
| --- | --- |
| calculator / game2048 | 计算器独立显示区与键盘；2048 棋盘、滑动、撤销和存档 |
| gomoku / sudoku / minesweeper | 五子棋双尺寸棋盘与三档人机、数独三档题库/笔记/提示、扫雷长按插旗 |
| sokoban / chinese_chess | 155 关推箱子；中国象棋合法走子与轻量人机 |
| airtune | API 8 实验性本机 MP3 电台：六个预置台、自定义地址、12 个收藏、触摸与实体键音量；需固件提供 `radio_audio` 能力 |
| woodfish | 木鱼计数、声音与独立静音开关；配套 S3 固件提供内置木鱼 PCM 采样 |
| buddy / reading_stats | 保留设备对应宠物；阅读概览、月历热力图、日期书单和系统成就 |
| rf_chat / wifi_chat / esp_chat | Lua 聊天页面、发现、气泡、重试、通知入口；使用固件通信服务 |
| avatar / standby | Lua 随机头像与 SVG 导出；大字钟面、月历与农历 |
| pixel_switch / airpage / weread | 公共像素画布；扫码传图与历史图片；微信读书书架、登录、离线下载与本地章节目录 |
| library / file_transfer / opds | 核心书库、文件传输、OPDS 的快捷入口 |

AirTune 0.1.2 需要 API 8 与 `radio_audio` 连续播放能力；能否使用由固件能力决定。Waveshare 3.97 已能播放，实机反馈 100% 音量仍小、声音基本干净，响度验收尚未通过；PaperMono 仍偏小，当前不继续调整其蜂鸣器方案。长时间播放稳定性仍待验收。reading_stats 0.3.0 和 weread 0.4.0 使用 API 5 的只读统计/缓存查询。2048、五子棋、数独 0.3.0 使用 API 4：操作先保存在内存，空闲 2 秒或连续操作 10 秒后写卡，退出/休眠前补存。avatar、standby、pixel_switch、airpage 使用 API 3，其余应用使用 API 2，均需要对应版本或更新的运行时固件。

Apps 首页只显示已安装应用，应用商店是其中一个入口；启动器网格/列表跟随用户设置。新版商店直接显示图标网格，顶部提供「全部」「已安装」和设置按钮；右下角勾表示已安装，上箭头表示有较新版本。商店网格按屏幕尺寸排布，不受启动器的列表设置影响。目录地址、硬件信息和应用权限集中在商店设置。

商店先显示上次缓存的 JSON，再在后台更新目录和图标；离线或刷新失败时保留缓存。首次使用需要联网获取目录，「已安装」可离线使用。已有连接直接复用，Wi-Fi 关闭时尝试保存的网络，不自动弹走缓存页。下载失败的图标会有限重试，取消刷新后保留旧图标。内置应用商店也有独立的 2/4/16 灰阶图标，母版在 `appstore/`。目录目前共有 22 个入口，服务端 JSON 分两页（16 + 6），设备按自己的网格容量连续翻页。独立图标预览每应用 7048 字节，包含 2/4/16 灰阶，不必先下载整个应用包。

以上网格与缓存行为需要 2026-10-23 的商店网格版 CrossMux 固件，仅更新应用包或静态目录不会改变旧固件界面。较新 API 的有效条目会在详情提示升级固件；旧固件可能跳过不支持的条目。

原有 21 个迁移应用的 C++ 源码保存在各包 `native/`，`ORIGIN.json` 记录来源。新增 AirTune 是参考 C1Max 使用方式重新实现的 Lua 应用；当前 22 个入口均有可安装包；`chat_common` 是公共源码，不单独安装。商店固件的应用入口转向 Lua；原生 C++ 界面源码仍供传统固件使用，协议、图片解码、下载和系统阅读服务保留在固件。原生游戏存档尚未迁移；聊天身份和历史继续使用原服务文件。Lua 中国象棋与五子棋使用有界的轻量 AI，不等同于原版深搜索；数独使用离线校验唯一解的三档题库及合法变换。头像改为 SVG 导出；待机时钟目前保持唤醒、按分钟刷新。阅读统计的画像与年度趋势、微信读书的在线边读边取、缓存删除和封面墙仍待完善。详见 [迁移与验收](docs/migration.md)。

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

图标母版和预处理资源位于各包 `icons/`；三个聊天图标用内置 image_gen 生成，原始提示词保存在各自 `icons/generation.json`。运行 `python3 scripts/prepare_icons.py packages/rf_chat` 可重新生成该包的 32/48/64/96/128 px 彩色及 2/4/16 灰阶文件（需要 Pillow），低灰阶 64 px 及以上保留直接量化和抖动两种版本。
