// Local DOM only. Install in WKContentWorld.defaultClient; never evaluates page code.
(() => {
  'use strict';
  if (globalThis.BTPDetector) return;
  const MAX_NODES = 6000, MAX_CONTEXT = 160, MAX_TEXT = 2400;
  const generic = 'Remaining tokens', manual = 'Выбранное значение';
  const normalize = s => String(s).replace(/[\s  ]+/g, ' ').trim().toLowerCase();
  const positive = /^(?:(?:remaining|available)\s+tokens?|tokens?\s+(?:remaining|available)|(?:token\s+)?(?:balance|quota)|(?:осталось|остаток|доступно|доступные)\s+токен(?:ов|а|ы)?|(?:баланс|квота)(?:\s+токен(?:ов|а|ы)?)?)\s*[:：]?$/i;
  const forbidden = /(?:\b(?:spent|used|total|purchased|billing|price|cost|usd|eur|dollars?|credits?)\b|потрачен|израсход|всего|куплен|оплачен|стоимост|руб|доллар|€|\$|£|₽|%)/i;
  const numeric = /^(\d{1,3}(?: \d{3})+|\d+)(?:([.,])(\d+))?\s*(k|m|b|к|м|в|тыс\.?|млн|млрд)?(?:\s+(?:tokens?|токен(?:ов|а|ы)?))?$/i;
  const excluded = 'input,textarea,select,option,button,script,style,noscript,template,svg,canvas,iframe,[contenteditable]:not([contenteditable="false"])';
  let picking = false, selected = null, feedback = null, outlined = null, previousOutline = null, nextId = 0;
  const candidateIds = new WeakMap();

  function visible(el) {
    if (!el || !el.isConnected || el.closest(excluded)) return false;
    for (let p = el; p; p = p.parentElement) {
      if (p.hidden || p.hasAttribute('inert') || p.getAttribute('aria-hidden') === 'true') return false;
      const s = getComputedStyle(p);
      if (s.display === 'none' || /^(hidden|collapse)$/.test(s.visibility) || s.opacity === '0') return false;
    }
    // No geometry dependency: this also works before the first WebKit layout pass.
    return true;
  }
  function ownText(el) {
    return normalize(Array.from(el.childNodes).filter(n => n.nodeType === 3).map(n => n.textContent).join(' '));
  }
  function parse(text) {
    let s = normalize(text);
    if (!s || s.length > 160 || forbidden.test(s)) return null;
    // A single inline label/count is supported, but arbitrary prose never is.
    const inline = s.match(/^(.+?[:：]\s*|(?:remaining tokens?|available tokens?|tokens? remaining|tokens? available|осталось токенов|остаток токенов|доступно токенов)\s+)(\d.*)$/i);
    if (inline && positive.test(inline[1].trim())) s = inline[2];
    const m = s.match(numeric);
    if (!m) return null;
    const u = (m[4] || '').toLowerCase();
    // A bare 1,234 / 1.234 has incompatible locale interpretations. Ask for a
    // clearer representation instead of silently displaying the wrong balance.
    if (!u && m[3] && m[3].length === 3 && !m[1].includes(' ')) return null;
    const multiplier = /^(b|в|млрд)$/.test(u) ? 1e9 : /^(m|м|млн)$/.test(u) ? 1e6 : /^(k|к|тыс\.?)$/.test(u) ? 1e3 : 1;
    const value = Number(m[1].replace(/ /g, '') + (m[3] ? '.' + m[3] : '')) * multiplier;
    return Number.isFinite(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER ? value : null;
  }
  function labelText(el) {
    const text = ownText(el);
    if (positive.test(text)) return text;
    if (parse(text) !== null) {
      const prefix = text.replace(/\d.*$/, '').trim();
      if (positive.test(prefix)) return prefix;
    }
    return text;
  }
  function boundedElements(root, limit) {
    const out = [], walker = document.createTreeWalker(root, 1);
    if (root.nodeType === 1) out.push(root);
    while (walker.nextNode()) {
      if (out.length >= limit) return null;
      out.push(walker.currentNode);
    }
    return out;
  }
  function unique(selector) {
    try {
      const matches = document.querySelectorAll(selector);
      return matches.length === 1 ? matches[0] : null;
    } catch (_) { return null; }
  }
  function quote(s) {
    return '"' + String(s).replace(/[\\"\n\r\f]/g, c => '\\' + c.charCodeAt(0).toString(16) + ' ') + '"';
  }
  function selector(el) {
    // Prefer identity attributes, never text or numerical content.
    for (const attr of ['id', 'data-testid', 'data-test', 'data-qa', 'data-key', 'aria-labelledby']) {
      const v = el.getAttribute(attr);
      if (v && v.length <= 256) {
        const s = el.localName + '[' + attr + '=' + quote(v) + ']';
        if (unique(s) === el) return s;
      }
    }
    const parts = [];
    for (let p = el; p && parts.length < 16; p = p.parentElement) {
      let index = 1;
      for (let s = p.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === p.localName) index++;
      parts.unshift(p.localName + ':nth-of-type(' + index + ')');
      const s = parts.join(' > ');
      if (unique(s) === el) return s;
    }
    return null;
  }
  function path(root, el) {
    const out = [];
    for (let p = el; p !== root; p = p.parentElement) {
      if (!p || !p.parentElement) return null;
      out.unshift(Array.prototype.indexOf.call(p.parentElement.children, p));
    }
    return out;
  }
  function numberNode(el) {
    return visible(el) && parse(el.textContent) !== null &&
      !Array.from(el.children).some(child => visible(child) && parse(child.textContent) !== null);
  }
  function fingerprint(context, value, label, version = 1) {
    const nodes = boundedElements(context, MAX_CONTEXT);
    if (!nodes || context.textContent.length > MAX_TEXT) return null;
    // Preserve static text, order, identity and relative layout. Mask *only* strict
    // numeric counters so changing 1K to 2M does not invalidate a confirmed rule.
    function snapshot(el) {
      if (!visible(el)) return null;
      const attrs = ['id', 'data-testid', 'data-test', 'data-qa', 'data-key', 'aria-label', 'aria-labelledby', 'role']
        .filter(a => el.hasAttribute(a)).map(a => [a, el.getAttribute(a)]);
      if (version === 2 && el === value) {
        function shape(node) {
          return [node.localName, Array.from(node.children).map(shape)];
        }
        return [el.localName, attrs, '#selected-number', shape(el)];
      }
      const content = [];
      for (const n of el.childNodes) {
        if (n.nodeType === 1) { const child = snapshot(n); if (child) content.push(child); }
        else if (n.nodeType === 3) {
          const text = normalize(n.textContent);
          if (text) {
            if (parse(text) !== null) {
              const prefix = text.replace(/\d.*$/, '').trim();
              content.push(positive.test(prefix) ? prefix + ' #number' : '#number');
            } else if (version === 2 && /^\d+(?:[.,]\d+)?\s*%(?:\s+(?:осталось|remaining|left|used|использовано))?$/.test(text)) content.push(text.replace(/^\d+(?:[.,]\d+)?/, '#percentage'));
            else content.push(text);
          }
        }
      }
      return [el.localName, attrs, content];
    }
    return JSON.stringify([version, path(context, value), label ? path(context, label) : null, label ? labelText(label) : '', snapshot(context)]);
  }
  function cleanPresentation(context, value, label) {
    // Do not mistake one numeric child of “-12”, “12 / 20”, or “12M”
    // for a complete standalone counter. Only the bound label and value may
    // contribute visible text. This deliberately rejects richer/unclear cards.
    const nodes = boundedElements(context, MAX_CONTEXT);
    if (!nodes) return false;
    for (let p = value.parentElement; p && context.contains(p); p = p.parentElement) {
      const composite = parse(p.textContent);
      if (composite !== null && composite !== parse(value.textContent)) return false;
    }
    for (const el of nodes) {
      if (!visible(el) || value.contains(el)) continue;
      if (el === label && el !== value) continue;
      if (ownText(el)) return false;
    }
    return true;
  }
  function chooseContext(value, automatic) {
    let unlabeled = null;
    // Small local groups only; do not interpret an entire dashboard as one card.
    for (let c = value, depth = 0; c && c !== document.body && depth < 5; c = c.parentElement, depth++) {
      const nodes = boundedElements(c, MAX_CONTEXT);
      if (!nodes || c.textContent.length > MAX_TEXT) break;
      const counts = nodes.filter(numberNode);
      if (counts.length !== 1 || counts[0] !== value) continue;
      const labels = nodes.filter(el => visible(el) && /[a-zа-яё]/i.test(labelText(el)) && parse(el.textContent) === null && ownText(el) && !/\d/.test(labelText(el)));
      // For inline label/value leaves labelText gives the static known prefix.
      if (positive.test(labelText(value))) labels.unshift(value);
      const recognized = labels.filter(el => positive.test(labelText(el)));
      if (recognized.length === 1 && !forbidden.test(c.textContent)) return { context: c, label: recognized[0] };
      if (!automatic && labels.length === 1 && !forbidden.test(c.textContent)) return { context: c, label: labels[0] };
      // Defer a no-label fallback: a containing card may have a useful label.
      // Without any stable identity an unlabeled positional rule could silently
      // bind to a different counter after a dashboard reorder, so refuse it.
      if (!automatic && depth > 0 && !unlabeled && labels.length === 0 && normalize(c.textContent) === normalize(value.textContent) &&
          [value, c].some(el => ['id', 'data-testid', 'data-test', 'data-qa', 'data-key'].some(a => el.getAttribute(a)))) {
        unlabeled = { context: c, label: null };
      }
    }
    return automatic ? null : unlabeled;
  }
  function manualContext(value) {
    const simple = chooseContext(value, false);
    if (simple && simple.label && cleanPresentation(simple.context, value, simple.label)) return simple;
    // Real dashboards group the balance with percentages, charts and other metrics.
    // Bind the clicked value to its nearest preceding static label, rather than
    // requiring its whole card to contain exactly one number and nothing else.
    for (let c = value.parentElement, depth = 0; c && c !== document.body && depth < 7; c = c.parentElement, depth++) {
      const nodes = boundedElements(c, MAX_CONTEXT);
      if (!nodes || c.textContent.length > MAX_TEXT) break;
      const labels = nodes.filter(el => visible(el) && el !== value && !el.contains(value) &&
        ownText(el) && /[a-zа-яё]/i.test(labelText(el)) && !/\d/.test(labelText(el)) &&
        parse(el.textContent) === null && (el.compareDocumentPosition(value) & 4));
      if (!labels.length) continue;
      const label = labels[labels.length - 1];
      if (forbidden.test(labelText(label))) return null;
      // Reject a numeric fragment of a decorated amount ("$<span>12</span>",
      // "<span>12</span>%", "12 / 20"), even when it has a distant good label.
      for (let p = value.parentElement; p && p !== c; p = p.parentElement) {
        const text = normalize(p.textContent);
        if (forbidden.test(text) || /[\/−]/.test(text) || /^\s*[-+]/.test(text)) return null;
        const amount = parse(text);
        if (amount !== null && amount !== parse(value.textContent)) return null;
      }
      // Direct siblings decorating this value must not change its numeric meaning.
      for (const sibling of [value.previousSibling, value.nextSibling]) {
        const text = normalize(sibling ? sibling.textContent : '');
        if (text && /^(?:[%$€£₽+−-]|\/\s*\d|(?:usd|eur|руб|credits?)\b)/i.test(text)) return null;
        if (/^(?:[kmbкмв]|тыс\.?|млн|млрд)$/i.test(text)) return null;
      }
      return { context: c, label, rich: true };
    }
    return simple && cleanPresentation(simple.context, value, simple.label) ? simple : null;
  }
  function candidate(value, automatic) {
    if (!numberNode(value)) return null;
    const binding = automatic ? chooseContext(value, true) : manualContext(value);
    if (!binding || (!binding.rich && !cleanPresentation(binding.context, value, binding.label))) return null;
    const s = selector(value), cs = selector(binding.context), ls = binding.label ? selector(binding.label) : '';
    const anchor = fingerprint(binding.context, value, binding.label, binding.rich ? 2 : 1);
    if (!s || !cs || (binding.label && !ls) || !anchor) return null;
    const rule = { version: 1, selector: s, contextSelector: cs, labelSelector: ls, anchor };
    if (!candidateIds.has(value)) candidateIds.set(value, 'btp-' + (++nextId));
    return { id: candidateIds.get(value), label: automatic ? generic : manual, display: normalize(value.textContent).replace(/^.*?[:：]\s*/, '').slice(0, 160), value: parse(value.textContent), rule };
  }
  function resolve(rule) {
    if (!rule || typeof rule !== 'object' || rule.version !== 1 ||
        !['selector', 'contextSelector', 'labelSelector', 'anchor'].every(k => typeof rule[k] === 'string') ||
        !rule.selector || !rule.contextSelector || !rule.anchor || rule.anchor.length > 30000) return null;
    const value = unique(rule.selector), context = unique(rule.contextSelector), label = rule.labelSelector ? unique(rule.labelSelector) : null;
    if (!value || !context || !visible(context) || !numberNode(value) || !context.contains(value) ||
        (rule.labelSelector && (!label || !visible(label) || !context.contains(label)))) return null;
    let marker;
    try { marker = JSON.parse(rule.anchor)[0]; } catch (_) { return null; }
    if (marker !== 1 && marker !== 2) return null;
    if (fingerprint(context, value, label, marker) !== rule.anchor) return null;
    const nodes = boundedElements(context, MAX_CONTEXT);
    if (!nodes || (marker === 1 && nodes.filter(numberNode).length !== 1)) return null;
    if (marker === 2) {
      const bound = manualContext(value);
      if (!bound || bound.context !== context || bound.label !== label) return null;
    }
    return value;
  }
  function clearHighlight() {
    if (outlined) {
      for (const [name, entry] of Object.entries(previousOutline)) {
        if (entry.value) outlined.style.setProperty(name, entry.value, entry.priority);
        else outlined.style.removeProperty(name);
      }
    }
    outlined = previousOutline = null;
  }
  function highlight(rule) {
    clearHighlight();
    const el = resolve(rule);
    if (!el) return false;
    outlined = el;
    previousOutline = {};
    for (const name of ['outline', 'outline-offset']) previousOutline[name] = { value: el.style.getPropertyValue(name), priority: el.style.getPropertyPriority(name) };
    el.style.setProperty('outline', '3px solid #1677ff', 'important');
    el.style.setProperty('outline-offset', '3px', 'important');
    if (typeof el.scrollIntoView === 'function') el.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'auto' });
    return true;
  }
  function pickElement(target) {
    selected = null;
    let el = target && (target.nodeType === 1 ? target : target.parentElement);
    const original = el;
    for (let depth = 0; el && el !== document.body && depth < 7; el = el.parentElement, depth++) {
      let value = numberNode(el) ? el : null;
      if (!value && el === original) {
        const nodes = boundedElements(el, MAX_CONTEXT);
        const values = nodes ? nodes.filter(numberNode) : [];
        if (values.length === 1) value = values[0];
      }
      if (value) {
        selected = candidate(value, false);
        if (selected) {
          highlight(selected.rule);
          return feedback = { candidate: selected, reason: '' };
        }
      }
    }
    clearHighlight();
    const reason = original && original.closest('iframe,canvas') ? 'unsupported' :
      original && parse(original.textContent) !== null ? 'context' : 'number';
    return feedback = { candidate: null, reason };
  }
  function intercept(event) {
    if (!picking) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    // A canceled pointer/mousedown can suppress the synthetic click in WebKit.
    // Handle release events as well; native macOS picking also bypasses this path.
    if (event.type === 'click' || event.type === 'pointerup' || event.type === 'mouseup') pickElement(event.target);
  }
  const events = ['click', 'auxclick', 'dblclick', 'pointerdown', 'pointerup', 'mousedown', 'mouseup', 'touchstart', 'touchend'];
  let attached = false;
  function attach() {
    if (attached) return;
    attached = true;
    // Registered at document start by WebKit, before ordinary page listeners.
    for (const event of events) window.addEventListener(event, intercept, { capture: true, passive: false });
  }
  attach();
  function enablePicker(enabled) {
    enabled = enabled === true;
    if (picking === enabled) return picking;
    picking = enabled;
    selected = null;
    feedback = null;
    if (enabled) attach();
    if (!enabled) clearHighlight();
    return picking;
  }
  globalThis.BTPDetector = Object.freeze({
    scan() {
      const nodes = document.body ? boundedElements(document.body, MAX_NODES) : [];
      if (!nodes) return [];
      const out = [];
      for (const el of nodes) { const found = candidate(el, true); if (found) out.push(found); if (out.length >= 40) break; }
      return out;
    },
    read(rule) { const el = resolve(rule); return el ? { remaining: parse(el.textContent), spent: null, total: null } : null; },
    highlight,
    enablePicker,
    takeSelection() { const result = selected; selected = null; return result; },
    takePickerEvent() { const result = feedback; feedback = null; return result; },
    pickAtPoint(x, y) {
      if (!picking || !Number.isFinite(x) || !Number.isFinite(y) || x < 0 || x > 1 || y < 0 || y > 1) return { candidate: null, reason: 'inactive' };
      return pickElement(document.elementFromPoint(x * innerWidth, y * innerHeight));
    },
    stop() {
      enablePicker(false); selected = null; clearHighlight();
      for (const event of events) window.removeEventListener(event, intercept, true);
      attached = false;
    }
  });
})();
