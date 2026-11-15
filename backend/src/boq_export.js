// BOQ (Bill of Quantities) numbering, totals and export to PDF and Excel.
// Every export carries the SmartFundi logo at the top and the SmartFundi logo + name as a watermark.
const fs = require('fs');
const path = require('path');
const { PDFDocument, StandardFonts, rgb, degrees } = require('pdf-lib');
const JSZip = require('jszip');

const ASSETS = path.join(__dirname, '..', 'assets');
const asset = (n) => fs.readFileSync(path.join(ASSETS, n));

/// rows: [{kind,...}] in order. Adds `no`: sections 1, 2, 3 ... ; items and groups 1.1, 1.2 ... ; sub items have no number.
function numberRows(rows) {
  let sec = 0, n = 0;
  return rows.map((r) => {
    let no = '';
    if (r.kind === 'section') { sec++; n = 0; no = String(sec); }
    else if (r.kind === 'item' || r.kind === 'group') { n++; no = sec ? `${sec}.${n}` : String(n); }
    return { ...r, no };
  });
}
const num = (v) => { const x = Number(v); return Number.isFinite(x) ? x : 0; };
const lineAmount = (l) => (l.kind === 'item' || l.kind === 'sub' ? Math.round(num(l.qty) * num(l.rate) * 100) / 100 : 0);
function totalOf(lines) { return Math.round(lines.reduce((a, l) => a + lineAmount(l), 0) * 100) / 100; }

const fmt = (n) => Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
const clean = (s) => String(s == null ? '' : s).replace(/\r/g, '').replace(/[^\x09\x0A\x20-\x7E\xA0-\xFF]/g, '?');

function headerRows(b) {
  return [
    ['Client name', b.client_name], ['Client contact', b.client_contact], ['Location / site', b.location],
    ...(b.tin ? [['TIN number', b.tin]] : []),
    ['Installer (company / fundi)', b.installer_name], ['Installer phone', b.installer_phone],
  ].filter((r) => r[1] && String(r[1]).trim());
}

