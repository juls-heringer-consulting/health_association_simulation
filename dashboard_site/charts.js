/* Small SVG chart kit for the KVSim dashboard. No dependencies.
   Every chart function takes (spec, width, height, palette) and returns an SVG string.
   Hover text lives in data-tip attributes (first line = title); a shared tooltip shows it.
   Elements with data-pick are clickable and call the card's onPick(value). */
'use strict';

const KV = (window.KV = {});

/* ---------- palette (light/dark are selected steps, not an automatic flip) ---------- */
KV.PALETTES = {
  light: {
    mode: 'light', surface: '#fcfcfb', ink: '#0b0b0b', ink2: '#52514e', muted: '#898781',
    grid: '#e1e0d9', axis: '#c3c2b7',
    blue: '#2a78d6', orange: '#eb6834', aqua: '#1baf7a', violet: '#6250d6', red: '#e34948', gray: '#898781',
    ordinal: ['#184f95', '#2a78d6', '#86b6ef'],                                   // most -> least urgent
    seq: ['#cde2fb', '#9ec5f4', '#6da7ec', '#3987e5', '#256abf', '#184f95'],      // low -> high
    div: { neg: '#e34948', mid: '#f0efec', pos: '#3987e5' },
  },
  dark: {
    mode: 'dark', surface: '#1a1a19', ink: '#f0efec', ink2: '#c3c2b7', muted: '#898781',
    grid: '#2c2c2a', axis: '#383835',
    blue: '#3987e5', orange: '#d95926', aqua: '#199e70', violet: '#9085e9', red: '#e66767', gray: '#898781',
    ordinal: ['#9ec5f4', '#3987e5', '#1c5cab'],
    seq: ['#0d366b', '#104281', '#1c5cab', '#2a78d6', '#5598e7', '#86b6ef'],
    div: { neg: '#e66767', mid: '#383835', pos: '#3987e5' },
  },
};

/* ---------- formatting ---------- */
const nf0 = new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
KV.fmt = {
  int: (v) => nf0.format(v),
  dec1: (v) => nf1.format(v),
  eur: (v) => nf0.format(v) + ' €',
  pct: (v, d = 1) => (v * 100).toFixed(d) + ' %',
  compact(v) {
    const a = Math.abs(v);
    if (a >= 1e6) return (v / 1e6).toFixed(a >= 1e7 ? 0 : 1).replace(/\.0$/, '') + ' M';
    if (a >= 1e3) return (v / 1e3).toFixed(a >= 1e4 ? 0 : 1).replace(/\.0$/, '') + ' k';
    return nf0.format(v);
  },
};
const esc = (KV.esc = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]));
const sum = (a) => a.reduce((s, v) => s + (v || 0), 0);

/* ---------- text measuring ---------- */
const FONT = 'system-ui, -apple-system, "Segoe UI", sans-serif';
const ctx = document.createElement('canvas').getContext('2d');
function tw(text, size = 12, weight = 400) {
  ctx.font = `${weight} ${size}px ${FONT}`;
  return ctx.measureText(String(text)).width;
}
function fit(text, max, size = 12, weight = 400) {
  text = String(text);
  if (tw(text, size, weight) <= max) return text;
  let t = text;
  while (t.length > 1 && tw(t + '…', size, weight) > max) t = t.slice(0, -1);
  return t + '…';
}
function wrap(text, max, size = 12, maxLines = 2) {
  const words = String(text).split(/\s+/);
  const lines = [];
  let cur = '';
  for (const w of words) {
    const t = cur ? cur + ' ' + w : w;
    if (!cur || tw(t, size) <= max) cur = t;
    else { lines.push(cur); cur = w; }
  }
  if (cur) lines.push(cur);
  if (lines.length > maxLines) {
    const rest = lines.slice(maxLines - 1).join(' ');
    lines.length = maxLines - 1;
    lines.push(rest);
  }
  return lines.map((l) => fit(l, max, size));
}
KV.tw = tw;

