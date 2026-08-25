// Regression tests for js/symb/collections.editor.imgtools.js, driving the REAL file
// in a stubbed DOM so the tests cannot drift from shipped code.
//
// Covers handover-audit findings:
//   high 4  - OCR must not clobber existing data / empty values / non-editable fields
//   high 5  - unmapped OCR text must not be concatenated into institutionCode
//             (BOTH sites: UpdateFromWithOCR and normalizeFieldValueText)
//   med  9  - a failed validation must not flip the button to "Update Form"
//   low  6  - confidence styling must clear once a human edits the field
//
// Usage: node test_imgtools.js <path to collections.editor.imgtools.js>
const fs = require('fs');
const vm = require('vm');

// Defaults to the shipped file so `node tests/js/test-imgtools.js` just works;
// pass a path to run the same assertions against another revision (that is how the
// before/after comparison in the PR was produced).
const path = require('path');
const FILE = process.argv[2] ||
  path.join(__dirname, '..', '..', 'js', 'symb', 'collections.editor.imgtools.js');
const src = fs.readFileSync(FILE, 'utf8');

function makeField(id, opts) {
  opts = opts || {};
  const listeners = {};
  const f = {
    id,
    value: opts.value || '',
    type: opts.type || 'text',
    disabled: !!opts.disabled,
    readOnly: !!opts.readOnly,
    innerText: '',
    classes: [],
    attrs: {},
    style: {},
    listeners,
    closest: () => null,
    dispatchEvent: () => {},
    addEventListener: (ev, fn, o) => { (listeners[ev] = listeners[ev] || []).push({ fn, once: !!(o && o.once) }); },
    classList: {
      add: c => { if (!f.classes.includes(c)) f.classes.push(c); },
      remove: c => { f.classes = f.classes.filter(x => x !== c); },
    },
    setAttribute: (k, v) => { f.attrs[k] = String(v); },
    removeAttribute: k => { delete f.attrs[k]; },
    getAttribute: k => (k in f.attrs ? f.attrs[k] : null),
  };
  f.fire = ev => (listeners[ev] || []).forEach(l => l.fn.call(f));
  return f;
}

