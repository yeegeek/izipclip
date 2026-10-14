# iZip Clip · 缩影

离线视频压缩与加速工具（iOS）。设定目标时长和文件大小，筛选相册中超限的视频，在设备本地变速并压缩后存回系统相册。

Offline video compress & speed-up for iOS. Set duration and size limits, pick over-limit clips from Photos, process them entirely on-device, and save results back to the library.

## Features · 功能

- Custom duration / size limits (up to 300s / 300MB)
- Filter videos that exceed your limits; multi-select + full-screen preview
- Smart speed-up (uniform rate when mild; eased ends + faster middle when needed)
- Size compression with hardware encoding
- Optional delete originals (system confirmation)
- Fully offline — no account, no server upload
- Chinese & English (follows system language)

## Privacy · 隐私

Videos never leave your device. See the full policy:

**https://yeegeek.github.io/iZipClip/privacy.html**

Source file: [`docs/privacy.html`](docs/privacy.html)

## Requirements · 环境

- Xcode 16+ (developed with Xcode 27 toolchain)
- iOS 17.0+
- Apple Developer account for device / App Store builds

## Build · 构建

```bash
open ZipClip.xcodeproj
```

1. Select the **ZipClip** scheme  
2. Choose your Development Team in Signing  
3. Run on a simulator or device  

Bundle ID: `app.zipclip.ios`  
Display name: **缩影** (zh-Hans) / **iZip Clip** (en)

## Project layout · 结构

```
ZipClip/                 App sources (SwiftUI)
ZipClipTests/            Unit tests
ZipClip.xcodeproj/       Xcode project
docs/privacy.html        Privacy policy (GitHub Pages)
```

## App Store notes · 上架

- Promotional copy / keywords: use “iZip Clip” in English listings and “缩影” in Chinese.
- Privacy Policy URL: `https://yeegeek.github.io/iZipClip/privacy.html`
- Photos usage strings are localized in `ZipClip/InfoPlist.xcstrings`

## License

Source in this repository is provided for the iZip Clip / 缩影 product.  
All rights reserved unless otherwise noted.
