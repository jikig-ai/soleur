#!/usr/bin/env bash
# test-cf-old-login-token-remint-browser.sh — the #12931 Phase 5 token slice's committed dashboard browser
# bodies (CTO ruling D1): p5-mint.js, p5-revoke.js and the one-shot hand-off sink p5-sink.py, all beside
# bootstrap.sh in the feat-one-shot-12931-phase5-token-remint spec directory, pinned by p5-browser.sha256.
#
#   bash tests/scripts/test-cf-old-login-token-remint-browser.sh            every row, then every mutant
#   bash tests/scripts/test-cf-old-login-token-remint-browser.sh --mutants  the mutation section only
#
# PROPERTIES
#   P-pin     p5-browser.sha256 lists exactly the three files and `sha256sum -c` passes; any runbook line of
#             the form `<file> sha256=<hex>` names the manifest's value.
#   P-shape   every return of either body carries only allowlisted keys with allowlisted value types (an
#             independent allowlist here, not the body's own guard).
#   P-leak    no return, page console line, sink line or harness line carries the stub's synthesized token
#             value, atok or any full token id (nor any hex run longer than 8).
#   P-revoke  refusals before any request: pin != old_id, old_id == new_id; after the list: a name equal to
#             new_name; 0 or 2 prefix matches; user and account endpoints; DELETE is Node-side with both headers.
#   P-mint    group resolution by name AND scope; one-token-per-key; read-back failures (account-wide resource,
#             extra group, deny, non-"*" value, expiry or name drift) delete the new token and never reach the
#             sink; a dead sink deletes it too; the happy path hands the value to the sink once.
#   P-sink    binds 127.0.0.1 only (a connect to 127.0.0.2 is refused); serves one request then no listener;
#             refuses a 127.0.0.2 peer, a wrong path, an Origin header, a GET, a bad body; writes mode 0600;
#             refuses an --out that exists, is relative, or sits in a git work tree; never prints the value.
#   P-compose the documented composition line `{ printf '('; cat F; printf ')(%s)\n' ARGS; }` yields a file
#             that the browser_run_code_unsafe wrapping (`"(" + code + ")"` called with page) runs.
#
# ASSEMBLY. A node harness (written to the sandbox) emulates browser_run_code_unsafe exactly as Playwright MCP
# does: a vm context holding only `page` and its exposed globals (no console), `(" + code + ")` evaluated, then
# called with page and JSON.stringify'd. The stub page serializes every page.evaluate function by toString()
# into a separate "page" vm context (window.bootstrap.atok, location.origin, a stub dash fetch), so a body that
# closes over a Node-side variable inside an in-page function fails here as it would in the browser. In-page
# DELETE answers the HTML 403 the dashboard edge gave on 2026-11-26. Values are synthesized sentinels
# (cq-test-fixtures-synthesized-only); the account and zone ids are the runbook's public id table. Nothing
# reaches a network beyond 127.0.0.1.
#
# MUTATIONS (--mutants, and the tail of a full run): each must land (cmp differs) and turn its row RED:
#   XR1 revoke pin guard deleted          -> R2     XR2 revoke same-id guard deleted -> R3
#   XR3 revoke name guard deleted         -> R4     XM1 mint read-back accepts the account key for zone groups -> M7a
#   XM2 mint one-token-per-key deleted    -> M6     XS1 sink peer check deleted -> S2
#   Instrument: XL1 a revoke return that bypasses the guard and carries the atok -> R1 (P-shape/P-leak);
#               XL2 an in-page function closing over a Node-side variable -> R1 (page serialization)
#
# LOCATION: finds its files by glob, so an archive-kb move of the spec directory breaks nothing.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
export LC_ALL=C

MODE=full
case "${1:-}" in
  "") ;;
  --mutants) MODE=mutants ;;
  *) printf 'usage: %s [--mutants]\n' "$0" >&2; exit 2 ;;
esac

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SUITE_DIR" rev-parse --show-toplevel 2>/dev/null)" || { printf 'HARNESS: not in a git work tree\n' >&2; exit 2; }
find_one() { # <name> -> absolute path, exactly one match
  local -a f
  mapfile -t f < <(git -C "$REPO_ROOT" ls-files --cached --others --exclude-standard --full-name \
    "*feat-one-shot-12931-phase5-token-remint/$1")
  [[ "${#f[@]}" -eq 1 ]] || { printf 'HARNESS: expected exactly one %s, found %s\n' "$1" "${#f[@]}" >&2; exit 2; }
  printf '%s/%s\n' "$REPO_ROOT" "${f[0]}"
}
MINT="$(find_one p5-mint.js)" || exit 2
REVOKE="$(find_one p5-revoke.js)" || exit 2
SINK="$(find_one p5-sink.py)" || exit 2
MANIFEST="$(find_one p5-browser.sha256)" || exit 2
RUNBOOK="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md"

for bin in node python3 sha256sum stat cmp perl; do command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }; done

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (last out: $(printf '%s' "${OUT:-}" | tr '\n' ' ' | cut -c1-400))"; fi; }

# Instrument self-test (ADR-193 shape): both helpers must move their counter, or nothing below means anything.
check "instrument self-test (pass arm)" 0 >/dev/null
check "instrument self-test (fail arm)" 1 >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then printf 'INSTRUMENT SELF-TEST FAILED (pass=%s fail=%s)\n' "$PASS" "$FAIL" >&2; exit 2; fi
FAIL=0

SB="$(mktemp -d "${TMPDIR}/cf-p5-browser.XXXXXXXX")" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
trap 'chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"' EXIT
chmod 700 "$SB"
ALL_OUT="$SB/all-output.log"; : > "$ALL_OUT"
SENT="$SB/sentinels"   # the harness writes its synthesized secrets here (mode 0600) for the P-leak grep

readonly NA=66d4f93f7397f196544e9fe84c3557c2 NZ=951ce525552201ec6c696b24251abed7

# --- the node harness --------------------------------------------------------------------------------------
cat > "$SB/harness.mjs" <<'HARNESS'
// Emulates Playwright MCP browser_run_code_unsafe and a dash.cloudflare.com page. Prints only `ok <row>` and
// `FAIL <row>: <why>` lines; never a sentinel.
import vm from 'node:vm';
import fs from 'node:fs';
import crypto from 'node:crypto';