function sandbox(fields) {
  const byId = {};
  Object.values(fields).forEach(f => { byId[f.id] = f; });
  const alerts = [], logs = [];
  const $stub = () => ({ ready: () => {}, tooltip: () => {}, data: () => null, imagetool: () => {} });
  const ctx = {
    $: $stub, jQuery: $stub,
    document: {
      getElementById: id => byId[id] || null,
      querySelector: sel => { const m = sel.match(/\[name="([^"]+)"\]/); return m ? (byId[m[1]] || null) : null; },
      cookie: '',
    },
    window: { addEventListener: () => {}, removeEventListener: () => {} },
    alert: m => alerts.push(m),
    console: {
      log: () => {}, warn: m => logs.push('warn: ' + m),
      error: m => logs.push('err: ' + m), info: m => logs.push('info: ' + m),
    },
    setTimeout: () => {}, Event: class { constructor(t) { this.type = t; } },
    imgArr: {}, imgLgArr: {},
    // confirmOCRresult reads the legacy implicit global `event` (only populated when
    // invoked from an inline onclick). Declare it so the reference does not throw.
    event: undefined,
  };
  vm.createContext(ctx);
  return { ctx, alerts, logs, fields };
}

function run(fields, driver) {
  const s = sandbox(fields);
  new vm.Script(src + '\n' + driver).runInContext(s.ctx, { timeout: 5000 });
  return s;
}

let fails = 0;
const check = (name, cond, detail) => {
  if (cond) console.log('ok    ' + name);
  else { console.log('FAIL  ' + name + (detail ? '  -- ' + detail : '')); fails++; }
};

// A realistic label: mostly keys the quick-entry form has no slot for.
const LABEL = [
  'scientificName: Acer rubrum',
  'recordedBy: J. Smith',
  'family: Aceraceae',
  'country: United States',
  'county: Middlesex',
  'habitat: rich mesic woods on a north-facing slope',
  'minimumElevationInMeters: 340',
].join('\n');

// --- high 5, second site: normalizeFieldValueText ------------------------------------
{
  const s = run({}, `globalThis.__out = normalizeFieldValueText(${JSON.stringify(LABEL)});`);
  const out = s.ctx.__out;
  const inst = (out.match(/^institutionCode: (.*)$/m) || [])[1];
  check('H5b institutionCode is not a dumping ground', !inst || inst.length <= 12,
    'got ' + JSON.stringify(inst));
  check('H5b recognised DWC keys survive normalisation',
    ['family: Aceraceae', 'country: United States', 'county: Middlesex',
     'habitat: rich mesic woods on a north-facing slope'].every(l => out.includes(l)),
    JSON.stringify(out));
  check('H5b the mapped fields still survive',
    out.includes('scientificName: Acer rubrum') && out.includes('recordedBy: J. Smith'),
    JSON.stringify(out));
}

// --- high 4 / high 5, first site: UpdateFromWithOCR ----------------------------------
{
  const f = { sci: makeField('ffcurrname'), rec: makeField('ffrecordedby'), inst: makeField('institutioncode') };
  const s = run(f, `storedOcrResponse = ${JSON.stringify(LABEL)}; UpdateFromWithOCR();`);
  check('H5a institutionCode stays empty for prose', f.inst.value === '', 'got ' + JSON.stringify(f.inst.value));
  check('H5a mapped fields populate', f.sci.value === 'Acer rubrum' && f.rec.value === 'J. Smith',
    f.sci.value + ' / ' + f.rec.value);
  check('H5a unmapped text reported', s.logs.some(l => l.includes('no matching field')), s.logs.join(' / '));
}
{
  const f = { sci: makeField('ffcurrname', { value: 'Acer rubrum' }), rec: makeField('ffrecordedby') };
  const s = run(f, `storedOcrResponse = "scientificName: Acer rubrm\\nrecordedBy: J. Smith"; UpdateFromWithOCR();`);
  check('H4 curated value not overwritten', f.sci.value === 'Acer rubrum', 'got ' + f.sci.value);
  check('H4 empty field still filled', f.rec.value === 'J. Smith', 'got ' + f.rec.value);
  check('H4 conflict surfaced', s.alerts.some(a => a.includes('scientificName')), s.alerts.join(' / '));
}
{
  const f = { bc: makeField('barcode', { disabled: true }) };
  run(f, `storedOcrResponse = "barcode: BU123456"; UpdateFromWithOCR();`);
  check('H4 disabled field not written', f.bc.value === '', 'got ' + JSON.stringify(f.bc.value));
}

// --- medium 9: failed validation must not advance the button -------------------------
{
  // Empty rawtext -> confirmOCRresult alerts and fails.
  const f = { raw: makeField('rawtext', { value: '' }), btn: makeField('updateButton') };
  f.btn.innerText = 'Validate';
  const s = run(f, `updateState = "needsValidation"; globalThis.__r = handleUpdateButtonClick(); globalThis.__state = updateState;`);
  check('M9 button stays on Validate after a failed validation',
    f.btn.innerText === 'Validate', 'got ' + JSON.stringify(f.btn.innerText));
  check('M9 state stays needsValidation', s.ctx.__state === 'needsValidation', 'got ' + s.ctx.__state);
  check('M9 handler still returns false (button would submit otherwise)', s.ctx.__r === false, 'got ' + s.ctx.__r);
  check('M9 user was told why', s.alerts.some(a => /empty/i.test(a)), s.alerts.join(' / '));
}
{
  // Valid rawtext -> confirmOCRresult succeeds, button advances.
  const f = { raw: makeField('rawtext', { value: 'scientificName: Acer rubrum' }), btn: makeField('updateButton') };
  f.btn.innerText = 'Validate';
  const s = run(f, `updateState = "needsValidation"; ocrAnalysisMode = true; handleUpdateButtonClick(); globalThis.__state = updateState;`);
  check('M9 button advances when validation passes',
    f.btn.innerText === 'Update Form', 'got ' + JSON.stringify(f.btn.innerText));
  check('M9 state advances', s.ctx.__state === 'ready', 'got ' + s.ctx.__state);
}

// --- low 6: confidence styling clears once the human edits ---------------------------
{
  const f = { fld: makeField('ffeventdate', { value: '1996-07-04' }) };
  const s = run(f, `applyConfidenceToField(document.getElementById("ffeventdate"), "eventDate", {eventDate: 0.45});`);
  const styled = f.fld.classes.includes('ml-confidence-field') && !!f.fld.attrs.title;
  check('L6 confidence styling applied first', styled,
    'classes=' + f.fld.classes + ' title=' + f.fld.attrs.title);
  f.fld.fire('input');
  check('L6 styling cleared after user input',
    !f.fld.classes.includes('ml-confidence-field') && !f.fld.attrs.title && !f.fld.attrs['data-confidence'],
    'classes=' + f.fld.classes + ' attrs=' + JSON.stringify(f.fld.attrs));
  check('L6 background reset', f.fld.style.backgroundColor === '', 'got ' + JSON.stringify(f.fld.style.backgroundColor));
}

// --- regressions found by review of the first version of this fix -------------------
// R1: the form's ONLY institutionCode input is <input type="hidden">, so skipping
//     hidden inputs meant OCR could never populate it at all.
{
  const f = { inst: makeField('institutioncode', { type: 'hidden' }) };
  run(f, `storedOcrResponse = "institutionCode: NEBC"; UpdateFromWithOCR();`);
  check('R1 hidden institutionCode input IS written', f.inst.value === 'NEBC',
    'got ' + JSON.stringify(f.inst.value));
}
// R2: institutionCodePattern matches any 2-12 char token, so treating the VALUE of an
//     unmapped "key: value" line as a candidate assigned real data to institutionCode.
for (const [line, label] of [['county: Norfolk', 'county'],
                             ['family: Aceraceae', 'family'],
                             ['dateIdentified: 1998-05-12', 'dateIdentified']]) {
  const f = { sci: makeField('ffcurrname'), inst: makeField('institutioncode') };
  run(f, `storedOcrResponse = ${JSON.stringify('scientificName: Acer rubrum\n' + line)}; UpdateFromWithOCR();`);
  check(`R2 ${label} value does not become institutionCode`, f.inst.value === '',
    'got ' + JSON.stringify(f.inst.value));
}
// R3: a genuinely bare code-shaped token must still work.
{
  const f = { sci: makeField('ffcurrname'), inst: makeField('institutioncode') };
  run(f, `storedOcrResponse = "NEBC\\nscientificName: Acer rubrum"; UpdateFromWithOCR();`);
  check('R3 bare code-shaped token still sets institutionCode', f.inst.value === 'NEBC',
    'got ' + JSON.stringify(f.inst.value));
}

// R4: a keyed line with an EMPTY value (a trailing "Notes:") must not have its KEY
//     harvested as an institution code. normalizeFieldValueText's fallback did that,
//     emitting "institutionCode: Notes", which then mapped cleanly downstream -- the
//     same corruption as R2 arriving through the other function.
{
  const s = sandbox({});
  new vm.Script(src + '\nglobalThis.__nfvt = normalizeFieldValueText;').runInContext(s.ctx, { timeout: 5000 });
  for (const key of ['Notes', 'Elev', 'Coll']) {
    const out = s.ctx.__nfvt('scientificName: Acer rubrum\n' + key + ':');
    check(`R4 keyed-empty line "${key}:" does not become institutionCode`,
      !/institutionCode/.test(out), 'got ' + JSON.stringify(out));
  }
}

console.log(fails === 0 ? '\nALL PASS' : '\n' + fails + ' FAILURES');
process.exit(fails === 0 ? 0 : 1);