/* ---------- colour helpers ---------- */
function hex2rgb(h) { const n = parseInt(h.slice(1), 16); return [(n >> 16) & 255, (n >> 8) & 255, n & 255]; }
function rgb2hex(r) { return '#' + r.map((v) => Math.round(v).toString(16).padStart(2, '0')).join(''); }
function lum(h) {
  const c = hex2rgb(h).map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4; });
  return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2];
}
const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
/** label colour inside a fill: white on saturated fills (palette rule), near-black where white drops below 3:1 */
KV.onFill = (fill) => (contrast(fill, '#ffffff') >= 3 ? '#ffffff' : '#0b0b0b');
function mix(a, b, t) { const x = hex2rgb(a), y = hex2rgb(b); return rgb2hex(x.map((v, i) => v + (y[i] - v) * t)); }
/** colour at position t (0..1) along a list of stops */
KV.ramp = (stops, t) => {
  t = Math.max(0, Math.min(1, t));
  const p = t * (stops.length - 1), i = Math.min(Math.floor(p), stops.length - 2);
  return mix(stops[i], stops[i + 1], p - i);
};
/** diverging: v below mid -> neg pole, above -> pos pole */
KV.diverge = (P, v, lo, mid, hi) =>
  v <= mid ? mix(P.div.neg, P.div.mid, Math.max(0, (v - lo) / (mid - lo))) : mix(P.div.mid, P.div.pos, Math.min(1, (v - mid) / (hi - mid)));

/* ---------- scales ---------- */
function niceTicks(max, n = 5) {
  if (!(max > 0)) return [0, 1];
  const raw = max / n, p = 10 ** Math.floor(Math.log10(raw)), m = raw / p;
  const step = (m <= 1 ? 1 : m <= 2 ? 2 : m <= 2.5 ? 2.5 : m <= 5 ? 5 : 10) * p;
  const top = Math.ceil(max / step - 1e-9) * step, out = [];
  for (let v = 0; v <= top + step * 1e-6; v += step) out.push(+v.toFixed(10));
  return out;
}

/* ---------- svg bits ---------- */
const svgOpen = (w, h, label) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" role="img" aria-label="${esc(label || '')}" font-family='${FONT}'>`;
const text = (x, y, s, o = {}) =>
  `<text x="${x}" y="${y}" font-size="${o.size || 12}" fill="${o.fill}" text-anchor="${o.anchor || 'start'}"` +
  `${o.weight ? ` font-weight="${o.weight}"` : ''}${o.base ? ` dominant-baseline="${o.base}"` : ''}` +
  `${o.cls ? ` class="${o.cls}"` : ''}>${esc(s)}</text>`;
const tipAttr = (lines) => ` data-tip="${esc(lines.filter((l) => l !== null && l !== undefined).join('\n'))}"`;
/** bar with 4px rounded data-end; dir: up | right */
function bar(x, y, w, h, fill, dir, round = true, extra = '') {
  if (w <= 0 || h <= 0) return '';
  const r = round ? Math.min(4, dir === 'up' ? w / 2 : h / 2, dir === 'up' ? h : w) : 0;
  let d;
  if (!r) d = `M${x},${y}h${w}v${h}h${-w}z`;
  else if (dir === 'up') d = `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}z`;
  else d = `M${x},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h - r}Q${x + w},${y + h} ${x + w - r},${y + h}H${x}z`;
  return `<path d="${d}" fill="${fill}"${extra}/>`;
}
function multiline(x, y, lines, o) {
  return lines.map((l, i) => text(x, y + i * 14, l, o)).join('');
}

/* ======================================================================
   BARS - vertical or horizontal; single, stacked or 100 % stacked
   spec: cats[], series[{name,color,values[]}], horizontal, percent, fmt, axisFmt,
         colorAt(si,ci), dim(ci), pick(ci), label:'total'|'inside'|'none',
         rule:{after:i,label} (vertical), valueRule:{value,label} (horizontal), tipTitle(ci)
   ====================================================================== */
