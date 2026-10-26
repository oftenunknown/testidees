import Foundation

/// JavaScript the checkout agent injects into shop pages. Pure DOM work:
/// find the promo-code box, type a code like a person would (so React/Vue
/// pages notice), press Apply, and read the order total back.
enum CheckoutScripts {
    /// Installed at document end on every page.
    static let bootstrap = #"""
    (function () {
      if (window.__snag) { return; }
      const CODE_HINT = /(promo|coupon|voucher|discount|gift ?card|offer|redeem|reduction)[\s_-]*(code)?/i;
      const APPLY_HINT = /^(apply|redeem|submit|use|add|ok|go|apply code|apply coupon|apply discount)$/i;
      const TOTAL_HINT = /(order total|grand total|estimated total|total to pay|total due|amount due|^total$|basket total|total \(inc)/i;
      const MONEY = /([$£€¥])\s?(\d{1,3}(?:[,\s]\d{3})*|\d+)(?:[.,](\d{2}))?|(\d+(?:[.,]\d{2}))\s?([$£€]|USD|GBP|EUR)/;

      function visible(el) {
        if (!el) return false;
        const r = el.getBoundingClientRect();
        const s = getComputedStyle(el);
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none';
      }
      function label(el) {
        const id = el.id ? document.querySelector('label[for="' + CSS.escape(el.id) + '"]') : null;
        return [el.name, el.id, el.placeholder, el.getAttribute('aria-label'), el.getAttribute('autocomplete'),
                id ? id.textContent : '', el.className].filter(Boolean).join(' ');
      }
      function findCodeInput() {
        const inputs = Array.from(document.querySelectorAll('input[type="text"], input:not([type]), input[type="search"]'));
        return inputs.find(i => visible(i) && CODE_HINT.test(label(i)) && !/email|search|postcode|zip|card ?number/i.test(label(i))) || null;
      }
      function revealCodeInput() {
        // Many checkouts hide the box behind "Have a promo code?"
        const togglers = Array.from(document.querySelectorAll('a, button, summary, [role="button"], span, div'))
          .filter(e => e.children.length < 3 && visible(e) && CODE_HINT.test(e.textContent || '') && (e.textContent || '').length < 60);
        if (togglers[0]) { togglers[0].click(); return true; }
        return false;
      }
      function setValue(input, value) {
        const proto = Object.getPrototypeOf(input);
        const setter = Object.getOwnPropertyDescriptor(proto, 'value') || Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
        input.focus();
        setter.set.call(input, value);
        input.dispatchEvent(new Event('input', { bubbles: true }));
        input.dispatchEvent(new Event('change', { bubbles: true }));
      }
      function findApply(input) {
        const scope = input.closest('form') || input.parentElement?.parentElement?.parentElement || document;
        const buttons = Array.from(scope.querySelectorAll('button, input[type="submit"], input[type="button"], [role="button"]'));
        return buttons.find(b => visible(b) && APPLY_HINT.test((textOf(b) || b.value || '').trim())) || buttons.find(b => visible(b)) || null;
      }
      function parseMoney(text) {
        const m = (text || '').match(MONEY);
        if (!m) return null;
        if (m[2]) { return parseFloat(m[2].replace(/[,\s]/g, '') + '.' + (m[3] || '00')); }
        return parseFloat(m[4].replace(',', '.'));
      }
      function readTotal() {
        const nodes = Array.from(document.querySelectorAll('div, span, p, td, th, dt, dd, li, strong, b'))
          .filter(e => e.children.length <= 4 && visible(e) && TOTAL_HINT.test(textOf(e).trim().split('\n')[0]));
        let best = null;
        for (const n of nodes) {
          let v = parseMoney(textOf(n));
          if (v == null && n.nextElementSibling) { v = parseMoney(textOf(n.nextElementSibling)); }
          if (v == null && n.parentElement) { v = parseMoney(textOf(n.parentElement)); }
          if (v != null) { best = v; }
        }
        return best;
      }
      function wait(ms) { return new Promise(r => setTimeout(r, ms)); }
      function textOf(el) { return el ? (el.innerText || el.textContent || '') : ''; }

      async function tryCodes(codes) {
        let input = findCodeInput();
        if (!input && revealCodeInput()) { await wait(700); input = findCodeInput(); }
        if (!input) { return { found: false }; }
        const before = readTotal();
        const results = [];
        for (const code of codes) {
          input = findCodeInput() || input;
          setValue(input, code);
          const apply = findApply(input);
          if (apply) { apply.click(); } else { input.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true })); }
          await wait(2600);
          const after = readTotal();
          const error = /(invalid|not valid|expired|doesn.t exist|not recognised|not recognized|cannot be applied|isn.t valid)/i.test(textOf(document.body).slice(0, 200000));
          results.push({ code: code, total: after, saving: (before != null && after != null) ? Math.max(0, before - after) : null, error: error });
          window.webkit.messageHandlers.snag.postMessage({ type: 'progress', code: code, total: after, before: before });
        }
        const winner = results.filter(r => r.saving && r.saving > 0.009).sort((a, b) => b.saving - a.saving)[0] || null;
        if (winner && results[results.length - 1].code !== winner.code) {
          input = findCodeInput() || input;
          setValue(input, winner.code);
          const apply = findApply(input);
          if (apply) { apply.click(); }
          await wait(2000);
        }
        return { found: true, before: before, results: results, winner: winner };
      }

      function scanForCodes() {
        // On discount-scheme pages, pick up revealed codes so they can be reused.
        const text = textOf(document.body);
        const near = text.match(/(?:code|voucher|coupon)[^A-Z0-9]{0,40}([A-Z0-9][A-Z0-9-]{4,24})/g) || [];
        const codes = near.map(s => (s.match(/([A-Z0-9][A-Z0-9-]{4,24})$/) || [])[1]).filter(Boolean);
        return Array.from(new Set(codes)).slice(0, 5);
      }

      function fillLogin(user, pass) {
        const pw = Array.from(document.querySelectorAll('input[type="password"]')).find(visible);
        if (!pw) return false;
        const form = pw.closest('form') || document;
        const userField = Array.from(form.querySelectorAll('input[type="email"], input[type="text"], input[autocomplete="username"], input[name*="user" i], input[name*="email" i]')).find(visible);
        if (userField) setValue(userField, user);
        setValue(pw, pass);
        return true;
      }

      document.addEventListener('copy', function () {
        const sel = (window.getSelection() || '').toString().trim();
        if (/^[A-Za-z0-9-]{4,25}$/.test(sel)) { window.webkit.messageHandlers.snag.postMessage({ type: 'copied', code: sel }); }
      });

      window.__snag = { tryCodes, readTotal, findCodeInput: () => !!findCodeInput() || revealCodeInput(), scanForCodes, fillLogin };
      window.webkit.messageHandlers.snag.postMessage({ type: 'ready', hasCodeBox: !!findCodeInput(), total: readTotal() });
    })();
    """#

    static func tryCodes(_ codes: [String]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: codes)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return "return await window.__snag.tryCodes(\(json));"
    }

    static func fillLogin(user: String, password: String) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: [user, password])).flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\",\"\"]"
        return "const a = \(json); return window.__snag.fillLogin(a[0], a[1]);"
    }

    static let probe = "return { hasCodeBox: window.__snag ? window.__snag.findCodeInput() : false, total: window.__snag ? window.__snag.readTotal() : null, codes: window.__snag ? window.__snag.scanForCodes() : [] };"
}