// ============================================================ PDF
async function buildPdf(b) {
  const lines = numberRows(b.lines || []);
  const doc = await PDFDocument.create();
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const logo = await doc.embedPng(asset('logo.png'));
  const wm = await doc.embedPng(asset('watermark.png'));
  const W = 595.28, H = 841.89, M = 32;
  const cols = [38, 232, 38, 44, 80, 99]; // sum = 531
  const x0 = M, tableW = cols.reduce((a, c) => a + c, 0);
  const navy = rgb(0.043, 0.145, 0.271), light = rgb(0.86, 0.9, 0.96), amber = rgb(1, 0.77, 0.0);
  const pages = [];
  let page, y;

  function wrap(text, f, size, maxW) {
    const out = [];
    for (const para of clean(text).split('\n')) {
      let cur = '';
      for (const word of para.split(/\s+/).filter(Boolean)) {
        const t = cur ? cur + ' ' + word : word;
        if (f.widthOfTextAtSize(t, size) <= maxW) { cur = t; continue; }
        if (cur) out.push(cur);
        let w = word;
        while (f.widthOfTextAtSize(w, size) > maxW && w.length > 1) { // very long word
          let k = w.length - 1;
          while (k > 1 && f.widthOfTextAtSize(w.slice(0, k), size) > maxW) k--;
          out.push(w.slice(0, k)); w = w.slice(k);
        }
        cur = w;
      }
      out.push(cur);
    }
    return out.length ? out : [''];
  }
  function newPage(first) {
    page = doc.addPage([W, H]);
    pages.push(page);
    // watermark: SmartFundi logo and name
    const ww = 380, wh = ww * (wm.height / wm.width);
    page.drawImage(wm, { x: (W - ww) / 2, y: (H - wh) / 2 - 20, width: ww, height: wh, opacity: 0.9 });
    // logo on top
    const lw = 150, lh = lw * (logo.height / logo.width);
    page.drawImage(logo, { x: M, y: H - M - lh, width: lw, height: lh });
    page.drawText('Bill of Quantities', { x: W - M - bold.widthOfTextAtSize('Bill of Quantities', 10), y: H - M - 12, size: 10, font: bold, color: navy });
    y = H - M - lh - 14;
    if (!first) tableHeader();
  }
  function tableHeader() {
    const h = 20;
    page.drawRectangle({ x: x0, y: y - h, width: tableW, height: h, color: navy });
    const heads = ['S/No', 'SUPPLY AND INSTALL THE FOLLOWING', 'UNIT', 'QTY', 'RATE (Tshs)', 'AMOUNT (Tshs)'];
    let x = x0;
    heads.forEach((t, i) => {
      const tw = bold.widthOfTextAtSize(t, 8);
      const tx = i === 1 ? x + 4 : x + (cols[i] - tw) / 2;
      page.drawText(t, { x: tx, y: y - 13, size: 8, font: bold, color: rgb(1, 1, 1) });
      x += cols[i];
    });
    y -= h;
  }

  newPage(true);
  const title = clean(b.title || 'BILLS OF QUANTITIES').toUpperCase();
  for (const t of wrap(title, bold, 13, tableW)) {
    page.drawText(t, { x: x0, y: y - 14, size: 13, font: bold, color: navy });
    y -= 17;
  }
  y -= 6;
  const info = headerRows(b);
  if (info.length) {
    const rowH = 15;
    page.drawRectangle({ x: x0, y: y - rowH * info.length - 6, width: tableW, height: rowH * info.length + 6, borderColor: navy, borderWidth: 0.8, color: rgb(0.97, 0.98, 1) });
    info.forEach(([k, v], i) => {
      const yy = y - 6 - rowH * (i + 1) + 4;
      page.drawText(clean(k) + ':', { x: x0 + 8, y: yy, size: 9, font: bold, color: navy });
      page.drawText(clean(v).slice(0, 80), { x: x0 + 150, y: yy, size: 9, font });
    });
    y -= rowH * info.length + 6 + 12;
  }
  tableHeader();

  const size = 8.5, lead = 10.5;
  for (const l of lines) {
    const isSec = l.kind === 'section', isGrp = l.kind === 'group';
    const f = isSec || isGrp ? bold : font;
    const desc = wrap(l.desc, f, size, cols[1] - 8);
    const h = Math.max(desc.length * lead + 6, 16);
    if (y - h < M + 70) newPage(false);
    if (isSec) page.drawRectangle({ x: x0, y: y - h, width: tableW, height: h, color: light });
    // borders
    page.drawRectangle({ x: x0, y: y - h, width: tableW, height: h, borderColor: rgb(0.7, 0.74, 0.8), borderWidth: 0.4 });
    let x = x0;
    for (let i = 0; i < cols.length - 1; i++) {
      x += cols[i];
      page.drawLine({ start: { x, y }, end: { x, y: y - h }, thickness: 0.4, color: rgb(0.7, 0.74, 0.8) });
    }
    page.drawText(clean(l.no), { x: x0 + 4, y: y - 11, size, font: f });
    desc.forEach((t, i) => page.drawText(t, { x: x0 + cols[0] + 4, y: y - 11 - i * lead, size, font: f }));
    if (l.kind === 'item' || l.kind === 'sub') {
      const right = (t, colIdx) => {
        let cx = x0;
        for (let i = 0; i <= colIdx; i++) cx += cols[i];
        page.drawText(t, { x: cx - 4 - font.widthOfTextAtSize(t, size), y: y - 11, size, font });
      };
      page.drawText(clean(l.unit || ''), { x: x0 + cols[0] + cols[1] + 4, y: y - 11, size, font });
      right(String(num(l.qty) % 1 ? num(l.qty) : Math.round(num(l.qty))), 3);
      right(fmt(num(l.rate)), 4);
      right(fmt(lineAmount(l)), 5);
    }
    y -= h;
  }
  // totals
  if (y - 60 < M + 40) newPage(false);
  const total = totalOf(b.lines || []);
  for (const [label, val] of [['SUB TOTAL', total], ['TOTAL BILLS OF QUANTITY', total]]) {
    page.drawRectangle({ x: x0, y: y - 20, width: tableW, height: 20, color: label.startsWith('TOTAL') ? amber : light, borderColor: navy, borderWidth: 0.6 });
    page.drawText(label, { x: x0 + 8, y: y - 14, size: 10, font: bold, color: navy });
    const t = 'TSh ' + fmt(val);
    page.drawText(t, { x: x0 + tableW - 6 - bold.widthOfTextAtSize(t, 10), y: y - 14, size: 10, font: bold, color: navy });
    y -= 20;
  }
  // footer on every page
  pages.forEach((p, i) => {
    p.drawLine({ start: { x: M, y: M + 8 }, end: { x: W - M, y: M + 8 }, thickness: 0.5, color: navy });
    p.drawText('Prepared with SmartFundi', { x: M, y: M - 4, size: 8, font, color: navy });
    const t = `Page ${i + 1} of ${pages.length}`;
    p.drawText(t, { x: W - M - font.widthOfTextAtSize(t, 8), y: M - 4, size: 8, font, color: navy });
  });
  doc.setTitle(clean(b.title || 'Bill of Quantities'));
  doc.setProducer('SmartFundi');
  return Buffer.from(await doc.save());
}

// ============================================================ XLSX (written by hand, formulas included)
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/[\x00-\x08\x0B\x0C\x0E-\x1F]/g, '');
const colL = ['A', 'B', 'C', 'D', 'E', 'F'];

