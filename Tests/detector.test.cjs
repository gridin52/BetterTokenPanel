'use strict';
// Run: NODE_PATH=/path/to/scratch/node_modules node --test Tests/detector.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { JSDOM } = require('jsdom');
const source = fs.readFileSync(path.join(__dirname, '../Sources/BetterTokenPanel/PanelDetector.js'), 'utf8');
function setup(html) {
  const dom = new JSDOM(html, { url: 'https://dashboard.example.test/', runScripts: 'outside-only' });
  dom.window.eval(source);
  return { dom, win: dom.window, doc: dom.window.document, api: dom.window.BTPDetector };
}
const card = (label = 'Remaining tokens', value = '188.1M', id = 'balance') => `<section id="${id}"><h3>${label}</h3><strong class="count">${value}</strong></section>`;
const plain = value => JSON.parse(JSON.stringify(value));
function only(api) { const found = api.scan(); assert.equal(found.length, 1); return found[0]; }

test('manual picker accepts a rich balance card with percentages and other metrics', () => {
  const { api, doc, win } = setup('<section id="summary"><h3>Осталось токенов</h3><div><strong class="balance">188.1M</strong></div><p id="percent">47.0% осталось</p><div><span>Потрачено</span><b>211.9M</b></div><div><span>Всего начислено</span><b>400M</b></div></section>');
  api.enablePicker(true);
  doc.querySelector('.balance').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const event = api.takePickerEvent();
  assert.ok(event.candidate, JSON.stringify(event));
  assert.equal(event.candidate.value, 188100000);
  const rule = plain(event.candidate.rule);
  assert.equal(JSON.parse(rule.anchor)[0], 2);
  doc.querySelector('.balance').textContent = '187.9M';
  doc.querySelector('#percent').textContent = '46.9% осталось';
  assert.equal(api.read(rule).remaining, 187900000);
  doc.querySelector('h3').textContent = 'Потрачено';
  assert.equal(api.read(rule), null);
});

test('manual rich rule never moves to another numeric sibling after reorder', () => {
  const { api, doc, win } = setup('<section><h3>Remaining tokens</h3><div><b id="n">12M</b></div><p>50%</p><h4>Used</h4><b>8M</b></section>');
  api.enablePicker(true);
  doc.querySelector('#n').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const result = api.takePickerEvent();
  assert.ok(result.candidate);
  const rule = plain(result.candidate.rule);
  doc.querySelector('section').append(doc.querySelector('#n').parentElement);
  assert.equal(api.read(rule), null);
});

test('native point selection reports a result immediately and maps normalized viewport coordinates', () => {
  const { api, doc, win } = setup(card());
  let point;
  doc.elementFromPoint = (x, y) => { point = [x, y]; return doc.querySelector('.count'); };
  assert.equal(api.pickAtPoint(0.25, 0.5).reason, 'inactive');
  assert.equal(api.enablePicker(true), true);
  const result = api.pickAtPoint(0.25, 0.5);
  assert.deepEqual(point, [win.innerWidth * 0.25, win.innerHeight * 0.5]);
  assert.equal(result.candidate.value, 188100000);
  assert.ok(api.takePickerEvent().candidate);
  assert.equal(api.takePickerEvent(), null);
  assert.equal(api.pickAtPoint(-1, 0).reason, 'inactive');
});

test('a rejected click emits feedback instead of silently returning no selection', () => {
  const { api, doc, win } = setup('<p id="bad">Nothing numeric here</p>');
  api.enablePicker(true);
  doc.querySelector('#bad').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const result = api.takePickerEvent();
  assert.equal(result.candidate, null);
  assert.equal(result.reason, 'number');
  assert.equal(api.takePickerEvent(), null);
});

test('pointerup without a synthesized click can select a value', () => {
  const { api, doc, win } = setup(card());
  api.enablePicker(true);
  doc.querySelector('.count').dispatchEvent(new win.MouseEvent('pointerup', { bubbles: true, cancelable: true }));
  assert.equal(api.takePickerEvent().candidate.value, 188100000);
});

test('manual rich context refuses decorated numeric fragments', () => {
  for (const markup of ['-<span>12</span>', '<span>12</span>%', '$<span>12</span>', '<span>12</span> / 20', '<span>12</span>M']) {
    const { api, doc, win } = setup('<section><h3>Remaining tokens</h3><b>' + markup + '</b><p>50%</p></section>');
    api.enablePicker(true);
    doc.querySelector('span').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    const result = api.takePickerEvent();
    assert.equal(result.candidate, null, markup);
  }
});

