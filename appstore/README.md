# 应用商店图标

这是 CrossMux 内置商店入口的素材，不是可下载安装的 Lua 应用。彩色透明母版位于 `icons/master.png`，与各应用使用同一套预处理规则。

```sh
python3 scripts/prepare_icons.py --builtin appstore
```

输出包含 32/48/64/96/128 px 彩色与 2/4/16 灰阶预览；64 px 以上的 2/4 灰阶同时提供抖动版本。`assets/icon.csi` 集合了固件需要的六套尺寸，7048 字节。

固件同步：把 `assets/icon.csi` 复制到 CrossMux 的 `assets/app-icons/appstore/icon.csi`，再运行 `python3 scripts/generate_store_icon.py`；PlatformIO 也会自动生成头文件。固件直接读取 Flash 中的图标，首次开机、离线和目录下载失败时均可使用，无需 TF 卡中的额外图片。

母版为本次生成的原创店铺插画，来源与摘要见 `artwork.json`。不要将内置商店图标添加到 `packages/` 目录或在线安装列表。
