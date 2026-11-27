// p5-mint.js — #12931 Phase 5 token slice: ONE account-owned Cloudflare token mint, run in the operator's
// signed-in dashboard session (runbook cloudflare-old-login-token-remint.md section 5; CTO ruling D1).
// Permission-group read, account-owned token POST, policy read-back and the hand-off to the 127.0.0.1 sink
// (p5-sink.py) run in this one body. Nothing is edited into this file: its sha256 is pinned in
// p5-browser.sha256, and every per-mint value arrives in the single JSON argument object below.
//
// SHAPE. This file is ONE function expression `(args) => async (page) => {...}` with no trailing semicolon.
// Compose the run file (sha check first), then pass it to Playwright MCP `browser_run_code_unsafe`:
//   { printf '('; cat p5-mint.js; printf ')(%s)\n' '<ARGS-JSON>'; } > <run-file>
// `browser_run_code_unsafe` evaluates `(<run-file>)` to the inner `async (page) => ...` and calls it with the
// current tab's page. The tool echoes the code it ran, so ARGS carries no secret: ids, names, a sink URL.
//
// ARGS (all required; any missing/malformed field refuses before any request):
//   account_id      32-hex account id the token is owned by and whose permission groups are read
//   zone_id         32-hex zone id; zone groups are granted on exactly this zone
//   name            token name, /^cf_api_token_[a-z0-9_]+-soleur-\d{8}$/ (runbook: <key>-soleur-<YYYYMMDD>)
//   zone_groups     array of exact permission-group names (the P5-SCOPE set), each ending in " Read"
//   account_groups  array (may be empty; AUDIT only) of exact account-scope group names, each ending " Read"
//   expires_on      "YYYY-MM-DDTHH:MM:SSZ", equal to the 0a/0b expiry
//   sink_url        "http://127.0.0.1:<port>/<nonce>" exactly as p5-sink.py printed it
//
// FLOW. goto https://dash.cloudflare.com/profile/api-tokens (a fresh window.bootstrap.atok); in-page GET
// /api/v4/accounts/<acct>/tokens/permission_groups and resolve each name to exactly ONE selectable group whose
// `scopes` holds the expected scope; in-page list of /api/v4/accounts/<acct>/tokens (refuse a same-name token:
// one token per key); in-page POST /api/v4/accounts/<acct>/tokens; in-page GET of the new token and the
// read-back (every resource key exactly com.cloudflare.api.account.zone.<zone> or, for account groups only,
// com.cloudflare.api.account.<acct>; value "*"; no "*" in a key; effect allow; group set == the resolved set;
// name, expires_on and status active as asked); only then a Node-side `fetch` POST of the value to sink_url.
// Any failure after the POST deletes the new token (Node-side page.request.delete, account endpoint) before the
// value goes anywhere: nothing reaches the sink or Doppler first (runbook section 5).
// In-page requests carry `x-atok` (window.bootstrap.atok) and `x-cross-site-security: dash`, the headers the
// 2026-11-26 0a/0b session sent (cloudflare-account-migration.md "Revoke recipe" step 3). The DELETE is
// Node-side because an in-page fetch DELETE got an HTML 403 from the dashboard edge (same section).
//
// ENDPOINTS (dash.cloudflare.com/api/v4 proxies the public v4 API with the session):
//   GET    /accounts/{account_id}/tokens/permission_groups  developers.cloudflare.com/api/resources/accounts/subresources/tokens/subresources/permission_groups/methods/list/
//   GET    /accounts/{account_id}/tokens                    developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/list/
//   POST   /accounts/{account_id}/tokens                    developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/create/
//   GET    /accounts/{account_id}/tokens/{token_id}         developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/get/
//   DELETE /accounts/{account_id}/tokens/{token_id}         developers.cloudflare.com/api/resources/accounts/subresources/tokens/methods/delete/
//
// RETURN. Only these keys ever appear: atok, matches, refused, status, contentType, success, error, id8.
//   {atok:false}                               the page is signed out (no window.bootstrap.atok)
//   {refused:<reason>}                         before any write; reason one of args:<field>, origin
//   {refused:"groups", matches:<n>}            only n of the asked names resolved to exactly one group
//   {refused:"name-exists", matches:<n>}       n account tokens already carry this name; nothing minted
//   {status, contentType, success:false}       a read or the POST answered no usable result; nothing minted
//   {status, contentType, success:true, id8}   MINTED: POST status, read-back passed, sink answered 200
//   {refused:"readback"|"sink"|"mint-shape", id8, status, contentType, success}
//                                              a token WAS created and failed; status/contentType/success
//                                              describe its cleanup DELETE (success:true = it is deleted)
//   {error:<e.name>[, id8, status, contentType, success]}  a thrown error; with id8, the cleanup as above
// id8 is the new token's 8-hex id prefix. Never returned or logged: the token value, the atok, a full id,
// e.message. A final guard drops any return that breaks this allowlist to {error:"ShapeError"}.
(args) => async (page) => {
  const DASH = 'https://dash.cloudflare.com';
  const HEX8 = /^[0-9a-f]{8}$/;
  const HEX32 = /^[0-9a-f]{32}$/;
  const KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error', 'id8'];
  const REFUSALS = ['args:object', 'args:account_id', 'args:zone_id', 'args:name', 'args:zone_groups',
    'args:account_groups', 'args:expires_on', 'args:sink_url', 'origin', 'groups', 'name-exists',
    'readback', 'sink', 'mint-shape'];

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
    || Number.isNaN(Date.parse(a.expires_on))) {
    return safe({ refused: 'args:expires_on' });
  }
  if (typeof a.sink_url !== 'string' || !/^http:\/\/127\.0\.0\.1:[0-9]{1,5}\/[A-Za-z0-9_-]{16,128}$/.test(a.sink_url)) {
    return safe({ refused: 'args:sink_url' });
  }
  const acct = a.account_id;
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
  const notOk = (r) => r.status !== 200 || !r.json || r.json.success !== true;
  const statusOf = (r) => ({ status: r.status, contentType: ctOf(r.contentType), success: false });

  // Node-side DELETE of the token this body minted (account endpoint). The atok is Node-local.
  const cleanup = async (id) => {
    const atok = await page.evaluate(() => (location.origin === 'https://dash.cloudflare.com'
      && window.bootstrap && window.bootstrap.atok) || null);
    if (!atok) return { atok: false };
    const r = await page.request.delete(`${DASH}/api/v4/accounts/${acct}/tokens/${id}`, {
      headers: { 'x-atok': atok, 'x-cross-site-security': 'dash' },
    });
    const contentType = ctOf(r.headers()['content-type']);
    let success = false;
    if (/json/.test(contentType)) { try { const j = await r.json(); success = !!j && j.success === true; } catch (e) { success = false; } }
    return { status: r.status(), contentType, success };
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
  let handed = false;
  try {
    await page.goto(`${DASH}/profile/api-tokens`, { waitUntil: 'domcontentloaded' });

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

    // 2. one token per key: no account token already carries this name.
    let same = 0;
    let seen = 0;
    for (let n = 1; n <= 20; n += 1) {
      const lr = await call('GET', `/api/v4/accounts/${acct}/tokens?page=${n}&per_page=50`);
      if (lr.atok === false) return safe({ atok: false });
      if (lr.origin === false) return safe({ refused: 'origin' });
      if (notOk(lr) || !Array.isArray(lr.json.result)) return safe(statusOf(lr));
      same += lr.json.result.filter((t) => t && t.name === a.name).length;
      seen += lr.json.result.length;
      const total = lr.json.result_info && Number.isInteger(lr.json.result_info.total_count)
        ? lr.json.result_info.total_count : seen;
      if (lr.json.result.length === 0 || seen >= total) break;
    }
    if (same !== 0) return safe({ refused: 'name-exists', matches: same });

    // 3. the mint.
    const policies = [{
      effect: 'allow', permission_groups: [...zoneIds].map((g) => ({ id: g })), resources: { [zoneKey]: '*' },
    }];
    if (acctIds.size > 0) {
      policies.push({ effect: 'allow', permission_groups: [...acctIds].map((g) => ({ id: g })), resources: { [acctKey]: '*' } });
    }
    const mr = await call('POST', `/api/v4/accounts/${acct}/tokens`, { name: a.name, policies, expires_on: a.expires_on });
    if (mr.atok === false) return safe({ atok: false });
    if (mr.origin === false) return safe({ refused: 'origin' });
    const res = mr.json && mr.json.result;
    if (res && typeof res.id === 'string' && HEX32.test(res.id)) id = res.id;
    if (res && typeof res.value === 'string') secret = res.value;
    if (res) { delete res.value; }
    const mintStatus = { status: mr.status, contentType: ctOf(mr.contentType) };
    if (id === null) return safe({ ...mintStatus, success: false });
    if (notOk(mr) || secret === null || secret.length < 20) {
      return safe({ refused: 'mint-shape', id8: id.slice(0, 8), ...(await cleanup(id)) });
    }

    // 4. the policy read-back, from a fresh GET of the stored token.
    const rb = await call('GET', `/api/v4/accounts/${acct}/tokens/${id}`);
    if (notOk(rb) || !readbackPasses(rb.json.result, zoneIds, acctIds)) {
      secret = null;
      return safe({ refused: 'readback', id8: id.slice(0, 8), ...(await cleanup(id)) });
    }

    // 5. the hand-off: Node-side fetch to the one-shot 127.0.0.1 sink. The value goes nowhere else.
    let sinkOk = false;
    try {
      const sr = await fetch(a.sink_url, {
        method: 'POST', headers: { 'content-type': 'text/plain' }, body: secret, signal: AbortSignal.timeout(15000),
      });
      sinkOk = sr.status === 200 && (await sr.text()) === 'ok';
    } catch (e) {
      sinkOk = false;
    }
    secret = null;
    if (!sinkOk) return safe({ refused: 'sink', id8: id.slice(0, 8), ...(await cleanup(id)) });
    handed = true;
    return safe({ ...mintStatus, success: true, id8: id.slice(0, 8) });
  } catch (e) {
    secret = null;
    if (id !== null && !handed) {
      let del = { success: false };
      try { del = await cleanup(id); } catch (e2) { del = { success: false }; }
      return safe({ error: errName(e), id8: id.slice(0, 8), ...del });
    }
    return safe({ error: errName(e) });
  } finally {
    secret = null;
  }
}