test('clicking money never selects an unrelated token counter elsewhere in the card', () => {
  const { api, doc, win } = setup('<section><h3>Remaining tokens</h3><b>12M</b><span id="money">$5</span></section>');
  api.enablePicker(true);
  doc.querySelector('#money').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(api.takePickerEvent().candidate, null);
});

test('idempotent installation, exact serializable candidate/rule/result contract, zero', () => {
  const { win, api } = setup(card('Tokens remaining', '0'));
  win.eval(source);
  assert.equal(win.BTPDetector, api);
  const c = only(api);
  assert.deepEqual(Object.keys(c).sort(), ['display', 'id', 'label', 'rule', 'value']);
  assert.deepEqual(Object.keys(c.rule).sort(), ['anchor', 'contextSelector', 'labelSelector', 'selector', 'version']);
  assert.equal(c.value, 0);
  assert.deepEqual(plain(api.read(plain(c.rule))), { remaining: 0, spent: null, total: null });
});

test('strict localized counts and units', () => {
  for (const [text, expected] of [['188.1M', 188100000], ['188,1 млн', 188100000], ['1 234 567', 1234567], ['1 234 567', 1234567], ['1.2B', 1200000000], ['2 тыс.', 2000], ['12 tokens', 12]]) {
    const { api } = setup(card('Доступно токенов', text));
    assert.equal(only(api).value, expected, text);
  }
});

test('saved rule reads only its binding; count and magnitude may change', () => {
  const { api, doc } = setup(card('Available tokens', '12K'));
  const rule = plain(only(api).rule);
  assert.ok(!rule.anchor.includes('12k'));
  doc.querySelector('.count').textContent = '2.5M';
  assert.equal(api.read(rule).remaining, 2500000);
  doc.querySelector('.count').textContent = '0';
  assert.equal(api.read(rule).remaining, 0);
  doc.querySelector('.count').remove();
  doc.body.insertAdjacentHTML('beforeend', card('Remaining tokens', '99', 'other'));
  assert.equal(api.read(rule), null, 'must not rescan or fall back');
});

test('ambiguous dashboard returns separate candidates, never chooses or confirms', () => {
  const { api } = setup(card('Balance', '10', 'a') + card('Quota', '20', 'b'));
  const list = api.scan();
  assert.equal(list.length, 2);
  assert.notEqual(list[0].id, list[1].id);
  assert.deepEqual(Array.from(list, c => c.value), [10, 20]);
  assert.equal(api.takeSelection(), null);
});

test('reordering positional cards never silently reads spent', () => {
  const { api, doc } = setup('<main><section><h3>Remaining tokens</h3><b>10</b></section><section><h3>Tokens spent</h3><b>90</b></section></main>');
  const rule = plain(only(api).rule);
  const main = doc.querySelector('main');
  main.prepend(main.lastElementChild);
  assert.equal(api.read(rule), null);
});

test('reordering label and count inside a confirmed card invalidates relative layout', () => {
  const { api, doc } = setup(card());
  const rule = only(api).rule;
  doc.querySelector('section').prepend(doc.querySelector('.count'));
  assert.equal(api.read(rule), null);
});

test('unchanged identity survives moving entire card with stable selectors', () => {
  const { api, doc } = setup(card() + card('Tokens spent', '50', 'spent'));
  const rule = only(api).rule;
  doc.body.append(doc.querySelector('#balance'));
  // A positional value selector must fail rather than make an unsafe guess.
  const result = api.read(rule);
  assert.ok(result === null || result.remaining === 188100000);
});

test('duplicate saved selectors fail even when duplicate is hidden', () => {
  const { api, doc } = setup('<section id="card"><h3 id="label">Balance</h3><b id="value">7</b></section>');
  const rule = only(api).rule;
  doc.body.insertAdjacentHTML('beforeend', '<b hidden id="value">88</b>');
  assert.equal(api.read(rule), null);
});

test('invisible counts, excluded elements and aggregate cards are ignored', () => {
  const { api } = setup('<section><h3>Balance</h3><b hidden>1</b></section>' +
    '<section style="display:none"><h3>Balance</h3><b>2</b></section>' +
    '<section aria-hidden="true"><h3>Balance</h3><b>3</b></section>' +
    '<section style="opacity:0"><h3>Balance</h3><b>4</b></section>' +
    '<section><h3>Balance</h3><input value="999"><input type="password" value="secret"></section>' +
    '<section><h3>Balance</h3><b>10 / 20</b></section>' +
    '<section><h3>Balance</h3><b>10</b><b>20</b></section>' +
    '<script>100</script><style>200</style>');
  assert.equal(api.scan().length, 0);
});

