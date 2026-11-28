// p5-read.js — #12931 Phase 5 token slice: the read-only dashboard reads of the section 4 reconcile (runbook
// cloudflare-old-login-token-remint.md section 4 steps 1-2; CTO rulings D1, D7, D9). It sends only GETs, never a
// write. Nothing is edited into this file: its sha256 is pinned in p5-browser.sha256, and every per-read value
// arrives in the single JSON argument object below.
//
// SHAPE. This file is ONE function expression `(args) => async (page) => {...}` with no trailing semicolon. The
// run file is `(<this file>)(JSON.parse(<string>))`, where <string> is the argument object re-encoded as ONE JSON
// string literal (`jq -c . | jq -Rs .`, after `jq -e 'type=="object"'` passes; CTO D9), so the argument is data
// and never JavaScript. Compose it with the runbook's section 5 line (sha check first), then pass it to
// Playwright MCP `browser_run_code_unsafe`.
//
// ARGS (any missing, malformed or unknown field refuses before any request):
//   {"what":"groups","scope":"account","acct":"<32-hex>"}  GET /accounts/<acct>/tokens/permission_groups
//   {"what":"groups","scope":"user"}                       GET /user/tokens/permission_groups (acct absent)
//   {"what":"policies","scope":"user","pin":"<8-hex>"}     GET /user/tokens (every page), then
//                                                          GET /user/tokens/<id> of the ONE token whose id
//                                                          starts with pin (the signed-in login's own tokens)
//
// FLOW. goto https://dash.cloudflare.com/profile/api-tokens (a fresh window.bootstrap.atok), then wait up to 15 s
// for window.bootstrap.atok, which the dashboard sets after DOMContentLoaded (measured 2026-11-28); in-page GETs with
// `x-atok` and `x-cross-site-security: dash` (the 2026-11-26 headers). The list ends on a page shorter than
// per_page unless result_info.total_count says more; 20 pages without an end refuses `listing`.
//
// RETURN. Only these keys ever appear: atok, refused, status, contentType, success, error, matches, groups,
// policies, skipped.
//   {atok:false}                         the page is signed out
//   {refused:<reason>}                   args:<field> (object, unknown, or the field's name), origin, listing
//   {status, contentType, success:false} a GET answered no usable result
//   {matches:<n>}                        policies: n != 1 listed tokens start with pin
//   {success:true, groups:[{name, scopes:[...], id8}], skipped:<n>}
//                                        every permission group: its name, its scope strings, the 8-hex prefix
//                                        of its id (id8 absent when the id is not 32-hex); skipped = groups
//                                        dropped because a name or scope fell outside the allowlisted alphabet
//   {success:true, policies:[{effect, groups:[<names>], resources:<n>, kinds:[...]}], skipped:<n>}
//                                        per policy: effect ("allow"|"deny"), its permission-group NAMES, the
//                                        COUNT of resource keys, and the sorted distinct KINDS of those keys:
//                                        zone (one zone), all-zones (zone.*), account (one account, value "*"),
//                                        account-nested (one account, object value), all-accounts, user, other.
//                                        Never an id, a resource key or a value. skipped = group names dropped
//                                        because they fell outside the allowlisted alphabet
//   {error:<e.name>}                     a thrown error (e.message never returned)
// Never returned or logged: the atok, a full id, a token value, a resource key, e.message. A final guard drops
// any return that breaks this allowlist to {error:"ShapeError"}.
(args) => async (page) => {
  const DASH = 'https://dash.cloudflare.com';
  const HEX8 = /^[0-9a-f]{8}$/;
  const HEX32 = /^[0-9a-f]{32}$/;
  const PER = 50;
  const PAGES = 20;
  const GROUP_NAME = /^[A-Za-z0-9 ,&:()\/.'+_-]{1,100}$/;
  const SCOPE_RE = /^com\.cloudflare\.[a-z][a-z.]{0,60}$/;
  const KINDS = ['zone', 'all-zones', 'account', 'account-nested', 'all-accounts', 'user', 'other'];
  const KEYS = ['atok', 'refused', 'status', 'contentType', 'success', 'error', 'matches', 'groups', 'policies',
    'skipped'];
  const ARG_KEYS = ['what', 'scope', 'acct', 'pin'];
  const REFUSALS = ['args:object', 'args:unknown', ...ARG_KEYS.map((k) => `args:${k}`), 'origin', 'listing'];

  const isCount = (v) => Number.isInteger(v) && v >= 0 && v < 100000;
  const groupOk = (g) => g && typeof g === 'object' && !Array.isArray(g)
    && Object.keys(g).every((k) => ['name', 'scopes', 'id8'].includes(k))
    && typeof g.name === 'string' && GROUP_NAME.test(g.name)
    && Array.isArray(g.scopes) && g.scopes.length <= 10 && g.scopes.every((s) => typeof s === 'string' && SCOPE_RE.test(s))
    && (g.id8 === undefined || (typeof g.id8 === 'string' && HEX8.test(g.id8)));
  const policyOk = (p) => p && typeof p === 'object' && !Array.isArray(p)
    && Object.keys(p).every((k) => ['effect', 'groups', 'resources', 'kinds'].includes(k))
    && (p.effect === 'allow' || p.effect === 'deny')
    && Array.isArray(p.groups) && p.groups.length <= 100 && p.groups.every((n) => typeof n === 'string' && GROUP_NAME.test(n))
    && isCount(p.resources)
    && Array.isArray(p.kinds) && p.kinds.every((k) => KINDS.includes(k));
  const safe = (r) => {
    if (!r || typeof r !== 'object') return { error: 'ShapeError' };
    for (const k of Object.keys(r)) {
      const v = r[k];
      const ok = (k === 'atok' && v === false)
        || ((k === 'matches' || k === 'skipped') && isCount(v))
        || (k === 'refused' && REFUSALS.includes(v))
        || (k === 'status' && Number.isInteger(v) && v >= 0 && v < 1000)
        || (k === 'contentType' && typeof v === 'string' && /^[a-z0-9.+\/-]{0,64}$/.test(v))
        || (k === 'success' && typeof v === 'boolean')
        || (k === 'error' && typeof v === 'string' && /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(v))
        || (k === 'groups' && Array.isArray(v) && v.length <= 2000 && v.every(groupOk))
        || (k === 'policies' && Array.isArray(v) && v.length <= 100 && v.every(policyOk));
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

  // ---- arguments ------------------------------------------------------------------------------------------
  const a = args;
  if (!a || typeof a !== 'object' || Array.isArray(a)) return safe({ refused: 'args:object' });
  if (Object.keys(a).some((k) => !ARG_KEYS.includes(k))) return safe({ refused: 'args:unknown' });
  if (a.what !== 'groups' && a.what !== 'policies') return safe({ refused: 'args:what' });
  if (a.what === 'groups') {
    if (a.scope !== 'account' && a.scope !== 'user') return safe({ refused: 'args:scope' });
    if (a.scope === 'account' ? (typeof a.acct !== 'string' || !HEX32.test(a.acct)) : a.acct !== undefined) {
      return safe({ refused: 'args:acct' });
    }
    if (a.pin !== undefined) return safe({ refused: 'args:pin' });
  } else {
    if (a.scope !== 'user') return safe({ refused: 'args:scope' });
    if (a.acct !== undefined) return safe({ refused: 'args:acct' });
    if (typeof a.pin !== 'string' || !HEX8.test(a.pin)) return safe({ refused: 'args:pin' });
  }

  // Runs IN THE PAGE (serialized by page.evaluate: it may use no Node-side variable). GET only.
  const inPage = async ({ path }) => {
    if (location.origin !== 'https://dash.cloudflare.com') return { origin: false };
    const atok = window.bootstrap && window.bootstrap.atok;
    if (!atok) return { atok: false };
    const r = await fetch(path, {
      method: 'GET', credentials: 'same-origin', headers: { 'x-atok': atok, 'x-cross-site-security': 'dash' },
    });
    const contentType = r.headers.get('content-type') || '';
    let json = null;
    if (/json/i.test(contentType)) { try { json = await r.json(); } catch (e) { json = null; } }
    return { status: r.status, contentType, json };
  };
  const get = (path) => page.evaluate(inPage, { path });
  const stopOf = (r) => {
    if (r.origin === false) return { refused: 'origin' };
    if (r.atok === false) return { atok: false };
    if (r.status !== 200 || !r.json || r.json.success !== true) {
      return { status: r.status, contentType: ctOf(r.contentType), success: false };
    }
    return null;
  };
  const kindOf = (k, v) => {
    if (k === 'com.cloudflare.api.account.zone.*') return 'all-zones';
    if (/^com\.cloudflare\.api\.account\.zone\.[0-9a-f]{32}$/.test(k)) return 'zone';
    if (k === 'com.cloudflare.api.account.*') return 'all-accounts';
    if (/^com\.cloudflare\.api\.account\.[0-9a-f]{32}$/.test(k)) return v === '*' ? 'account' : 'account-nested';
    if (/^com\.cloudflare\.api\.user\./.test(k)) return 'user';
    return 'other';
  };

  try {
    await page.goto(`${DASH}/profile/api-tokens`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});

    if (a.what === 'groups') {
      const r = await get(a.scope === 'account' ? `/api/v4/accounts/${a.acct}/tokens/permission_groups`
        : '/api/v4/user/tokens/permission_groups');
      const stop = stopOf(r);
      if (stop) return safe(stop);
      if (!Array.isArray(r.json.result)) return safe({ status: r.status, contentType: ctOf(r.contentType), success: false });
      const groups = [];
      let skipped = 0;
      for (const g of r.json.result) {
        const scopes = g && Array.isArray(g.scopes) ? g.scopes : null;
        if (!g || typeof g.name !== 'string' || !GROUP_NAME.test(g.name) || !scopes || scopes.length > 10
          || !scopes.every((s) => typeof s === 'string' && SCOPE_RE.test(s))) {
          skipped += 1;
          continue;
        }
        const out = { name: g.name, scopes: [...scopes] };
        if (typeof g.id === 'string' && HEX32.test(g.id)) out.id8 = g.id.slice(0, 8);
        groups.push(out);
      }
      return safe({ success: true, groups, skipped });
    }

    // policies: find the ONE listed token whose id starts with pin, then read it.
    const hits = [];
    let seen = 0;
    let ended = false;
    for (let n = 1; n <= PAGES && !ended; n += 1) {
      const lr = await get(`/api/v4/user/tokens?page=${n}&per_page=${PER}`);
      const stop = stopOf(lr);
      if (stop) return safe(stop);
      if (!Array.isArray(lr.json.result)) return safe({ status: lr.status, contentType: ctOf(lr.contentType), success: false });
      for (const t of lr.json.result) if (t && typeof t.id === 'string' && t.id.startsWith(a.pin)) hits.push(t.id);
      seen += lr.json.result.length;
      const ri = lr.json.result_info || {};
      const per = Number.isInteger(ri.per_page) && ri.per_page > 0 && ri.per_page <= PER ? ri.per_page : PER;
      const more = Number.isInteger(ri.total_count) && seen < ri.total_count;
      if (lr.json.result.length < per && !more) ended = true;
    }
    if (!ended) return safe({ refused: 'listing' });
    if (hits.length !== 1 || !HEX32.test(hits[0])) return safe({ matches: hits.length === 1 ? 0 : hits.length });
    const tr = await get(`/api/v4/user/tokens/${hits[0]}`);
    const stop = stopOf(tr);
    if (stop) return safe(stop);
    const t = tr.json.result;
    if (!t || !Array.isArray(t.policies)) return safe({ status: tr.status, contentType: ctOf(tr.contentType), success: false });
    const policies = [];
    let skipped = 0;
    for (const p of t.policies) {
      const res = p && p.resources && typeof p.resources === 'object' && !Array.isArray(p.resources) ? p.resources : {};
      const keys = Object.keys(res);
      const groups = [];
      for (const g of (p && Array.isArray(p.permission_groups) ? p.permission_groups : [])) {
        if (g && typeof g.name === 'string' && GROUP_NAME.test(g.name)) groups.push(g.name); else skipped += 1;
      }
      policies.push({
        effect: p && p.effect === 'allow' ? 'allow' : 'deny',
        groups,
        resources: keys.length,
        kinds: [...new Set(keys.map((k) => kindOf(k, res[k])))].sort(),
      });
    }
    return safe({ success: true, policies, skipped });
  } catch (e) {
    return safe({ error: errName(e) });
  }
}