const [mintPath, revokePath, sentPath] = process.argv.slice(2);
const MODE = process.env.P5_MODE || 'unit';
const ONLY = (process.env.P5_ONLY || '').split(',').filter(Boolean);
const DASH = 'https://dash.cloudflare.com';
const NA = '66d4f93f7397f196544e9fe84c3557c2';
const NZ = '951ce525552201ec6c696b24251abed7';
const ZK = `com.cloudflare.api.account.zone.${NZ}`;
const AK = `com.cloudflare.api.account.${NA}`;
const hex = (n) => crypto.randomBytes(n).toString('hex');
const ATOK = `SYNTHatok${hex(12)}`;
const VALUE = `SYNTHvalue${crypto.randomBytes(24).toString('base64url')}`;
const NEW_FULL = `c0ffee12${hex(12)}`;
const PIN_P = '86aa993e';
const OLD_P = `${PIN_P}${hex(12)}`;
const OLD_A = `dd6d1427${hex(12)}`;
const OTHER = Array.from({ length: 12 }, () => `aa${hex(15)}`);
const SENTINELS = [ATOK, VALUE, NEW_FULL, OLD_P, OLD_A, ...OTHER];
fs.writeFileSync(sentPath, SENTINELS.join('\n') + '\n', { mode: 0o600 });

const MINT_SRC = fs.readFileSync(mintPath, 'utf8');
const REVOKE_SRC = fs.readFileSync(revokePath, 'utf8');
const MINT_KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error', 'id8'];
const REVOKE_KEYS = ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error'];
const EXPOSED = ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'setImmediate', 'clearImmediate',
  'queueMicrotask', 'URL', 'URLSearchParams', 'TextEncoder', 'TextDecoder', 'AbortController', 'AbortSignal',
  'fetch', 'Headers', 'Request', 'Response', 'FormData', 'Blob', 'Buffer', 'crypto', 'atob', 'btoa',
  'structuredClone'];

let failures = 0;
const ok = (row) => { console.log(`ok ${row}`); };
const bad = (row, why) => { failures += 1; console.log(`FAIL ${row}: ${why}`); };

const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });
const html = (status) => new Response('<html>denied</html>', { status, headers: { 'content-type': 'text/html' } });

