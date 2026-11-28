// p5-revoke.js — #12931 Phase 5 token slice: ONE Cloudflare token delete, run in the operator's signed-in
// dashboard session (runbook cloudflare-old-login-token-remint.md section 7 step 3; the migration runbook's
// "Revoke recipe" step 3; CTO rulings F21, D1, D8, D9). Nothing is edited into this file: its sha256 is pinned
// in p5-browser.sha256, and every per-run value arrives in the single JSON argument object below.
//
// SHAPE. This file is ONE function expression `(args) => async (page) => {...}` with no trailing semicolon. The
// run file is `(<this file>)(JSON.parse(<string>))`, where <string> is the argument object re-encoded as ONE JSON
// string literal (`jq -c . | jq -Rs .`, after `jq -e 'type=="object"'` passes; CTO D9), so the argument is data
// and never JavaScript. Compose it with the runbook's section 5 line (sha check first), then pass it to
// Playwright MCP `browser_run_code_unsafe`. The tool echoes the code it ran, so ARGS carries only 8-hex
// prefixes, a name and an account id.
//
// MODES. `mode` absent (or "revoke"): revoke an OLD token after its replacement is live. `mode` "retire" (D8):
// delete a BAD new token (one that failed after the mint) by its id8 and exact name.
//
// ARGS, mode revoke (any missing, malformed or unknown field refuses before any request):
//   pin         required: 8-hex pinned old id prefix (the runbook's section 2 table)
//   old_id      required: 8-hex `old_id` from this sitting's `SOLEUR_P5_REVOKE_READY` line
//   new_id      required: 8-hex `new_id` from the same line (the replacement token)
//   new_name    required: the replacement token's name, /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/
//   scope       required: "user"    -> list GET /user/tokens, DELETE /user/tokens/<id> (the old-login tokens)
//                         "account" -> list GET /accounts/<account_id>/tokens, DELETE .../tokens/<id> (a later
//                                      rotation revoking an account-owned `_PREV` token; runbook section 7 tail)
//   account_id  required with scope "account" (32-hex); must be absent with scope "user"
// ARGS, mode retire:
//   mode        required: "retire"
//   pin         required: 8-hex id prefix of the bad NEW token (its id8); never one of the committed old pins
//   retire_name required: that token's exact name, /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/
//   scope       required: "user" | "account", as above
//   account_id  as above
//   (old_id, new_id, new_name must be absent in retire mode.)
//
// GUARDS. Before any request, revoke: pin == old_id; old_id != new_id; scope user: old_id is one of the
// committed old pins 86aa993e, dd6d1427, 5993721f (anything else is refused). Retire: pin is NOT one of those
// pins. After the list (one in-page pass over every page, collecting the old_id hits and the new_id hits):
// exactly one token whose id starts with pin, else {matches:<n>}. Revoke: refuse when that token's name equals
// new_name (case- and space-insensitive); scope user: refuse a target whose name ends `-soleur-<8 digits>` (a
// replacement-shaped name never dies here); scope account: require exactly one listed token whose id starts
// with new_id and whose normalised name equals new_name (the replacement is live in this list). Retire: refuse
// unless the target's name equals retire_name exactly, and any target whose id starts with an old pin.
//
// FLOW. goto https://dash.cloudflare.com/profile/api-tokens first (a page not reloaded since sign-in listed 0
// tokens on 2026-11-26), then wait up to 15 s for window.bootstrap.atok, which the dashboard sets after
// DOMContentLoaded (measured 2026-11-28); in-page list of every page (a page shorter than per_page ends it unless
// result_info.total_count says more; 20 pages without an end refuses `listing`), with window.bootstrap.atok as
// `x-atok` plus `x-cross-site-security: dash`, the headers of the 2026-11-26 deletes that returned 200 (#12931
// comment 7203873359); Node-side page.request.delete (an in-page fetch DELETE got an HTML 403 from the
// dashboard edge, measured 2026-11-26). Only 200 with success:true is a delete; the read-back is the recipe's
// step 4, outside this body.
//
// ENDPOINTS (dash.cloudflare.com/api/v4 proxies the public v4 API with the session):
//   GET    /user/tokens?page=&per_page=                 developers.cloudflare.com/api/resources/user/subresources/tokens/methods/list/
//   DELETE /user/tokens/{token_id}                      cloudflare-account-migration.md "Revoke recipe" step 3 (2026-11-26 200s)
//   GET    /accounts/{account_id}/tokens?page=&per_page= developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/list/
//   DELETE /accounts/{account_id}/tokens/{token_id}     developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/delete/
//
// RETURN. Only these keys ever appear: atok, matches, refused, status, contentType, success, error.
//   {atok:false}                       the page is signed out; nothing deleted
//   {refused:<reason>}                 nothing deleted. Before any request: args:<field> (object, unknown, or the
//                                      field's name), pin, same-id, unpinned, old-pin. After the list: origin,
//                                      listing, name, soleur-name, new-token, retire-name, old-pin.
//   {matches:<n>}                      n != 1 tokens carry the pin prefix (0: this login does not own it -- ask
//                                      the operator to sign in as the owner); nothing deleted
//   {status, contentType, success}     the list failed (success:false, nothing deleted) or the DELETE answered
//                                      (success:true only for 200 + JSON success:true; false: it MAY still exist)
//   {error:<e.name>}                   a thrown error (e.message may carry the request; never returned); a
//                                      DELETE may have been sent if the throw came after the list
// Never returned or logged: the atok, a full token id, a token value, e.message. A final guard drops any
// return that breaks this allowlist to {error:"ShapeError"}.
(args) => async (page) => {
  const DASH = 'https://dash.cloudflare.com';
  const HEX8 = /^[0-9a-f]{8}$/;
  const HEX32 = /^[0-9a-f]{32}$/;
  const NAME_RE = /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/;
  const OLD_PINS = ['86aa993e', 'dd6d1427', '5993721f'];
  const KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error'];
  const ARG_KEYS = ['mode', 'pin', 'old_id', 'new_id', 'new_name', 'retire_name', 'scope', 'account_id'];
  const REFUSALS = ['args:object', 'args:unknown', ...ARG_KEYS.map((k) => `args:${k}`), 'pin', 'same-id',
    'unpinned', 'old-pin', 'origin', 'listing', 'name', 'soleur-name', 'new-token', 'retire-name'];

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
  const isOld = (id) => OLD_PINS.some((p) => id.startsWith(p));

  // ---- arguments and the literal guards (before any request) ---------------------------------------------
  const a = args;
  if (!a || typeof a !== 'object' || Array.isArray(a)) return safe({ refused: 'args:object' });
  if (Object.keys(a).some((k) => !ARG_KEYS.includes(k))) return safe({ refused: 'args:unknown' });
  if (a.mode !== undefined && a.mode !== 'revoke' && a.mode !== 'retire') return safe({ refused: 'args:mode' });
  const retire = a.mode === 'retire';
  if (typeof a.pin !== 'string' || !HEX8.test(a.pin)) return safe({ refused: 'args:pin' });
  if (retire) {
    for (const k of ['old_id', 'new_id', 'new_name']) if (a[k] !== undefined) return safe({ refused: `args:${k}` });
    if (typeof a.retire_name !== 'string' || !NAME_RE.test(a.retire_name)) return safe({ refused: 'args:retire_name' });
  } else {
    if (typeof a.old_id !== 'string' || !HEX8.test(a.old_id)) return safe({ refused: 'args:old_id' });
    if (typeof a.new_id !== 'string' || !HEX8.test(a.new_id)) return safe({ refused: 'args:new_id' });
    if (typeof a.new_name !== 'string' || !NAME_RE.test(a.new_name)) return safe({ refused: 'args:new_name' });
    if (a.retire_name !== undefined) return safe({ refused: 'args:retire_name' });
  }
  if (a.scope !== 'user' && a.scope !== 'account') return safe({ refused: 'args:scope' });
  if (a.scope === 'account' ? (typeof a.account_id !== 'string' || !HEX32.test(a.account_id))
    : a.account_id !== undefined) {
    return safe({ refused: 'args:account_id' });
  }
  if (retire) {
    if (isOld(a.pin)) return safe({ refused: 'old-pin' });
  } else {
    if (a.pin !== a.old_id) return safe({ refused: 'pin' });
    if (a.old_id === a.new_id) return safe({ refused: 'same-id' });
    if (a.scope === 'user' && !OLD_PINS.includes(a.old_id)) return safe({ refused: 'unpinned' });
  }
  const base = a.scope === 'account' ? `/api/v4/accounts/${a.account_id}/tokens` : '/api/v4/user/tokens';

  // Runs IN THE PAGE (serialized by page.evaluate: it may use no Node-side variable). Lists every page of
  // `base` and returns {origin:false}, {atok:false}, {fail:{status, contentType}}, {capped:true} or
  // {atok, hits:[{id,name}], newHits:[{id,name}]} with only the tokens whose id starts with `prefix` (hits) or
  // `newPrefix` (newHits). The atok and full ids go to Node-local variables only.
  const listInPage = async ({ base: b, prefix, newPrefix, per: PER, pages }) => {
    if (location.origin !== 'https://dash.cloudflare.com') return { origin: false };
    const atok = window.bootstrap && window.bootstrap.atok;
    if (!atok) return { atok: false };
    const hits = [];
    const newHits = [];
    let seen = 0;
    for (let n = 1; n <= pages; n += 1) {
      const r = await fetch(`${b}?page=${n}&per_page=${PER}`, {
        method: 'GET', credentials: 'same-origin', headers: { 'x-atok': atok, 'x-cross-site-security': 'dash' },
      });
      const contentType = r.headers.get('content-type') || '';
      let j = null;
      if (/json/i.test(contentType)) { try { j = await r.json(); } catch (e) { j = null; } }
      if (r.status !== 200 || !j || j.success !== true || !Array.isArray(j.result)) {
        return { fail: { status: r.status, contentType } };
      }
      for (const t of j.result) {
        if (!t || typeof t.id !== 'string') continue;
        if (t.id.startsWith(prefix)) hits.push({ id: t.id, name: t.name });
        if (newPrefix && t.id.startsWith(newPrefix)) newHits.push({ id: t.id, name: t.name });
      }
      seen += j.result.length;
      const ri = j.result_info || {};
      const per = Number.isInteger(ri.per_page) && ri.per_page > 0 && ri.per_page <= PER ? ri.per_page : PER;
      const more = Number.isInteger(ri.total_count) && seen < ri.total_count;
      if (j.result.length < per && !more) return { atok, hits, newHits };
    }
    return { capped: true };
  };

  try {
    await page.goto(`${DASH}/profile/api-tokens`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});
    const l = await page.evaluate(listInPage, {
      base, prefix: a.pin, newPrefix: retire ? null : a.new_id, per: 50, pages: 20,
    });
    if (l.origin === false) return safe({ refused: 'origin' });
    if (l.atok === false) return safe({ atok: false });
    if (l.fail) return safe({ status: l.fail.status, contentType: ctOf(l.fail.contentType), success: false });
    if (l.capped) return safe({ refused: 'listing' });
    if (!Array.isArray(l.hits) || l.hits.length !== 1) return safe({ matches: Array.isArray(l.hits) ? l.hits.length : 0 });
    const target = l.hits[0];
    if (typeof target.id !== 'string' || !HEX32.test(target.id) || !target.id.startsWith(a.pin)) {
      return safe({ matches: 0 });
    }
    if (retire) {
      if (target.name !== a.retire_name) return safe({ refused: 'retire-name' });
      if (isOld(target.id)) return safe({ refused: 'old-pin' });
    } else {
      if (typeof target.name === 'string' && norm(target.name) === norm(a.new_name)) return safe({ refused: 'name' });
      if (a.scope === 'user' && /-soleur-\d{8}$/.test(norm(target.name))) return safe({ refused: 'soleur-name' });
      if (a.scope === 'account') {
        const live = Array.isArray(l.newHits) ? l.newHits : [];
        if (live.length !== 1 || typeof live[0].name !== 'string' || norm(live[0].name) !== norm(a.new_name)) {
          return safe({ refused: 'new-token' });
        }
      }
    }

    const r = await page.request.delete(`${DASH}${base}/${target.id}`, {
      headers: { 'x-atok': l.atok, 'x-cross-site-security': 'dash' },
    });
    const contentType = ctOf(r.headers()['content-type']);
    let success = false;
    if (/json/.test(contentType)) {
      try { const j = await r.json(); success = r.status() === 200 && !!j && j.success === true; } catch (e) { success = false; }
    }
    return safe({ status: r.status(), contentType, success });
  } catch (e) {
    return safe({ error: errName(e) });
  }
}