KV.bars = function (o, W, H, P) {
  const n = o.cats.length, S = o.series;
  const fmt = o.fmt || KV.fmt.int, axisFmt = o.axisFmt || (o.percent ? (v) => Math.round(v * 100) + ' %' : KV.fmt.compact);
  const totals = o.cats.map((_, ci) => sum(S.map((s) => s.values[ci])));
  const val = (si, ci) => { const v = S[si].values[ci] || 0; return o.percent ? (totals[ci] ? v / totals[ci] : 0) : v; };
  const maxV = o.percent ? 1 : Math.max(...totals, o.valueRule ? o.valueRule.value : 0);
  const tk = o.percent ? [0, 0.25, 0.5, 0.75, 1] : niceTicks(maxV, H < 230 ? 3 : 4);
  const top = tk[tk.length - 1];
  const label = o.label || (o.percent ? 'inside' : 'total');
  const color = (si, ci) => (o.colorAt ? o.colorAt(si, ci) : S[si].color);
  const tipFor = (ci) => [o.tipTitle ? o.tipTitle(ci) : o.cats[ci],
    ...S.map((s, si) => (S.length > 1 ? `${s.name}: ` : '') +
      (o.percent ? `${fmt(s.values[ci] || 0)} (${KV.fmt.pct(val(si, ci), 0)})` : fmt(s.values[ci] || 0))),
    S.length > 1 ? `Total: ${fmt(totals[ci])}` : null, ...(o.tipExtra ? o.tipExtra(ci) : [])];
  let out = svgOpen(W, H, o.aria);

  if (!o.horizontal) {
    const left = Math.max(...tk.map((t) => tw(axisFmt(t), 11))) + 10, right = 6, topM = label === 'total' ? 18 : 8;
    const band = (W - left - right) / n;
    const catLines = o.cats.map((c) => wrap(c, Math.max(band - 6, 24), 11, 2));
    const bottom = 10 + 14 * Math.max(...catLines.map((l) => l.length));
    const ph = H - topM - bottom, y = (v) => topM + ph * (1 - v / top);
    const bw = Math.min(band * 0.62, 46);
    tk.forEach((t) => {
      out += `<line x1="${left}" x2="${W - right}" y1="${y(t)}" y2="${y(t)}" stroke="${t === 0 ? P.axis : P.grid}" stroke-width="1"/>`;
      out += text(left - 6, y(t), axisFmt(t), { fill: P.muted, size: 11, anchor: 'end', base: 'middle', cls: 'num' });
    });
    o.cats.forEach((c, ci) => {
      const cx = left + band * ci + band / 2, x0 = cx - bw / 2;
      const op = o.dim && o.dim(ci) ? ' opacity="0.3"' : '';
      out += `<g${op}>`;
      let cum = 0;
      const visible = S.map((_, si) => si).filter((si) => val(si, ci) > 0);
      visible.forEach((si, k) => {
        const v = val(si, ci), yTop = y(cum + v), yBot = y(cum), last = k === visible.length - 1;
        const hgt = yBot - yTop - (last ? 0 : 2);
        out += bar(x0, yTop + (last ? 0 : 2), bw, hgt, color(si, ci), 'up', last);
        if (label === 'inside' && hgt >= 16) out += text(cx, yTop + (last ? 0 : 2) + hgt / 2, o.percent ? KV.fmt.pct(v, 0) : fmt(S[si].values[ci]), { fill: KV.onFill(color(si, ci)), size: 11, anchor: 'middle', base: 'central' });
        cum += v;
      });
      if (label === 'total' && totals[ci] > 0) out += text(cx, y(cum) - 5, (o.labelFmt || fmt)(totals[ci]), { fill: P.ink2, size: 11, anchor: 'middle', cls: 'num' });
      out += multiline(cx, H - bottom + 16, catLines[ci], { fill: P.ink2, size: 11, anchor: 'middle' });
      out += '</g>';
      const pick = o.pick ? ` data-pick="${esc(o.pick(ci))}" class="hit pick"` : ' class="hit"';
      out += `<rect x="${left + band * ci}" y="${topM}" width="${band}" height="${ph}" fill="transparent"${pick}${tipAttr(tipFor(ci))}/>`;
    });
    if (o.rule) {
      const rx = left + band * (o.rule.after + 1);
      out += `<line x1="${rx}" x2="${rx}" y1="${topM - 4}" y2="${topM + ph}" stroke="${P.ink2}" stroke-dasharray="3 3"/>`;
      out += text(rx + 4, topM + 6, o.rule.label, { fill: P.ink2, size: 11 });
    }
  } else {
    const labW = Math.min(Math.max(...o.cats.map((c) => tw(c, 12))), W * (o.labelShare || 0.36));
    const left = labW + 12;
    const right = label === 'total' ? Math.max(...totals.map((t) => tw(fmt(t), 11))) + 10 : 8;
    const axisH = o.percent || o.axis ? 18 : 0, topM = o.valueRule ? 16 : 2;
    const band = (H - topM - axisH) / n, bh = Math.min(band * 0.66, 26);
    const pw = W - left - right, x = (v) => left + pw * (v / top);
    if (axisH) tk.forEach((t) => {
      out += `<line x1="${x(t)}" x2="${x(t)}" y1="${topM}" y2="${H - axisH}" stroke="${t === 0 ? P.axis : P.grid}"/>`;
      out += text(x(t), H - 4, axisFmt(t), { fill: P.muted, size: 11, anchor: 'middle', cls: 'num' });
    });
    else out += `<line x1="${left}" x2="${left}" y1="${topM}" y2="${H}" stroke="${P.axis}"/>`;
    o.cats.forEach((c, ci) => {
      const cy = topM + band * ci + band / 2, y0 = cy - bh / 2;
      const op = o.dim && o.dim(ci) ? ' opacity="0.3"' : '';
      out += `<g${op}>` + text(left - 8, cy, fit(c, labW, 12), { fill: P.ink2, anchor: 'end', base: 'central' });
      let cum = 0;
      const visible = S.map((_, si) => si).filter((si) => val(si, ci) > 0);
      visible.forEach((si, k) => {
        const v = val(si, ci), last = k === visible.length - 1, x0 = x(cum), wdt = x(cum + v) - x0 - (last ? 0 : 2);
        out += bar(x0, y0, wdt, bh, color(si, ci), 'right', last);
        if (label === 'inside' && wdt >= 34) out += text(x0 + wdt / 2, cy, o.percent ? KV.fmt.pct(v, 0) : fmt(S[si].values[ci]), { fill: KV.onFill(color(si, ci)), size: 11, anchor: 'middle', base: 'central' });
        cum += v;
      });
      if (label === 'total') out += text(x(cum) + 6, cy, fmt(totals[ci]), { fill: P.ink2, size: 11, base: 'central', cls: 'num' });
      out += '</g>';
      const pick = o.pick ? ` data-pick="${esc(o.pick(ci))}" class="hit pick"` : ' class="hit"';
      out += `<rect x="0" y="${topM + band * ci}" width="${W}" height="${band}" fill="transparent"${pick}${tipAttr(tipFor(ci))}/>`;
    });
    if (o.valueRule) {
      const rx = x(o.valueRule.value);
      out += `<line x1="${rx}" x2="${rx}" y1="${topM - 2}" y2="${H - axisH}" stroke="${P.ink2}" stroke-dasharray="3 3" pointer-events="none"/>`;
      out += text(rx, 10, o.valueRule.label, { fill: P.ink2, size: 11, anchor: 'middle' });
    }
  }
  return out + '</svg>';
};

