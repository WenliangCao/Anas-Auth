// 校验外包交回的图标批次，并生成人工审核页。
// 用法：node Scripts/validate_icon_delivery.mjs <批次号，如 01>
// 读取：IconSourcing/batches/batch-XX.json（应交付的 slug）
//       IconSourcing/deliveries/batch-XX.json（对方交回的 JSON，可直接粘贴多个代码块）
// 输出：IconSourcing/review/batch-XX/ 下清理后的 SVG 与 review.html；有错误时退出码为 1
import fs from "node:fs";
import path from "node:path";
import { optimize } from "svgo";
import svgpath from "svgpath";

const id = process.argv[2]?.padStart(2, "0");
if (!id) throw new Error("usage: node validate_icon_delivery.mjs <batch id>");

const root = path.join(path.dirname(new URL(import.meta.url).pathname), "..");
const dir = path.join(root, "IconSourcing");
const expected = JSON.parse(fs.readFileSync(path.join(dir, "batches", `batch-${id}.json`), "utf8"));
const reviewDir = path.join(dir, "review", `batch-${id}`);

// ---------- 读取交付：容忍 ```json 代码块和多个数组首尾相接 ----------
function readDelivery() {
  const raw = fs.readFileSync(path.join(dir, "deliveries", `batch-${id}.json`), "utf8");
  const text = raw.replace(/```(?:json)?/g, "").trim();
  try {
    return JSON.parse(text);
  } catch {
    return JSON.parse(`[${text.replace(/^\[|\]$/g, "").replace(/\]\s*\[/g, ",")}]`);
  }
}

const ALLOWED = new Set([
  "svg", "g", "path", "circle", "ellipse", "rect", "polygon", "polyline",
  "defs", "linearGradient", "radialGradient", "stop", "title", "desc",
]);
const FORBIDDEN_SOURCES = /ente\.io|ente-io|simpleicons|simple-icons|2fas|aegis|flaticon|iconfinder|icons8|dribbble|freepik|seeklogo|worldvectorlogo|brandslogo/i;
const MAX_BYTES = 30 * 1024;

// ---------- 原始 SVG 规范检查 ----------
function inspect(svg) {
  const errors = [];
  const warnings = [];
  if (Buffer.byteLength(svg) > MAX_BYTES) errors.push(`超过 30 KB（${Math.round(Buffer.byteLength(svg) / 1024)} KB）`);
  const seen = new Set();
  const inspector = {
    name: "inspect",
    fn: () => ({
      element: {
        enter(node) {
          if (!ALLOWED.has(node.name)) seen.add(`禁止的元素 <${node.name}>`);
          for (const [attr, value] of Object.entries(node.attributes)) {
            if (attr === "style" || attr === "class") seen.add(`禁止的属性 ${attr}`);
            if (attr === "transform") warnings.push("使用了 transform");
            if (/currentColor|var\(/.test(value)) seen.add(`颜色不能用 ${value}`);
            if (/^xlink:href|^href$/.test(attr)) seen.add(`禁止的引用 ${attr}`);
          }
        },
      },
    }),
  };
  try {
    optimize(svg, { plugins: [inspector] });
  } catch (error) {
    errors.push(`不是合法 SVG：${error.message.split("\n")[0]}`);
  }
  errors.push(...seen);
  return { errors, warnings: [...new Set(warnings)] };
}

// ---------- 清理：形状转路径并把 transform 直接算进坐标 ----------
// svgo 自带插件展不开带圆角的 rect、嵌套 group 上的 transform，这里自己处理
const num = (node, attr) => Number(node.attributes[attr] ?? 0);
function shapeToPath(node) {
  const a = node.attributes;
  switch (node.name) {
    case "rect": {
      const [x, y, w, h] = ["x", "y", "width", "height"].map((k) => num(node, k));
      let rx = Math.min(Number(a.rx ?? a.ry ?? 0), w / 2);
      let ry = Math.min(Number(a.ry ?? a.rx ?? 0), h / 2);
      if (!rx || !ry) return `M${x} ${y}H${x + w}V${y + h}H${x}Z`;
      return `M${x + rx} ${y}H${x + w - rx}A${rx} ${ry} 0 0 1 ${x + w} ${y + ry}V${y + h - ry}` +
        `A${rx} ${ry} 0 0 1 ${x + w - rx} ${y + h}H${x + rx}A${rx} ${ry} 0 0 1 ${x} ${y + h - ry}` +
        `V${y + ry}A${rx} ${ry} 0 0 1 ${x + rx} ${y}Z`;
    }
    case "circle":
    case "ellipse": {
      const [cx, cy] = [num(node, "cx"), num(node, "cy")];
      const rx = node.name === "circle" ? num(node, "r") : num(node, "rx");
      const ry = node.name === "circle" ? num(node, "r") : num(node, "ry");
      return `M${cx - rx} ${cy}A${rx} ${ry} 0 1 0 ${cx + rx} ${cy}A${rx} ${ry} 0 1 0 ${cx - rx} ${cy}Z`;
    }
    case "polygon":
    case "polyline":
      return `M${(a.points ?? "").trim()}${node.name === "polygon" ? "Z" : ""}`;
    default:
      return null;
  }
}

const flatten = {
  name: "flatten",
  fn: () => {
    const transforms = new Map();
    return {
      element: {
        enter(node, parent) {
          const inherited = transforms.get(parent) ?? "";
          const own = node.attributes.transform ?? "";
          const total = `${inherited} ${own}`.trim();
          transforms.set(node, total);
          delete node.attributes.transform;
          const d = node.name === "path" ? node.attributes.d : shapeToPath(node);
          if (d == null) return;
          for (const k of ["x", "y", "width", "height", "rx", "ry", "cx", "cy", "r", "points"]) delete node.attributes[k];
          node.name = "path";
          node.attributes.d = svgpath(d).transform(total).abs().unarc().round(3).toString();
        },
      },
    };
  },
};

function clean(svg) {
  const result = optimize(svg, {
    multipass: true,
    floatPrecision: 3,
    plugins: [
      "convertStyleToAttrs",
      flatten,
      "preset-default",
      "removeDimensions",
    ],
  }).data;
  // preset 可能把路径重新压缩出圆弧简写，再展开一次保证 CoreSVG 能正确渲染
  return result.replace(/ d="([^"]+)"/g, (_, d) => ` d="${svgpath(d).abs().unarc().unshort().round(3).toString()}"`);
}

// ---------- 按图形包围盒把 viewBox 收成正方形 ----------
function fitViewBox(svg) {
  if (/transform=/.test(svg)) return { svg, error: "清理后仍有无法展开的 transform，需人工处理" };
  const box = { minX: Infinity, minY: Infinity, maxX: -Infinity, maxY: -Infinity };
  const add = (x, y) => {
    box.minX = Math.min(box.minX, x); box.maxX = Math.max(box.maxX, x);
    box.minY = Math.min(box.minY, y); box.maxY = Math.max(box.maxY, y);
  };
  for (const [, d] of svg.matchAll(/ d="([^"]+)"/g)) {
    svgpath(d).abs().unshort().iterate((seg, _i, x, y) => {
      const [cmd, ...n] = seg;
      if (cmd === "H") add(n[0], y);
      else if (cmd === "V") add(x, n[0]);
      else for (let i = 0; i + 1 < n.length; i += 2) add(n[i], n[i + 1]);
    });
  }
  if (!Number.isFinite(box.minX)) return { svg, error: "没有可见路径" };
  const size = Math.max(box.maxX - box.minX, box.maxY - box.minY);
  const x = box.minX - (size - (box.maxX - box.minX)) / 2;
  const y = box.minY - (size - (box.maxY - box.minY)) / 2;
  const viewBox = [x, y, size, size].map((v) => +v.toFixed(3)).join(" ");
  const fitted = svg.replace(/ viewBox="[^"]*"/, "").replace(/^<svg/, `<svg viewBox="${viewBox}"`);
  return { svg: fitted };
}

// ---------- 逐项校验 ----------
const delivery = readDelivery();
const expectedSlugs = new Set(expected.map((e) => e.slug));
const results = [];
const counts = {};

for (const item of delivery) {
  const errors = [];
  const warnings = [];
  const r = { item, errors, warnings, files: {} };
  results.push(r);
  counts[item.slug] = (counts[item.slug] ?? 0) + 1;

  if (!expectedSlugs.has(item.slug)) errors.push("slug 不在本批清单里");
  if (!["ok", "not_found", "ambiguous"].includes(item.status)) errors.push(`status 无效：${item.status}`);
  if (item.status !== "ok") continue;

  for (const key of ["brand", "website", "source_url", "source_type", "mark_type", "svg"]) {
    if (!item[key]) errors.push(`缺少 ${key}`);
  }
  if (typeof item.mono !== "boolean") errors.push("mono 必须是 true / false");
  if (item.hex && !/^[0-9a-fA-F]{6}$/.test(item.hex)) errors.push(`hex 格式不对：${item.hex}`);
  if (item.source_url && !/^https:\/\//.test(item.source_url)) errors.push("source_url 不是 https 链接");
  if (FORBIDDEN_SOURCES.test(item.source_url ?? "")) errors.push(`来源属于禁止范围：${item.source_url}`);
  if (item.source_type === "app_store") warnings.push("据 App 图标重绘，需核对形状");
  if (item.source_type === "wikimedia") warnings.push("来源是 Wikimedia，需确认是否为官方最新版");
  if (item.website && item.source_url) {
    const host = (u) => { try { return new URL(u).hostname.replace(/^www\./, ""); } catch { return ""; } };
    const brandHost = host(item.website).split(".").slice(-2).join(".");
    if (["brand_kit", "official_site"].includes(item.source_type) && !host(item.source_url).endsWith(brandHost)) {
      warnings.push(`来源域名 ${host(item.source_url)} 与官网 ${brandHost} 不一致`);
    }
  }

  for (const variant of ["svg", "svg_dark"]) {
    if (!item[variant]) continue;
    const check = inspect(item[variant]);
    errors.push(...check.errors.map((e) => `${variant}: ${e}`));
    warnings.push(...check.warnings.map((w) => `${variant}: ${w}`));
    if (check.errors.length) continue;
    const fitted = fitViewBox(clean(item[variant]));
    if (fitted.error) {
      errors.push(`${variant}: ${fitted.error}`);
      continue;
    }
    // 多色标志里有接近黑/白的颜色，在对应背景上会看不见
    if (!item.mono) {
      const luminances = [...fitted.svg.matchAll(/(?:fill|stroke|stop-color)="#([0-9a-f]{3}|[0-9a-f]{6})"/gi)]
        .map(([, h]) => (h.length === 3 ? [...h].map((c) => c + c).join("") : h))
        .map((h) => [0, 2, 4].map((i) => parseInt(h.slice(i, i + 2), 16) / 255))
        .map(([r, g, b]) => 0.2126 * r + 0.7152 * g + 0.0722 * b);
      if (variant === "svg" && !item.svg_dark && luminances.some((l) => l < 0.15)) {
        warnings.push("含接近黑色的部分，深色背景下可能看不见（没有 svg_dark）");
      }
      if (variant === "svg" && luminances.some((l) => l > 0.9)) warnings.push("含接近白色的部分，浅色背景下可能看不见");
    }
    const name = variant === "svg" ? `${item.slug}.svg` : `${item.slug}-dark.svg`;
    r.files[variant] = name;
    r.cleaned ??= {};
    r.cleaned[variant] = fitted.svg;
  }
}

for (const slug of expectedSlugs) {
  if (!counts[slug]) results.push({ item: { slug, status: "missing" }, errors: ["交付中缺少此项"], warnings: [], files: {} });
}
for (const [slug, n] of Object.entries(counts)) {
  if (n > 1) results.find((r) => r.item.slug === slug).errors.push(`重复出现 ${n} 次`);
}

// ---------- 输出清理后的 SVG 与审核页 ----------
fs.rmSync(reviewDir, { recursive: true, force: true });
fs.mkdirSync(reviewDir, { recursive: true });
for (const r of results) {
  for (const [variant, svg] of Object.entries(r.cleaned ?? {})) fs.writeFileSync(path.join(reviewDir, r.files[variant]), svg);
}

const esc = (s) => String(s ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
// 审核页自包含：SVG 以 data URI 内联，直接双击打开即可
const dataURI = (svg) => `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;
const tile = (svg, dark, mono) => {
  if (!svg) return `<div class="tile ${dark ? "dark" : ""}"></div>`;
  const file = dataURI(svg);
  // mono 图标在深色背景下模拟 App 的处理：用遮罩染成白色
  const img = dark && mono
    ? `<span class="mask" style="-webkit-mask-image:url('${file}');mask-image:url('${file}')"></span>`
    : `<img src="${file}">`;
  return `<div class="tile ${dark ? "dark" : ""}">${img}</div>`;
};
const cards = results.map(({ item, errors, warnings, cleaned = {} }) => {
  const state = errors.length ? "error" : item.status !== "ok" ? "skip" : warnings.length ? "warn" : "pass";
  const darkSVG = cleaned.svg_dark ?? cleaned.svg;
  return `<article class="${state}">
  <header><strong>${esc(item.brand ?? item.slug)}</strong><code>${esc(item.slug)}</code><span class="badge">${esc(item.status)}</span></header>
  <div class="tiles">${tile(cleaned.svg, false, item.mono)}${tile(darkSVG, true, item.mono && !cleaned.svg_dark)}</div>
  <p class="meta">${esc(item.mark_type ?? "")} · ${esc(item.source_type ?? "")} · mono=${esc(item.mono)}
  ${item.source_url ? `<br><a href="${esc(item.source_url)}" target="_blank">${esc(item.source_url)}</a>` : ""}</p>
  ${errors.map((e) => `<p class="e">✗ ${esc(e)}</p>`).join("")}
  ${warnings.map((w) => `<p class="w">! ${esc(w)}</p>`).join("")}
  ${item.notes ? `<p class="n">${esc(item.notes)}</p>` : ""}
</article>`;
});
const summary = ["pass", "warn", "error", "skip"].map((s) => `${s}: ${cards.filter((c) => c.startsWith(`<article class="${s}"`)).length}`).join(" · ");
fs.writeFileSync(path.join(reviewDir, "review.html"), `<!doctype html><meta charset="utf-8"><title>Batch ${id} review</title>
<style>
body{font:13px -apple-system,sans-serif;margin:16px;background:#f2f2f7}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:12px}
article{background:#fff;border-radius:12px;padding:12px;border-left:4px solid #34c759}
article.warn{border-color:#ff9f0a}article.error{border-color:#ff3b30}article.skip{border-color:#8e8e93}
header{display:flex;gap:6px;align-items:baseline}header code{color:#8e8e93}.badge{margin-left:auto;color:#8e8e93}
.tiles{display:flex;gap:8px;margin:8px 0}
.tile{width:96px;height:96px;border-radius:12px;background:#f6f6f6;display:grid;place-items:center}
.tile.dark{background:#282828}.tile img,.tile .mask{width:56px;height:56px}
.mask{display:block;background:#fff;-webkit-mask-size:contain;mask-size:contain;-webkit-mask-repeat:no-repeat;mask-repeat:no-repeat;-webkit-mask-position:center;mask-position:center}
.meta{color:#636366;word-break:break-all}.e{color:#ff3b30;margin:2px 0}.w{color:#c77c00;margin:2px 0}.n{color:#3a3a3c}
</style><h1>Batch ${id}</h1><p>${summary}</p><main>${cards.join("\n")}</main>`);

const errorCount = results.filter((r) => r.errors.length).length;
console.log(`batch ${id}: ${summary}`);
for (const r of results.filter((r) => r.errors.length)) console.log(`  ✗ ${r.item.slug}: ${r.errors.join("; ")}`);
console.log(`review: ${path.join(reviewDir, "review.html")}`);
process.exitCode = errorCount ? 1 : 0;
