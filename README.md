# Anas Auth 🦆

*Anas* is Latin for "duck".

Anas Auth is a native iOS two-factor authenticator written in SwiftUI. It is a native re-implementation of [ente Auth](https://github.com/ente-io/ente/tree/main/mobile/apps/auth).

[中文说明](#中文说明)

## Why

We love ente Auth: it is open source, well designed and respects its users. ente Auth is built with Flutter, though, and we wanted the same app written the native way, with SwiftUI, SwiftData, iCloud sync and the system Liquid Glass look. Anas Auth follows ente Auth's features and layout closely and uses iOS-native components throughout.

## Features

- TOTP, HOTP and Steam codes, with the current and the next code shown on every card
- Add codes by scanning a QR code, typing them in, or picking a QR image from Photos
- Import from ente (encrypted export), 2FAS, Aegis, andOTP, Bitwarden, Google Authenticator, Proton Authenticator, Raivo, LastPass, OTP Auth and plain-text `otpauth://` lists
- Encrypted or plain backup export
- Face ID / Touch ID / passcode app lock, and the app is blurred in the app switcher
- iCloud sync through your private CloudKit database. There is no server of our own.
- Tags, pinning, several sort orders, search, and a compact layout
- Brand icons: ente's community icons plus [simple-icons](https://simpleicons.org), matched by issuer name the same way ente does it

## Relationship to ente

Anas Auth is an independent project. It is **not affiliated with or endorsed by ente**. "ente" is a trademark of its owners.

It is not a fork, and it contains no Dart or Flutter code from ente. These parts are derived from ente's repository, which is licensed under **AGPL-3.0**:

| What | Where | How |
|---|---|---|
| Community brand icons | `AnasAuth/BrandIcons.xcassets/custom/` | Taken from `mobile/apps/auth/assets/custom-icons` and pre-rendered to PNG by `Scripts/generate_brand_icons.mjs` |
| Import formats | `AnasAuth/ImportExport/` | Parsing and decryption of the ente export format and other apps' export formats, ported to Swift from ente's implementation |
| Layout and behaviour | `AnasAuth/Views/` | Card layout, compact mode, tags, sorting and icon matching modeled on ente Auth |

The full list of third-party material and its licenses is in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## License

Copyright © 2026 [WenliangCao](https://github.com/WenliangCao)

Anas Auth is free software, licensed under the **GNU Affero General Public License v3.0** ([LICENSE](LICENSE)), the same license as ente. The whole app is released under AGPL-3.0 because it includes AGPL-3.0 material from ente.

Our AGPL-3.0 commitments:

- **The complete source is public.** Everything needed to build the app is in this repository.
- **No additional restrictions.** You may use, study, modify and redistribute this code under AGPL-3.0. If you distribute a modified version, it must also be under AGPL-3.0 and its source must be made available.
- **Notices are kept.** Copyright and license notices from ente and from all other third-party material are preserved.
- **App Store builds.** The App Store version is distributed under Apple's Standard EULA, which explicitly allows whatever the licenses of included open-source components permit. Your rights under AGPL-3.0 are not limited by it. The same notices are shown in the app under *Settings → 开源许可*.

Brand icons are trademarks of their respective owners. They are used only to identify the corresponding services and do not imply endorsement.

## Building

Requirements: Xcode 27 or later. The app targets iOS 27.

1. Open `AnasAuth.xcodeproj`.
2. Choose your own development team under *Signing & Capabilities*. iCloud sync requires a CloudKit container on your team.
3. Build and run the `AnasAuth` scheme.

The brand icons are already committed. To regenerate them, see the usage notes at the top of `Scripts/generate_brand_icons.mjs`.

---

## 中文说明

*Anas* 在拉丁语里是"鸭子"的意思。

Anas Auth 是一个用 SwiftUI 原生编写的 iOS 两步验证 App。

**为什么做**：我们很喜欢 [ente Auth](https://github.com/ente-io/ente/tree/main/mobile/apps/auth)。它开源、设计好，也尊重用户。但 ente Auth 是用 Flutter 写的，所以我们按原生的方式重新实现了一版：SwiftUI、SwiftData、iCloud 同步和系统的 Liquid Glass 风格。功能和布局尽量与 ente Auth 保持一致。

**与 ente 的关系**：本项目是独立项目，与 ente 没有隶属关系，也没有得到 ente 的背书。它不是 fork，不包含 ente 的 Dart/Flutter 代码。以下部分来自以 **AGPL-3.0** 发布的 ente 仓库：

- ente 社区品牌图标
- 参照 ente 实现移植到 Swift 的各导入格式解析与解密
- 参照 ente 的卡片布局与交互细节

**许可证**：因为包含 ente 的 AGPL-3.0 内容，整个 App 以 **AGPL-3.0** 开源，与 ente 相同。我们承诺：

- 构建 App 所需的完整源代码都公开在本仓库。
- 不附加任何额外限制。
- 保留 ente 及其他第三方资源的版权与许可声明。
- App Store 版本使用 Apple 标准 EULA，该协议明确允许开源组件许可证所允许的一切，不限制你依据 AGPL-3.0 享有的权利；App 内「设置 → 开源许可」有同样的声明。

第三方资源清单见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
