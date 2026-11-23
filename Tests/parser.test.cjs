// Synthetic fixtures based on visible panel labels; not a live provider integration test.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const script = fs.readFileSync(path.join(__dirname, '../Sources/BetterTokenPanel/BalanceReader.js'), 'utf8');
function read(text) { return vm.runInNewContext(script, { document: { body: { innerText: text } } }); }
const fixtures = [
  ['Осталось токенов\n188.1M\n47.0% осталось\nПотрачено\n211.9M\nВсего начислено\n400M\nИз них бонус\n+350M', 188100000, 211900000, 400000000],
  ['Осталось токенов: 188,1 млн', 188100000],
  ['Осталось токенов\n1 234 567', 1234567],
  ['Осталось токенов\n1 234 567', 1234567],
  ['Остаток токенов\n1.2B', 1200000000],
  ['Осталось токенов\n12.5K', 12500],
  ['Осталось токенов\n12 тыс.', 12000],
  ['Осталось токенов\n0', 0],
  ['Tokens remaining\n42M', 42000000],
  ['Remaining tokens: 1,5 млрд', 1500000000],
  ['Осталось токенов\n188.1M токенов', 188100000],
  ['Осталось токенов\nЗагрузка…\n188.1M', 188100000],
];
for (const [text, remaining, spent, total] of fixtures) {
  const result = read(text);
  assert.equal(result?.remaining, remaining, text);
  if (spent !== undefined) assert.equal(result.spent, spent);
  if (total !== undefined) assert.equal(result.total, total);
}
for (const text of [
  'Плановые работы у VPS-провайдера\n18.08, 22:00',
  'Ошибка авторизации\n401',
  'Потрачено\n211.9M\nВсего начислено\n400M',
  'Осталось токенов\n47.0% осталось',
  'Осталось токенов\n-10M',
  'Осталось токенов\n188.1.2M',
  'Осталось токенов\nsk-demo-1234',
  'Осталось токенов\nЗагрузка…\nВсего начислено\n400M',
  ''
]) assert.equal(read(text), null, text);
assert.equal(vm.runInNewContext(script, { document: { body: null } }), null);
console.log('22 parser checks passed. Live WebKit/macOS integration still requires a Mac.');