/* ======================================================================
   DONUT - spec: items[{name,value,color}], fmt, centerValue, centerLabel
   ====================================================================== */
KV.donut = function (o, W, H, P) {
  const fmt = o.fmt || KV.fmt.int, total = sum(o.items.map((d) => d.value));
  const stacked = W < 380;
  const size = stacked ? Math.min(W, H - o.items.length * 22 - 8) : Math.min(H, W * 0.48);
  const R = size / 2 - 2, r = R * 0.62, cx = stacked ? W / 2 : size / 2, cy = size / 2;
  let out = svgOpen(W, H, o.aria), a0 = -Math.PI / 2;
  o.items.forEach((d) => {
    const a1 = a0 + (d.value / total) * Math.PI * 2, large = a1 - a0 > Math.PI ? 1 : 0;
    const p = (rad, a) => `${cx + rad * Math.cos(a)},${cy + rad * Math.sin(a)}`;
    const path = d.value >= total
      ? `M${cx - R},${cy}a${R},${R} 0 1,0 ${2 * R},0a${R},${R} 0 1,0 ${-2 * R},0M${cx - r},${cy}a${r},${r} 0 1,1 ${2 * r},0a${r},${r} 0 1,1 ${-2 * r},0`
      : `M${p(R, a0)}A${R},${R} 0 ${large} 1 ${p(R, a1)}L${p(r, a1)}A${r},${r} 0 ${large} 0 ${p(r, a0)}z`;
    out += `<path d="${path}" fill="${d.color}" stroke="${P.surface}" stroke-width="2" fill-rule="evenodd" class="hit"${tipAttr([d.name, `${fmt(d.value)} (${KV.fmt.pct(d.value / total)})`])}/>`;
    a0 = a1;
  });
  out += text(cx, cy - 4, o.centerValue ?? fmt(total), { fill: P.ink, size: Math.max(14, Math.min(22, r / 2.6)), weight: 600, anchor: 'middle', cls: 'num' });
  out += text(cx, cy + 14, o.centerLabel || 'total', { fill: P.ink2, size: 11, anchor: 'middle' });
  // direct-labelled legend
  const lx = stacked ? 8 : size + 18, lw = W - lx - 4;
  const ly0 = stacked ? size + 14 : cy - (o.items.length * 40) / 2 + 12;
  o.items.forEach((d, i) => {
    const y = ly0 + i * (stacked ? 22 : 40);
    out += `<rect x="${lx}" y="${y - 9}" width="10" height="10" rx="2" fill="${d.color}"/>`;
    if (stacked) {
      out += text(lx + 16, y, fit(d.name, lw - 110, 12), { fill: P.ink2 });
      out += text(W - 4, y, `${fmt(d.value)} · ${KV.fmt.pct(d.value / total, 0)}`, { fill: P.ink, anchor: 'end', cls: 'num' });
    } else {
      out += text(lx + 16, y, fit(d.name, lw - 16, 12), { fill: P.ink2 });
      out += text(lx + 16, y + 17, `${fmt(d.value)} · ${KV.fmt.pct(d.value / total, 1)}`, { fill: P.ink, size: 13, weight: 600, cls: 'num' });
    }
  });
  return out + '</svg>';
};