async function buildXlsx(b) {
  const lines = numberRows(b.lines || []);
  const rows = []; // xml of rows
  const merges = [];
  let r = 1;
  const cell = (c, row, s, v, kind = 's') => {
    const ref = colL[c] + row;
    if (v === null || v === undefined || v === '') return `<c r="${ref}" s="${s}"/>`;
    if (kind === 'n') return `<c r="${ref}" s="${s}"><v>${v}</v></c>`;
    if (kind === 'f') return `<c r="${ref}" s="${s}"><f>${v.f}</f><v>${v.v}</v></c>`;
    return `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${esc(v)}</t></is></c>`;
  };
  const addRow = (cells, ht) => { rows.push(`<row r="${r}"${ht ? ` ht="${ht}" customHeight="1"` : ''}>${cells.join('')}</row>`); r++; };

  // rows 1-3: room for the logo
  for (let i = 0; i < 3; i++) addRow([], 26);
  addRow([cell(0, r, 1, b.title || 'BILLS OF QUANTITIES'), ...[1, 2, 3, 4, 5].map((c) => cell(c, r, 1, ''))], 24);
  merges.push(`A${r - 1}:F${r - 1}`);
  addRow([]);
  for (const [k, v] of headerRows(b)) {
    addRow([cell(0, r, 2, k), cell(1, r, 2, ''), cell(2, r, 3, v), cell(3, r, 3, ''), cell(4, r, 3, ''), cell(5, r, 3, '')]);
    merges.push(`A${r - 1}:B${r - 1}`, `C${r - 1}:F${r - 1}`);
  }
  addRow([]);
  addRow(['S/No', 'SUPPLY AND INSTALL THE FOLLOWING', 'UNIT', 'QTY', 'RATE (Tshs)', 'AMOUNT (Tshs)'].map((t, i) => cell(i, r, 4, t)), 22);
  const first = r;
  for (const l of lines) {
    if (l.kind === 'section') {
      addRow([cell(0, r, 5, l.no), cell(1, r, 5, l.desc), ...[2, 3, 4, 5].map((c) => cell(c, r, 5, ''))]);
    } else if (l.kind === 'group') {
      addRow([cell(0, r, 6, l.no), cell(1, r, 6, l.desc), ...[2, 3, 4, 5].map((c) => cell(c, r, 6, ''))]);
    } else {
      addRow([
        cell(0, r, 7, l.no), cell(1, r, 8, l.desc), cell(2, r, 9, l.unit || ''),
        cell(3, r, 10, num(l.qty), 'n'), cell(4, r, 11, num(l.rate), 'n'),
        cell(5, r, 11, { f: `D${r}*E${r}`, v: lineAmount(l) }, 'f'),
      ]);
    }
  }
  const last = r - 1;
  const total = totalOf(b.lines || []);
  addRow([cell(0, r, 12, ''), cell(1, r, 12, 'SUB TOTAL'), cell(2, r, 12, ''), cell(3, r, 12, ''), cell(4, r, 12, ''), cell(5, r, 13, { f: `SUM(F${first}:F${last})`, v: total }, 'f')], 22);
  const sub = r - 1;
  addRow([cell(0, r, 12, ''), cell(1, r, 12, 'TOTAL BILLS OF QUANTITY'), cell(2, r, 12, ''), cell(3, r, 12, ''), cell(4, r, 12, ''), cell(5, r, 13, { f: `F${sub}`, v: total }, 'f')], 24);
  addRow([]);
  addRow([cell(0, r, 14, 'Prepared with SmartFundi')]);

  const sheet = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
<sheetViews><sheetView workbookViewId="0" showGridLines="0"><pane ySplit="${first - 1}" topLeftCell="A${first}" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
<sheetFormatPr defaultRowHeight="15"/>
<cols><col min="1" max="1" width="8" customWidth="1"/><col min="2" max="2" width="62" customWidth="1"/><col min="3" max="3" width="9" customWidth="1"/><col min="4" max="4" width="10" customWidth="1"/><col min="5" max="5" width="17" customWidth="1"/><col min="6" max="6" width="19" customWidth="1"/></cols>
<sheetData>${rows.join('')}</sheetData>
<mergeCells count="${merges.length}">${merges.map((m) => `<mergeCell ref="${m}"/>`).join('')}</mergeCells>
<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" header="0.3" footer="0.3"/>
<pageSetup paperSize="9" orientation="portrait" fitToWidth="1" fitToHeight="0"/>
<headerFooter><oddFooter>&amp;LPrepared with SmartFundi&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter>
<drawing r:id="rId1"/>
<picture r:id="rId2"/>
</worksheet>`;

  const fonts = [
    '<font><sz val="10"/><name val="Arial"/></font>',
    '<font><b/><sz val="14"/><color rgb="FF0B2545"/><name val="Arial"/></font>',
    '<font><b/><sz val="10"/><color rgb="FF0B2545"/><name val="Arial"/></font>',
    '<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/></font>',
    '<font><b/><sz val="10"/><name val="Arial"/></font>',
    '<font><i/><sz val="9"/><color rgb="FF5A6B80"/><name val="Arial"/></font>',
  ];
  const fills = [
    '<fill><patternFill patternType="none"/></fill>', '<fill><patternFill patternType="gray125"/></fill>',
    '<fill><patternFill patternType="solid"><fgColor rgb="FF0B2545"/></patternFill></fill>',
    '<fill><patternFill patternType="solid"><fgColor rgb="FFDCE6F5"/></patternFill></fill>',
    '<fill><patternFill patternType="solid"><fgColor rgb="FFFFC400"/></patternFill></fill>',
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF4F8FD"/></patternFill></fill>',
  ];
  const thin = '<left style="thin"><color rgb="FFB4BCC8"/></left><right style="thin"><color rgb="FFB4BCC8"/></right><top style="thin"><color rgb="FFB4BCC8"/></top><bottom style="thin"><color rgb="FFB4BCC8"/></bottom><diagonal/>';
  const borders = ['<border><left/><right/><top/><bottom/><diagonal/></border>', `<border>${thin}</border>`];
  // cellXfs: 0 default | 1 title | 2 label | 3 value | 4 header | 5 section | 6 group | 7 no | 8 desc | 9 unit | 10 qty | 11 money | 12 total label | 13 total money | 14 note
  const xf = (font, fill, border, extra = '', nf = 0) => `<xf numFmtId="${nf}" fontId="${font}" fillId="${fill}" borderId="${border}" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyNumberFormat="1"${extra ? ' applyAlignment="1"' : ''}>${extra}</xf>`;
  const al = (h, v = 'center', wrap = false) => `<alignment horizontal="${h}" vertical="${v}"${wrap ? ' wrapText="1"' : ''}/>`;
  const xfs = [
    xf(0, 0, 0), xf(1, 0, 0, al('center')), xf(2, 5, 1, al('left')), xf(0, 5, 1, al('left')),
    xf(3, 2, 1, al('center', 'center', true)), xf(2, 3, 1, al('left')), xf(4, 0, 1, al('left', 'top', true)),
    xf(0, 0, 1, al('center', 'top')), xf(0, 0, 1, al('left', 'top', true)), xf(0, 0, 1, al('center', 'top')),
    xf(0, 0, 1, al('right', 'top'), 0), xf(0, 0, 1, al('right', 'top'), 3),
    xf(2, 3, 1, al('left')), xf(2, 4, 1, al('right'), 3), xf(5, 0, 0, al('left')),
  ];
  const styles = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<fonts count="${fonts.length}">${fonts.join('')}</fonts><fills count="${fills.length}">${fills.join('')}</fills><borders count="${borders.length}">${borders.join('')}</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="${xfs.length}">${xfs.join('')}</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>`;

  // logo (top left) as a drawing, watermark as the sheet background
  const lw = 230;
  const emu = (px) => Math.round(px * 9525);
  const logoH = Math.round(230 * (448 / 2168));
  const drawing = `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
<xdr:oneCellAnchor><xdr:from><xdr:col>0</xdr:col><xdr:colOff>${emu(6)}</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>${emu(10)}</xdr:rowOff></xdr:from><xdr:ext cx="${emu(lw)}" cy="${emu(logoH)}"/>
<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="2" name="SmartFundi logo"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="rId1"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="${emu(lw)}" cy="${emu(logoH)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:oneCellAnchor>
</xdr:wsDr>`;

  const zip = new JSZip();
  zip.file('[Content_Types].xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/>
<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>`);
  zip.file('_rels/.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`);
  zip.file('xl/workbook.xml', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="BOQ" sheetId="1" r:id="rId1"/></sheets><calcPr calcId="191029" fullCalcOnLoad="1"/></workbook>`);
  zip.file('xl/_rels/workbook.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>`);
  zip.file('xl/styles.xml', styles);
  zip.file('xl/worksheets/sheet1.xml', sheet);
  zip.file('xl/worksheets/_rels/sheet1.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/watermark.png"/></Relationships>`);
  zip.file('xl/drawings/drawing1.xml', drawing);
  zip.file('xl/drawings/_rels/drawing1.xml.rels', `<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/logo.png"/></Relationships>`);
  zip.file('xl/media/logo.png', asset('logo.png'));
  zip.file('xl/media/watermark.png', asset('watermark.png'));
  return zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' });
}

module.exports = { numberRows, totalOf, lineAmount, buildPdf, buildXlsx };
