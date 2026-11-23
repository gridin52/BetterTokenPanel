// Runs in an isolated WebKit content world; no network calls and no secrets returned.
(() => {
  const text = document.body ? document.body.innerText.replace(/ /g, ' ') : '';
  const lines = text.split(/\n/).map(s => s.trim()).filter(Boolean);
  const number = '(\\d[\\d \\u202f]*(?:[.,]\\d+)?)[ \\t]*(млрд|млн|тыс\\.?|[KMBКМВ])?';
  function parse(raw, unit) {
    const n = Number(raw.replace(/[  ]/g, '').replace(',', '.'));
    const u = (unit || '').toLowerCase();
    const multiplier = /^(b|в|млрд)$/.test(u) ? 1e9 : /^(m|м|млн)$/.test(u) ? 1e6 : /^(k|к|тыс\.?)$/.test(u) ? 1e3 : 1;
    const value = n * multiplier;
    return Number.isFinite(value) && value >= 0 ? value : null;
  }
  function afterLabel(labels) {
    for (let i = 0; i < lines.length; i++) {
      for (const label of labels) {
        const match = lines[i].match(label);
        if (!match) continue;
        const tail = lines[i].slice(match.index + match[0].length).replace(/^\s*[:—–-]?\s*/, '');
        const candidates = tail ? [tail] : lines.slice(i + 1, i + 3);
        for (const candidate of candidates) {
          const m = candidate.match(new RegExp('^' + number + '(?![\\d.,])(?:\\s*(?:токен(?:ов|а)?|tokens?))?\\s*$', 'i'));
          if (m) return parse(m[1], m[2]);
        }
      }
    }
    return null;
  }
  const remaining = afterLabel([/осталось\s+токенов/i, /остаток\s+токенов/i, /tokens?\s+remaining/i, /remaining\s+tokens?/i]);
  if (remaining === null) return null;
  return {
    remaining,
    spent: afterLabel([/^потрачено/i, /^tokens?\s+used/i]),
    total: afterLabel([/^всего\s+начислено/i, /^total\s+tokens?/i])
  };
})()
