# 第三方资源

| 资源 | 位置 | 来源 | 许可 |
|---|---|---|---|
| 品牌图标（单色） | `AnasAuth/BrandIcons.xcassets/brand/` | [simple-icons](https://github.com/simple-icons/simple-icons) | CC0-1.0 |
| 品牌图标（ente 社区提交） | `AnasAuth/BrandIcons.xcassets/custom/` | [ente-io/ente](https://github.com/ente-io/ente) `mobile/apps/auth/assets/custom-icons` | 随 ente 仓库以 AGPL-3.0 发布 |
| 导入格式解析与解密 | `AnasAuth/ImportExport/` | 参照 [ente-io/ente](https://github.com/ente-io/ente) `mobile/apps/auth` 的实现移植为 Swift | AGPL-3.0 |
| 导入测试样本（仅测试，不进 App） | `AnasAuthTests/EnteImportFixtures.swift` | [ente-io/ente](https://github.com/ente-io/ente) `mobile/apps/auth/test/ui/settings/data/import/fixtures` | AGPL-3.0 |
| swift-sodium / libsodium | Swift Package `swift-sodium` 0.11.0 | [jedisct1/swift-sodium](https://github.com/jedisct1/swift-sodium) | ISC（原文见下） |

- 两套图标由 `Scripts/generate_brand_icons.mjs` 生成，ente 图标经 resvg 预渲染为 PNG。
- 因包含上述 AGPL-3.0 内容，本 App 整体以 AGPL-3.0 发布，源代码见本仓库；App 内「设置 → 开源许可」展示同样的声明。
- 图标中的商标归各自所有者，仅用于标识对应服务。

## swift-sodium / libsodium 许可原文

```
ISC License

Copyright (c) 2014-2026, Frank Denis <j at pureftpd dot org>

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
```