test('malformed numbers, money, percentage, negatives and billing are rejected', () => {
  for (const text of ['$12', '12 USD', '€12', '12 ₽', '12 руб', '12%', '-12', '−12', '1,234.56', '1.234,56', '12 34', '1..2', '12M 4K', '10/20', '1e3', 'NaN', 'Infinity', '9007199254740992']) {
    assert.equal(setup(card('Balance', text)).api.scan().length, 0, text);
  }
  for (const label of ['Total tokens', 'Purchased tokens', 'Tokens spent', 'Billing balance', 'Balance USD', 'Стоимость']) {
    assert.equal(setup(card(label, '12')).api.scan().length, 0, label);
  }
});

test('removed/changed label, invisible value, login replacement and currency invalidate persisted rule', () => {
  const changes = [
    doc => doc.querySelector('h3').remove(),
    doc => { doc.querySelector('h3').textContent = 'Tokens spent'; },
    doc => { doc.querySelector('.count').hidden = true; },
    doc => { doc.body.innerHTML = '<form><h3>Sign in</h3><input type="password"><b>100</b></form>'; },
    doc => { doc.querySelector('.count').textContent = '$200'; },
    doc => { doc.querySelector('.count').textContent = '50%'; },
    doc => { doc.querySelector('h3').style.visibility = 'hidden'; }
  ];
  for (const change of changes) {
    const { api, doc } = setup(card());
    const rule = plain(only(api).rule);
    change(doc);
    assert.equal(api.read(rule), null);
  }
});

test('manual picker intercepts page actions, consumes selection, binds unknown static label', () => {
  const { api, doc, win } = setup('<a href="#delete"><section id="custom"><h3>Private account abc@example.test</h3><b id="n">42K</b></section></a>');
  const count = doc.querySelector('#n');
  let pageClicks = 0, pageDown = 0;
  doc.addEventListener('click', () => pageClicks++);
  doc.addEventListener('mousedown', () => pageDown++);
  assert.equal(api.scan().length, 0);
  api.enablePicker(true);
  count.dispatchEvent(new win.MouseEvent('mousedown', { bubbles: true, cancelable: true }));
  const event = new win.MouseEvent('click', { bubbles: true, cancelable: true });
  assert.equal(count.dispatchEvent(event), false);
  assert.equal(event.defaultPrevented, true);
  assert.equal(pageClicks, 0);
  assert.equal(pageDown, 0);
  const c = api.takeSelection();
  assert.equal(c.value, 42000);
  assert.equal(c.label, 'Выбранное значение');
  assert.ok(!JSON.stringify({ label: c.label, display: c.display }).includes('abc@example'));
  assert.equal(api.takeSelection(), null);
  api.enablePicker(false);
  count.textContent = '43M';
  assert.equal(api.read(c.rule).remaining, 43000000);
  doc.querySelector('h3').textContent = 'Different account';
  assert.equal(api.read(c.rule), null);
  count.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(pageClicks, 1);
});

test('picker picks nearest nested numeric element, rejects invalid selection', () => {
  const { api, doc, win } = setup('<section><h3>Custom counter</h3><b><span id="n">21</span></b><em id="bad">hello</em></section>');
  api.enablePicker(true);
  doc.querySelector('#n').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const c = api.takeSelection();
  assert.ok(c);
  assert.equal(c.value, 21);
  doc.body.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(api.takeSelection(), null);
  api.stop();
});

test('highlight and stop restore existing inline styles and remove interception', () => {
  const { api, doc, win } = setup(card());
  const el = doc.querySelector('.count');
  el.style.setProperty('outline', '1px dotted red', 'important');
  el.style.setProperty('outline-offset', '8px');
  const before = el.getAttribute('style');
  const rule = only(api).rule;
  assert.equal(api.highlight(rule), true);
  assert.equal(el.style.outline, '3px solid #1677ff');
  assert.equal(api.highlight({}), false);
  assert.equal(el.getAttribute('style'), before);
  api.enablePicker(true);
  api.highlight(rule);
  api.stop();
  assert.equal(el.getAttribute('style'), before);
  let clicks = 0;
  doc.addEventListener('click', () => clicks++);
  el.dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(clicks, 1);
  assert.equal(api.takeSelection(), null);
});

test('inline generic label and count, generic result never leaks context text', () => {
  const { api } = setup('<section id="private-key"><p>Remaining tokens: 15M</p></section>');
  const c = only(api);
  assert.equal(c.label, 'Remaining tokens');
  assert.equal(c.value, 15000000);
  assert.equal(api.read(c.rule).remaining, 15000000);
});

