/* KVSim dashboard - pages, slicers, cards. Data: window.KVSIM (data.js), charts: window.KV (charts.js). */
'use strict';
(function () {
  const D = window.KVSIM, F = KV.fmt, esc = KV.esc;
  const sum = (a) => a.reduce((s, v) => s + (v || 0), 0);
  const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const WEEKDAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // fixed category -> colour-slot assignments (colour follows the entity, never its rank)
  const FORMS = ['Einzelpraxis', 'Berufsausübungsgemeinschaft', 'Medizinisches Versorgungszentrum'];
  const FORM_SHORT = { Einzelpraxis: 'Einzelpraxis', 'Berufsausübungsgemeinschaft': 'BAG', 'Medizinisches Versorgungszentrum': 'MVZ' };
  const formColor = (P, f) => [P.blue, P.orange, P.aqua][FORMS.indexOf(f)] || P.gray;
  const LEVELS = ['hausärztliche Versorgung', 'allgemeine fachärztliche Versorgung', 'spezialisierte fachärztliche Versorgung'];
  const LEVEL_EN = { 'hausärztliche Versorgung': 'Primary care', 'allgemeine fachärztliche Versorgung': 'General specialist care', 'spezialisierte fachärztliche Versorgung': 'Specialised care' };
  const levelColor = (P, l) => [P.blue, P.orange, P.aqua][LEVELS.indexOf(l)] || P.gray;
  const URGENCY = ['AKUT', 'DRINGEND', 'ROUTINE'];
  const URGENCY_EN = { AKUT: 'Acute (AKUT)', DRINGEND: 'Urgent (DRINGEND)', ROUTINE: 'Routine (ROUTINE)' };
  const CHANNELS = ['TELEFON', 'ONLINE', 'APP'];
  const CHANNEL_EN = { TELEFON: 'Phone', ONLINE: 'Online', APP: 'App' };
  const STATUS_EN = { OFFEN: 'Open', GESPERRT: 'Closed', UNTERVERSORGT: 'Under-supplied' };
  const ageLabel = (s) => s.replace(/^(\d+) bis (\d+) Jahre$/, '$1–$2').replace(/^(\d+) Jahre und älter$/, '$1+');

  /* ---------------- state, theme, tooltip ---------------- */
  const PAGES = [];
  const state = { page: 'overview', kreis: 'all', quarter: 'all', specialty: 'all', stichtag: null, exQuarter: 'all', exKreis: 'all', exFach: 'all' };
  const live = [];
  let P;
  const root = document.documentElement;
  const resolved = () => (root.dataset.theme === 'light' || root.dataset.theme === 'dark' ? root.dataset.theme
    : matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  const redrawAll = () => { P = KV.PALETTES[resolved()]; live.forEach((c) => c.draw(true)); };

  const THEMES = ['auto', 'light', 'dark'];
  const themeBtn = document.getElementById('theme');
  function applyTheme(t) {
    if (t === 'auto') delete root.dataset.theme; else root.dataset.theme = t;
    themeBtn.textContent = { auto: 'Theme: auto', light: 'Theme: light', dark: 'Theme: dark' }[t];
    try { localStorage.setItem('kvsim-theme', t); } catch (e) { /* storage unavailable */ }
    redrawAll();
  }
  themeBtn.addEventListener('click', () => {
    const cur = root.dataset.theme || 'auto';
    applyTheme(THEMES[(THEMES.indexOf(cur) + 1) % THEMES.length]);
  });
  matchMedia('(prefers-color-scheme: dark)').addEventListener('change', redrawAll);

  const tip = document.getElementById('tip');
  function showTip(e) {
    if (e.target.closest && e.target.closest('.vega-stage')) return;   // Vega views drive the tooltip themselves
    const t = e.target.closest && e.target.closest('[data-tip]');
    if (!t) { tip.hidden = true; return; }
    const lines = t.getAttribute('data-tip').split('\n');
    tip.innerHTML = `<strong>${esc(lines[0])}</strong>` + lines.slice(1).map((l) => `<div>${esc(l)}</div>`).join('');
    tip.hidden = false;
    placeTip(e);
  }
  function placeTip(e) {
    const r = tip.getBoundingClientRect(), pad = 14;
    let x = e.clientX + pad, y = e.clientY + pad;
    if (x + r.width > innerWidth - 8) x = e.clientX - r.width - pad;
    if (y + r.height > innerHeight - 8) y = e.clientY - r.height - pad;
    tip.style.left = Math.max(8, x) + 'px';
    tip.style.top = Math.max(8, y) + 'px';
  }
  document.addEventListener('pointermove', showTip);
  document.addEventListener('pointerdown', showTip);
  document.addEventListener('scroll', () => (tip.hidden = true), { passive: true });

  /* ---------------- building blocks ---------------- */
  function h(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  const swatches = (items) => items.map((i) => `<span class="key"><i style="background:${i.color}"></i>${esc(i.name)}</span>`).join('');

  /** a chart card. o: title, sub, span, rows, height(w)|number, legend(P)->[{name,color}] | legendHtml(P), render(w,h,P), table()->{head,rows}, onPick, foot */
  function card(grid, o) {
    const sec = h('section', `card span-${o.span || 6}${o.rows ? ' rows-' + o.rows : ''}`);
    sec.innerHTML = `<header class="card-head"><div><h3>${esc(o.title)}</h3>${o.sub ? `<p class="sub">${esc(o.sub)}</p>` : ''}</div>` +
      (o.table ? '<button type="button" class="tbl-toggle" aria-pressed="false">Table</button>' : '') + '</header>' +
      '<div class="legend"></div><div class="plot"></div><div class="table-view" hidden></div>' +
      (o.foot ? `<p class="foot">${esc(o.foot)}</p>` : '');
    grid.appendChild(sec);
    const plot = sec.querySelector('.plot'), legend = sec.querySelector('.legend'), tv = sec.querySelector('.table-view');
    let lastW = 0;
    const draw = (force) => {
      const w = Math.floor(plot.clientWidth);
      if (!w || (w === lastW && !force)) return;
      lastW = w;
      const ht = typeof o.height === 'function' ? o.height(w) : o.height || 260;
      plot.style.height = ht + 'px';
      plot.innerHTML = o.render(w, ht, P);
      legend.innerHTML = o.legendHtml ? o.legendHtml(P) : o.legend ? swatches(o.legend(P)) : '';
      legend.hidden = !legend.innerHTML;
    };
    if (o.table) {
      const btn = sec.querySelector('.tbl-toggle');
      btn.addEventListener('click', () => {
        const on = btn.getAttribute('aria-pressed') !== 'true';
        btn.setAttribute('aria-pressed', on);
        btn.textContent = on ? 'Chart' : 'Table';
        if (on) {
          const t = o.table();
          tv.innerHTML = `<table><thead><tr>${t.head.map((c, i) => `<th${i ? ' class="n"' : ''}>${esc(c)}</th>`).join('')}</tr></thead><tbody>` +
            t.rows.map((r) => `<tr>${r.map((c, i) => `<td${i ? ' class="n"' : ''}>${esc(c)}</td>`).join('')}</tr>`).join('') + '</tbody></table>';
        }
        tv.hidden = !on; plot.hidden = on; legend.hidden = on || !legend.innerHTML;
        if (!on) draw(true);
      });
    }
    if (o.onPick) plot.addEventListener('click', (e) => { const t = e.target.closest('[data-pick]'); if (t) o.onPick(t.getAttribute('data-pick')); });
    const ro = new ResizeObserver(() => draw(false));
    ro.observe(plot);
    live.push({ draw, ro });
  }

  function kpis(parent, items) {
    const row = h('div', 'kpis');
    row.innerHTML = items.map((k) => `<div class="kpi"><div class="kpi-label">${esc(k.label)}</div>` +
      `<div class="kpi-value">${esc(k.value)}</div>${k.sub ? `<div class="kpi-sub">${esc(k.sub)}</div>` : ''}</div>`).join('');
    parent.appendChild(row);
  }

  function slicer(parent, label, options, value, onChange) {
    const wrap = h('label', 'slicer');
    wrap.innerHTML = `<span>${esc(label)}</span><select>${options.map((o) => `<option value="${esc(o.value)}"${String(o.value) === String(value) ? ' selected' : ''}>${esc(o.label)}</option>`).join('')}</select>`;
    wrap.querySelector('select').addEventListener('change', (e) => onChange(e.target.value));
    parent.appendChild(wrap);
  }

  function pageHead(parent, pg, filters) {
    const head = h('div', 'page-head');
    head.innerHTML = `<div><h2>${esc(pg.label)}</h2><p class="question">${esc(pg.question)}</p></div>`;
    const bar = h('div', 'filters');
    filters.forEach((f) => slicer(bar, ...f));
    if (filters.length) head.appendChild(bar);
    parent.appendChild(head);
  }
  const lede = (parent, html) => parent.appendChild(h('p', 'lede', html));
  const grid = (parent) => parent.appendChild(h('div', 'grid'));
  const b = (s) => `<b>${esc(s)}</b>`;

  /* ======================================================================
     PAGE 1 - Overview
     ====================================================================== */
  PAGES.push({
    id: 'overview', label: 'Overview', question: 'How big is the system and where does the volume sit?',
    build(main) {
      const O = D.overview, cases = sum(O.casesByQuarter.map((r) => r[1]));
      pageHead(main, this, []);
      const top = O.casesBySpecialty[0];
      const primary = sum(O.casesBySpecialty.filter((r) => r[1] === LEVELS[0]).map((r) => r[2]));
      const single = (O.practicesByForm.find((r) => r[0] === FORMS[0]) || [0, 0])[1] / O.practices;
      lede(main, `${b(F.pct(primary / cases, 0))} of all billing cases are in primary care; ${b(top[0])} alone accounts for ${b(F.pct(top[2] / cases, 0))}. ` +
        `${b(F.pct(single, 0))} of practices are solo practices (Einzelpraxis).`);
      kpis(main, [
        { label: 'Practices', value: F.int(O.practices), sub: 'BSNR' },
        { label: 'Doctors', value: F.int(D.doctors.rows.length), sub: 'current version' },
        { label: 'Billing cases', value: F.int(cases), sub: `${D.billing.quarters.length} quarters ${D.meta.dataYear}` },
        { label: 'Honorar brutto', value: F.eur(sum(D.billing.honorar.map((r) => r[1]))), sub: 'sample, all quarters' },
        { label: 'TSS requests', value: F.int(D.tss.rows.length), sub: 'appointment service' },
      ]);
      const g = grid(main);
      card(g, {
        title: 'Billing cases by specialty', sub: 'Area = number of cases · colour = level of care',
        span: 8, height: 340,
        legend: (P) => LEVELS.map((l) => ({ name: LEVEL_EN[l], color: levelColor(P, l) })),
        render: (w, ht, P) => KV.treemap({ aria: 'Treemap of billing cases by specialty', items: O.casesBySpecialty.map((r) => ({ name: r[0], value: r[2], color: levelColor(P, r[1]), tip: [`${LEVEL_EN[r[1]]} (${r[1]})`] })) }, w, ht, P),
        table: () => ({ head: ['Specialty', 'Level of care', 'Cases', 'Share'], rows: O.casesBySpecialty.map((r) => [r[0], LEVEL_EN[r[1]], F.int(r[2]), F.pct(r[2] / cases)]) }),
      });
      card(g, {
        title: 'Practices by form of cooperation', sub: 'BAG = group practice · MVZ = medical care centre',
        span: 4, height: 340,
        render: (w, ht, P) => KV.donut({ aria: 'Donut of practices by form', centerLabel: 'practices', items: FORMS.map((f) => ({ name: FORM_SHORT[f], value: (O.practicesByForm.find((r) => r[0] === f) || [0, 0])[1], color: formColor(P, f) })) }, w, ht, P),
        table: () => ({ head: ['Form of cooperation', 'Practices'], rows: O.practicesByForm.map((r) => [r[0], F.int(r[1])]) }),
      });
      card(g, {
        title: 'Billing cases per quarter', span: 4, height: 240,
        render: (w, ht, P) => KV.bars({ cats: O.casesByQuarter.map((r) => r[0]), series: [{ name: 'Cases', color: P.blue, values: O.casesByQuarter.map((r) => r[1]) }] }, w, ht, P),
        table: () => ({ head: ['Quarter', 'Cases'], rows: O.casesByQuarter.map((r) => [r[0], F.int(r[1])]) }),
      });
      card(g, {
        title: 'Billing cases by patient age', sub: 'Age group in years', span: 4, height: 240,
        render: (w, ht, P) => KV.bars({ cats: O.casesByAgeGroup.map((r) => ageLabel(r[0])), tipTitle: (i) => O.casesByAgeGroup[i][0], series: [{ name: 'Cases', color: P.blue, values: O.casesByAgeGroup.map((r) => r[1]) }] }, w, ht, P),
        table: () => ({ head: ['Age group', 'Cases'], rows: O.casesByAgeGroup.map((r) => [r[0], F.int(r[1])]) }),
      });
      card(g, {
        title: 'Billing cases by Kreis', sub: 'Region of the practice', span: 4, height: 240,
        render: (w, ht, P) => KV.bars({ horizontal: true, labelShare: 0.45, cats: O.casesByKreis.map((r) => r[0]), series: [{ name: 'Cases', color: P.blue, values: O.casesByKreis.map((r) => r[1]) }] }, w, ht, P),
        table: () => ({ head: ['Kreis', 'Cases'], rows: O.casesByKreis.map((r) => [r[0], F.int(r[1])]) }),
      });
    },
  });

  /* ======================================================================
     PAGE 2 - Doctors
     ====================================================================== */
  const AGE_BANDS = [['under 40', 0, 39], ['40–49', 40, 49], ['50–59', 50, 59], ['60–64', 60, 64], ['65 and over', 65, 200]];
  PAGES.push({
    id: 'doctors', label: 'Doctors', question: 'Who provides care?',
    build(main) {
      const DR = D.doctors, kreisIdx = state.kreis === 'all' ? null : DR.kreis.indexOf(state.kreis);
      const rows = DR.rows.filter((r) => kreisIdx === null || r[0] === kreisIdx);
      pageHead(main, this, [['Kreis', [{ value: 'all', label: 'All Kreise' }, ...[...DR.kreis].sort().map((k) => ({ value: k, label: k }))], state.kreis, (v) => { state.kreis = v; render(); }]]);
      const n = rows.length || 1, female = rows.filter((r) => r[2] === 'w').length, old = rows.filter((r) => r[3] >= 60).length;
      lede(main, `${b(F.pct(female / n, 0))} of doctors${kreisIdx === null ? '' : ' in ' + esc(state.kreis)} are women. ` +
        `${b(F.pct(old / n, 0))} are 60 or older (age in ${DR.ageReferenceYear}) – roughly one in ${Math.round(n / Math.max(old, 1))}.` +
        (kreisIdx === null ? '' : ' <span class="muted">Doctors without an active practice are only included under “All Kreise”.</span>'));
      kpis(main, [
        { label: 'Doctors', value: F.int(rows.length), sub: 'current version' },
        { label: 'Share female', value: F.pct(female / n) },
        { label: 'Average age', value: F.dec1(sum(rows.map((r) => r[3])) / n), sub: `in ${DR.ageReferenceYear}` },
        { label: 'Share 60+', value: F.pct(old / n) },
        { label: 'Share employed', value: F.pct(rows.filter((r) => r[4] === 'ANG').length / n), sub: 'Anstellung' },
      ]);
      const g = grid(main);
      // gender by specialty, sorted by share female
      const spec = DR.specialty.map((s, i) => {
        const rs = rows.filter((r) => r[1] === i);
        return { s, f: rs.filter((r) => r[2] === 'w').length, m: rs.filter((r) => r[2] === 'm').length };
      }).filter((x) => x.f + x.m > 0).sort((a, b2) => b2.f / (b2.f + b2.m) - a.f / (a.f + a.m));
      card(g, {
        title: 'Gender mix by specialty', sub: 'Share of doctors · sorted by share female', span: 7, rows: 2,
        height: (w) => Math.max(spec.length * 30 + 24, w > 600 ? 470 : 0), // fills the two stacked cards beside it
        legend: (P) => [{ name: 'Female', color: P.aqua }, { name: 'Male', color: P.violet }],
        render: (w, ht, P) => KV.bars({ horizontal: true, percent: true, labelShare: 0.42, cats: spec.map((x) => x.s), series: [{ name: 'Female', color: P.aqua, values: spec.map((x) => x.f) }, { name: 'Male', color: P.violet, values: spec.map((x) => x.m) }] }, w, ht, P),
        table: () => ({ head: ['Specialty', 'Female', 'Male', 'Share female'], rows: spec.map((x) => [x.s, F.int(x.f), F.int(x.m), F.pct(x.f / (x.f + x.m))]) }),
      });
      const ages = AGE_BANDS.map(([l, lo, hi]) => rows.filter((r) => r[3] >= lo && r[3] <= hi).length);
      card(g, {
        title: 'Age structure', sub: `Doctors by age in ${DR.ageReferenceYear}`, span: 5, height: 200,
        render: (w, ht, P) => KV.bars({ cats: AGE_BANDS.map((a) => a[0]), series: [{ name: 'Doctors', color: P.blue, values: ages }], tipExtra: (i) => [F.pct(ages[i] / n) + ' of doctors'] }, w, ht, P),
        table: () => ({ head: ['Age band', 'Doctors', 'Share'], rows: AGE_BANDS.map((a, i) => [a[0], F.int(ages[i]), F.pct(ages[i] / n)]) }),
      });
      const part = FORMS.map((f) => {
        const fi = DR.practiceForm.indexOf(f), rs = rows.filter((r) => r[5] === fi);
        return { f, zul: rs.filter((r) => r[4] === 'ZUL').length, ang: rs.filter((r) => r[4] === 'ANG').length };
      });
      card(g, {
        title: 'Licensed vs. employed by practice type', sub: 'Doctors with an active participation', span: 5, height: 200,
        legend: (P) => [{ name: 'Licensed (Zulassung)', color: P.blue }, { name: 'Employed (Anstellung)', color: P.orange }],
        render: (w, ht, P) => KV.bars({ cats: part.map((x) => FORM_SHORT[x.f]), tipTitle: (i) => part[i].f, series: [{ name: 'Licensed', color: P.blue, values: part.map((x) => x.zul) }, { name: 'Employed', color: P.orange, values: part.map((x) => x.ang) }] }, w, ht, P),
        table: () => ({ head: ['Practice type', 'Licensed', 'Employed'], rows: part.map((x) => [x.f, F.int(x.zul), F.int(x.ang)]) }),
      });
    },
  });

  /* ======================================================================
     PAGE 3 - Billing & Honorar
     ====================================================================== */
  PAGES.push({
    id: 'billing', label: 'Billing & Honorar', question: 'Where does the money go?',
    build(main) {
      const B = D.billing, sel = state.quarter, inQ = (q) => sel === 'all' || q === sel;
      const qi = B.quarters.indexOf(sel);
      pageHead(main, this, [['Quarter', [{ value: 'all', label: 'All quarters' }, ...B.quarters.map((q) => ({ value: q, label: q }))], sel, (v) => { state.quarter = v; render(); }]]);
      const hon = B.honorar.filter((r) => inQ(r[0])), col = (i) => sum(hon.map((r) => r[i]));
      const brutto = col(1), admin = col(2), adv = col(3), payout = col(4), egv = col(6);
      const cs = B.cases.filter((r) => inQ(r[0]));
      const per100 = (v) => F.int(Math.round((v / brutto) * 100));
      lede(main, `Of every ${b('100 €')} of gross Honorar${sel === 'all' ? '' : ' in ' + esc(sel)}, ${b(per100(adv) + ' €')} had already been paid as advance payments during the quarter ` +
        `and ${b(per100(admin) + ' €')} go to administrative costs – the final payment is the remaining ${b(per100(payout) + ' €')}. ` +
        `${b(F.pct(egv / brutto, 0))} of the Honorar is extra-budgetary (EGV), paid at full price outside the budget.`);
      kpis(main, [
        { label: 'Honorar brutto', value: F.eur(brutto) },
        { label: 'Final payment', value: F.eur(payout), sub: 'after advances & costs' },
        { label: 'EGV share', value: F.pct(egv / brutto), sub: 'extra-budgetary' },
        { label: 'Points per case', value: F.int(sum(cs.map((r) => r[2])) / sum(cs.map((r) => r[1]))), sub: `${F.int(sum(cs.map((r) => r[1])))} cases` },
      ]);
      const g = grid(main);
      card(g, {
        title: 'From Honorar brutto to final payment', sub: 'Waterfall · red = deductions, grey = what is paid out at the end',
        span: 7, height: 300,
        render: (w, ht, P) => KV.waterfall({ shareOf: brutto, colors: { start: P.blue, neg: P.red, pos: P.blue, total: P.gray }, steps: [
          { name: 'Honorar brutto', value: brutto, kind: 'start' },
          { name: 'Administrative costs', value: -admin, kind: 'delta' },
          { name: 'Advance payments made', value: -adv, kind: 'delta' },
          { name: 'Final payment', value: payout, kind: 'total' }] }, w, ht, P),
        table: () => ({ head: ['Step', 'Amount', 'Share of brutto'], rows: [['Honorar brutto', F.eur(brutto), '100 %'], ['− Administrative costs', F.eur(admin), F.pct(admin / brutto)], ['− Advance payments made', F.eur(adv), F.pct(adv / brutto)], ['= Final payment', F.eur(payout), F.pct(payout / brutto)]] }),
      });
      card(g, {
        title: 'MGV vs. EGV per quarter', sub: 'Budgeted (MGV) and extra-budgetary (EGV) Honorar, one € axis',
        span: 5, height: 300,
        legend: (P) => [{ name: 'MGV (budgeted)', color: P.blue }, { name: 'EGV (extra-budgetary)', color: P.orange }],
        render: (w, ht, P) => KV.bars({ cats: B.honorar.map((r) => r[0]), fmt: F.eur, axisFmt: (v) => F.compact(v) + ' €', labelFmt: (v) => F.compact(v) + ' €', dim: (i) => sel !== 'all' && B.honorar[i][0] !== sel,
          series: [{ name: 'MGV', color: P.blue, values: B.honorar.map((r) => r[5]) }, { name: 'EGV', color: P.orange, values: B.honorar.map((r) => r[6]) }],
          tipExtra: (i) => [`EGV share: ${F.pct(B.honorar[i][6] / (B.honorar[i][5] + B.honorar[i][6]))}`] }, w, ht, P),
        table: () => ({ head: ['Quarter', 'MGV', 'EGV', 'EGV share'], rows: B.honorar.map((r) => [r[0], F.eur(r[5]), F.eur(r[6]), F.pct(r[6] / (r[5] + r[6]))]) }),
      });
      // insurer heat map
      const ins = [...new Set(B.casesByInsurer.map((r) => r[0]))];
      const insVal = (k, q) => (B.casesByInsurer.find((r) => r[0] === k && r[1] === q) || [0, 0, 0])[2];
      ins.sort((a, c) => sum(B.quarters.map((q) => insVal(c, q))) - sum(B.quarters.map((q) => insVal(a, q))));
      const insMax = Math.max(...B.casesByInsurer.map((r) => r[2]));
      card(g, {
        title: 'Cases by type of insurer and quarter', sub: 'Stronger blue = more cases',
        span: 5, height: ins.length * 36 + 30,
        legendHtml: (P) => `<span class="grad-lbl">0</span><span class="grad" style="background:linear-gradient(90deg,${P.seq.join(',')})"></span><span class="grad-lbl">${F.int(insMax)} cases</span>`,
        render: (w, ht, P) => KV.heatmap({ rows: ins, cols: B.quarters, rowLabelShare: 0.42, highlightCol: qi >= 0 ? qi : null,
          cell: (ri, ci) => { const v = insVal(ins[ri], B.quarters[ci]); const fill = KV.ramp(P.seq, v / insMax); return { fill, text: F.int(v), tip: [ins[ri], `${B.quarters[ci]}: ${F.int(v)} cases`] }; } }, w, ht, P),
        table: () => ({ head: ['Type of insurer', ...B.quarters], rows: ins.map((k) => [k, ...B.quarters.map((q) => F.int(insVal(k, q)))]) }),
      });
      // scatter: every practice
      const agg = new Map();
      B.practices.filter((r) => inQ(r[2])).forEach((r) => {
        const a = agg.get(r[0]) || { form: B.practiceForm[r[1]], cases: 0, hon: 0 };
        a.cases += r[3]; a.hon += r[4]; agg.set(r[0], a);
      });
      const pts = [...agg.values()];
      card(g, {
        title: 'Every practice: cases vs. Honorar', sub: `${F.int(pts.length)} practices · one dot each`,
        span: 7, height: 300,
        legend: (P) => FORMS.map((f) => ({ name: FORM_SHORT[f], color: formColor(P, f) })),
        render: (w, ht, P) => KV.scatter({ xLabel: 'Billing cases →', yLabel: '↑ Honorar brutto (€)', yFmt: (v) => F.compact(v) + ' €',
          points: pts.sort((a, c) => FORMS.indexOf(a.form) - FORMS.indexOf(c.form)).map((p) => ({ x: p.cases, y: p.hon, color: formColor(P, p.form),
            tip: [FORM_SHORT[p.form] + ' practice', `Cases: ${F.int(p.cases)}`, `Honorar brutto: ${F.eur(p.hon)}`, p.cases ? `Per case: ${F.eur(p.hon / p.cases)}` : null] })) }, w, ht, P),
        table: () => ({ head: ['Practice type', 'Practices', 'Cases', 'Honorar brutto', 'Per case'], rows: FORMS.map((f) => { const ps = pts.filter((p) => p.form === f), c = sum(ps.map((p) => p.cases)), hh = sum(ps.map((p) => p.hon)); return [f, F.int(ps.length), F.int(c), F.eur(hh), c ? F.eur(hh / c) : '–']; }) }),
      });
      // EBM chapters
      const chapters = [...new Set(B.ebm.map((r) => r[0]))];
      const ebm = chapters.map((k) => ({ k, mgv: sum(B.ebm.filter((r) => r[0] === k && !r[1] && inQ(r[2])).map((r) => r[3])), egv: sum(B.ebm.filter((r) => r[0] === k && r[1] && inQ(r[2])).map((r) => r[3])) }))
        .sort((a, c) => c.mgv + c.egv - (a.mgv + a.egv));
      card(g, {
        title: 'Billed amount by EBM chapter', sub: 'Split into budgeted (MGV) and extra-budgetary (EGV) services',
        span: 12, height: () => ebm.length * 28 + 24,
        legend: (P) => [{ name: 'MGV (budgeted)', color: P.blue }, { name: 'EGV (extra-budgetary)', color: P.orange }],
        render: (w, ht, P) => KV.bars({ horizontal: true, labelShare: 0.4, fmt: F.eur, cats: ebm.map((x) => x.k), series: [{ name: 'MGV', color: P.blue, values: ebm.map((x) => x.mgv) }, { name: 'EGV', color: P.orange, values: ebm.map((x) => x.egv) }] }, w, ht, P),
        table: () => ({ head: ['EBM chapter', 'MGV', 'EGV', 'Total'], rows: ebm.map((x) => [x.k, F.eur(x.mgv), F.eur(x.egv), F.eur(x.mgv + x.egv)]) }),
      });
    },
  });

  /* ======================================================================
     PAGE 4 - Appointments (TSS)
     ====================================================================== */
  const WAIT = [['0–7 days', 0, 7], ['8–14', 8, 14], ['15–21', 15, 21], ['22–28', 22, 28], ['29–35', 29, 35], ['over 35', 36, 1e9]];
  PAGES.push({
    id: 'tss', label: 'Appointments (TSS)', question: 'How fast do patients get an appointment?',
    build(main) {
      const T = D.tss, si = state.specialty === 'all' ? null : T.specialty.indexOf(state.specialty);
      const rows = T.rows.filter((r) => si === null || r[0] === si);
      pageHead(main, this, [['Specialty', [{ value: 'all', label: 'All specialties' }, ...[...T.specialty].sort().map((s) => ({ value: s, label: s }))], state.specialty, (v) => { state.specialty = v; render(); }]]);
      const n = rows.length || 1, arr = rows.filter((r) => r[4]), att = rows.filter((r) => r[7]).length;
      const waits = rows.filter((r) => r[5] != null).map((r) => r[5]), within = rows.filter((r) => r[6]).length;
      lede(main, `Out of ${b('100')} requests${si === null ? '' : ' for ' + esc(state.specialty)}, ${b(F.int(Math.round((arr.length / n) * 100)))} lead to an appointment and ` +
        `${b(F.int(Math.round((att / n) * 100)))} patients attend it. ${b(F.pct(within / Math.max(arr.length, 1), 0))} of arranged appointments are within the 4-week target.`);
      kpis(main, [
        { label: 'TSS requests', value: F.int(rows.length) },
        { label: 'Placement rate', value: F.pct(arr.length / n), sub: `${F.int(arr.length)} arranged` },
        { label: 'Within 4 weeks', value: F.pct(within / Math.max(arr.length, 1)), sub: 'of arranged' },
        { label: 'Avg waiting time', value: waits.length ? F.dec1(sum(waits) / waits.length) + ' days' : '–' },
      ]);
      const g = grid(main);
      card(g, {
        title: 'From request to attended appointment', sub: 'Funnel · ▼ = conversion from the previous step',
        span: 5, height: 280,
        render: (w, ht, P) => KV.funnel({ stepLabels: ['', 'arranged', 'attended'], stages: [{ name: 'Requests', value: rows.length, color: P.blue }, { name: 'Arranged', value: arr.length, color: P.blue }, { name: 'Attended', value: att, color: P.blue }] }, w, ht, P),
        table: () => ({ head: ['Stage', 'Requests', 'Share'], rows: [['Requests', F.int(rows.length), '100 %'], ['Arranged', F.int(arr.length), F.pct(arr.length / n)], ['Attended', F.int(att), F.pct(att / n)]] }),
      });
      const byMonth = URGENCY.map((u) => MONTHS.map((_, m) => rows.filter((r) => r[1] === m + 1 && r[2] === u).length));
      card(g, {
        title: 'Requests per month by urgency', sub: 'Stronger blue = more urgent', span: 7, height: 280,
        legend: (P) => URGENCY.map((u, i) => ({ name: URGENCY_EN[u], color: P.ordinal[i] })),
        render: (w, ht, P) => KV.bars({ cats: MONTHS, label: 'total', series: URGENCY.map((u, i) => ({ name: URGENCY_EN[u], color: P.ordinal[i], values: byMonth[i] })) }, w, ht, P),
        table: () => ({ head: ['Month', ...URGENCY.map((u) => URGENCY_EN[u])], rows: MONTHS.map((m, mi) => [m, ...byMonth.map((s) => F.int(s[mi]))]) }),
      });
      const hist = WAIT.map(([, lo, hi]) => arr.filter((r) => r[5] >= lo && r[5] <= hi).length);
      card(g, {
        title: 'Waiting time until the appointment', sub: 'Arranged appointments · red = beyond 4 weeks', span: 4, height: 260,
        render: (w, ht, P) => KV.bars({ cats: WAIT.map((x) => x[0]), rule: { after: 3, label: '4 weeks' }, colorAt: (s, ci) => (ci >= 4 ? P.red : P.blue),
          series: [{ name: 'Appointments', values: hist }], tipExtra: (i) => [F.pct(hist[i] / Math.max(arr.length, 1)) + ' of arranged'] }, w, ht, P),
        table: () => ({ head: ['Waiting time (days)', 'Appointments', 'Share'], rows: WAIT.map((x, i) => [x[0], F.int(hist[i]), F.pct(hist[i] / Math.max(arr.length, 1))]) }),
      });
      // average wait by specialty - always all specialties, the selected one highlighted; click to filter
      const avg = T.specialty.map((s, i) => { const w = T.rows.filter((r) => r[0] === i && r[5] != null).map((r) => r[5]); return { s, v: w.length ? sum(w) / w.length : 0, n: w.length }; }).sort((a, c) => c.v - a.v);
      card(g, {
        title: 'Average waiting time by specialty', sub: 'Red = above 28 days · click a bar to filter the page', span: 5,
        height: () => avg.length * 26 + 22,
        onPick: (v) => { state.specialty = state.specialty === v ? 'all' : v; render(); },
        render: (w, ht, P) => KV.bars({ horizontal: true, labelShare: 0.42, fmt: (v) => F.dec1(v) + ' d', cats: avg.map((x) => x.s), valueRule: { value: 28, label: '28 days' },
          colorAt: (s, ci) => (avg[ci].v > 28 ? P.red : P.blue), dim: (ci) => si !== null && avg[ci].s !== state.specialty, pick: (ci) => avg[ci].s,
          series: [{ name: 'Average wait', values: avg.map((x) => x.v) }], tipExtra: (ci) => [`${F.int(avg[ci].n)} appointments`] }, w, ht, P),
        table: () => ({ head: ['Specialty', 'Avg waiting time (days)', 'Appointments'], rows: avg.map((x) => [x.s, F.dec1(x.v), F.int(x.n)]) }),
      });
      card(g, {
        title: 'Request channel', span: 3, height: 260,
        render: (w, ht, P) => KV.donut({ centerLabel: 'requests', items: CHANNELS.map((c, i) => ({ name: CHANNEL_EN[c], value: rows.filter((r) => r[3] === c).length, color: [P.blue, P.orange, P.aqua][i] })) }, w, ht, P),
        table: () => ({ head: ['Channel', 'Requests'], rows: CHANNELS.map((c) => [CHANNEL_EN[c], F.int(rows.filter((r) => r[3] === c).length)]) }),
      });
    },
  });

  /* ======================================================================
     PAGE 5 - Planning & out-of-hours
     ====================================================================== */
  PAGES.push({
    id: 'planning', label: 'Planning & Out-of-hours', question: 'Where are doctors missing?',
    build(main) {
      const PL = D.planning, dates = [...new Set(PL.supply.map((r) => r[0]))].sort();
      if (!state.stichtag) state.stichtag = dates[dates.length - 1];
      const dateLabel = (d) => d.split('-').reverse().join('.');
      pageHead(main, this, [['Reference date', dates.map((d) => ({ value: d, label: dateLabel(d) })), state.stichtag, (v) => { state.stichtag = v; render(); }]]);
      const cur = PL.supply.filter((r) => r[0] === state.stichtag), cnt = (s) => cur.filter((r) => r[8] === s).length;
      const shifts = sum(PL.shifts.map((r) => r[3])), swapped = sum(PL.shifts.map((r) => r[5]));
      lede(main, `On ${b(dateLabel(state.stichtag))}, ${b(cnt('GESPERRT') + ' of ' + cur.length)} planning cells were ${b('closed')} to new doctors (supply level ≥ 110 %), ` +
        `${b(String(cnt('OFFEN')))} were open for new admissions and ${b(String(cnt('UNTERVERSORGT')))} under-supplied.`);
      kpis(main, [
        { label: 'Areas open', value: F.int(cnt('OFFEN')), sub: 'planning cells' },
        { label: 'Areas closed', value: F.int(cnt('GESPERRT')), sub: '≥ 110 %' },
        { label: 'Areas under-supplied', value: F.int(cnt('UNTERVERSORGT')) },
        { label: 'Out-of-hours shifts', value: F.int(shifts), sub: String(PL.shiftYear) },
        { label: 'Swap rate', value: F.pct(swapped / shifts), sub: 'shifts swapped' },
      ]);
      const g = grid(main);
      const groups = [...new Set(PL.supply.map((r) => r[1]))].sort((a, c) => {
        const la = LEVELS.indexOf(PL.supply.find((r) => r[1] === a)[2]), lc = LEVELS.indexOf(PL.supply.find((r) => r[1] === c)[2]);
        return la - lc || a.localeCompare(c, 'de');
      });
      const areas = [...new Set(PL.supply.map((r) => r[3] + '|' + r[4]))].sort((a, c) => (a.endsWith('|ROR') - c.endsWith('|ROR')) || a.localeCompare(c, 'de')).map((x) => x.split('|')[0]);
      const cell = (gname, area) => cur.find((r) => r[1] === gname && r[3] === area);
      card(g, {
        title: 'Supply level by physician group and planning area', sub: 'Actual ÷ target doctors · red = below target, grey = at target, blue = above; ≥ 110 % = closed to new doctors · “–” = not planned at this level',
        span: 12, height: groups.length * 34 + 44,
        legendHtml: (P) => `<span class="grad-lbl">≤ 75 %</span><span class="grad wide" style="background:linear-gradient(90deg,${P.div.neg} 0%,${P.div.mid} 71%,${P.div.pos} 100%)"></span><span class="grad-lbl">≥ 110 %</span>` +
          `<span class="key-note">100 % = target · under-supply threshold 75 % (Hausärzte) / 50 % (specialists)</span>`,
        render: (w, ht, P) => KV.heatmap({ rows: groups, cols: areas, rowLabelShare: 0.24,
          cell: (ri, ci) => { const r = cell(groups[ri], areas[ci]); if (!r) return null; const pct = r[7];
            return { fill: KV.diverge(P, pct, 75, 100, 110), text: F.int(pct) + ' %', bold: r[8] === 'UNTERVERSORGT',
              tip: [`${groups[ri]} · ${areas[ci]}`, `Supply level: ${F.dec1(pct)} %`, `Status: ${STATUS_EN[r[8]] || r[8]}`, `Target doctors: ${F.dec1(r[5])}`, `Actual doctors: ${F.dec1(r[6])}`] }; } }, w, ht, P),
        table: () => ({ head: ['Physician group', 'Planning area', 'Target', 'Actual', 'Supply level', 'Status'], rows: cur.map((r) => [r[1], r[3], F.dec1(r[5]), F.dec1(r[6]), F.dec1(r[7]) + ' %', STATUS_EN[r[8]] || r[8]]) }),
      });
      const wd = (d, we) => sum(PL.shifts.filter((r) => r[1] === d && r[2] === we).map((r) => r[4]));
      card(g, {
        title: 'Out-of-hours service hours by weekday', sub: `${PL.shiftYear} · not affected by the reference date`, span: 5, height: 260,
        legend: (P) => [{ name: 'Weekday', color: P.blue }, { name: 'Weekend / holiday', color: P.orange }],
        render: (w, ht, P) => KV.bars({ cats: WEEKDAYS, fmt: (v) => F.int(v) + ' h', series: [{ name: 'Weekday', color: P.blue, values: WEEKDAYS.map((_, i) => wd(i + 1, 0)) }, { name: 'Weekend / holiday', color: P.orange, values: WEEKDAYS.map((_, i) => wd(i + 1, 1)) }] }, w, ht, P),
        table: () => ({ head: ['Weekday', 'Weekday hours', 'Weekend / holiday hours'], rows: WEEKDAYS.map((d, i) => [d, F.int(wd(i + 1, 0)), F.int(wd(i + 1, 1))]) }),
      });
      const mh = (m, we) => sum(PL.shifts.filter((r) => r[0] === m && r[2] === we).map((r) => r[4]));
      card(g, {
        title: 'Out-of-hours service hours per month', sub: `${PL.shiftYear} · stacked`, span: 7, height: 260,
        legend: (P) => [{ name: 'Weekday', color: P.blue }, { name: 'Weekend / holiday', color: P.orange }],
        render: (w, ht, P) => KV.area({ cats: MONTHS, fmt: (v) => F.int(v) + ' h', series: [{ name: 'Weekday', color: P.blue, values: MONTHS.map((_, i) => mh(i + 1, 0)) }, { name: 'Weekend / holiday', color: P.orange, values: MONTHS.map((_, i) => mh(i + 1, 1)) }] }, w, ht, P),
        table: () => ({ head: ['Month', 'Weekday hours', 'Weekend / holiday hours'], rows: MONTHS.map((m, i) => [m, F.int(mh(i + 1, 0)), F.int(mh(i + 1, 1))]) }),
      });
    },
  });

  /* ======================================================================
     Deneb visuals: the Power BI report's Vega / Vega-Lite specs (deneb_specs.js), rendered by Vega itself
     ====================================================================== */
  const loaded = {};
  function loadScript(src) {
    if (!loaded[src]) {
      loaded[src] = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = src; s.onload = resolve; s.onerror = () => reject(new Error('could not load ' + src));
        document.head.appendChild(s);
      });
    }
    return loaded[src];
  }
  // Vega-Lite's browser build needs the global `vega`, so the scripts load one after the other
  const loadVega = (lite) => ['vendor/vega.min.js', ...(lite ? ['vendor/vega-lite.min.js'] : []), 'deneb_specs.js']
    .reduce((p, src) => p.then(() => loadScript(src)), Promise.resolve());

  // Vega tooltips use the dashboard's tooltip box (first value = title)
  function vegaTooltip(handler, event, item, value) {
    if (value == null || value === '') { tip.hidden = true; return; }
    const entries = typeof value === 'object' ? Object.entries(value) : [['', value]];
    // numbers without a Vega format get the dashboard format; years stay as they are
    const fmtV = (k, v) => (typeof v !== 'number' ? String(v) : /year|jahr/i.test(k) ? String(v) : F.dec1(v).replace(/[.,]0$/, ''));
    tip.innerHTML = `<strong>${esc(fmtV(entries[0][0], entries[0][1]))}</strong>` + entries.slice(1).map(([k, v]) => `<div>${esc(k)}: ${esc(fmtV(k, v))}</div>`).join('');
    tip.hidden = false;
    placeTip(event);
  }

  window.KVSIM_VIEWS = {};   // live Vega views by Deneb visual name (handy in the browser console)

  /** card that runs one Deneb visual. o: key, title, sub, span, height, minWidth, values, rendererSwitch, foot(html), onView(view) */
  function vegaCard(parent, o) {
    const sec = h('section', `card span-${o.span || 12} vega-card`);
    sec.innerHTML = `<header class="card-head"><div><h3>${esc(o.title)}</h3>${o.sub ? `<p class="sub">${esc(o.sub)}</p>` : ''}</div>` +
      (o.rendererSwitch ? '<div class="renderer-switch" role="group" aria-label="Vega renderer">' +
        '<button type="button" class="tbl-toggle" data-renderer="svg">SVG</button>' +
        '<button type="button" class="tbl-toggle" data-renderer="canvas">Canvas</button></div>' : '') + '</header>' +
      `<div class="vega-scroll"><div class="vega-stage" style="height:${o.height}px;min-width:${o.minWidth || 0}px"><p class="muted">Loading Vega…</p></div></div>` +
      (o.foot ? `<p class="foot">${o.foot}</p>` : '');
    parent.appendChild(sec);
    const stage = sec.querySelector('.vega-stage');
    let view = null, renderer = null, lastW = 0, disposed = false;
    const draw = (force) => {
      const dn = window.KVSIM_DENEB && window.KVSIM_DENEB[o.key];
      if (!window.vega || !dn || disposed || (dn.provider === 'vegaLite' && !window.vegaLite)) return;
      const w = Math.max(o.minWidth || 0, Math.floor(stage.clientWidth));
      if (view && w === lastW && !force) return;
      lastW = w;
      if (view) view.finalize();
      stage.innerHTML = '';
      renderer = renderer || dn.renderMode || 'svg';
      sec.querySelectorAll('[data-renderer]').forEach((x) => x.setAttribute('aria-pressed', x.getAttribute('data-renderer') === renderer));
      const spec = JSON.parse(JSON.stringify(dn.spec));
      spec.width = w - 12; spec.height = o.height - 12;   // Deneb sizes the view to the visual the same way
      const runtime = dn.provider === 'vegaLite' ? vega.parse(vegaLite.compile(spec, { config: dn.config }).spec) : vega.parse(spec, dn.config);
      view = new vega.View(runtime, { renderer, container: stage, hover: true });
      view.tooltip(vegaTooltip);
      view.data('dataset', o.values);   // Deneb's dataset, with the same field names as in Power BI
      view.runAsync();
      window.KVSIM_VIEWS[o.key] = view;
      if (o.onView) o.onView(view, sec);
    };
    sec.querySelectorAll('[data-renderer]').forEach((btn) => btn.addEventListener('click', () => {
      renderer = btn.getAttribute('data-renderer');
      draw(true);
    }));
    loadVega(o.lite).then(() => draw(true)).catch((e) => { stage.innerHTML = `<p class="muted">${esc(e.message)}</p>`; });
    const ro = new ResizeObserver(() => draw(false));
    ro.observe(stage);
    live.push({ draw: () => {}, ro, dispose: () => { disposed = true; if (view) view.finalize(); view = null; } });
  }

  /* ======================================================================
     PAGE 6 - Fachgruppe Explorer (Power BI page of the same name)
     ====================================================================== */
  PAGES.push({
    id: 'explorer', label: 'Fachgruppe Explorer', question: 'Explore billing cases and fees by specialty',
    build(main) {
      const E = D.explorer;
      const qi = state.exQuarter === 'all' ? null : E.quarter.indexOf(state.exQuarter);
      const ki = state.exKreis === 'all' ? null : E.kreis.indexOf(state.exKreis);
      const fi = state.exFach === 'all' ? null : E.fachgruppe.indexOf(state.exFach);
      pageHead(main, this, [
        ['Quarter', [{ value: 'all', label: 'All quarters' }, ...E.quarter.map((q) => ({ value: q, label: q }))], state.exQuarter, (v) => { state.exQuarter = v; render(); }],
        ['Kreis', [{ value: 'all', label: 'All Kreise' }, ...E.kreis.map((k) => ({ value: k, label: k }))], state.exKreis, (v) => { state.exKreis = v; render(); }],
      ]);
      const inK = (k) => ki === null || k === ki;
      const sliced = E.cases.filter((r) => (qi === null || r[1] === qi) && inK(r[2]));   // slicers
      const sel = sliced.filter((r) => fi === null || r[0] === fi);                      // + clicked Fachgruppe
      // measure 'Honorar Brutto (Practices in Fachgruppe)': Honorar of the practices that billed cases in the filter
      const honorar = (f, q) => {
        const pr = new Set(E.activity.filter((a) => (f === null || a[1] === f) && (q === null || a[2] === q) && inK(E.practiceKreis[a[0]])).map((a) => a[0]));
        return sum(E.honorar.filter((x) => pr.has(x[0]) && (q === null || x[1] === q) && inK(E.practiceKreis[x[0]])).map((x) => x[2]));
      };
      const nCases = sum(sel.map((r) => r[3])), nAll = sum(sliced.map((r) => r[3]));
      const ppc = nCases ? sum(sel.map((r) => r[4])) / nCases : 0;
      const scope = [state.exQuarter === 'all' ? 'all quarters' : state.exQuarter, state.exKreis === 'all' ? 'all Kreise' : state.exKreis].join(', ');
      lede(main, (fi === null
        ? `In ${esc(scope)}, ${b(F.int(nCases))} billing cases were billed across ${b(String(E.fachgruppe.length))} Fachgruppen. `
        : `${b(state.exFach)} accounts for ${b(F.int(nCases))} billing cases in ${esc(scope)}, ${b(F.pct(nCases / Math.max(nAll, 1), 0))} of all cases. `) +
        `Click a bar to focus the page on one Fachgruppe, click it again to clear.`);
      kpis(main, [
        { label: 'Billing cases', value: F.int(nCases), sub: fi === null ? 'all Fachgruppen' : state.exFach },
        { label: 'Honorar brutto', value: F.eur(honorar(fi, qi)), sub: 'practices in Fachgruppe' },
        { label: 'EBM points per case', value: F.int(Math.round(ppc)) },
      ]);
      const g = grid(main);
      const byF = E.fachgruppe.map((name, f) => {
        const rs = sliced.filter((r) => r[0] === f), n = sum(rs.map((r) => r[3]));
        return { name, f, n, ppc: n ? sum(rs.map((r) => r[4])) / n : 0, hon: honorar(f, qi) };
      }).sort((a, c) => c.n - a.n);
      card(g, {
        title: 'Billing cases by Fachgruppe', sub: 'Click a bar to filter the page · hover for Honorar and points per case', span: 7,
        height: () => byF.length * 30 + 22,
        onPick: (v) => { state.exFach = state.exFach === v ? 'all' : v; render(); },
        render: (w, ht, P) => KV.bars({ horizontal: true, labelShare: 0.36, cats: byF.map((x) => x.name), label: 'total',
          colorAt: () => P.blue, dim: (ci) => fi !== null && byF[ci].f !== fi, pick: (ci) => byF[ci].name,
          series: [{ name: 'Billing cases', values: byF.map((x) => x.n) }],
          tipExtra: (ci) => [`Honorar (practices in Fachgruppe): ${F.eur(byF[ci].hon)}`, `EBM points per case: ${F.int(Math.round(byF[ci].ppc))}`,
            `${F.pct(byF[ci].n / Math.max(nAll, 1), 1)} of all cases`] }, w, ht, P),
        table: () => ({ head: ['Fachgruppe', 'Billing cases', 'Honorar (practices in Fachgruppe)', 'EBM points per case'],
          rows: byF.map((x) => [x.name, F.int(x.n), F.eur(x.hon), F.int(Math.round(x.ppc))]) }),
        foot: 'Honorar is paid per practice, not per Fachgruppe: a practice that bills in several Fachgruppen counts fully in each, so the values do not add up to the total.',
      });
      const byQ = E.quarter.map((q, qq) => sum(E.cases.filter((r) => r[1] === qq && inK(r[2]) && (fi === null || r[0] === fi)).map((r) => r[3])));
      card(g, {
        title: 'Billing cases per quarter', sub: fi === null ? 'All Fachgruppen · click a quarter to filter' : `${state.exFach} · click a quarter to filter`, span: 5,
        height: () => byF.length * 30 + 22,
        onPick: (v) => { state.exQuarter = state.exQuarter === v ? 'all' : v; render(); },
        render: (w, ht, P) => KV.bars({ cats: E.quarter, label: 'total', colorAt: () => P.blue,
          dim: (ci) => qi !== null && ci !== qi, pick: (ci) => E.quarter[ci], series: [{ name: 'Billing cases', values: byQ }] }, w, ht, P),
        table: () => ({ head: ['Quarter', 'Billing cases'], rows: E.quarter.map((q, i) => [q, F.int(byQ[i])]) }),
      });
    },
  });

  /* ======================================================================
     PAGE 7 - Fachgruppe Growth (Deneb raincloud + heatmap from the report)
     ====================================================================== */
  PAGES.push({
    id: 'growth', label: 'Fachgruppe Growth', question: 'How fast is each Fachgruppe growing?',
    build(main) {
      const G = D.growth;
      const values = G.rows.map((r) => ({ fachgruppe: r[0], Year: r[1], 'Active Doctors (Year End)': r[2], 'Doctor Growth YoY': r[3] }));
      pageHead(main, this, []);
      const byG = {};
      G.rows.forEach((r) => { if (r[3] != null) (byG[r[0]] = byG[r[0]] || []).push(r[3]); });
      const median = (a) => { const s = [...a].sort((x, y) => x - y), m = s.length >> 1; return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };
      const meds = Object.entries(byG).map(([k, v]) => [k, median(v)]).sort((a, c) => c[1] - a[1]);
      lede(main, `Yearly growth in active doctors per Fachgruppe, ${G.fromYear}–${G.toYear}, from the Arztregister history. ` +
        (meds.length ? `The median ranges from ${b(F.pct(meds[meds.length - 1][1], 1))} a year (${esc(meds[meds.length - 1][0])}) to ${b(F.pct(meds[0][1], 1))} (${esc(meds[0][0])}). ` : '') +
        `The simulated register mainly holds today's doctors, so earlier growth is overstated.`);
      const g = grid(main);
      vegaCard(g, { key: 'growth_raincloud', title: 'Distribution of yearly growth rates', span: 7, height: 600, minWidth: 640, values,
        sub: 'Cloud = density · box = middle 50 % with median · dots = single years (red = shrinking)' });
      vegaCard(g, { key: 'growth_heatmap', lite: true, title: 'Growth by year', span: 5, height: 600, minWidth: 440, values,
        sub: 'Same order as the raincloud · red = fewer active doctors than the year before' });
    },
  });

  /* ======================================================================
     PAGE 8 - Vega Showcase (Deneb visual 'tss_year_clock' from the report)
     ====================================================================== */
  PAGES.push({
    id: 'showcase', label: 'Vega Showcase', question: 'A year of appointment requests: does the 4-week promise hold?',
    build(main) {
      pageHead(main, this, []);
      lede(main, `The ${b('same Vega specification')} as the Deneb visual on the Power BI page “Vega Showcase”, rendered here by ` +
        `${b('Vega 6.4')} directly in the browser. Every dot is one of ${b(F.int(D.tss.rows.length))} requests: angle = day received, ` +
        `distance from the centre = days until the appointment. Hover dots and month segments, click a specialty or urgency, double-click to reset. ` +
        `Use the renderer switch to compare ${b('SVG')} and ${b('Canvas')}.`);
      const T = D.tss;
      // the field names Deneb passes to the spec in Power BI (one row per request)
      const values = T.rows.map((r) => {
        const [y, m, d] = r[9].split('-').map(Number);
        return { anfrage_id: r[8], datum: new Date(y, m - 1, d), arztgruppe: T.specialty[r[0]], dringlichkeit: r[2],
          kanal: r[3], status: r[10], wartezeit_tage: r[5], termin_wahrgenommen: r[10] === 'VERMITTELT' ? r[7] === 1 : null };
      });
      vegaCard(grid(main), { key: 'tss_year_clock', title: 'TSS year clock', span: 12, height: 632, minWidth: 1000, values, rendererSwitch: true,
        sub: '1:1 copy of the Deneb spec (python/export_deneb_specs.py) · data: data.js',
        foot: 'Hover state: <span class="hover-state">–</span>',
        onView: (view, sec) => {
          const hs = sec.querySelector('.hover-state');
          view.addSignalListener('hoverReq', (_, v) => { hs.textContent = v ? `request #${v.d.anfrage_id}` : '–'; });
          window.KVSIM_SHOWCASE_VIEW = view;   // kept for existing debugging snippets
        } });
    },
  });

  /* ---------------- routing & render ---------------- */
  const nav = document.getElementById('nav'), main = document.getElementById('main');
  nav.innerHTML = PAGES.map((p) => `<a href="#${p.id}" data-page="${p.id}">${esc(p.label)}</a>`).join('');
  function render() {
    live.forEach((c) => { c.ro.disconnect(); if (c.dispose) c.dispose(); });
    live.length = 0;
    main.innerHTML = '';
    const pg = PAGES.find((p) => p.id === state.page) || PAGES[0];
    nav.querySelectorAll('a').forEach((a) => (a.getAttribute('data-page') === pg.id ? a.setAttribute('aria-current', 'page') : a.removeAttribute('aria-current')));
    document.title = `${pg.label} · KV Saarland dashboard`;
    pg.build(main);
    live.forEach((c) => c.draw(true));
  }
  function fromHash() { const id = location.hash.slice(1); state.page = PAGES.some((p) => p.id === id) ? id : 'overview'; render(); }
  window.addEventListener('hashchange', () => { fromHash(); window.scrollTo(0, 0); });

  document.getElementById('meta').textContent = `Exported ${D.meta.exported} from database ${D.meta.database} · data year ${D.meta.dataYear}`;
  let saved = 'auto';
  try { saved = localStorage.getItem('kvsim-theme') || 'auto'; } catch (e) { /* storage unavailable */ }
  if (saved !== 'auto') root.dataset.theme = saved;
  themeBtn.textContent = `Theme: ${saved}`;
  P = KV.PALETTES[resolved()];
  fromHash();
})();