/* ======================================================================
   TREEMAP (squarified) - spec: items[{name,value,color,tip[]}], fmt
   ====================================================================== */
function squarify(items, X, Y, Wd, Ht) {
  const total = sum(items.map((d) => d.value)), k = (Wd * Ht) / total;
  const nodes = items.map((d) => ({ d, a: d.value * k }));
  const out = [], rect = { x: X, y: Y, w: Wd, h: Ht };
  const worst = (row, side) => {
    const s = sum(row.map((n) => n.a)), mx = Math.max(...row.map((n) => n.a)), mn = Math.min(...row.map((n) => n.a));
    return Math.max((side * side * mx) / (s * s), (s * s) / (side * side * mn));
  };
  const lay = (row) => {
    const s = sum(row.map((n) => n.a));
    if (rect.w >= rect.h) {
      const sw = s / rect.h; let yy = rect.y;
      row.forEach((n) => { const hh = n.a / sw; out.push({ ...n, x: rect.x, y: yy, w: sw, h: hh }); yy += hh; });
      rect.x += sw; rect.w -= sw;
    } else {
      const sh = s / rect.w; let xx = rect.x;
      row.forEach((n) => { const ww = n.a / sh; out.push({ ...n, x: xx, y: rect.y, w: ww, h: sh }); xx += ww; });
      rect.y += sh; rect.h -= sh;
    }
  };
  let row = [], i = 0;
  while (i < nodes.length) {
    const side = Math.min(rect.w, rect.h);
    if (!row.length || worst([...row, nodes[i]], side) <= worst(row, side)) row.push(nodes[i++]);
    else { lay(row); row = []; }
  }
  if (row.length) lay(row);
  return out;
}
KV.treemap = function (o, W, H, P) {
  const fmt = o.fmt || KV.fmt.int, total = sum(o.items.map((d) => d.value));
  const items = [...o.items].sort((a, b) => b.value - a.value);
  let out = svgOpen(W, H, o.aria);
  squarify(items, 0, 0, W, H).forEach((n) => {
    const x = n.x + 1, y = n.y + 1, w = n.w - 2, h = n.h - 2, d = n.d, ink = KV.onFill(d.color);
    out += `<rect x="${x}" y="${y}" width="${Math.max(w, 0)}" height="${Math.max(h, 0)}" rx="4" fill="${d.color}" class="hit"` +
      tipAttr([d.name, ...(d.tip || []), `${fmt(d.value)} (${KV.fmt.pct(d.value / total)})`]) + '/>';
    if (w > 54 && h > 34) {
      const lines = wrap(d.name, w - 14, 12, h > 62 ? 2 : 1);
      out += `<g pointer-events="none">` + multiline(x + 7, y + 17, lines, { fill: ink, size: 12, weight: 600 });
      if (h > 26 + lines.length * 14) out += text(x + 7, y + 17 + lines.length * 14 + 2, `${fmt(d.value)} · ${KV.fmt.pct(d.value / total, 0)}`, { fill: ink, size: 11, cls: 'num' });
      out += '</g>';
    }
  });
  return out + '</svg>';
};

/* ======================================================================
   HEATMAP - spec: rows[], cols[], cell(ri,ci) -> {fill,text,tip[]} | null, highlightCol, rowLabelShare
   ====================================================================== */
