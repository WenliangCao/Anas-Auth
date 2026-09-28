// 生成品牌图标资源，与 ente Auth 使用同一套图标：
//   1. simple-icons（CC0）：单色矢量，按品牌色着色 → AnasAuth/BrandIcons.xcassets/brand/
//   2. ente custom-icons（ente 社区提交，随 ente 仓库以 AGPL-3.0 发布）：多为彩色，
//      用 resvg 预渲染成 PNG（它们大量使用 CSS、clipPath、mask、滤镜，Xcode 的 SVG 渲染器靠不住）
//      → AnasAuth/BrandIcons.xcassets/custom/
//   同名时 custom 优先（与 ente 一致）。另生成 AnasAuth/Resources/BrandIcons.json：名称、颜色、匹配索引。
//
// 用法：
//   npm install --prefix Scripts
//   npm pack simple-icons && tar xzf simple-icons-*.tgz
//   node Scripts/generate_brand_icons.mjs ./package <ente 仓库>/mobile/apps/auth/assets/custom-icons
import fs from "node:fs";
import path from "node:path";
import { Resvg } from "@resvg/resvg-js";
import svgpath from "svgpath";

const [simplePkg, customDir] = process.argv.slice(2);
if (!simplePkg || !customDir) {
  throw new Error("usage: node generate_brand_icons.mjs <simple-icons package> <ente custom-icons dir>");
}

const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
const catalog = path.join(root, "AnasAuth/BrandIcons.xcassets");
const info = { author: "xcode", version: 1 };
/// 预渲染尺寸：最大显示 64pt @3x
const PNG_SIZE = 192;

fs.rmSync(catalog, { recursive: true, force: true });
const writeJSON = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2));
fs.mkdirSync(catalog, { recursive: true });
writeJSON(path.join(catalog, "Contents.json"), { info });
for (const folder of ["brand", "custom"]) {
  fs.mkdirSync(path.join(catalog, folder));
  writeJSON(path.join(catalog, folder, "Contents.json"), { info, properties: { "provides-namespace": true } });
}

// 匹配键：小写且只保留字母数字，如 "\"xAI\"" → "xai"
const normalize = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
const icons = [];
const lookup = {};
const addKey = (key, id) => {
  const k = normalize(key);
  if (k && !(k in lookup)) lookup[k] = id;
};

// ---------- ente custom-icons ----------
const customData = JSON.parse(fs.readFileSync(path.join(customDir, "_data/custom-icons.json"), "utf8")).icons;
const customTitles = new Set();

// 把 viewBox 扩成正方形并居中，渲染出来的 PNG 就是方的
function squareSVG(svg) {
  const tag = svg.match(/<svg\b[^>]*>/)[0];
  const attr = (name) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];
  let [x, y, w, h] = (attr("viewBox") ?? "").split(/[\s,]+/).map(Number);
  if (![x, y, w, h].every(Number.isFinite)) {
    [x, y, w, h] = [0, 0, parseFloat(attr("width")), parseFloat(attr("height"))];
  }
  const size = Math.max(w, h);
  const viewBox = [x - (size - w) / 2, y - (size - h) / 2, size, size].join(" ");
  const newTag = tag
    .replace(/\s(width|height|viewBox|preserveAspectRatio)="[^"]*"/g, "")
    .replace(/^<svg/, `<svg viewBox="${viewBox}" width="${size}" height="${size}"`);
  return svg.replace(tag, newTag);
}

for (const icon of customData) {
  const file = icon.slug ?? icon.title.replace(/ /g, "").toLowerCase();
  const id = `ente_${file.replace(/[^a-z0-9_]/g, "_")}`;
  const svg = fs.readFileSync(path.join(customDir, "icons", `${file}.svg`), "utf8");
  const png = new Resvg(squareSVG(svg), { fitTo: { mode: "width", value: PNG_SIZE } }).render().asPng();
  const set = path.join(catalog, "custom", `${id}.imageset`);
  fs.mkdirSync(set);
  fs.writeFileSync(path.join(set, `${id}.png`), png);
  // 带 hex 的是单色图标，ente 会按该颜色着色，这里用模板图
  const tinted = Boolean(icon.hex);
  writeJSON(path.join(set, "Contents.json"), {
    images: [{ filename: `${id}.png`, idiom: "universal", scale: "3x" }],
    info,
    properties: { "template-rendering-intent": tinted ? "template" : "original" },
  });
  icons.push({ id, title: icon.title, hex: icon.hex ?? null, tinted, asset: `custom/${id}` });
  customTitles.add(normalize(icon.title));
  addKey(icon.title, id);
  addKey(file, id);
  (icon.altNames ?? []).forEach((name) => addKey(name, id));
}

// ---------- simple-icons ----------
// Xcode 的 SVG 渲染器解析不了压缩写法的圆弧（如 "a1 1 0 00-4.8 1"），会错位、被裁切，
// 统一转成绝对坐标并把圆弧改写成贝塞尔曲线
const normalizePaths = (svg) =>
  svg.replace(/ d="([^"]+)"/g, (_, d) => ` d="${svgpath(d).abs().unarc().round(3).toString()}"`);

const simpleData = JSON.parse(fs.readFileSync(path.join(simplePkg, "data/simple-icons.json"), "utf8"));
/// 被同名 custom 图标取代的 simple-icons：旧数据里存的 slug 转到新图标
const replaced = {};
const simpleAliases = [];
for (const icon of simpleData) {
  const shadowedBy = customTitles.has(normalize(icon.title)) ? lookup[normalize(icon.title)] : null;
  if (shadowedBy) {
    replaced[icon.slug] = shadowedBy;
    continue;
  }
  const set = path.join(catalog, "brand", `${icon.slug}.imageset`);
  fs.mkdirSync(set);
  const svg = fs.readFileSync(path.join(simplePkg, "icons", `${icon.slug}.svg`), "utf8");
  fs.writeFileSync(path.join(set, `${icon.slug}.svg`), normalizePaths(svg));
  writeJSON(path.join(set, "Contents.json"), {
    images: [{ filename: `${icon.slug}.svg`, idiom: "universal" }],
    info,
    properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
  });
  icons.push({ id: icon.slug, title: icon.title, hex: icon.hex, tinted: true, asset: `brand/${icon.slug}` });
  addKey(icon.title, icon.slug);
  addKey(icon.slug, icon.slug);
  simpleAliases.push(icon);
}
// 别名最后登记，只补空缺，避免抢占其他品牌的正式名
for (const icon of simpleAliases) {
  const a = icon.aliases ?? {};
  [...(a.aka ?? []), ...(a.old ?? []), ...(a.dup ?? []).map((d) => d.title), ...Object.values(a.loc ?? {})]
    .forEach((alias) => addKey(alias, icon.slug));
}

icons.sort((a, b) => a.title.localeCompare(b.title, "en", { sensitivity: "base" }));
fs.mkdirSync(path.join(root, "AnasAuth/Resources"), { recursive: true });
fs.writeFileSync(path.join(root, "AnasAuth/Resources/BrandIcons.json"), JSON.stringify({ icons, lookup, replaced }));
const customCount = icons.filter((i) => i.asset.startsWith("custom/")).length;
console.log(`${icons.length} icons (${customCount} ente custom, ${icons.length - customCount} simple-icons), ` +
  `${Object.keys(replaced).length} simple-icons replaced, ${Object.keys(lookup).length} lookup keys`);
