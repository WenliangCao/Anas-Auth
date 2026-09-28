// 从 simple-icons（CC0）生成品牌图标资源：
//   Auth/BrandIcons.xcassets/brand/<slug>.imageset  矢量模板图
//   Auth/Resources/BrandIcons.json                  名称、品牌色与匹配索引
// 用法：npm install --prefix Scripts
//       npm pack simple-icons && tar xzf simple-icons-*.tgz
//       node Scripts/generate_brand_icons.mjs ./package
import fs from "node:fs";
import path from "node:path";
import svgpath from "svgpath";

const pkg = process.argv[2];
if (!pkg) throw new Error("usage: node generate_brand_icons.mjs <simple-icons package dir>");

const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
const catalog = path.join(root, "Auth/BrandIcons.xcassets");
const folder = path.join(catalog, "brand");
const icons = JSON.parse(fs.readFileSync(path.join(pkg, "data/simple-icons.json"), "utf8"));

fs.rmSync(catalog, { recursive: true, force: true });
fs.mkdirSync(folder, { recursive: true });
const info = { info: { author: "xcode", version: 1 } };
fs.writeFileSync(path.join(catalog, "Contents.json"), JSON.stringify(info, null, 2));
fs.writeFileSync(
  path.join(folder, "Contents.json"),
  JSON.stringify({ ...info, properties: { "provides-namespace": true } }, null, 2),
);

// Xcode 资源目录的 SVG 渲染器解析不了压缩写法的圆弧（如 "a1 1 0 00-4.8 1"，
// flag 与坐标粘连），图形会错位、被裁切。统一转成绝对坐标并把圆弧改写成贝塞尔曲线。
const normalizePaths = (svg) =>
  svg.replace(/ d="([^"]+)"/g, (_, d) => ` d="${svgpath(d).abs().unarc().round(3).toString()}"`);

// 匹配键：小写且只保留字母数字，如 "\"xAI\"" → "xai"
const normalize = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");
const lookup = {};
const addKey = (key, slug) => {
  const k = normalize(key);
  if (k && !(k in lookup)) lookup[k] = slug;
};

for (const icon of icons) {
  const set = path.join(folder, `${icon.slug}.imageset`);
  fs.mkdirSync(set);
  const svg = fs.readFileSync(path.join(pkg, "icons", `${icon.slug}.svg`), "utf8");
  fs.writeFileSync(path.join(set, `${icon.slug}.svg`), normalizePaths(svg));
  fs.writeFileSync(
    path.join(set, "Contents.json"),
    JSON.stringify(
      {
        images: [{ filename: `${icon.slug}.svg`, idiom: "universal" }],
        info: info.info,
        properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
      },
      null,
      2,
    ),
  );
}
// 先登记所有正式名称，别名只补空缺，避免别名抢占其他品牌的正式名
for (const icon of icons) {
  addKey(icon.title, icon.slug);
  addKey(icon.slug, icon.slug);
}
for (const icon of icons) {
  const a = icon.aliases ?? {};
  [...(a.aka ?? []), ...(a.old ?? []), ...(a.dup ?? []).map((d) => d.title), ...Object.values(a.loc ?? {})]
    .forEach((alias) => addKey(alias, icon.slug));
}

const index = {
  icons: icons.map((i) => ({ slug: i.slug, title: i.title, hex: i.hex })),
  lookup,
};
fs.mkdirSync(path.join(root, "Auth/Resources"), { recursive: true });
fs.writeFileSync(path.join(root, "Auth/Resources/BrandIcons.json"), JSON.stringify(index));
console.log(`${icons.length} icons, ${Object.keys(lookup).length} lookup keys`);