KV.heatmap = function (o, W, H, P) {
  const labW = Math.min(Math.max(...o.rows.map((r) => tw(r, 12))), W * (o.rowLabelShare || 0.3));
  const left = labW + 12, cw = (W - left) / o.cols.length;
  const colLines = o.cols.map((c) => wrap(c, cw - 6, 11, 2));
  const topM = 8 + 14 * Math.max(...colLines.map((l) => l.length));
  const ch = (H - topM) / o.rows.length;
  let out = svgOpen(W, H, o.aria);
  o.cols.forEach((c, ci) => {
    const hl = o.highlightCol === ci;
    out += multiline(left + cw * ci + cw / 2, 12, colLines[ci], { fill: hl ? P.ink : P.ink2, size: 11, anchor: 'middle', weight: hl ? 700 : 400 });
  });
  o.rows.forEach((r, ri) => {
    const y = topM + ch * ri;
    out += text(left - 8, y + ch / 2, fit(r, labW, 12), { fill: P.ink2, anchor: 'end', base: 'central' });
    o.cols.forEach((c, ci) => {
      const x = left + cw * ci, cell = o.cell(ri, ci);
      if (!cell) {
        out += `<rect x="${x + 1}" y="${y + 1}" width="${cw - 2}" height="${ch - 2}" rx="3" fill="none" stroke="${P.grid}"/>`;
        out += text(x + cw / 2, y + ch / 2, '–', { fill: P.muted, anchor: 'middle', base: 'central' });
        return;
      }
      out += `<rect x="${x + 1}" y="${y + 1}" width="${cw - 2}" height="${ch - 2}" rx="3" fill="${cell.fill}" class="hit"${tipAttr(cell.tip)}/>`;
      if (cw > 30 && ch > 16) out += `<g pointer-events="none">` + text(x + cw / 2, y + ch / 2, fit(cell.text, cw - 6, 11), { fill: KV.onFill(cell.fill), size: 11, anchor: 'middle', base: 'central', cls: 'num', weight: cell.bold ? 700 : 400 }) + '</g>';
    });
  });
  if (o.highlightCol != null) {
    const x = left + cw * o.highlightCol;
    out += `<rect x="${x - 1}" y="${topM - 2}" width="${cw + 2}" height="${H - topM + 1}" rx="5" fill="none" stroke="${P.ink}" stroke-width="2" pointer-events="none"/>`;
  }
  return out + '</svg>';
};

/* ======================================================================
   SCATTER - spec: points[{x,y,color,tip[]}], xLabel, yLabel, xFmt, yFmt
   ====================================================================== */
KV.scatter = function (o, W, H, P) {
  const xs = o.points.map((p) => p.x), ys = o.points.map((p) => p.y);
  const xt = niceTicks(Math.max(...xs), 5), yt = niceTicks(Math.max(...ys), 4);
  const xFmt = o.xFmt || KV.fmt.compact, yFmt = o.yFmt || KV.fmt.compact;
  const left = Math.max(...yt.map((t) => tw(yFmt(t), 11))) + 12, bottom = 36, topM = 10, right = 12;
  const pw = W - left - right, ph = H - topM - bottom;
  const X = (v) => left + (pw * v) / xt[xt.length - 1], Y = (v) => topM + ph * (1 - v / yt[yt.length - 1]);
  let out = svgOpen(W, H, o.aria);
  yt.forEach((t) => {
    out += `<line x1="${left}" x2="${W - right}" y1="${Y(t)}" y2="${Y(t)}" stroke="${t === 0 ? P.axis : P.grid}"/>`;
    out += text(left - 6, Y(t), yFmt(t), { fill: P.muted, size: 11, anchor: 'end', base: 'middle', cls: 'num' });
  });
  xt.forEach((t) => {
    out += `<line x1="${X(t)}" x2="${X(t)}" y1="${topM}" y2="${topM + ph}" stroke="${t === 0 ? P.axis : P.grid}"/>`;
    out += text(X(t), topM + ph + 15, xFmt(t), { fill: P.muted, size: 11, anchor: 'middle', cls: 'num' });
  });
  out += text(left + pw, H - 3, o.xLabel, { fill: P.ink2, size: 11, anchor: 'end' });
  out += text(left + 4, topM + 10, o.yLabel, { fill: P.ink2, size: 11 });
  o.points.forEach((p) => {
    out += `<circle cx="${X(p.x).toFixed(1)}" cy="${Y(p.y).toFixed(1)}" r="4.5" fill="${p.color}" fill-opacity="0.85" stroke="${P.surface}" stroke-width="1.5" class="hit dot"${tipAttr(p.tip)}/>`;
  });
  return out + '</svg>';
};

