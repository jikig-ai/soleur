// p5-mint.js — #12931 Phase 5 token slice: ONE Cloudflare token mint, run in the operator's signed-in dashboard
// session (runbook cloudflare-old-login-token-remint.md section 5; CTO rulings D1, D7, D9). Permission-group
// read, token POST, policy read-back and the hand-off to the 127.0.0.1 sink (p5-sink.py) run in this one body.
// Nothing is edited into this file: its sha256 is pinned in p5-browser.sha256, and every per-mint value arrives
// in the single JSON argument object below.
//
// SHAPE. This file is ONE function expression `(args) => async (page) => {...}` with no trailing semicolon. The
// run file is `(<this file>)(JSON.parse(<string>))`, where <string> is the argument object re-encoded as ONE JSON
// string literal (`jq -c . | jq -Rs .`, after `jq -e 'type=="object"'` passes; CTO D9), so the argument is data
// and never JavaScript. Compose it with the runbook's section 5 line (sha check first), then pass it to
// Playwright MCP `browser_run_code_unsafe`, which evaluates `(<run-file>)` to the inner `async (page) => ...` and
// calls it with the current tab's page. The tool echoes the code it ran, so ARGS carries no secret.
//
// ARGS (any missing, malformed or unknown field refuses before any request):
//   owner           required: "account" -> list/POST/GET/DELETE at /accounts/<account_id>/tokens[...]
//                             "user"    -> list/POST/GET/DELETE at /user/tokens[...] (the D7 user-owned fallback)
//   account_id      required: 32-hex account id; its permission groups are read, and (owner account) it owns
//   zone_id         required: 32-hex zone id; zone groups are granted on exactly this zone
//   name            required: token name, /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/ (<key>-soleur-<YYYYMMDD>)
//   zone_groups     required: array of 1..20 exact permission-group names (the P5-SCOPE set), each ending " Read"
//   account_groups  required: array of 0..20 (AUDIT only) exact account-scope group names, each ending " Read"
//   expires_on      required: "YYYY-MM-DDTHH:MM:SSZ", the 0a/0b expiry, no earlier than now + 30 days
//   sink_url        required: "http://127.0.0.1:<port>/<nonce>" exactly as p5-sink.py printed it
//   refuse_ids      owner "user": REQUIRED array of 1..20 8-hex old-token pins; if any token the signed-in login
//                   lists starts with one, the body refuses (it never mints under the old owner's login).
//                   owner "account": must be absent.
//
// FLOW. goto https://dash.cloudflare.com/profile/api-tokens (a fresh window.bootstrap.atok), then wait up to 15 s
// for window.bootstrap.atok, which the dashboard sets after DOMContentLoaded (measured 2026-11-28); in-page GET
// /api/v4/accounts/<acct>/tokens/permission_groups and resolve each name to exactly ONE selectable group whose
// `scopes` holds the expected scope; in-page list of every page of the owner's token list (a page shorter than
// per_page ends it, unless result_info.total_count says more; 20 pages without an end refuses `listing`); refuse
// an old-owner pin (owner user) and a same-name token (one token per exact name); the token POST, Node-side
// (page.request.post, the atok read from the page just before it, no redirect followed); in-page GET of
// the new token and the read-back (every resource key exactly com.cloudflare.api.account.zone.<zone> or, for
// account groups only, com.cloudflare.api.account.<acct>; value "*"; no "*" in a key; effect allow; group set ==
// the resolved set; name, expires_on and status active as asked); only then a Node-side `fetch` POST of the
// value to sink_url with `redirect: "error"` (a redirect never carries the value on).
// CLEANUP. Once the POST was sent, every path but the handed-off one (an error answer, a non-JSON answer, an id
// that is not 32-hex, a missing value, a read-back or sink failure, a throw) re-lists the owner's tokens, DELETEs
// every token carrying exactly `name` or the id the POST answered (Node-side page.request.delete), and re-lists
// again. A POST answer proves nothing about whether a token was stored, so only that re-list does.
// `success:true` on a refused/error return means: every DELETE answered JSON success:true AND the re-list shows
// no token with that name or id.
// Every request carries `x-atok` (window.bootstrap.atok) and `x-cross-site-security: dash`, the headers the
// 2026-11-26 0a/0b session sent (cloudflare-account-migration.md "Revoke recipe" step 3). The writes (the token
// POST and the cleanup DELETE) are Node-side, through the page's request context: an in-page fetch DELETE got an
// HTML 403 from the dashboard edge on 2026-11-26 (same section), and an in-page fetch POST to
// /accounts/<acct>/tokens got one on 2026-11-28, twice, while the in-page GETs of the same run answered JSON.
// The reads stay in-page. The token POST's answer (which carries the value) is read with json() only, never
// text(), and only when its content-type is JSON.
//
// ENDPOINTS (dash.cloudflare.com/api/v4 proxies the public v4 API with the session):
//   GET    /accounts/{account_id}/tokens/permission_groups  developers.cloudflare.com/api/resources/accounts/subresources/tokens/subresources/permission_groups/methods/list/
//   GET    /accounts/{account_id}/tokens                    developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/list/
//   POST   /accounts/{account_id}/tokens                    developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/create/
//   GET    /accounts/{account_id}/tokens/{token_id}         developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/get/
//   DELETE /accounts/{account_id}/tokens/{token_id}         developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/delete/
//   GET    /user/tokens                                     developers.cloudflare.com/api/resources/user/subresources/tokens/methods/list/
//   POST   /user/tokens                                     developers.cloudflare.com/api/resources/user/subresources/tokens/methods/create/
//   GET    /user/tokens/{token_id}                          developers.cloudflare.com/api/resources/user/subresources/tokens/methods/get/
//   DELETE /user/tokens/{token_id}                          developers.cloudflare.com/api/resources/user/subresources/tokens/methods/delete/
//
// RETURN. Only these keys ever appear: atok, matches, refused, status, contentType, success, error, id8,
// del_status, del_contentType.
//   BEFORE THE POST (no token can exist from this run):
//   {atok:false}                               the page is signed out (no window.bootstrap.atok)
//   {refused:"args:<field>"}                   a bad argument (field object, unknown, or the field's name)
//   {refused:"origin"}                         the page is not on https://dash.cloudflare.com
//   {refused:"groups", matches:<n>}            only n of the asked names resolved to exactly one group
//   {refused:"listing"}                        the token list did not end within 20 pages
//   {refused:"old-owner-login", matches:<n>}   owner user: n listed tokens start with a refuse_ids pin
//   {refused:"name-exists", matches:<n>}       n tokens already carry this exact name
//   {status, contentType, success:false}       the group read or the list answered no usable result
//   AFTER THE POST (a token MAY have been stored; the cleanup ran):
//   {status, contentType, success:true, id8}   MINTED and handed off: POST status, read-back passed, sink 200 "ok"
//   {refused:"mint"|"mint-shape"|"readback"|"sink", [id8], status, contentType, success, [matches],
//    [del_status, del_contentType]}
//     mint        the POST answered no JSON success:true (an error, or a non-JSON body; an HTML 403 is the
//                 dashboard edge refusing the write)
//     mint-shape  the POST answered success but no 32-hex id or no value
//     readback    the stored token's policy/name/expiry/status differs from the request
//     sink        the sink did not answer 200 "ok" (down, refused, redirected, timed out)
//     status/contentType: the POST's answer. id8: present when the POST answered a 32-hex id.
//     success: the cleanup verdict (true = every DELETE answered JSON success and the re-list shows none).
//     matches: tokens with that name (or id) the re-list still shows (absent when the re-list could not run).
//     del_status/del_contentType: the first DELETE that did not answer JSON success (absent if none).
//     success:false: a token with this name (or id) MAY still exist; read the list before any re-mint.
//   {error:<e.name>}                           a thrown error before the POST was sent
//   {error:<e.name>, [id8, status, contentType], success, [matches, del_status, del_contentType]}
//                                              a thrown error after the POST was sent; the cleanup as above
// Never returned or logged: the token value, the atok, a full id, e.message. A final guard drops any return
// that breaks this allowlist to {error:"ShapeError"}.
(args) => async (page) => {
  const DASH = 'https://dash.cloudflare.com';
  const HEX8 = /^[0-9a-f]{8}$/;
  const HEX32 = /^[0-9a-f]{32}$/;
  const PER = 50;
  const PAGES = 20;
  const KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error', 'id8', 'del_status',
    'del_contentType'];
  const ARG_KEYS = ['owner', 'account_id', 'zone_id', 'name', 'zone_groups', 'account_groups', 'expires_on',
    'sink_url', 'refuse_ids'];
  const REFUSALS = ['args:object', 'args:unknown', ...ARG_KEYS.map((k) => `args:${k}`), 'origin', 'groups',
    'listing', 'old-owner-login', 'name-exists', 'mint', 'mint-shape', 'readback', 'sink'];

  const safe = (r) => {
    if (!r || typeof r !== 'object') return { error: 'ShapeError' };
    for (const k of Object.keys(r)) {
      const v = r[k];
      const ok = (k === 'atok' && v === false)
        || (k === 'matches' && Number.isInteger(v) && v >= 0 && v < 100000)
        || (k === 'refused' && REFUSALS.includes(v))
        || ((k === 'status' || k === 'del_status') && Number.isInteger(v) && v >= 0 && v < 1000)
        || ((k === 'contentType' || k === 'del_contentType') && typeof v === 'string' && /^[a-z0-9.+\/-]{0,64}$/.test(v))
        || (k === 'success' && typeof v === 'boolean')
        || (k === 'error' && typeof v === 'string' && /^[A-Za-z][A-Za-z0-9]{0,39}$/.test(v))
        || (k === 'id8' && typeof v === 'string' && HEX8.test(v));
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
  if (a.owner !== 'account' && a.owner !== 'user') return safe({ refused: 'args:owner' });
  if (typeof a.account_id !== 'string' || !HEX32.test(a.account_id)) return safe({ refused: 'args:account_id' });
  if (typeof a.zone_id !== 'string' || !HEX32.test(a.zone_id)) return safe({ refused: 'args:zone_id' });
  if (typeof a.name !== 'string' || !/^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/.test(a.name)) {
    return safe({ refused: 'args:name' });
  }
  const groupList = (v, min) => Array.isArray(v) && v.length >= min && v.length <= 20
    && v.every((g) => typeof g === 'string' && /^[A-Za-z0-9 ,&:()\/.-]{1,80} Read$/.test(g))
    && new Set(v).size === v.length;
  if (!groupList(a.zone_groups, 1)) return safe({ refused: 'args:zone_groups' });
  if (!groupList(a.account_groups, 0)) return safe({ refused: 'args:account_groups' });
  if (typeof a.expires_on !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(a.expires_on)
    || Number.isNaN(Date.parse(a.expires_on)) || Date.parse(a.expires_on) < Date.now() + 30 * 86400000) {
    return safe({ refused: 'args:expires_on' });
  }
  if (typeof a.sink_url !== 'string' || !/^http:\/\/127\.0\.0\.1:[0-9]{1,5}\/[A-Za-z0-9_-]{16,128}$/.test(a.sink_url)) {
    return safe({ refused: 'args:sink_url' });
  }
  if (a.owner === 'user') {
    if (!Array.isArray(a.refuse_ids) || a.refuse_ids.length < 1 || a.refuse_ids.length > 20
      || !a.refuse_ids.every((p) => typeof p === 'string' && HEX8.test(p))) {
      return safe({ refused: 'args:refuse_ids' });
    }
  } else if (a.refuse_ids !== undefined) return safe({ refused: 'args:refuse_ids' });
  const acct = a.account_id;
  const base = a.owner === 'account' ? `/api/v4/accounts/${acct}/tokens` : '/api/v4/user/tokens';
  const ZONE_SCOPE = 'com.cloudflare.api.account.zone';
  const ACCT_SCOPE = 'com.cloudflare.api.account';
  const zoneKey = `${ZONE_SCOPE}.${a.zone_id}`;
  const acctKey = `${ACCT_SCOPE}.${acct}`;

  // ---- helpers --------------------------------------------------------------------------------------------
  // Runs IN THE PAGE (serialized by page.evaluate: it may use no Node-side variable). Returns {origin:false},
  // {atok:false} or {status, contentType, json}; the atok never leaves the page here.
  const inPage = async ({ method, path, body }) => {
    if (location.origin !== 'https://dash.cloudflare.com') return { origin: false };
    const atok = window.bootstrap && window.bootstrap.atok;
    if (!atok) return { atok: false };
    const headers = { 'x-atok': atok, 'x-cross-site-security': 'dash' };
    if (body !== undefined) headers['content-type'] = 'application/json';
    const r = await fetch(path, {
      method, headers, credentials: 'same-origin', body: body === undefined ? undefined : JSON.stringify(body),
    });
    const contentType = r.headers.get('content-type') || '';
    let json = null;
    if (/json/i.test(contentType)) { try { json = await r.json(); } catch (e) { json = null; } }
    return { status: r.status, contentType, json };
  };
  const call = (method, path, body) => page.evaluate(inPage, { method, path, body });
  // Runs NODE-SIDE: the token POST, through the page's request context (cookies included). The origin and the
  // atok are read from the page first, as inPage reads them; same return shape as inPage. maxRedirects 0: a
  // redirect never carries the atok on or turns the POST into a GET.
  const postNode = async (path, body) => {
    const pgs = await page.evaluate(() => ({ origin: location.origin === 'https://dash.cloudflare.com',
      atok: (window.bootstrap && window.bootstrap.atok) || null }));
    if (!pgs.origin) return { origin: false };
    if (!pgs.atok) return { atok: false };
    const r = await page.request.post(`${DASH}${path}`, {
      headers: { 'x-atok': pgs.atok, 'x-cross-site-security': 'dash', 'content-type': 'application/json' },
      data: body, failOnStatusCode: false, maxRedirects: 0, timeout: 30000,
    });
    try {
      const contentType = r.headers()['content-type'] || '';
      let parsed = null;
      if (/json/i.test(contentType)) { try { parsed = await r.json(); } catch (e) { parsed = null; } }
      return { status: r.status(), contentType, json: parsed };
    } finally {
      await r.dispose().catch(() => {});
    }
  };
  const notOk = (r) => r.status !== 200 || !r.json || r.json.success !== true;
  const statusOf = (r) => ({ status: r.status, contentType: ctOf(r.contentType), success: false });

  // Every page of the owner's token list -> {tokens} or {stop:<return>}. A page shorter than per_page ends the
  // list unless result_info.total_count says more were listed; no end within PAGES pages refuses `listing`.
  const listAll = async () => {
    const tokens = [];
    for (let n = 1; n <= PAGES; n += 1) {
      const lr = await call('GET', `${base}?page=${n}&per_page=${PER}`);
      if (lr.atok === false) return { stop: { atok: false } };
      if (lr.origin === false) return { stop: { refused: 'origin' } };
      if (notOk(lr) || !Array.isArray(lr.json.result)) return { stop: statusOf(lr) };
      tokens.push(...lr.json.result);
      const ri = lr.json.result_info || {};
      const per = Number.isInteger(ri.per_page) && ri.per_page > 0 && ri.per_page <= PER ? ri.per_page : PER;
      const more = Number.isInteger(ri.total_count) && tokens.length < ri.total_count;
      if (lr.json.result.length < per && !more) return { tokens };
    }
    return { stop: { refused: 'listing' } };
  };

  // The cleanup: DELETE (Node-side, owner endpoint) every listed token carrying exactly a.name or the id the POST
  // answered (a stored name may drift from the request), then re-list.
  // Returns {success[, matches, del_status, del_contentType]}; success is true only on a verified-clean re-list.
  const cleanup = async () => {
    const out = { success: false };
    const ours = (t) => !!t && (t.name === a.name || (id !== null && t.id === id));
    try {
      const atok = await page.evaluate(() => (location.origin === 'https://dash.cloudflare.com'
        && window.bootstrap && window.bootstrap.atok) || null);
      if (!atok) return out;
      const before = await listAll();
      if (!before.tokens) return out;
      let allDeleted = true;
      for (const t of before.tokens) {
        if (!ours(t)) continue;
        if (typeof t.id !== 'string' || !HEX32.test(t.id)) { allDeleted = false; continue; }
        const r = await page.request.delete(`${DASH}${base}/${t.id}`, {
          headers: { 'x-atok': atok, 'x-cross-site-security': 'dash' }, failOnStatusCode: false, maxRedirects: 0,
        });
        const contentType = ctOf(r.headers()['content-type']);
        let ok = false;
        if (/json/.test(contentType)) {
          try { const j = await r.json(); ok = r.status() === 200 && !!j && j.success === true; } catch (e) { ok = false; }
        }
        if (!ok) {
          allDeleted = false;
          if (out.del_status === undefined) { out.del_status = r.status(); out.del_contentType = contentType; }
        }
      }
      const after = await listAll();
      if (!after.tokens) return out;
      out.matches = after.tokens.filter(ours).length;
      out.success = allDeleted && out.matches === 0;
      return out;
    } catch (e) {
      out.success = false;
      return out;
    }
  };

  const eqSet = (x, y) => x.size === y.size && [...x].every((v) => y.has(v));
  const readbackPasses = (t, zoneIds, acctIds) => {
    if (!t || typeof t !== 'object' || !Array.isArray(t.policies) || t.policies.length === 0) return false;
    const gotZone = new Set();
    const gotAcct = new Set();
    for (const p of t.policies) {
      if (!p || p.effect !== 'allow') return false;
      const res = p.resources;
      if (!res || typeof res !== 'object' || Array.isArray(res)) return false;
      const keys = Object.keys(res);
      if (keys.length !== 1) return false;
      const k = keys[0];
      if (k.includes('*') || res[k] !== '*') return false;
      let bucket;
      let allowed;
      if (k === zoneKey) { bucket = gotZone; allowed = zoneIds; } else if (k === acctKey && acctIds.size > 0) {
        bucket = gotAcct; allowed = acctIds;
      } else return false;
      if (!Array.isArray(p.permission_groups) || p.permission_groups.length === 0) return false;
      for (const g of p.permission_groups) {
        if (!g || !allowed.has(g.id)) return false;
        bucket.add(g.id);
      }
    }
    return eqSet(gotZone, zoneIds) && eqSet(gotAcct, acctIds) && t.name === a.name
      && Date.parse(t.expires_on) === Date.parse(a.expires_on) && t.status === 'active';
  };

  let id = null;
  let secret = null;
  let posted = false;
  let handed = false;
  let postInfo = {};
  const failAfterPost = async (reason) => {
    secret = null;
    return safe({ refused: reason, ...(id !== null ? { id8: id.slice(0, 8) } : {}), ...postInfo, ...(await cleanup()) });
  };
  try {
    await page.goto(`${DASH}/profile/api-tokens`, { waitUntil: 'domcontentloaded' });
    await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});

    // 1. permission groups: each asked name -> exactly one selectable group carrying the expected scope.
    const pg = await call('GET', `/api/v4/accounts/${acct}/tokens/permission_groups`);
    if (pg.origin === false) return safe({ refused: 'origin' });
    if (pg.atok === false) return safe({ atok: false });
    if (notOk(pg) || !Array.isArray(pg.json.result)) return safe(statusOf(pg));
    const resolve = (names, scope) => names.map((n) => {
      const hits = pg.json.result.filter((g) => g && g.name === n && Array.isArray(g.scopes)
        && g.scopes.includes(scope) && g.is_selectable !== false && typeof g.id === 'string' && g.id.length > 0);
      return hits.length === 1 ? hits[0].id : null;
    });
    const zoneRes = resolve(a.zone_groups, ZONE_SCOPE);
    const acctRes = resolve(a.account_groups, ACCT_SCOPE);
    const resolved = [...zoneRes, ...acctRes].filter((x) => x !== null).length;
    if (resolved !== a.zone_groups.length + a.account_groups.length) {
      return safe({ refused: 'groups', matches: resolved });
    }
    const zoneIds = new Set(zoneRes);
    const acctIds = new Set(acctRes);

    // 2. the owner's token list: never under the old owner's login (owner user); one token per exact name.
    const listed = await listAll();
    if (!listed.tokens) return safe(listed.stop);
    if (a.owner === 'user') {
      const old = listed.tokens.filter((t) => t && typeof t.id === 'string'
        && a.refuse_ids.some((p) => t.id.startsWith(p))).length;
      if (old !== 0) return safe({ refused: 'old-owner-login', matches: old });
    }
    const same = listed.tokens.filter((t) => t && t.name === a.name).length;
    if (same !== 0) return safe({ refused: 'name-exists', matches: same });

    // 3. the mint. From here on every non-handed-off path runs the cleanup.
    const policies = [{
      effect: 'allow', permission_groups: [...zoneIds].map((g) => ({ id: g })), resources: { [zoneKey]: '*' },
    }];
    if (acctIds.size > 0) {
      policies.push({ effect: 'allow', permission_groups: [...acctIds].map((g) => ({ id: g })), resources: { [acctKey]: '*' } });
    }
    posted = true;
    const mr = await postNode(base, { name: a.name, policies, expires_on: a.expires_on });
    // atok/origin false: postNode returned before its request, so no POST was sent.
    if (mr.atok === false) return safe({ atok: false });
    if (mr.origin === false) return safe({ refused: 'origin' });
    postInfo = { status: mr.status, contentType: ctOf(mr.contentType) };
    const res = mr.json && mr.json.result;
    if (res && typeof res.id === 'string' && HEX32.test(res.id)) id = res.id;
    if (res && typeof res.value === 'string') secret = res.value;
    if (res) { delete res.value; }
    if (notOk(mr)) return await failAfterPost('mint');
    if (id === null || secret === null || secret.length < 20) return await failAfterPost('mint-shape');

    // 4. the policy read-back, from a fresh GET of the stored token.
    const rb = await call('GET', `${base}/${id}`);
    if (notOk(rb) || !readbackPasses(rb.json.result, zoneIds, acctIds)) return await failAfterPost('readback');

    // 5. the hand-off: Node-side fetch to the one-shot 127.0.0.1 sink, no redirect followed. The value goes
    //    nowhere else.
    let sinkOk = false;
    try {
      const sr = await fetch(a.sink_url, {
        method: 'POST', headers: { 'content-type': 'text/plain' }, body: secret, redirect: 'error',
        signal: AbortSignal.timeout(15000),
      });
      sinkOk = sr.status === 200 && (await sr.text()) === 'ok';
    } catch (e) {
      sinkOk = false;
    }
    secret = null;
    if (!sinkOk) return await failAfterPost('sink');
    handed = true;
    return safe({ ...postInfo, success: true, id8: id.slice(0, 8) });
  } catch (e) {
    secret = null;
    if (posted && !handed) {
      return safe({ error: errName(e), ...(id !== null ? { id8: id.slice(0, 8) } : {}), ...postInfo, ...(await cleanup()) });
    }
    return safe({ error: errName(e) });
  } finally {
    secret = null;
  }
}
