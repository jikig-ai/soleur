// p5-revoke.js — #12931 Phase 5 token slice: ONE Cloudflare token revoke, run in the operator's signed-in
// dashboard session (runbook cloudflare-old-login-token-remint.md section 7 step 3; the migration runbook's
// "Revoke recipe" step 3; CTO rulings F21 and D1). Nothing is edited into this file: its sha256 is pinned in
// p5-browser.sha256, and every per-revoke value arrives in the single JSON argument object below.
//
// SHAPE. This file is ONE function expression `(args) => async (page) => {...}` with no trailing semicolon.
// Compose the run file (sha check first), then pass it to Playwright MCP `browser_run_code_unsafe`:
//   { printf '('; cat p5-revoke.js; printf ')(%s)\n' '<ARGS-JSON>'; } > <run-file>
// The tool echoes the code it ran, so ARGS carries only 8-hex prefixes, a name and an account id.
//
// ARGS:
//   pin         8-hex pinned old id prefix (the runbook's section 2 table)
//   old_id      8-hex `old_id` from this sitting's `SOLEUR_P5_REVOKE_READY` line
//   new_id      8-hex `new_id` from the same line (the replacement token)
//   new_name    the replacement token's name, /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/
//   scope       "user"    -> list GET /user/tokens, DELETE /user/tokens/<id> (the old-login user tokens)
//               "account" -> list GET /accounts/<account_id>/tokens, DELETE /accounts/<account_id>/tokens/<id>
//                            (a later rotation revoking an account-owned `_PREV` token; runbook section 7 tail)
//   account_id  32-hex account id; required with scope "account", refused with scope "user"
//
// GUARD (three literals, checked before any request): refuse unless pin == old_id and old_id != new_id. After
// the list: exactly one token whose id starts with old_id, else {matches:<n>}; refuse when that token's name
// equals new_name (case- and space-insensitive) -- the token about to die must never be the replacement.
//
// FLOW. goto https://dash.cloudflare.com/profile/api-tokens first (a page not reloaded since sign-in listed 0
// tokens on 2026-11-26); in-page list (window.bootstrap.atok as `x-atok`, plus `x-cross-site-security: dash`,
// the headers of the 2026-11-26 deletes that returned 200, #12931 comment 7203873359); Node-side
// page.request.delete (an in-page fetch DELETE got an HTML 403 from the dashboard edge, measured 2026-11-26).
// Only 200 with success:true is a revoke; the read-back is the recipe's step 4, outside this body.
//
// ENDPOINTS (dash.cloudflare.com/api/v4 proxies the public v4 API with the session):
//   GET    /user/tokens?page=&per_page=                 developers.cloudflare.com/api/resources/user/subresources/tokens/methods/list/
//   DELETE /user/tokens/{token_id}                      cloudflare-account-migration.md "Revoke recipe" step 3 (2026-11-26 200s)
//   GET    /accounts/{account_id}/tokens?page=&per_page= developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/list/
//   DELETE /accounts/{account_id}/tokens/{token_id}     developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/delete/
//
// RETURN. Only these keys ever appear: atok, matches, refused, status, contentType, success, error.
//   {atok:false}                       the page is signed out
//   {refused:<reason>}                 args:<field>, pin, same-id, name, origin; nothing deleted
//   {matches:<n>}                      n != 1 tokens carry the old_id prefix (0: this login does not own it --
//                                      ask the operator to sign in as the owner); nothing deleted
//   {status, contentType, success}     the list failed (success:false, nothing deleted) or the DELETE answered
//   {error:<e.name>}                   a thrown error (e.message may carry the request; never returned)
// Never returned or logged: the atok, a full token id, a token value, e.message. A final guard drops any
// return that breaks this allowlist to {error:"ShapeError"}.
(args) => async (page) => {
  const DASH = 'https://dash.cloudflare.com';
  const HEX8 = /^[0-9a-f]{8}$/;
  const HEX32 = /^[0-9a-f]{32}$/;
  const KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error'];
  const REFUSALS = ['args:object', 'args:pin', 'args:old_id', 'args:new_id', 'args:new_name', 'args:scope',
    'args:account_id', 'pin', 'same-id', 'name', 'origin'];

  const safe = (r) => {
    if (!r || typeof r !== 'object') return { error: 'ShapeError' };
    for (const k of Object.keys(r)) {
      const v = r[k];
      const ok = (k === 'atok' && v === false)
        || (k === 'matches' && Number.isInteger(v) && v >= 0 && v < 100000)
        || (k === 'refused' && REFUSALS.includes(v))
        || (k === 'status' && Number.isInteger(v) && v >= 0 && v < 1000)
        || (k === 'contentType' && typeof v === 'string' && /^[a-z0-9.+\/-]{0,64}$/.test(v))
        || (k === 'success' && typeof v === 'boolean')
        || (k === 'error' && typeof v === 'string' && /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(v));
      if (!KEYS.includes(k) || !ok) return { error: 'ShapeError' };
    }
    return r;
  };
  const ctOf = (raw) => {
    const t = String(raw || '').toLowerCase().split(';')[0].trim();
    if (t === '') return '';
    return /^[a-z0-9.+-]{1,30}\/[a-z0-9.+-]{1,33}$/.test(t) ? t : 'other';
  };
  const errName = (e) => {
    const n = e && typeof e.name === 'string' ? e.name : '';
    return /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(n) ? n : 'Error';
  };
  const norm = (s) => String(s).trim().replace(/\s+/g, ' ').toLowerCase();

  // ---- arguments and the three-literal guard (before any request) ----------------------------------------
  const a = args;
  if (!a || typeof a !== 'object' || Array.isArray(a)) return safe({ refused: 'args:object' });
  if (typeof a.pin !== 'string' || !HEX8.test(a.pin)) return safe({ refused: 'args:pin' });
  if (typeof a.old_id !== 'string' || !HEX8.test(a.old_id)) return safe({ refused: 'args:old_id' });
  if (typeof a.new_id !== 'string' || !HEX8.test(a.new_id)) return safe({ refused: 'args:new_id' });
  if (typeof a.new_name !== 'string' || !/^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/.test(a.new_name)) {
    return safe({ refused: 'args:new_name' });
  }
  if (a.scope !== 'user' && a.scope !== 'account') return safe({ refused: 'args:scope' });
  if (a.scope === 'account' ? (typeof a.account_id !== 'string' || !HEX32.test(a.account_id))
    : a.account_id !== undefined) {
    return safe({ refused: 'args:account_id' });
  }
  if (a.pin !== a.old_id) return safe({ refused: 'pin' });
  if (a.old_id === a.new_id) return safe({ refused: 'same-id' });
  const base = a.scope === 'account' ? `/api/v4/accounts/${a.account_id}/tokens` : '/api/v4/user/tokens';

  // Runs IN THE PAGE (serialized by page.evaluate: it may use no Node-side variable). Lists every page of
  // `base` and returns {origin:false}, {atok:false}, {fail:{status, contentType}} or {atok, hits:[{id,name}]}
  // with only the tokens whose id starts with `prefix`. The atok and full ids go to Node-local variables only.
  const listInPage = async ({ base: b, prefix }) => {
    if (location.origin !== 'https://dash.cloudflare.com') return { origin: false };
    const atok = window.bootstrap && window.bootstrap.atok;
    if (!atok) return { atok: false };
    const hits = [];
    let seen = 0;
    for (let n = 1; n <= 20; n += 1) {
      const r = await fetch(`${b}?page=${n}&per_page=50`, {
        method: 'GET', credentials: 'same-origin', headers: { 'x-atok': atok, 'x-cross-site-security': 'dash' },
      });
      const contentType = r.headers.get('content-type') || '';
      let j = null;
      if (/json/i.test(contentType)) { try { j = await r.json(); } catch (e) { j = null; } }
      if (r.status !== 200 || !j || j.success !== true || !Array.isArray(j.result)) {
        return { fail: { status: r.status, contentType } };
      }
      for (const t of j.result) {
        if (t && typeof t.id === 'string' && t.id.startsWith(prefix)) hits.push({ id: t.id, name: t.name });
      }
      seen += j.result.length;
      const total = j.result_info && Number.isInteger(j.result_info.total_count) ? j.result_info.total_count : seen;
      if (j.result.length === 0 || seen >= total) break;
    }
    return { atok, hits };
  };

  try {
    await page.goto(`${DASH}/profile/api-tokens`, { waitUntil: 'domcontentloaded' });
    const l = await page.evaluate(listInPage, { base, prefix: a.old_id });
    if (l.origin === false) return safe({ refused: 'origin' });
    if (l.atok === false) return safe({ atok: false });
    if (l.fail) return safe({ status: l.fail.status, contentType: ctOf(l.fail.contentType), success: false });
    if (!Array.isArray(l.hits) || l.hits.length !== 1) return safe({ matches: Array.isArray(l.hits) ? l.hits.length : 0 });
    const target = l.hits[0];
    if (typeof target.id !== 'string' || !HEX32.test(target.id) || !target.id.startsWith(a.old_id)) {
      return safe({ matches: 0 });
    }
    if (target.id.startsWith(a.new_id)) return safe({ refused: 'same-id' });
    if (typeof target.name === 'string' && norm(target.name) === norm(a.new_name)) return safe({ refused: 'name' });

    const r = await page.request.delete(`${DASH}${base}/${target.id}`, {
      headers: { 'x-atok': l.atok, 'x-cross-site-security': 'dash' },
    });
    const contentType = ctOf(r.headers()['content-type']);
    let success = false;
    if (/json/.test(contentType)) { try { const j = await r.json(); success = !!j && j.success === true; } catch (e) { success = false; } }
    return safe({ status: r.status(), contentType, success });
  } catch (e) {
    return safe({ error: errName(e) });
  }
}