test('nested decorations and numeric aggregates cannot masquerade as a plain child count', () => {
  for (const markup of ['-<span>12</span>', '−<span>12</span>', '<span>12</span>%', '$<span>12</span>', '<span>12</span> / 20', '<span>12</span>M', '<span>12</span> and 15']) {
    const { api } = setup(`<section><h3>Balance</h3><b>${markup}</b></section>`);
    assert.equal(api.scan().length, 0, markup);
  }
});

test('manual nested value binds enclosing static label, not a label-free inner wrapper', () => {
  const { api, doc, win } = setup('<section><h3>Custom counter</h3><b><span id="n">21</span></b></section>');
  api.enablePicker(true);
  doc.querySelector('#n').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const c = api.takeSelection();
  assert.ok(c.rule.labelSelector);
  doc.querySelector('h3').remove();
  assert.equal(api.read(c.rule), null);
});

test('no-label manual selection requires stable identity and a single counter', () => {
  const { api, doc, win } = setup('<section id="stable"><b>18</b></section>');
  api.enablePicker(true);
  doc.querySelector('b').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  const c = api.takeSelection();
  assert.ok(c);
  assert.equal(c.rule.labelSelector, '');
  doc.querySelector('b').textContent = '19M';
  assert.equal(api.read(c.rule).remaining, 19000000);
  doc.querySelector('section').id = 'different';
  assert.equal(api.read(c.rule), null);
  const other = setup('<main><section><b>18</b></section><section><b>99</b></section></main>');
  other.api.enablePicker(true);
  other.doc.querySelector('b').dispatchEvent(new other.win.MouseEvent('click', { bubbles: true, cancelable: true }));
  assert.equal(other.api.takeSelection(), null, 'anonymous counters are unsafe to persist');
});

test('no network or browser storage is accessed', () => {
  const dom = new JSDOM(card(), { url: 'https://dashboard.example.test/', runScripts: 'outside-only' });
  for (const name of ['fetch', 'XMLHttpRequest', 'WebSocket', 'localStorage', 'sessionStorage', 'indexedDB']) {
    Object.defineProperty(dom.window, name, { configurable: true, get() { throw new Error('forbidden API: ' + name); } });
  }
  dom.window.eval(source);
  const api = dom.window.BTPDetector;
  assert.equal(api.read(only(api).rule).remaining, 188100000);
  api.enablePicker(true);
  api.stop();
});

test('ambiguous locale separators fail closed; explicit magnitude remains readable', () => {
  for (const text of ['1,234', '1.234', '1234.567']) assert.equal(setup(card('Balance', text)).api.scan().length, 0, text);
  assert.equal(only(setup(card('Balance', '1.234M')).api).value, 1234000);
});

test('picker installed before page capture handlers blocks them only while enabled', () => {
  const { api, doc, win } = setup(card());
  let clicks = 0;
  win.addEventListener('click', () => clicks++, true);
  const click = () => doc.querySelector('.count').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
  click();
  assert.equal(clicks, 1);
  api.enablePicker(true); click();
  assert.equal(clicks, 1);
  api.enablePicker(false); click();
  assert.equal(clicks, 2);
  api.stop();
});

test('saved rule survives a full page reload with a changed balance', () => {
  const first = setup(card('Remaining tokens', '188.1M'));
  const rule = plain(only(first.api).rule);
  const second = setup(card('Remaining tokens', '187.9M'));
  assert.equal(second.api.read(rule).remaining, 187900000);
});

test('context fingerprint changes fail even when positional selector still resolves a number', () => {
  const { api, doc } = setup('<section><h3>Remaining tokens</h3><b>12M</b></section>');
  const rule = plain(only(api).rule);
  doc.querySelector('section').innerHTML = '<h3>Remaining tokens</h3><div>Used</div><b>9M</b>';
  assert.equal(api.read(rule), null);
});

test('manual choice rejects money and percentages too', () => {
  for (const value of ['$42', '42%', '42 credits']) {
    const { api, doc, win } = setup(card('Balance', value));
    api.enablePicker(true);
    doc.querySelector('.count').dispatchEvent(new win.MouseEvent('click', { bubbles: true, cancelable: true }));
    assert.equal(api.takeSelection(), null, value);
    api.stop();
  }
});

test('invalid selectors, unbound rules and over-budget DOM fail closed', () => {
  const { api } = setup(card());
  const r = only(api).rule;
  for (const bad of [null, {}, { ...r, version: 2 }, { ...r, selector: '[' }, { ...r, selector: 'strong, h3' }, { ...r, anchor: 'wrong' }, { ...r, contextSelector: 'body' }]) assert.equal(api.read(bad), null);
  const { api: huge } = setup(card() + '<i></i>'.repeat(6001));
  assert.equal(huge.scan().length, 0);
});
