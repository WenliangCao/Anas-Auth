# 自有品牌图标库

simple-icons 缺了很多 2FA 常见服务（Amazon、xAI 等）。这里按 ente custom-icons 的**品牌清单**（只取名称，不用它的图标文件）从各品牌官方渠道重新取材，整理成我们自己的图标库。

## 文件

| 路径 | 说明 |
|---|---|
| `icon-list.csv` | 全部 551 个品牌；`simple_icons_slug` 非空表示已有 simple-icons 单色版 |
| `prompt-template.md` | 给外部 AI 的要求（来源、SVG 规范、交付格式） |
| `batches/batch-XX.md` | 每批 30 个的完整 prompt，直接整段发给外部 AI |
| `batches/batch-XX.json` | 该批应交付的 slug，校验用 |
| `deliveries/batch-XX.json` | 外部 AI 交回的 JSON，原样粘贴（多个代码块也可以） |
| `review/batch-XX/` | 校验生成的清理后 SVG 和 `review.html`（不入库） |

批次 01–14 是 simple-icons 完全没有的品牌，优先做；15 开始混入已有单色版的品牌。

## 流程

1. 把 `batches/batch-XX.md` 整段发给联网能力强的 AI；
2. 交回的内容存为 `deliveries/batch-XX.json`；
3. 校验并生成审核页：

   ```
   npm install --prefix Scripts
   node Scripts/validate_icon_delivery.mjs XX
   open IconSourcing/review/batch-XX/review.html
   ```

   脚本会检查字段、来源、禁用的 SVG 元素，并自动把 transform 算进坐标、形状转路径、圆弧转曲线（Xcode 的 SVG 渲染器只认这种写法），再把 viewBox 收成贴合图形的正方形。审核页同时显示浅色、深色背景下的效果；
4. 有 ✗ 的项打回重做，! 的项人工确认；通过后再合并进 `Auth/BrandIcons.xcassets`。

## 重新生成批次

```
node Scripts/make_icon_batches.mjs <ente 仓库>/mobile/apps/auth/assets/custom-icons/_data/custom-icons.json 30
```