const GROUPS = [
  { id: 'g-pagerules-zone', name: 'Page Rules Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-pagerules-decoy', name: 'Page Rules Read', scopes: ['com.cloudflare.api.user'] },
  { id: 'g-analytics', name: 'Analytics Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-zonesettings', name: 'Zone Settings Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-dns', name: 'DNS Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-ssl', name: 'SSL and Certificates Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-fw', name: 'Firewall Services Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: 'g-acctsettings', name: 'Account Settings Read', scopes: ['com.cloudflare.api.account'] },
  { id: 'g-notif', name: 'Notifications Read', scopes: ['com.cloudflare.api.account'] },
  { id: 'g-dns-edit', name: 'DNS Write', scopes: ['com.cloudflare.api.account.zone'] },
];

function makeWorld(over = {}) {
  return {
    atok: ATOK, origin: DASH, groups: GROUPS.map((g) => ({ ...g })),
    userTokens: [
      ...OTHER.slice(0, 7).map((id, i) => ({ id, name: `other-${i}`, status: 'active' })),
      { id: OLD_P, name: 'soleur-pagerules-read', status: 'active' },
    ],
    acctTokens: [
      { id: OLD_A, name: 'cf_api_token_audit-soleur-20261101', status: 'active' },
      ...OTHER.slice(7).map((id, i) => ({ id, name: `acct-other-${i}`, status: 'active' })),
    ],
    pageCap: 5, log: [], gotos: [], deletes: [], sinkCalls: [], pageConsole: [], stored: null,
    mintResp: null, mutateStored: null, sinkMode: 'ok', deleteResp: null, listFail: false, throwOnReadback: false,
    ...over,
  };
}

function page(world) {
  const rec = { log: (...x) => world.pageConsole.push(x.join(' ')) };
  rec.error = rec.log; rec.warn = rec.log; rec.info = rec.log; rec.debug = rec.log;
  const paged = (arr, u) => {
    const per = Math.min(Number(u.searchParams.get('per_page') || 20), world.pageCap);
    const pg = Number(u.searchParams.get('page') || 1);
    const slice = arr.slice((pg - 1) * per, pg * per).map(({ value, ...t }) => t);
    return json(200, { success: true, result: slice, result_info: { page: pg, per_page: per, count: slice.length, total_count: arr.length } });
  };
  const dashFetch = async (path, opts = {}) => {
    const u = new URL(path, DASH);
    const method = (opts.method || 'GET').toUpperCase();
    const h = opts.headers || {};
    world.log.push({ method, path: u.pathname, xatok: h['x-atok'] === world.atok, xcss: h['x-cross-site-security'] === 'dash', body: opts.body });
    if (u.origin !== DASH) throw new TypeError('cross-origin');
    if (h['x-atok'] !== world.atok) return json(403, { success: false, errors: [{ code: 10000 }] });
    if (method === 'DELETE') return html(403);
    const p = u.pathname;
    if (world.listFail && method === 'GET' && /\/tokens$/.test(p)) return json(403, { success: false, errors: [{ code: 9109 }] });
    if (method === 'GET' && p === `/api/v4/accounts/${NA}/tokens/permission_groups`) return json(200, { success: true, result: world.groups });
    if (method === 'GET' && p === `/api/v4/accounts/${NA}/tokens`) return paged(world.acctTokens, u);
    if (method === 'GET' && p === '/api/v4/user/tokens') return paged(world.userTokens, u);
    if (method === 'POST' && p === `/api/v4/accounts/${NA}/tokens`) {
      if (world.mintResp) return world.mintResp();
      const b = JSON.parse(opts.body);
      const byId = Object.fromEntries(world.groups.map((g) => [g.id, g.name]));
      const t = {
        id: NEW_FULL, name: b.name, status: 'active', expires_on: b.expires_on,
        policies: b.policies.map((x, i) => ({ id: `pol${i}`, effect: x.effect, resources: { ...x.resources },
          permission_groups: x.permission_groups.map((g) => ({ id: g.id, name: byId[g.id] })) })),
      };
      world.stored = JSON.parse(JSON.stringify(t));
      if (world.mutateStored) world.mutateStored(world.stored);
      world.acctTokens.push({ id: NEW_FULL, name: b.name, status: 'active' });
      return json(200, { success: true, result: { ...t, value: VALUE } });
    }
    if (method === 'GET' && p === `/api/v4/accounts/${NA}/tokens/${NEW_FULL}`) {
      if (world.throwOnReadback) throw new TypeError('network');
      return world.stored ? json(200, { success: true, result: world.stored }) : json(404, { success: false });
    }
    return json(404, { success: false });
  };
  const pctx = vm.createContext({
    window: { bootstrap: world.atok ? { atok: world.atok } : {} }, location: { origin: world.origin },
    fetch: dashFetch, console: rec, Headers, URL, JSON, Response,
  });
  return {
    async goto(url) { world.gotos.push(url); },
    async evaluate(fn, arg) {
      if (typeof fn !== 'function') throw new TypeError('evaluate(fn)');
      const f = vm.runInContext(`(${fn.toString()})`, pctx);
      const r = await f(arg === undefined ? undefined : JSON.parse(JSON.stringify(arg)));
      return r === undefined ? undefined : JSON.parse(JSON.stringify(r));
    },
    request: {
      async delete(url, opts = {}) {
        const h = (opts && opts.headers) || {};
        const u = new URL(url);
        const okHdr = u.origin === DASH && h['x-atok'] === world.atok && h['x-cross-site-security'] === 'dash';
        world.deletes.push({ path: u.pathname, okHdr });
        const reply = (status, ct, body) => ({ status: () => status, headers: () => ({ 'content-type': ct }),
          json: async () => JSON.parse(body), text: async () => body });
        if (world.deleteResp) return world.deleteResp(reply);
        if (!okHdr) return reply(403, 'application/json', '{"success":false}');
        let m = u.pathname.match(/^\/api\/v4\/user\/tokens\/([0-9a-f]{32})$/);
        let list = world.userTokens;
        if (!m) { m = u.pathname.match(new RegExp(`^/api/v4/accounts/${NA}/tokens/([0-9a-f]{32})$`)); list = world.acctTokens; }
        const i = m ? list.findIndex((t) => t.id === m[1]) : -1;
        if (i < 0) return reply(404, 'application/json', '{"success":false}');
        list.splice(i, 1);
        return reply(200, 'application/json', JSON.stringify({ success: true, result: { id: m[1] } }));
      },
    },
  };
}

function sinkStub(world) {
  return async (url, opts = {}) => {
    world.sinkCalls.push({ url, body: opts.body, method: opts.method });
    if (world.sinkMode === 'down') throw new TypeError('fetch failed');
    if (world.sinkMode === 'refuse') return new Response('refused', { status: 403 });
    return new Response('ok', { status: 200 });
  };
}

// browser_run_code_unsafe, as Playwright MCP 1.64 implements it (coreBundle.js runCode): a fresh vm context
// with `page` and the exposed globals only (no console), `(" + code + ")`, called with page, JSON.stringify'd.
async function runCode(code, world, nodeFetch) {
  const ctx = { page: page(world) };
  for (const n of EXPOSED) ctx[n] = globalThis[n];
  ctx.fetch = nodeFetch;
  vm.createContext(ctx);
  const fn = vm.runInContext(`(${code})`, ctx);
  const result = await fn(ctx.page);
  return JSON.stringify(result);
}
const compose = (src, args) => `(${src})(${JSON.stringify(args)})\n`;

function shapeOk(out, keys) {
  let o;
  try { o = JSON.parse(out); } catch (e) { return 'not JSON'; }
  if (!o || typeof o !== 'object' || Array.isArray(o)) return 'not an object';
  for (const [k, v] of Object.entries(o)) {
    if (!keys.includes(k)) return `key ${k} not allowlisted`;
    const good = { atok: v === false, matches: Number.isInteger(v), refused: typeof v === 'string' && /^[a-z:_-]{1,40}$/.test(v),
      status: Number.isInteger(v), contentType: typeof v === 'string' && v.length <= 64, success: typeof v === 'boolean',
      error: typeof v === 'string' && /^[A-Za-z0-9]{1,40}$/.test(v), id8: typeof v === 'string' && /^[0-9a-f]{8}$/.test(v) }[k];
    if (!good) return `value of ${k} not allowlisted`;
  }
  return null;
}
function leakOf(out, world) {
  for (const s of SENTINELS) if (out.includes(s)) return 'a synthesized secret or full id';
  if (/[0-9a-f]{9,}/i.test(out.replace(/"id8":"[0-9a-f]{8}"/g, ''))) return 'a hex run longer than 8';
  for (const line of world.pageConsole) for (const s of SENTINELS) if (line.includes(s)) return 'page console';
  if (world.pageConsole.length) return 'page console not empty';
  return null;
}

const rows = [];
const row = (name, body, fn) => rows.push({ name, body, fn });

async function exec(name, body, args, world, { nodeFetch, code } = {}) {
  const src = body === 'mint' ? MINT_SRC : REVOKE_SRC;
  const out = await runCode(code || compose(src, args), world, nodeFetch || sinkStub(world));
  const shape = shapeOk(out, body === 'mint' ? MINT_KEYS : REVOKE_KEYS);
  if (shape) throw new Error(`P-shape: ${shape}`);
  const leak = leakOf(out, world);
  if (leak) throw new Error(`P-leak: ${leak}`);
  return JSON.parse(out);
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const must = (cond, why) => { if (!cond) throw new Error(why); };
const nothingSent = (w) => must(w.gotos.length === 0 && w.log.length === 0 && w.deletes.length === 0 && w.sinkCalls.length === 0, 'a request was made before the refusal');

// ---- p5-mint.js --------------------------------------------------------------------------------------------
const MINT_P = { account_id: NA, zone_id: NZ, name: 'cf_api_token_pagerules_read-soleur-20261204',
  zone_groups: ['Page Rules Read'], account_groups: [], expires_on: '2027-02-20T00:00:00Z',
  sink_url: 'http://127.0.0.1:41234/AbCdEfGhIjKlMnOpQrStUv' };
const MINT_A = { ...MINT_P, name: 'cf_api_token_audit-soleur-20261204',
  zone_groups: ['Zone Settings Read', 'DNS Read', 'SSL and Certificates Read', 'Firewall Services Read'],
  account_groups: ['Account Settings Read', 'Notifications Read'] };
const posts = (w) => w.log.filter((l) => l.method === 'POST');

row('M1 pagerules mint: one zone policy on the zone key, scope-resolved group, value to the sink once', 'mint', async () => {
  const w = makeWorld();
  const r = await exec('M1', 'mint', MINT_P, w);
  must(eq(r, { status: 200, contentType: 'application/json', success: true, id8: NEW_FULL.slice(0, 8) }), `return ${JSON.stringify(r)}`);
  must(w.gotos[0] === `${DASH}/profile/api-tokens`, 'no goto to /profile/api-tokens first');
  const p = posts(w); must(p.length === 1 && p[0].xatok && p[0].xcss, 'POST count or headers');
  const b = JSON.parse(p[0].body);
  must(eq(b.policies, [{ effect: 'allow', permission_groups: [{ id: 'g-pagerules-zone' }], resources: { [ZK]: '*' } }]), `policies ${p[0].body}`);
  must(b.expires_on === MINT_P.expires_on && b.name === MINT_P.name, 'name/expiry');
  must(w.sinkCalls.length === 1 && w.sinkCalls[0].body === VALUE && w.sinkCalls[0].url === MINT_P.sink_url && w.sinkCalls[0].method === 'POST', 'sink hand-off');
  must(w.deletes.length === 0, 'a delete on the happy path');
});
row('M2 audit mint: zone groups on the zone key, account groups on the account key only', 'mint', async () => {
  const w = makeWorld();
  const r = await exec('M2', 'mint', MINT_A, w);
  must(r.success === true && r.id8 === NEW_FULL.slice(0, 8), `return ${JSON.stringify(r)}`);
  const b = JSON.parse(posts(w)[0].body);
  must(b.policies.length === 2, 'two policies');
  must(eq(b.policies[0].resources, { [ZK]: '*' }) && eq(b.policies[0].permission_groups.map((g) => g.id), ['g-zonesettings', 'g-dns', 'g-ssl', 'g-fw']), 'zone policy');
  must(eq(b.policies[1].resources, { [AK]: '*' }) && eq(b.policies[1].permission_groups.map((g) => g.id), ['g-acctsettings', 'g-notif']), 'account policy');
});
row('M3 signed out -> {atok:false}, nothing minted', 'mint', async () => {
  const w = makeWorld({ atok: null });
  const r = await exec('M3', 'mint', MINT_P, w);
  must(eq(r, { atok: false }), `return ${JSON.stringify(r)}`); must(posts(w).length === 0 && w.sinkCalls.length === 0, 'minted');
});
row('M4 a missing group name -> {refused:groups, matches:n-1}, nothing minted', 'mint', async () => {
  const w = makeWorld(); w.groups = w.groups.filter((g) => g.name !== 'Notifications Read');
  const r = await exec('M4', 'mint', MINT_A, w);
  must(eq(r, { refused: 'groups', matches: 5 }), `return ${JSON.stringify(r)}`); must(posts(w).length === 0, 'minted');
});
row('M5 an ambiguous zone-scoped name -> refused groups', 'mint', async () => {
  const w = makeWorld(); w.groups.push({ id: 'g-pagerules-zone-2', name: 'Page Rules Read', scopes: ['com.cloudflare.api.account.zone'] });
  const r = await exec('M5', 'mint', MINT_P, w);
  must(eq(r, { refused: 'groups', matches: 0 }), `return ${JSON.stringify(r)}`); must(posts(w).length === 0, 'minted');
});
row('M6 an account token already carries the name -> {refused:name-exists}, nothing minted', 'mint', async () => {
  const w = makeWorld(); w.acctTokens.push({ id: `bb${hex(15)}`, name: MINT_P.name, status: 'active' });
  SENTINELS.push(w.acctTokens[w.acctTokens.length - 1].id);
  const r = await exec('M6', 'mint', MINT_P, w);
  must(eq(r, { refused: 'name-exists', matches: 1 }), `return ${JSON.stringify(r)}`); must(posts(w).length === 0, 'minted');
});
const readbackRow = (tag, why, mutate, args = MINT_P) => row(`M7${tag} read-back fails (${why}) -> new token deleted, sink never called`, 'mint', async () => {
  const w = makeWorld({ mutateStored: mutate });
  const r = await exec(`M7${tag}`, 'mint', args, w);
  must(eq(r, { refused: 'readback', id8: NEW_FULL.slice(0, 8), status: 200, contentType: 'application/json', success: true }), `return ${JSON.stringify(r)}`);
  must(w.sinkCalls.length === 0, 'the value reached the sink');
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${NEW_FULL}`, 'cleanup DELETE');
  must(!w.acctTokens.some((t) => t.id === NEW_FULL), 'token still listed');
});
readbackRow('a', 'zone group on the account-wide key', (t) => { t.policies[0].resources = { [AK]: '*' }; });
readbackRow('b', 'an extra group', (t) => { t.policies[0].permission_groups.push({ id: 'g-dns-edit' }); });
readbackRow('c', 'effect deny', (t) => { t.policies[0].effect = 'deny'; });
readbackRow('d', 'a non-"*" resource value', (t) => { t.policies[0].resources = { [ZK]: { x: '*' } }; });
readbackRow('e', 'expiry drift', (t) => { t.expires_on = '2027-12-31T00:00:00Z'; });
readbackRow('f', 'a wildcard key', (t) => { t.policies[0].resources = { 'com.cloudflare.api.account.zone.*': '*' }; });
readbackRow('g', 'an account group missing', (t) => { t.policies[1].permission_groups.pop(); }, MINT_A);
readbackRow('h', 'name drift', (t) => { t.name = 'cf_api_token_pagerules_read-soleur-20991231'; });
row('M8 sink down -> new token deleted, {refused:sink}', 'mint', async () => {
  const w = makeWorld({ sinkMode: 'down' });
  const r = await exec('M8', 'mint', MINT_P, w);
  must(eq(r, { refused: 'sink', id8: NEW_FULL.slice(0, 8), status: 200, contentType: 'application/json', success: true }), `return ${JSON.stringify(r)}`);
  must(w.deletes.length === 1, 'cleanup DELETE');
});
row('M9 sink refuses (403) -> new token deleted, {refused:sink}', 'mint', async () => {
  const w = makeWorld({ sinkMode: 'refuse' });
  const r = await exec('M9', 'mint', MINT_P, w);
  must(r.refused === 'sink' && w.deletes.length === 1, `return ${JSON.stringify(r)}`);
});
row('M10 the POST answers a JSON 403 -> {status:403, success:false}, no cleanup', 'mint', async () => {
  const w = makeWorld({ mintResp: () => json(403, { success: false, errors: [{ code: 9109 }] }) });
  const r = await exec('M10', 'mint', MINT_P, w);
  must(eq(r, { status: 403, contentType: 'application/json', success: false }), `return ${JSON.stringify(r)}`);
  must(w.deletes.length === 0 && w.sinkCalls.length === 0, 'cleanup or sink');
});
row('M11 a POST that answers an id but no value -> {refused:mint-shape}, deleted', 'mint', async () => {
  const w = makeWorld({ mintResp: () => json(200, { success: true, result: { id: NEW_FULL, name: MINT_P.name } }) });
  const r = await exec('M11', 'mint', MINT_P, w);
  must(r.refused === 'mint-shape' && r.id8 === NEW_FULL.slice(0, 8) && w.deletes.length === 1 && w.sinkCalls.length === 0, `return ${JSON.stringify(r)}`);
});
row('M12 a throw after the mint -> {error:e.name, id8,...} and the token deleted', 'mint', async () => {
  const w = makeWorld({ throwOnReadback: true });
  const r = await exec('M12', 'mint', MINT_P, w);
  must(r.error === 'TypeError' && r.id8 === NEW_FULL.slice(0, 8) && r.success === true && w.deletes.length === 1 && w.sinkCalls.length === 0, `return ${JSON.stringify(r)}`);
});
row('M13 a page off dash.cloudflare.com -> {refused:origin}', 'mint', async () => {
  const w = makeWorld({ origin: 'https://evil.example' });
  const r = await exec('M13', 'mint', MINT_P, w);
  must(eq(r, { refused: 'origin' }) && posts(w).length === 0, `return ${JSON.stringify(r)}`);
});
for (const [field, val] of [['account_id', 'xyz'], ['zone_id', 'not-a-zone'], ['name', 'soleur-pagerules'],
  ['zone_groups', ['DNS Write']], ['zone_groups', []], ['account_groups', ['Account Settings Read', 'Account Settings Read']],
  ['expires_on', '2027-02-20'], ['sink_url', 'http://10.0.0.1:4000/AbCdEfGhIjKlMnOpQrStUv'], ['sink_url', 'https://127.0.0.1:4000/AbCdEfGhIjKlMnOpQrStUv']]) {
  row(`M14 bad ${field} ${JSON.stringify(val).slice(0, 30)} -> {refused:args:${field}} before any request`, 'mint', async () => {
    const w = makeWorld();
    const r = await exec('M14', 'mint', { ...MINT_P, [field]: val }, w);
    must(eq(r, { refused: `args:${field}` }), `return ${JSON.stringify(r)}`); nothingSent(w);
  });
}
row('M15 args not an object -> {refused:args:object}', 'mint', async () => {
  const w = makeWorld(); const r = await exec('M15', 'mint', null, w);
  must(eq(r, { refused: 'args:object' }), `return ${JSON.stringify(r)}`); nothingSent(w);
});

// ---- p5-revoke.js ------------------------------------------------------------------------------------------
const REV = { pin: PIN_P, old_id: PIN_P, new_id: NEW_FULL.slice(0, 8), new_name: 'cf_api_token_pagerules_read-soleur-20261204', scope: 'user' };
row('R1 user-scope revoke over paged lists: Node-side DELETE of the one prefix match with both headers', 'revoke', async () => {
  const w = makeWorld();
  const r = await exec('R1', 'revoke', REV, w);
  must(eq(r, { status: 200, contentType: 'application/json', success: true }), `return ${JSON.stringify(r)}`);
  must(w.gotos[0] === `${DASH}/profile/api-tokens`, 'no goto first');
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/user/tokens/${OLD_P}`, `delete ${JSON.stringify(w.deletes)}`);
  must(w.log.filter((l) => l.path === '/api/v4/user/tokens').length === 2, 'did not page through the list');
  must(!w.log.some((l) => l.method === 'DELETE'), 'an in-page DELETE');
});
row('R2 pin != old_id -> {refused:pin} before any request', 'revoke', async () => {
  const w = makeWorld(); const r = await exec('R2', 'revoke', { ...REV, pin: 'dd6d1427' }, w);
  must(eq(r, { refused: 'pin' }), `return ${JSON.stringify(r)}`); nothingSent(w);
});
row('R3 old_id == new_id -> {refused:same-id} before any request', 'revoke', async () => {
  const w = makeWorld(); const r = await exec('R3', 'revoke', { ...REV, new_id: PIN_P }, w);
  must(eq(r, { refused: 'same-id' }), `return ${JSON.stringify(r)}`); nothingSent(w);
});
row('R4 the match carries the new token name -> {refused:name}, nothing deleted', 'revoke', async () => {
  const w = makeWorld(); w.userTokens.find((t) => t.id === OLD_P).name = REV.new_name;
  const r = await exec('R4', 'revoke', REV, w);
  must(eq(r, { refused: 'name' }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R4b the name match ignores case and spacing', 'revoke', async () => {
  const w = makeWorld(); w.userTokens.find((t) => t.id === OLD_P).name = `  ${REV.new_name.toUpperCase()} `;
  const r = await exec('R4b', 'revoke', REV, w);
  must(eq(r, { refused: 'name' }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R5 zero prefix matches -> {matches:0}', 'revoke', async () => {
  const w = makeWorld(); w.userTokens = w.userTokens.filter((t) => t.id !== OLD_P);
  const r = await exec('R5', 'revoke', REV, w);
  must(eq(r, { matches: 0 }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R5b two prefix matches -> {matches:2}', 'revoke', async () => {
  const w = makeWorld(); const twin = `${PIN_P}${hex(12)}`; SENTINELS.push(twin); w.userTokens.push({ id: twin, name: 'twin' });
  const r = await exec('R5b', 'revoke', REV, w);
  must(eq(r, { matches: 2 }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R6 signed out -> {atok:false}', 'revoke', async () => {
  const w = makeWorld({ atok: null }); const r = await exec('R6', 'revoke', REV, w);
  must(eq(r, { atok: false }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R7 account scope: lists and deletes on /accounts/<acct>/tokens only', 'revoke', async () => {
  const w = makeWorld();
  const r = await exec('R7', 'revoke', { ...REV, pin: 'dd6d1427', old_id: 'dd6d1427', new_name: 'cf_api_token_audit-soleur-20270215', scope: 'account', account_id: NA }, w);
  must(eq(r, { status: 200, contentType: 'application/json', success: true }), `return ${JSON.stringify(r)}`);
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${OLD_A}`, 'account delete path');
  must(!w.log.some((l) => l.path === '/api/v4/user/tokens'), 'read the user list');
});
for (const [tag, over, want] of [['scope', { scope: 'zone' }, 'args:scope'], ['account_id missing', { scope: 'account' }, 'args:account_id'],
  ['account_id with user', { account_id: NA }, 'args:account_id'], ['pin', { pin: '86AA993E' }, 'args:pin'],
  ['old_id', { old_id: '86aa993e00' }, 'args:old_id'], ['new_id', { new_id: '' }, 'args:new_id'], ['new_name', { new_name: 'x' }, 'args:new_name']]) {
  row(`R8 bad ${tag} -> {refused:${want}} before any request`, 'revoke', async () => {
    const w = makeWorld(); const r = await exec('R8', 'revoke', { ...REV, ...over }, w);
    must(eq(r, { refused: want }), `return ${JSON.stringify(r)}`); nothingSent(w);
  });
}
row('R9 the list answers 403 -> {status:403, success:false}', 'revoke', async () => {
  const w = makeWorld({ listFail: true }); const r = await exec('R9', 'revoke', REV, w);
  must(eq(r, { status: 403, contentType: 'application/json', success: false }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});
row('R10 the DELETE answers a JSON 403 -> {status:403, success:false}', 'revoke', async () => {
  const w = makeWorld({ deleteResp: (reply) => reply(403, 'application/json', '{"success":false,"errors":[{"code":9109}]}') });
  const r = await exec('R10', 'revoke', REV, w);
  must(eq(r, { status: 403, contentType: 'application/json', success: false }), `return ${JSON.stringify(r)}`);
});
row('R11 the DELETE answers HTML -> {contentType:text/html, success:false}', 'revoke', async () => {
  const w = makeWorld({ deleteResp: (reply) => reply(403, 'text/html', '<html>no</html>') });
  const r = await exec('R11', 'revoke', REV, w);
  must(eq(r, { status: 403, contentType: 'text/html', success: false }), `return ${JSON.stringify(r)}`);
});
row('R12 a page off dash.cloudflare.com -> {refused:origin}', 'revoke', async () => {
  const w = makeWorld({ origin: 'https://evil.example' }); const r = await exec('R12', 'revoke', REV, w);
  must(eq(r, { refused: 'origin' }) && w.deletes.length === 0, `return ${JSON.stringify(r)}`);
});

// ---- composed run files (P-compose) and the real sink (integration) -----------------------------------------
if (process.env.P5_RUNFILE_REVOKE) {
  row('C1 the shell-composed revoke run file runs under the run_code wrapping', 'revoke', async () => {
    const w = makeWorld(); const r = await exec('C1', 'revoke', null, w, { code: fs.readFileSync(process.env.P5_RUNFILE_REVOKE, 'utf8') });
    must(eq(r, { status: 200, contentType: 'application/json', success: true }), `return ${JSON.stringify(r)}`);
    must(fs.readFileSync(process.env.P5_RUNFILE_REVOKE, 'utf8') === compose(REVOKE_SRC, JSON.parse(process.env.P5_ARGS_REVOKE)), 'shell composition differs from the harness formula');
  });
}
if (process.env.P5_RUNFILE_MINT) {
  row('C2 the shell-composed mint run file runs under the run_code wrapping', 'mint', async () => {
    const w = makeWorld(); const r = await exec('C2', 'mint', null, w, { code: fs.readFileSync(process.env.P5_RUNFILE_MINT, 'utf8') });
    must(r.success === true && w.sinkCalls.length === 1, `return ${JSON.stringify(r)}`);
  });
}
if (MODE === 'integration') {
  rows.length = 0;
  row('I1 mint -> the real p5-sink.py over 127.0.0.1: file holds the value byte-exact', 'mint', async () => {
    const w = makeWorld();
    const r = await exec('I1', 'mint', { ...MINT_P, sink_url: process.env.P5_SINK_URL }, w, { nodeFetch: globalThis.fetch });
    must(r.success === true && r.id8 === NEW_FULL.slice(0, 8), `return ${JSON.stringify(r)}`);
    must(fs.readFileSync(process.env.P5_OUT, 'utf8') === VALUE, 'file content differs from the minted value');
    must(w.deletes.length === 0, 'cleanup on the happy path');
  });
}

for (const r of rows) {
  if (ONLY.length && !ONLY.some((o) => r.name.startsWith(`${o} `))) continue;
  try { await r.fn(); ok(r.name); } catch (e) { bad(r.name, String(e && e.message).slice(0, 300)); }
}
process.exit(failures ? 1 : 0);
HARNESS

H_OUT="$SB/h.out"
harness() { # <mint> <revoke> [env...] -> prints harness lines into $H_OUT, appends to ALL_OUT
  local m="$1" r="$2"; shift 2
  env "$@" node "$SB/harness.mjs" "$m" "$r" "$SENT" > "$H_OUT" 2>&1
  local rc=$?
  cat "$H_OUT" >> "$ALL_OUT"
  return "$rc"
}
relay() { # turn harness lines into suite assertions
  local line
  while IFS= read -r line; do
    case "$line" in
      "ok "*) pass "${line#ok }" ;;
      "FAIL "*) fail "${line#FAIL }" ;;
      *) fail "harness printed an unexpected line: $(printf '%s' "$line" | cut -c1-200)" ;;
    esac
  done < "$H_OUT"
}

# --- sink helpers ------------------------------------------------------------------------------------------
cat > "$SB/client.py" <<'CLIENT'
import http.client, sys
url, src, origin, method, body_file = sys.argv[1:6]
rest = url[len("http://"):]
hostport, _, path = rest.partition("/")
host, _, port = hostport.partition(":")
if len(sys.argv) > 6:
    host = sys.argv[6]
body = open(body_file, "rb").read() if body_file != "-" else None
kw = {"timeout": 10}
if src != "-":
    kw["source_address"] = (src, 0)
try:
    c = http.client.HTTPConnection(host, int(port), **kw)
    h = {"Content-Type": "text/plain"}
    if origin != "-":
        h["Origin"] = origin
    c.request(method, "/" + path, body=body, headers=h)
    r = c.getresponse()
    print("status=%d body=%s" % (r.status, r.read().decode("ascii", "replace")[:20]))
except ConnectionRefusedError:
    print("conn=refused")
except OSError as e:
    print("conn=error:" + type(e).__name__)
CLIENT
SVAL="SYNTHsinkvalue$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s' "$SVAL" > "$SB/sval"; chmod 600 "$SB/sval"
printf '%s\n' "$SVAL" >> "$SB/sink-sentinels"
SINK_PID=""; SINK_URL=""
sink_start() { # <out> [sink path]; sets SINK_PID SINK_URL; sink stdout -> $SB/sink.<n>.out
  local out="$1" src="${2:-$SINK}"
  SINK_N=$(( ${SINK_N:-0} + 1 )); SINK_LOG="$SB/sink.${SINK_N}.out"
  python3 -I "$src" --out "$out" --timeout 30 > "$SINK_LOG" 2>&1 &
  SINK_PID=$!; SINK_URL=""
  local i
  for ((i = 0; i < 200; i++)); do
    SINK_URL="$(sed -n 's/^SOLEUR_P5_SINK url=//p' "$SINK_LOG")"
    [[ -n "$SINK_URL" ]] && return 0
    kill -0 "$SINK_PID" 2>/dev/null || break
    sleep 0.05
  done
  return 1
}
sink_wait() { wait "$SINK_PID"; SINK_RC=$?; cat "$SINK_LOG" >> "$ALL_OUT"; }
client() { python3 -I "$SB/client.py" "$@" 2>&1 | tee -a "$ALL_OUT"; }
port_of() { local hp="${1#http://}"; hp="${hp%%/*}"; printf '%s' "${hp#*:}"; }

run_sink_rows() { # <sink path>
  local S="$1" d
  d="$SB/sinkrows.$RANDOM"; mkdir -m 700 "$d"
  # S1: bound to 127.0.0.1 only; one request; mode 0600; second request finds no listener.
  sink_start "$d/s1.tok" "$S" || { fail "S1 sink did not print its url"; return; }
  OUT="$(client "$SINK_URL" - - POST "$SB/sval" 127.0.0.2)"
  [[ "$OUT" == conn=refused ]]; check "S1a a connect to 127.0.0.2 (not the bound address) is refused" $?
  OUT="$(client "$SINK_URL" - - POST "$SB/sval")"
  [[ "$OUT" == "status=200 body=ok" ]]; check "S1b the one POST from 127.0.0.1 to /<nonce> answers 200 ok" $?
  sink_wait
  [[ "$SINK_RC" -eq 0 ]] && grep -qx 'SOLEUR_P5_SINK result=written' "$SINK_LOG"; check "S1c the sink exits 0 with result=written" $?
  [[ "$(stat -c %a "$d/s1.tok" 2>/dev/null)" == 600 ]]; check "S1d the written file is mode 0600" $?
  cmp -s "$d/s1.tok" "$SB/sval"; check "S1e the file holds the body byte-exact" $?
  printf 'SYNTHsecondvalue00000000000' > "$d/v2"
  OUT="$(client "$SINK_URL" - - POST "$d/v2")"
  [[ "$OUT" == conn=refused ]] && cmp -s "$d/s1.tok" "$SB/sval"; check "S1f a second request finds no listener and the file is unchanged" $?
  [[ "$(wc -l < "$SINK_LOG")" -eq 2 ]]; check "S1g the sink printed exactly two lines (url, result)" $?
  # S2: a peer that is not 127.0.0.1 is refused, writes nothing, and still ends the sink.
  sink_start "$d/s2.tok" "$S" || { fail "S2 sink did not start"; return; }
  OUT="$(client "$SINK_URL" 127.0.0.2 - POST "$SB/sval")"
  [[ "$OUT" == status=403* ]]; check "S2a a 127.0.0.2 peer gets 403" $?
  sink_wait
  [[ "$SINK_RC" -eq 1 && ! -e "$d/s2.tok" ]] && grep -qx 'SOLEUR_P5_SINK result=refused reason=peer' "$SINK_LOG"; check "S2b reason=peer, exit 1, no file" $?
  OUT="$(client "$SINK_URL" - - POST "$SB/sval")"
  [[ "$OUT" == conn=refused && ! -e "$d/s2.tok" ]]; check "S2c a valid request after the refusal finds no listener" $?
  # S3-S6: wrong path, Origin header, GET, bad body: each refused with its reason and no file.
  local tag how reason
  for tag in path origin method body; do
    sink_start "$d/s-$tag.tok" "$S" || { fail "S-$tag sink did not start"; continue; }
    case "$tag" in
      path)   OUT="$(client "${SINK_URL%/*}/wrongnoncewrongnonce" - - POST "$SB/sval")"; reason=path ;;
      origin) OUT="$(client "$SINK_URL" - https://dash.cloudflare.com POST "$SB/sval")"; reason=origin ;;
      method) OUT="$(client "$SINK_URL" - - GET -)"; reason=method ;;
      body)   printf 'SYNTH bad value with spaces\n' > "$d/bad"; OUT="$(client "$SINK_URL" - - POST "$d/bad")"; reason=body ;;
    esac
    sink_wait
    [[ "$SINK_RC" -eq 1 && ! -e "$d/s-$tag.tok" ]] && grep -qx "SOLEUR_P5_SINK result=refused reason=$reason" "$SINK_LOG"
    check "S3-$tag the first request refused reason=$reason, no file" $?
  done
  # S7: --out refusals before binding.
  : > "$d/exists"
  mkdir -p "$d/g/.git" "$d/g/sub"
  for how in "exists:$d/exists" "relative:rel.tok" "in-git:$d/g/sub/t.tok" "parent:$d/nodir/t.tok"; do
    OUT="$(python3 -I "$S" --out "${how#*:}" --timeout 2 2>&1)"; local rc=$?
    printf '%s\n' "$OUT" >> "$ALL_OUT"
    [[ "$rc" -eq 2 && "$OUT" == "SOLEUR_P5_SINK result=refused reason=out-${how%%:*}" ]]
    check "S7-${how%%:*} --out refused (exit 2) before binding" $?
  done
}

# --- P-pin ---------------------------------------------------------------------------------------------------
echo "== P-pin: manifest =="
MDIR="$(dirname "$MANIFEST")"
OUT="$(cd "$MDIR" && sha256sum -c p5-browser.sha256 2>&1)"; check "p5-browser.sha256 verifies (sha256sum -c)" $?
OUT="$(awk '{print $2}' "$MANIFEST" | sort | tr '\n' ' ')"
[[ "$OUT" == "p5-mint.js p5-revoke.js p5-sink.py " ]]; check "the manifest lists exactly p5-mint.js, p5-revoke.js, p5-sink.py" $?
[[ "$(awk 'NF!=2 || $1 !~ /^[0-9a-f]{64}$/' "$MANIFEST" | wc -l)" -eq 0 ]]; check "every manifest line is <sha256>  <file>" $?
cites=0; bad_cite=0
if [[ -r "$RUNBOOK" ]]; then
  while read -r f h; do
    cites=$((cites + 1))
    want="$(awk -v f="$f" '$2==f{print $1}' "$MANIFEST")"
    [[ "$h" == "$want" ]] || { bad_cite=1; OUT="runbook cites $f sha256=$h, manifest $want"; }
  done < <(perl -ne 'while (/\b(p5-(?:mint\.js|revoke\.js|sink\.py)) sha256=([0-9a-f]{64})\b/g) { print "$1 $2\n" }' "$RUNBOOK")
fi
[[ "$bad_cite" -eq 0 ]]; check "every runbook \`<file> sha256=<hex>\` citation (${cites} found) equals the manifest" $?
for f in "$MINT" "$REVOKE"; do
  OUT="$(tail -c 2 "$f" | od -An -c | tr -d ' ')"
  [[ "$OUT" == '}\n' ]]; check "$(basename "$f") ends in the function's closing brace (no trailing ;) for the composition line" $?
  OUT="$(grep -c 'console\.' "$f")"; [[ "$OUT" -eq 0 ]]; check "$(basename "$f") never calls console" $?
done
OUT="$(grep -nE 'print\(' "$SINK")"
[[ -z "$OUT" ]]; check "p5-sink.py has no print() (its only output is say())" $?

if [[ "$MODE" == full ]]; then
  echo "== P-shape / P-leak / P-revoke / P-mint: bodies under the run_code emulation =="
  harness "$MINT" "$REVOKE"; relay

  echo "== P-compose: the documented shell composition =="
  RA='{"pin":"86aa993e","old_id":"86aa993e","new_id":"c0ffee12","new_name":"cf_api_token_pagerules_read-soleur-20261204","scope":"user"}'
  MA='{"account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_pagerules_read-soleur-20261204","zone_groups":["Page Rules Read"],"account_groups":[],"expires_on":"2027-02-20T00:00:00Z","sink_url":"http://127.0.0.1:41234/AbCdEfGhIjKlMnOpQrStUv"}'
  { printf '('; cat "$REVOKE"; printf ')(%s)\n' "$RA"; } > "$SB/p5-revoke.run.js"
  { printf '('; cat "$MINT"; printf ')(%s)\n' "$MA"; } > "$SB/p5-mint.run.js"
  harness "$MINT" "$REVOKE" P5_ONLY=C1,C2 P5_RUNFILE_REVOKE="$SB/p5-revoke.run.js" P5_ARGS_REVOKE="$RA" P5_RUNFILE_MINT="$SB/p5-mint.run.js"; relay
  [[ "$(grep -c '^ok C' "$H_OUT")" -eq 2 ]]; check "both composition rows ran" $?

  echo "== P-sink =="
  run_sink_rows "$SINK"

  echo "== integration: p5-mint.js -> the real p5-sink.py =="
  d="$SB/integ"; mkdir -m 700 "$d"
  if sink_start "$d/cf_api_token_pagerules_read.tok"; then
    harness "$MINT" "$REVOKE" P5_MODE=integration P5_SINK_URL="$SINK_URL" P5_OUT="$d/cf_api_token_pagerules_read.tok"; relay
    sink_wait
    [[ "$SINK_RC" -eq 0 && "$(stat -c %a "$d/cf_api_token_pagerules_read.tok")" == 600 ]]; check "I1 the sink wrote the minted value at mode 0600 and exited 0" $?
  else
    fail "I1 sink did not start"
  fi

  echo "== P-leak: every captured line =="
  cat "$SENT" "$SB/sink-sentinels" > "$SB/all-sentinels"
  [[ "$(wc -l < "$SB/all-sentinels")" -ge 10 ]]; check "the sentinel list is populated (instrument)" $?
  OUT="$(grep -cF -f "$SB/all-sentinels" "$ALL_OUT")"
  [[ "$OUT" -eq 0 ]]; check "no synthesized value, atok or full id in any captured output ($(wc -l < "$ALL_OUT") lines)" $?
  OUT="$(grep -v '^SOLEUR_P5_SINK url=' "$ALL_OUT" | grep -cE '[0-9a-f]{9,}')"   # the url line's nonce is random base64url
  [[ "$OUT" -eq 0 ]]; check "no hex run longer than 8 in any captured output" $?
fi

# --- mutations ---------------------------------------------------------------------------------------------
echo "== mutations =="
mutate() { # <src> <dst> <perl literal from> <perl literal to>: proven to land
  cp "$1" "$2"
  FROM="$3" TO="$4" perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$2"
  ! cmp -s "$1" "$2"
}
killed_row() { # <label> <mint> <revoke> <row>
  harness "$2" "$3" P5_ONLY="$4"
  grep -q "^FAIL $4 " "$H_OUT" && ! grep -q "^ok $4 " "$H_OUT"
}
M="$SB/mut"; mkdir -m 700 "$M"
mutate "$REVOKE" "$M/xr1.js" "if (a.pin !== a.old_id) return safe({ refused: 'pin' });" ""; check "XR1 lands" $?
killed_row XR1 "$MINT" "$M/xr1.js" R2; check "XR1 (pin guard deleted) turns R2 RED" $?
mutate "$REVOKE" "$M/xr2.js" "if (a.old_id === a.new_id) return safe({ refused: 'same-id' });" ""; check "XR2 lands" $?
killed_row XR2 "$MINT" "$M/xr2.js" R3; check "XR2 (same-id guard deleted) turns R3 RED" $?
mutate "$REVOKE" "$M/xr3.js" "if (typeof target.name === 'string' && norm(target.name) === norm(a.new_name)) return safe({ refused: 'name' });" ""; check "XR3 lands" $?
killed_row XR3 "$MINT" "$M/xr3.js" R4; check "XR3 (name guard deleted) turns R4 RED" $?
mutate "$MINT" "$M/xm1.js" "if (k === zoneKey) {" "if (k === zoneKey || k === acctKey) {"; check "XM1 lands" $?
killed_row XM1 "$M/xm1.js" "$REVOKE" M7a; check "XM1 (account key accepted for zone groups) turns M7a RED" $?
mutate "$MINT" "$M/xm2.js" "if (same !== 0) return safe({ refused: 'name-exists', matches: same });" ""; check "XM2 lands" $?
killed_row XM2 "$M/xm2.js" "$REVOKE" M6; check "XM2 (one-token-per-key deleted) turns M6 RED" $?
# Instrument rows: the P-shape/P-leak check and the page-serialization emulation must each catch a real slip.
mutate "$REVOKE" "$M/xl1.js" "return safe({ status: r.status(), contentType, success });" "return { status: r.status(), contentType, success, atok: l.atok };"; check "XL1 lands" $?
killed_row XL1 "$MINT" "$M/xl1.js" R1; check "XL1 (DELETE return bypasses the guard and carries the atok) turns R1 RED" $?
mutate "$REVOKE" "$M/xl2.js" "t.id.startsWith(prefix)) hits.push" "t.id.startsWith(a.old_id)) hits.push"; check "XL2 lands" $?
killed_row XL2 "$MINT" "$M/xl2.js" R1; check "XL2 (an in-page function closes over a Node-side variable) turns R1 RED" $?
mutate "$SINK" "$M/xs1.py" 'if self.client_address[0] != "127.0.0.1":' 'if False:'; check "XS1 lands" $?
PASS_BEFORE=$PASS FAIL_BEFORE=$FAIL
( PASS=0; FAIL=0; run_sink_rows "$M/xs1.py" >/dev/null 2>&1; [[ "$FAIL" -gt 0 ]] ); check "XS1 (sink peer check deleted) turns the S2 rows RED" $?
PASS=$PASS_BEFORE FAIL=$FAIL_BEFORE

# --- anti-vacuity floor (reported directly, never through fail()) -----------------
TOTAL=$((PASS + FAIL))
SELFTEST_PASSES=1
MIN_ASSERTIONS_FULL=95
if [[ "$MODE" == full && $((TOTAL - SELFTEST_PASSES)) -lt "$MIN_ASSERTIONS_FULL" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran in full mode, floor is %s\n' "$((TOTAL - SELFTEST_PASSES))" "$MIN_ASSERTIONS_FULL" >&2
  printf 'Total: %s assertions, %s failed\n' "$TOTAL" "$((FAIL + 1))"
  exit 1
fi
MIN_ASSERTIONS_MUTANTS=20
if [[ "$MODE" == mutants && $((TOTAL - SELFTEST_PASSES)) -lt "$MIN_ASSERTIONS_MUTANTS" ]]; then
  printf '  [FAIL] anti-vacuity floor: only %s assertions ran in --mutants mode, floor is %s\n' "$((TOTAL - SELFTEST_PASSES))" "$MIN_ASSERTIONS_MUTANTS" >&2
  printf 'Total: %s assertions, %s failed\n' "$TOTAL" "$((FAIL + 1))"
  exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed (mode=${MODE})"
[[ "$FAIL" -eq 0 ]]