/* ======================================================================
   FUNNEL - spec: stages[{name,value,color}], fmt, stepLabel(prev,cur)
   ====================================================================== */
KV.funnel = function (o, W, H, P) {
  const fmt = o.fmt || KV.fmt.int, first = o.stages[0].value, n = o.stages.length;
  const labW = Math.min(Math.max(...o.stages.map((s) => tw(s.name, 12, 600))) + 8, W * 0.34);
  const left = labW + 10, pw = W - left - 4, rowH = H / n, bh = Math.min(rowH * 0.56, 46), mid = left + pw / 2;
  let out = svgOpen(W, H, o.aria);
  o.stages.forEach((s, i) => {
    const cy = rowH * i + rowH / 2, w = Math.max(pw * (s.value / first), 2), share = first ? s.value / first : 0;
    out += text(0, cy - 4, fit(s.name, labW, 12, 600), { fill: P.ink, weight: 600 });
    out += text(0, cy + 13, fmt(s.value), { fill: P.ink2, cls: 'num' });
    out += `<rect x="${mid - w / 2}" y="${cy - bh / 2}" width="${w}" height="${bh}" rx="4" fill="${s.color}" class="hit"${tipAttr([s.name, fmt(s.value), `${KV.fmt.pct(share)} of ${o.stages[0].name.toLowerCase()}`])}/>`;
    if (w > 60) out += `<g pointer-events="none">${text(mid, cy, KV.fmt.pct(share), { fill: KV.onFill(s.color), size: 13, weight: 600, anchor: 'middle', base: 'central', cls: 'num' })}</g>`;
    if (i > 0) {
      const prev = o.stages[i - 1].value, yArrow = rowH * i;
      out += text(mid, yArrow + 4, `▼ ${KV.fmt.pct(prev ? s.value / prev : 0)} ${o.stepLabels ? o.stepLabels[i] : ''}`.trim(), { fill: P.ink2, size: 11, anchor: 'middle', base: 'middle' });
    }
  });
  return out + '</svg>';
};

/* ======================================================================
   WATERFALL - spec: steps[{name,value,kind:'start'|'delta'|'total'}], colors{start,neg,pos,total}, fmt
   ====================================================================== */
KV.waterfall = function (o, W, H, P) {
  const fmt = o.fmt || KV.fmt.eur;
  let cum = 0;
  const bars = o.steps.map((s) => {
    let a, b;
    if (s.kind === 'start') { a = 0; b = s.value; cum = s.value; }
    else if (s.kind === 'total') { a = 0; b = s.value; }
    else { a = cum; b = cum + s.value; cum = b; }
    return { ...s, lo: Math.min(a, b), hi: Math.max(a, b), end: s.kind === 'delta' ? b : s.value };
  });
  const tk = niceTicks(Math.max(...bars.map((b) => b.hi)), 4), top = tk[tk.length - 1];
  const left = Math.max(...tk.map((t) => tw(KV.fmt.compact(t) + ' €', 11))) + 10, right = 6, topM = 20;
  const n = bars.length, band = (W - left - right) / n;
  const lines = o.steps.map((s) => wrap(s.name, band - 8, 11, 2));
  const bottom = 10 + 14 * Math.max(...lines.map((l) => l.length));
  const ph = H - topM - bottom, y = (v) => topM + ph * (1 - v / top), bw = Math.min(band * 0.58, 70);
  let out = svgOpen(W, H, o.aria);
  tk.forEach((t) => {
    out += `<line x1="${left}" x2="${W - right}" y1="${y(t)}" y2="${y(t)}" stroke="${t === 0 ? P.axis : P.grid}"/>`;
    out += text(left - 6, y(t), KV.fmt.compact(t) + ' €', { fill: P.muted, size: 11, anchor: 'end', base: 'middle', cls: 'num' });
  });
  bars.forEach((b, i) => {
    const cx = left + band * i + band / 2, x0 = cx - bw / 2;
    const color = b.kind === 'start' ? o.colors.start : b.kind === 'total' ? o.colors.total : b.value < 0 ? o.colors.neg : o.colors.pos;
    const y1 = y(b.hi), h = Math.max(y(b.lo) - y1, 1.5);
    out += `<rect x="${x0}" y="${y1}" width="${bw}" height="${h}" rx="3" fill="${color}"/>`;
    const lbl = (b.kind === 'delta' && b.value < 0 ? '− ' + fmt(-b.value) : fmt(b.value));
    const short = tw(lbl, 12, 600) > band - 6 ? (b.value < 0 ? '− ' : '') + KV.fmt.compact(Math.abs(b.value)) + ' €' : lbl;
    out += text(cx, y1 - 6, short, { fill: P.ink, size: 12, weight: 600, anchor: 'middle', cls: 'num' });
    if (o.shareOf) out += text(cx, y1 - 6 - 15, KV.fmt.pct(Math.abs(b.value) / o.shareOf, 1), { fill: P.ink2, size: 11, anchor: 'middle', cls: 'num' });
    if (i < n - 1) {
      const ly = y(b.end), nx = left + band * (i + 1) + band / 2 - bw / 2;
      out += `<line x1="${x0 + bw}" x2="${nx}" y1="${ly}" y2="${ly}" stroke="${P.muted}" stroke-dasharray="2 3"/>`;
    }
    out += multiline(cx, H - bottom + 16, lines[i], { fill: P.ink2, size: 11, anchor: 'middle' });
    out += `<rect x="${left + band * i}" y="${topM}" width="${band}" height="${ph}" fill="transparent" class="hit"${tipAttr([b.name, lbl, o.shareOf ? `${KV.fmt.pct(Math.abs(b.value) / o.shareOf)} of ${o.steps[0].name}` : null])}/>`;
  });
  return out + '</svg>';
};

