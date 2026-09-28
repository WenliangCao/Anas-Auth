// 从 ente 的 custom-icons.json 提取品牌清单（只用名称，不用它的图标文件），
// 生成 IconSourcing/icon-list.csv 和按批次切好的外包 prompt。
// 用法：node Scripts/make_icon_batches.mjs <ente custom-icons.json> [每批数量，默认 30]
// custom-icons.json 位于 ente 仓库 mobile/apps/auth/assets/custom-icons/_data/
import fs from "node:fs";
import path from "node:path";

const [source, sizeArg] = process.argv.slice(2);
if (!source) throw new Error("usage: node make_icon_batches.mjs <custom-icons.json> [batch size]");
const batchSize = Number(sizeArg ?? 30);

const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
const dir = path.join(root, "IconSourcing");
const template = fs.readFileSync(path.join(dir, "prompt-template.md"), "utf8");
const lookup = JSON.parse(fs.readFileSync(path.join(root, "Auth/Resources/BrandIcons.json"), "utf8")).lookup;
const icons = JSON.parse(fs.readFileSync(source, "utf8")).icons;

const normalize = (s) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");

const rows = icons.map((icon) => {
  const altNames = icon.altNames ?? [];
  return {
    slug: (icon.slug ?? normalize(icon.title)).toLowerCase().replace(/[^a-z0-9_]/g, ""),
    title: icon.title,
    altNames,
    // 已有 simple-icons 单色版的排后面，先补完全缺失的
    simpleIcon: [icon.title, ...altNames].map((n) => lookup[normalize(n)]).find(Boolean) ?? "",
  };
});
rows.sort((a, b) => Number(Boolean(a.simpleIcon)) - Number(Boolean(b.simpleIcon)) || a.slug.localeCompare(b.slug));

const batches = [];
for (let i = 0; i < rows.length; i += batchSize) batches.push(rows.slice(i, i + batchSize));

const batchDir = path.join(dir, "batches");
fs.rmSync(batchDir, { recursive: true, force: true });
fs.mkdirSync(batchDir, { recursive: true });

const csv = [["slug", "title", "alt_names", "simple_icons_slug", "batch"].join(",")];
const cell = (v) => (/[",\n]/.test(v) ? `"${v.replaceAll('"', '""')}"` : v);
const md = (v) => v.replaceAll("|", "\\|");

batches.forEach((batch, index) => {
  const id = String(index + 1).padStart(2, "0");
  const items = batch
    .map((r) => `| ${r.slug} | ${md(r.title)} | ${md(r.altNames.join("、"))} |`)
    .join("\n");
  const prompt = template
    .replaceAll("{{BATCH_ID}}", id)
    .replaceAll("{{COUNT}}", String(batch.length))
    .replace("{{ITEMS}}", items);
  fs.writeFileSync(path.join(batchDir, `batch-${id}.md`), prompt);
  fs.writeFileSync(
    path.join(batchDir, `batch-${id}.json`),
    JSON.stringify(batch.map(({ slug, title }) => ({ slug, title })), null, 2) + "\n",
  );
  batch.forEach((r) => csv.push([r.slug, r.title, r.altNames.join("; "), r.simpleIcon, id].map(cell).join(",")));
});

fs.writeFileSync(path.join(dir, "icon-list.csv"), csv.join("\n") + "\n");
const missing = rows.filter((r) => !r.simpleIcon).length;
console.log(`${rows.length} brands (${missing} not in simple-icons), ${batches.length} batches of ≤${batchSize}`);
