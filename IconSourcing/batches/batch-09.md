# 任务：为 2FA 应用整理品牌图标（批次 09，共 30 个）

你是一名熟悉品牌设计和 SVG 的研究助理。请为下表中的每个品牌，从**官方渠道**找到它当前使用的品牌标志，整理成符合下述规范的 SVG，并按第 5 节的格式交付。

这些图标会显示在一款双因素验证（2FA）App 的账户卡片上，显示尺寸约 24–56pt，浅色和深色背景都会用到。

## 品牌列表

名称来自用户账户里的「发行方」字段，可能是公司、产品或在线服务。遇到同名品牌时，选**提供账号登录 / 两步验证的那个在线服务**，并在 notes 里写明判断依据；实在无法确定就把 status 填 `ambiguous`。

| slug | 名称 | 别名 / 线索 |
|---|---|---|
| macrumors | MacRumors | MacRumors Forums |
| mailcow | MailCow | mailcow、mailcow UI |
| managemyhealth | Manage My Health | managemyhealth、Manage My Health NZ |
| mangadex | MangaDex |  |
| marketplacedottf | Marketplace.tf |  |
| matlab | matlab | mathworks |
| maxon | Maxon |  |
| mbin | Mbin | kbin、thebrainbin、gehirneimer |
| medeo | Medeo |  |
| meesman | Meesman Indexbeleggen |  |
| mein_grundeinkommen | Mein Grundeinkommen |  |
| memed | Memed |  |
| mercado_libre | Mercado Libre | Mercado Libre、MercadoLibre、MercadoLivre |
| mexc | MEXC |  |
| mfc | MyFigureCollection | MyFigureCollection.net、MFC |
| microsoft | microsoft |  |
| microsoft365 | Microsoft 365 |  |
| migros | Migros |  |
| mintmobile | Mint Mobile | MintMobile |
| mintos | Mintos |  |
| mobile01 | Mobile01 | M01 |
| myfritz | MyFRITZ!Net | MyFRITZ!、FritzBox、Fritz!Box、FritzBox 7590、FritzBox 7590 AX、FritzBox 7530、FritzBox 7530 AX、FritzBox 4040、FritzBox 4060、FritzBox 5530 Fiber、FritzBox 6490 Cable、FritzBox 6590 Cable、FritzBox 6591 Cable、FritzBox 6660 Cable、FritzBox 6820 LTE、FritzBox 6850 LTE、FritzBox 6850 5G、FritzBox 6890 LTE、FritzBox 7583、FritzBox 7520、FritzBox 7490、FritzBox 7583 |
| myheritage | MyHeritage | MyHeritage |
| myhsa | myHSA | myHSA |
| name_com | Name.com |  |
| nasdaq | nasdaq |  |
| nekohosting | NekoHosting | NekoHosting Billing、NekoHosting Dashboard |
| nekohosting_gp | NekoHosting Gaming Panel | NekoHosting Game Panel、NekoHosting GamePanel |
| nelnet | Nelnet |  |
| netbird | NetBird |  |

## 1. 选哪个标志

- 优先用品牌的**图形标志**（symbol / logomark），也就是它的 App 图标或网站 favicon 里的那个图形；
- 品牌没有独立图形、只有文字标志时，用官方文字标志（wordmark）或官方字母组合（monogram）；
- 用**当前**版本，不要品牌更新前的旧标志；
- 不要加 App 图标的圆角方形底板，除非官方标志本身就定义为「有色底板上的图形」；
- 使用官方颜色，不要改色、加阴影、描边或背景。

## 2. 素材来源（按优先级）

1. 品牌自己域名下的 brand / press / media kit 页面；
2. 官网页面内嵌的 SVG 标志，或官网的 favicon.svg；
3. 官方 App Store / Google Play 图标：只能作为参考，需据此绘制矢量版，并在 notes 说明；
4. Wikimedia Commons 上注明出处为官方的文件。

**禁止**使用：ente、simple-icons、2FAS、Aegis 等其他 App 或图标包里的图标；图标素材站、Dribbble 等；AI 生成或凭记忆画出的图形。

每个图标都必须填写 `source_url`，指向你实际取材的页面或文件。找不到可靠的官方来源时，status 填 `not_found`，**不要编造**。

## 3. SVG 技术规范

- 根元素：`<svg xmlns="http://www.w3.org/2000/svg" viewBox="…">`，不要写 width / height；
- viewBox 不要求正方形，也不需要留边，我们会自动裁成贴合图形的正方形；
- 只允许这些元素：`svg` `g` `path` `circle` `ellipse` `rect` `polygon` `polyline` `defs` `linearGradient` `radialGradient` `stop`；
- **禁止**：`image`（位图）、`text` / `tspan`（文字必须转成路径）、`style`、`class`、`script`、`foreignObject`、`filter`、`mask`、`clipPath`、`pattern`、`use`、`symbol`、动画元素；
- 颜色写在 `fill` / `stroke` 属性上，格式 `#RRGGBB`，可配合 `fill-opacity`；不要用 `currentColor`、CSS 变量或 `style` 属性；
- 渐变只在官方标志本身有渐变时使用；
- 尽量不用 `transform`，坐标直接写成最终位置；
- 不要放铺满画布的背景矩形（透明或白色都不行）；
- 坐标最多保留 3 位小数，单个 SVG 不超过 30 KB。

## 4. 深浅色模式

- `mono`：标志只有一种颜色时填 `true`，我们会在深色背景下自动换成可读的颜色；
- `svg_dark`：多色标志中有深色部分、放在深色背景上会看不见，并且官方提供了反白 / 深色背景版本时，把那个版本放进 `svg_dark`；否则填 `null`。

## 5. 交付格式

只输出一个 JSON 数组，不要任何解释文字。数组必须包含上表**全部 30 个 slug**，每项结构如下：

```json
{
  "slug": "表中的 slug，原样照抄",
  "status": "ok | not_found | ambiguous",
  "brand": "官方品牌名",
  "website": "https://品牌官网",
  "source_url": "https://实际取材的页面或文件",
  "source_type": "brand_kit | official_site | app_store | wikimedia",
  "mark_type": "symbol | wordmark | monogram",
  "mono": true,
  "hex": "主品牌色，6 位十六进制，不带 #",
  "svg": "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 24 24\">…</svg>",
  "svg_dark": null,
  "notes": "判断依据、绘制说明或其他需要人工留意的地方，没有就填空字符串"
}
```

- status 不是 `ok` 时，`svg` 填 `null`，其余能填的尽量填，并在 notes 说明原因；
- 能生成文件就交付为 `batch-09.json`；只能在对话里输出时，每 10 项一个 ```json 代码块，每块都是完整合法的 JSON 数组。

## 6. 提交前自查

- 表中每个 slug 都出现且只出现一次；
- 每个 `svg` 都是合法 XML，放进浏览器能完整显示，图形没有被裁切或变形；
- `source_url` 能打开，而且确实是官方来源；
- 没有违反第 3 节的任何禁止项。