/* ======================================================================
   STACKED AREA - spec: cats[], series[{name,color,values[]}], fmt
   ====================================================================== */
KV.area = function (o, W, H, P) {
  const fmt = o.fmt || KV.fmt.int, S = o.series, n = o.cats.length;
  const totals = o.cats.map((_, i) => sum(S.map((s) => s.values[i])));
  const tk = niceTicks(Math.max(...totals), 4), top = tk[tk.length - 1];
  const left = Math.max(...tk.map((t) => tw(KV.fmt.compact(t), 11))) + 10, right = 10, topM = 8, bottom = 24;
  const pw = W - left - right, ph = H - topM - bottom;
  const X = (i) => left + (pw * i) / (n - 1), Y = (v) => topM + ph * (1 - v / top);
  let out = svgOpen(W, H, o.aria);
  tk.forEach((t) => {
    out += `<line x1="${left}" x2="${W - right}" y1="${Y(t)}" y2="${Y(t)}" stroke="${t === 0 ? P.axis : P.grid}"/>`;
    out += text(left - 6, Y(t), KV.fmt.compact(t), { fill: P.muted, size: 11, anchor: 'end', base: 'middle', cls: 'num' });
  });
  const base = new Array(n).fill(0);
  S.forEach((s) => {
    const lo = base.slice(), hi = base.map((b, i) => b + (s.values[i] || 0));
    const upper = hi.map((v, i) => `${X(i)},${Y(v)}`), lower = lo.map((v, i) => `${X(i)},${Y(v)}`).reverse();
    out += `<path d="M${upper.join('L')}L${lower.join('L')}z" fill="${s.color}" fill-opacity="0.28"/>`;
    out += `<path d="M${upper.join('L')}" fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round"/>`;
    hi.forEach((v, i) => (base[i] = v));
  });
  const step = Math.ceil(tw('Sep', 11) * 1.8 / (pw / (n - 1)));
  o.cats.forEach((c, i) => { if (i % step === 0) out += text(X(i), H - 6, c, { fill: P.ink2, size: 11, anchor: 'middle' }); });
  o.cats.forEach((c, i) => {
    const x0 = i === 0 ? left : (X(i - 1) + X(i)) / 2, x1 = i === n - 1 ? W - right : (X(i) + X(i + 1)) / 2;
    out += `<g class="hit xhair"${tipAttr([o.tipTitle ? o.tipTitle(i) : c, ...S.map((s) => `${s.name}: ${fmt(s.values[i] || 0)}`), `Total: ${fmt(totals[i])}`])}>` +
      `<rect x="${x0}" y="${topM}" width="${x1 - x0}" height="${ph}" fill="transparent"/>` +
      `<line x1="${X(i)}" x2="${X(i)}" y1="${topM}" y2="${topM + ph}" stroke="${P.ink2}" class="xline"/>` +
      S.map((s, si) => `<circle cx="${X(i)}" cy="${Y(sum(S.slice(0, si + 1).map((q) => q.values[i])))}" r="4" fill="${s.color}" stroke="${P.surface}" stroke-width="2" class="xline"/>`).join('') +
      '</g>';
  });
  return out + '</svg>';
};
