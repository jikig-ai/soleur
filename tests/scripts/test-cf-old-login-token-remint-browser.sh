#!/usr/bin/env bash
# test-cf-old-login-token-remint-browser.sh — the #12931 Phase 5 token slice's committed dashboard browser
# bodies (CTO rulings D1, D7, D8, D9): p5-mint.js, p5-revoke.js, p5-read.js and the one-shot hand-off sink
# p5-sink.py, all beside bootstrap.sh in the feat-one-shot-12931-phase5-token-remint spec directory, pinned by
# p5-browser.sha256.
#
#   bash tests/scripts/test-cf-old-login-token-remint-browser.sh            every row, then every mutant
#   bash tests/scripts/test-cf-old-login-token-remint-browser.sh --mutants  the mutation section only
#
# PROPERTIES
#   P-pin     p5-browser.sha256 lists exactly the four files and `sha256sum -c` passes; the runbook is
#             readable and carries at least 5 sha256 citations (`<file> sha256=<hex>` or the hold form
#             `` `<file>` (sha256=<hex>) ``), each equal to that file's sha256.
#   P-shape   every return of every body carries only allowlisted keys with allowlisted value types (an
#             independent allowlist here, not the body's own guard).
#   P-leak    no return, page console line, sink line or harness line carries the stub's synthesized token
#             value, atok, any 12-character window of either, or any full token id (nor any hex run over 8).
#   P-revoke  refusals before any request: pin != old_id, old_id == new_id, a user-scope old_id that is not a
#             committed old pin; after the list: a name equal to new_name, a replacement-shaped name (user
#             scope), no single live replacement (account scope); 0 or 2 prefix matches; paging without
#             total_count; user and account endpoints; DELETE Node-side with both headers. Retire mode (D8):
#             exact retire_name, never an old pin.
#   P-mint    group resolution by name AND scope (decoy listed first); one token per EXACT name (a different
#             date suffix does not block); paging without total_count; expires_on >= now + 30 days; owner
#             account|user (D7) with the old-owner pin refusal; read-back failures (account-wide resource,
#             another zone, another account, extra group, deny, non-"*" value, expiry, name or status drift)
#             and sink failures (down, refused, not "ok", redirected) run the cleanup and never reach the sink;
#             the cleanup re-lists by name after ANY post-POST failure (error, non-JSON, bad id, throw) and
#             reports success:true only on a verified-clean re-list; the happy path hands the value off once.
#             The token POST is ONE Node-side page.request.post (JSON body, maxRedirects 0, failOnStatusCode
#             false, answer never read as text, disposed); the stub answers an in-page POST or DELETE with the
#             dashboard edge's HTML 403 (measured 2026-11-26 and 2026-11-28), so an in-page write cannot pass.
#   P-read    p5-read.js: groups (account and user scope), policies (names, counts, key kinds only), every
#             refusal, GET only.
#   P-sink    binds 127.0.0.1 only; serves one request then no listener; refuses a 127.0.0.2 peer, a wrong
#             path, an Origin header, a GET, a short Content-Length, a bad body; times out; a failed fsync
#             unlinks the file and refuses `write`; writes mode 0600; refuses an --out that exists, is
#             relative, has no parent, or sits in a git work tree (a .git directory or a .git FILE).
#   P-wait    each body waits once, after its last goto, for window.bootstrap.atok (set ~283 ms after
#             DOMContentLoaded, measured 2026-11-28, recorded in
#             knowledge-base/project/plans/archive/20261128-131628-2026-11-28-fix-p5-browser-bodies-wait-for-atok-plan.md) with a
#             timeout in [1000, 30000] ms, interval polling below it, and a condition that is true only when
#             the atok is set (L1-L3); a signed-out page still returns {atok:false} (M3, R6, D7).
#   P-holds   the archived plan's Operator Holds equal the runbook's section 6 holds, modulo an exact
#             sha256=<64 hex> value (CTO F5; the archived plan is never edited on a re-pin).
#   P-compose the runbook's section 5 composition line (read from the runbook, placeholders filled) yields a
#             run file that the browser_run_code_unsafe wrapping runs, byte-equal to
#             `(<body>)(JSON.parse(<json string>))`; a JavaScript-expression argument is DATA: refused at jq
#             or received as a string, and no side effect runs (CTO D9).
#
# ASSEMBLY. A node harness (written to the sandbox) emulates browser_run_code_unsafe exactly as Playwright MCP
# does: a vm context holding only `page` and its exposed globals (no console), `(" + code + ")` evaluated, then
# called with page and JSON.stringify'd. The stub page serializes every page.evaluate function by toString()
# into a separate "page" vm context (window.bootstrap.atok, location.origin, a stub dash fetch), so a body that
# closes over a Node-side variable inside an in-page function fails here as it would in the browser. In-page
# DELETE answers the HTML 403 the dashboard edge gave on 2026-11-26. Values are synthesized sentinels
# (cq-test-fixtures-synthesized-only); the account and zone ids are the runbook's public id table. Nothing
# reaches a network beyond 127.0.0.1. The sandbox is created under the first of $TMPDIR, /var/tmp, /tmp that
# sits outside every git work tree (the sink refuses an --out inside one); the EXIT trap reaps every sink.
#
# MUTATIONS (--mutants, and the tail of a full run). Every scored row first runs GREEN on the pristine bodies
# (else exit 2); a mutant must land (cmp differs) and its row's FAIL text must name the expected outcome.
#   XR1 pin guard deleted -> R2            XR2 same-id guard deleted -> R3      XR3 name guard deleted -> R4
#   XR4 old-pin allowlist deleted -> R8u   XR5 soleur-name guard deleted -> R4c XR6 live-replacement check -> R7b
#   XR7 paging ends on the requested per_page -> R1b                           XR8 retire-name guard -> R13c
#   XR9 retire old-pin guard deleted -> R13d
#   XM1 account key accepted for zone groups -> M7a     XM2 one-token-per-exact-name deleted -> M6
#   XM3 cleanup verdict starts true -> M16f             XM4 a DELETE starts as ok -> M16a
#   XM5 no cleanup after a non-JSON POST -> M16c        XM6 sink redirect followed -> M9c
#   XM7 mint paging ends on the requested per_page -> M6c                      XM8 30-day expiry floor deleted -> M17
#   XM9 old-owner-login refusal deleted -> M18b         XM10 owner user posts to the account endpoint -> M18a
#   XM11 the cleanup ignores the answered id (a drifted stored name survives) -> M7h
#   XS1 sink peer check deleted -> S2b                  XS2 sink keeps a partial file on a failed fsync -> S8
#   XW1 the read wait deleted -> L1     XW2 the mint wait deleted -> L2     XW3 the revoke wait deleted -> L3
#   XW4 the read wait's .catch dropped -> D7 ({error:TimeoutError})
#   XW5 the read wait moved above its goto -> L1   XW6 a second goto after the revoke wait -> L3
#   XW7 the read wait timeout 15 ms -> L1          XW8 the read wait polls 'raf' -> L1
#   XW9 the read wait called with two arguments (no options) -> L1
#   XW10 the read wait condition true before the atok (!!window.bootstrap) -> L1
#   XW11 the mint wait's .catch dropped -> M3      XW12 the revoke wait's .catch dropped -> R6
#   XH1 wording after the sha on a sha-bearing runbook hold edited -> the sha-normalized hold compare
#   XC1 a runbook sha written outside the <body> (sha256=<hex>) form -> the runbook citation check
#   Instrument: XL1 a revoke return that bypasses the guard and carries the atok -> R1 (P-shape);
#               XL2 an in-page function closing over a Node-side variable -> R1 (page serialization);
#               XL3 a read return that bypasses the guard with resource keys -> D5 (P-shape)
#
# LOCATION: finds its files by glob, so an archive-kb move of the spec directory breaks nothing.
# The pristine and mutant sink runs reset FAIL inside a ( ) subshell on purpose: their rows must not count.
# shellcheck disable=SC2030,SC2031
set -uo pipefail

export LC_ALL=C

MODE=full
case "${1:-}" in
  "") ;;
  --mutants) MODE=mutants ;;
  *) printf 'usage: %s [--mutants]\n' "$0" >&2; exit 2 ;;
esac

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SUITE_DIR" rev-parse --show-toplevel 2>/dev/null)" || { printf 'HARNESS: not in a git work tree\n' >&2; exit 2; }
find_one() { # <name> -> absolute path, exactly one match (bash-3.2 safe: no mapfile)
  local f n=0 hit=""
  while IFS= read -r f; do n=$((n + 1)); hit="$f"; done < <(git -C "$REPO_ROOT" ls-files --cached --others \
    --exclude-standard --full-name "*feat-one-shot-12931-phase5-token-remint/$1")
  [[ "$n" -eq 1 ]] || { printf 'HARNESS: expected exactly one %s, found %s\n' "$1" "$n" >&2; exit 2; }
  printf '%s/%s\n' "$REPO_ROOT" "$hit"
}
MINT="$(find_one p5-mint.js)" || exit 2
REVOKE="$(find_one p5-revoke.js)" || exit 2
READ="$(find_one p5-read.js)" || exit 2
SINK="$(find_one p5-sink.py)" || exit 2
MANIFEST="$(find_one p5-browser.sha256)" || exit 2
RUNBOOK="${REPO_ROOT}/knowledge-base/engineering/operations/runbooks/cloudflare-old-login-token-remint.md"

for bin in node python3 sha256sum stat cmp perl jq; do command -v "$bin" >/dev/null 2>&1 || { printf 'HARNESS: %s is required\n' "$bin" >&2; exit 2; }; done

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); echo "  [ok] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  [FAIL] $1" >&2; }
check() { if [[ "$2" -eq 0 ]]; then pass "$1"; else fail "$1 (last out: $(printf '%s' "${OUT:-}" | tr '\n' ' ' | cut -c1-400))"; fi; }

# Instrument self-test (ADR-193 shape): both helpers must move their counter, or nothing below means anything.
check "instrument self-test (pass arm)" 0 >/dev/null
check "instrument self-test (fail arm)" 1 >/dev/null 2>&1
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then printf 'INSTRUMENT SELF-TEST FAILED (pass=%s fail=%s)\n' "$PASS" "$FAIL" >&2; exit 2; fi
FAIL=0

# The sandbox sits outside every git work tree: the sink refuses an --out inside one, and a TMPDIR inside a
# checkout would turn every sink row red for the wrong reason.
outside_git() { # <dir>
  local d
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  while :; do
    [[ -e "$d/.git" ]] && return 1
    [[ "$d" == / ]] && return 0
    d="$(dirname "$d")"
  done
}
SB_BASE=""
for cand in "${TMPDIR:-}" /var/tmp /tmp; do
  if [[ "$cand" == /?* && -d "$cand" && -w "$cand" ]] && outside_git "$cand"; then SB_BASE="$cand"; break; fi
done
[[ -n "$SB_BASE" ]] || { printf 'HARNESS: no writable temp directory outside a git work tree\n' >&2; exit 2; }
export TMPDIR="$SB_BASE"
SB="$(mktemp -d -t cf-p5-browser.XXXXXXXX)" || { printf 'HARNESS: mktemp failed\n' >&2; exit 2; }
case "$SB" in /?*) ;; *) printf 'HARNESS: sandbox path %s is not absolute\n' "$SB" >&2; exit 2 ;; esac
PIDS="$SB/sink.pids"; : > "$PIDS"
reap() {
  local p
  while read -r p; do [[ -n "$p" ]] && kill "$p" 2>/dev/null; done < "$PIDS" 2>/dev/null
  chmod -R u+rwx "$SB" 2>/dev/null; rm -rf "$SB"
}
trap reap EXIT
chmod 700 "$SB"
ALL_OUT="$SB/all-output.log"; : > "$ALL_OUT"
SENT="$SB/sentinels"   # the harness writes its synthesized secrets here (mode 0600) for the P-leak grep

# --- the node harness --------------------------------------------------------------------------------------
cat > "$SB/harness.mjs" <<'HARNESS'
// Emulates Playwright MCP browser_run_code_unsafe and a dash.cloudflare.com page. Prints only `ok <row>` and
// `FAIL <row>: <why>` lines; never a sentinel.
import vm from 'node:vm';
import fs from 'node:fs';
import http from 'node:http';
import crypto from 'node:crypto';

const [mintPath, revokePath, readPath, sentPath] = process.argv.slice(2);
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
const windows = (s) => Array.from({ length: s.length - 11 }, (_, i) => s.slice(i, i + 12));
const SENTINELS = [ATOK, VALUE, NEW_FULL, OLD_P, OLD_A, ...OTHER];
const WINDOWS = [...windows(ATOK), ...windows(VALUE)];
fs.writeFileSync(sentPath, [...SENTINELS, ...WINDOWS].join('\n') + '\n', { mode: 0o600 });
const gid = (k) => crypto.createHash('sha256').update(`synth-group-${k}`).digest('hex').slice(0, 32);
const G = Object.fromEntries(['pagerules', 'decoy', 'analytics', 'zonesettings', 'dns', 'ssl', 'fw', 'acctsettings',
  'notif', 'dnsedit'].map((k) => [k, gid(k)]));
const isoDays = (d) => new Date(Date.now() + d * 86400000).toISOString().replace(/\.\d{3}Z$/, 'Z');
const EXP = isoDays(60);

const SRC = { mint: fs.readFileSync(mintPath, 'utf8'), revoke: fs.readFileSync(revokePath, 'utf8'), read: fs.readFileSync(readPath, 'utf8') };
const KEYS = {
  mint: ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error', 'id8', 'del_status', 'del_contentType'],
  revoke: ['atok', 'matches', 'refused', 'status', 'contentType', 'success', 'error'],
  read: ['atok', 'refused', 'status', 'contentType', 'success', 'error', 'matches', 'groups', 'policies', 'skipped'],
};
const EXPOSED = ['setTimeout', 'clearTimeout', 'setInterval', 'clearInterval', 'setImmediate', 'clearImmediate',
  'queueMicrotask', 'URL', 'URLSearchParams', 'TextEncoder', 'TextDecoder', 'AbortController', 'AbortSignal',
  'fetch', 'Headers', 'Request', 'Response', 'FormData', 'Blob', 'Buffer', 'crypto', 'atob', 'btoa',
  'structuredClone'];

let failures = 0;
const ok = (row) => { console.log(`ok ${row}`); };
const bad = (row, why) => { failures += 1; console.log(`FAIL ${row}: ${why}`); };

const json = (status, obj) => new Response(JSON.stringify(obj), { status, headers: { 'content-type': 'application/json; charset=utf-8' } });
const html = (status) => new Response('<html>denied</html>', { status, headers: { 'content-type': 'text/html' } });

// The scope decoy is listed BEFORE the real group: a body that takes the first name match picks the wrong one.
const GROUPS = [
  { id: G.decoy, name: 'Page Rules Read', scopes: ['com.cloudflare.api.user'] },
  { id: G.pagerules, name: 'Page Rules Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.analytics, name: 'Analytics Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.zonesettings, name: 'Zone Settings Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.dns, name: 'DNS Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.ssl, name: 'SSL and Certificates Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.fw, name: 'Firewall Services Read', scopes: ['com.cloudflare.api.account.zone'] },
  { id: G.acctsettings, name: 'Account Settings Read', scopes: ['com.cloudflare.api.account'] },
  { id: G.notif, name: 'Notifications Read', scopes: ['com.cloudflare.api.account'] },
  { id: G.dnsedit, name: 'DNS Write', scopes: ['com.cloudflare.api.account.zone'] },
];

function makeWorld(over = {}) {
  return {
    atok: ATOK, origin: DASH, groups: GROUPS.map((g) => ({ ...g })), userGroups: null,
    userTokens: [
      ...OTHER.slice(0, 7).map((id, i) => ({ id, name: `other-${i}`, status: 'active' })),
      { id: OLD_P, name: 'soleur-pagerules-read', status: 'active' },
    ],
    acctTokens: [
      { id: OLD_A, name: 'cf_api_token_audit-soleur-20261101', status: 'active' },
      ...OTHER.slice(7).map((id, i) => ({ id, name: `acct-other-${i}`, status: 'active' })),
    ],
    pageCap: 5, noTotal: false, endless: false, log: [], gotos: [], deletes: [], sinkCalls: [], pageConsole: [],
    mintResp: null, mutateStored: null, sinkMode: 'ok', deleteResp: null, listFail: false, throwOnReadback: false,
    onGetToken: null, win: null, lateAtok: false, waits: [], postText: 0, postDisposed: 0,
    ...over,
  };
}

function page(world) {
  const rec = { log: (...x) => world.pageConsole.push(x.join(' ')) };
  rec.error = rec.log; rec.warn = rec.log; rec.info = rec.log; rec.debug = rec.log;
  const paged = (arr, u) => {
    const per = Math.min(Number(u.searchParams.get('per_page') || 20), world.pageCap);
    const pg = Number(u.searchParams.get('page') || 1);
    const src = world.endless ? Array.from({ length: per }, (_, i) => ({ id: OTHER[i % OTHER.length], name: `endless-${i}` })) : arr;
    const slice = (world.endless ? src : src.slice((pg - 1) * per, pg * per)).map(({ value, ...t }) => t);
    const info = { page: pg, per_page: per, count: slice.length };
    if (!world.noTotal && !world.endless) info.total_count = arr.length;
    return json(200, { success: true, result: slice, result_info: info });
  };
  const tokenList = (p) => (p.startsWith('/api/v4/user/') ? world.userTokens : world.acctTokens);
  const create = (p, b) => {
    const byId = Object.fromEntries(world.groups.map((g) => [g.id, g.name]));
    const t = {
      id: NEW_FULL, name: b.name, status: 'active', expires_on: b.expires_on,
      policies: b.policies.map((x, i) => ({ id: `pol${i}`, effect: x.effect, resources: { ...x.resources },
        permission_groups: x.permission_groups.map((g) => ({ id: g.id, name: byId[g.id] })) })),
    };
    const stored = JSON.parse(JSON.stringify(t));
    if (world.mutateStored) world.mutateStored(stored);
    tokenList(p).push(stored);
    return json(200, { success: true, result: { ...t, value: VALUE } });
  };
  const dashFetch = async (path, opts = {}) => {
    const u = new URL(path, DASH);
    const method = (opts.method || 'GET').toUpperCase();
    const h = opts.headers || {};
    world.log.push({ method, path: u.pathname, xatok: h['x-atok'] === world.atok, xcss: h['x-cross-site-security'] === 'dash', body: opts.body, via: 'page' });
    if (u.origin !== DASH) throw new TypeError('cross-origin');
    if (h['x-atok'] !== world.atok) return json(403, { success: false, errors: [{ code: 10000 }] });
    // The dashboard edge answers an in-page write with an HTML 403 (DELETE measured 2026-11-26, the account
    // token POST 2026-11-28); only the page's request context (page.request) gets through.
    if (method === 'DELETE' || method === 'POST') return html(403);
    const p = u.pathname;
    if (world.listFail && method === 'GET' && /\/tokens$/.test(p)) return json(403, { success: false, errors: [{ code: 9109 }] });
    if (method === 'GET' && p === `/api/v4/accounts/${NA}/tokens/permission_groups`) return json(200, { success: true, result: world.groups });
    if (method === 'GET' && p === '/api/v4/user/tokens/permission_groups') return json(200, { success: true, result: world.userGroups || world.groups });
    if (method === 'GET' && p === `/api/v4/accounts/${NA}/tokens`) return paged(world.acctTokens, u);
    if (method === 'GET' && p === '/api/v4/user/tokens') return paged(world.userTokens, u);
    const m = p.match(new RegExp(`^/api/v4/(?:accounts/${NA}|user)/tokens/([0-9a-f]{32})$`));
    if (method === 'GET' && m) {
      if (world.onGetToken) world.onGetToken(world);
      if (world.throwOnReadback) throw new TypeError('network');
      const t = tokenList(p).find((x) => x.id === m[1]);
      return t ? json(200, { success: true, result: JSON.parse(JSON.stringify(t)) }) : json(404, { success: false });
    }
    return json(404, { success: false });
  };
  // lateAtok: the page loads with no window.bootstrap at all; the dashboard sets it only after
  // DOMContentLoaded (measured 2026-11-28: ~283 ms later). Only waitForFunction installs it, after its first
  // falsy poll, and every goto drops it again (a navigation is a new page), so a body that reads the atok
  // without waiting, waits before its goto, navigates again after the wait, or waits on an unguarded
  // condition (it throws on the missing key) cannot pass by accident.
  const win = world.lateAtok ? {} : { bootstrap: world.atok ? { atok: world.atok } : {} };
  world.win = win;
  const pctx = vm.createContext({ window: win, location: { origin: world.origin }, fetch: dashFetch, console: rec, Headers, URL, JSON, Response });
  return {
    async goto(url) { world.gotos.push(url); if (world.lateAtok) delete win.bootstrap; },
    async evaluate(fn, arg) {
      if (typeof fn !== 'function') throw new TypeError('evaluate(fn)');
      const f = vm.runInContext(`(${fn.toString()})`, pctx);
      const r = await f(arg === undefined ? undefined : JSON.parse(JSON.stringify(arg)));
      return r === undefined ? undefined : JSON.parse(JSON.stringify(r));
    },
    // Playwright's signature: waitForFunction(pageFunction, arg, options). Options are read from the THIRD
    // parameter only, as Playwright does; a two-argument call records an undefined timeout and fails the L rows.
    async waitForFunction(fn, arg, opts) {
      if (typeof fn !== 'function') throw new TypeError('waitForFunction(fn)');
      const f = vm.runInContext(`(${fn.toString()})`, pctx);
      const wrec = { timeout: opts && opts.timeout, polling: opts && opts.polling, resolved: false,
        src: fn.toString(), arg };
      world.waits.push(wrec);
      for (let i = 0; i < 3; i += 1) {
        if (await f(arg === undefined ? undefined : JSON.parse(JSON.stringify(arg)))) { wrec.resolved = true; return true; }
        if (i === 0 && world.lateAtok) win.bootstrap = { atok: world.atok };
      }
      const e = new Error('waitForFunction: timeout'); e.name = 'TimeoutError';
      throw e;
    },
    request: {
      // The Node-side token POST. Records the request (in world.log, in order with the in-page calls) and answers
      // a Playwright APIResponse; text() and dispose() are counted so a row can see a body read as text.
      async post(url, opts = {}) {
        const h = (opts && opts.headers) || {};
        const u = new URL(url);
        const data = opts.data === undefined ? undefined : JSON.parse(JSON.stringify(opts.data));
        world.log.push({ method: 'POST', path: u.pathname, xatok: h['x-atok'] === world.atok,
          xcss: h['x-cross-site-security'] === 'dash', ctJson: h['content-type'] === 'application/json',
          body: JSON.stringify(data), via: 'node', maxRedirects: opts.maxRedirects, failOnStatusCode: opts.failOnStatusCode });
        const api = async (resp) => {
          const body = await resp.text();
          return { status: () => resp.status, headers: () => ({ 'content-type': resp.headers.get('content-type') || '' }),
            json: async () => JSON.parse(body), text: async () => { world.postText += 1; return body; },
            body: async () => { world.postText += 1; return Buffer.from(body); },
            dispose: async () => { world.postDisposed += 1; } };
        };
        if (u.origin !== DASH) throw new TypeError('cross-origin');
        if (h['x-atok'] !== world.atok) return api(json(403, { success: false, errors: [{ code: 10000 }] }));
        const p = u.pathname;
        if (!(p === `/api/v4/accounts/${NA}/tokens` || p === '/api/v4/user/tokens')) return api(json(404, { success: false }));
        if (world.mintResp) return api(await world.mintResp(() => create(p, data)));
        return api(create(p, data));
      },
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
    world.sinkCalls.push({ url, body: opts.body, method: opts.method, redirect: opts.redirect });
    if (world.sinkMode === 'down') throw new TypeError('fetch failed');
    if (world.sinkMode === 'refuse') return new Response('refused', { status: 403 });
    if (world.sinkMode === 'notok') return new Response('nope', { status: 200 });
    return new Response('ok', { status: 200 });
  };
}

// browser_run_code_unsafe, as Playwright MCP 1.64 implements it (coreBundle.js runCode): a fresh vm context
// with `page` and the exposed globals only (no console), `(" + code + ")`, called with page, JSON.stringify'd.
async function runCode(code, world, nodeFetch, ctxOut) {
  const ctx = { page: page(world) };
  for (const n of EXPOSED) ctx[n] = globalThis[n];
  ctx.fetch = nodeFetch;
  vm.createContext(ctx);
  if (ctxOut) ctxOut.ctx = ctx;
  const fn = vm.runInContext(`(${code})`, ctx);
  const result = await fn(ctx.page);
  return JSON.stringify(result);
}
// The ruled composition (CTO D9): the argument object as ONE JSON string literal, parsed inside the run file.
const compose = (src, args) => `(${src})(JSON.parse(${JSON.stringify(`${JSON.stringify(args)}\n`)}))\n`;

const NAME_RE = /^[A-Za-z0-9 ,&:()\/.'+_-]{1,100}$/;
function shapeOk(out, keys) {
  let o;
  try { o = JSON.parse(out); } catch (e) { return 'not JSON'; }
  if (!o || typeof o !== 'object' || Array.isArray(o)) return 'not an object';
  const groupGood = (g) => g && typeof g === 'object' && Object.keys(g).every((k) => ['name', 'scopes', 'id8'].includes(k))
    && NAME_RE.test(g.name) && Array.isArray(g.scopes) && g.scopes.every((s) => /^com\.cloudflare\.[a-z.]+$/.test(s))
    && (g.id8 === undefined || /^[0-9a-f]{8}$/.test(g.id8));
  const polGood = (p) => p && typeof p === 'object' && Object.keys(p).every((k) => ['effect', 'groups', 'resources', 'kinds'].includes(k))
    && ['allow', 'deny'].includes(p.effect) && Array.isArray(p.groups) && p.groups.every((n) => typeof n === 'string' && NAME_RE.test(n))
    && Number.isInteger(p.resources) && Array.isArray(p.kinds)
    && p.kinds.every((k) => ['zone', 'all-zones', 'account', 'account-nested', 'all-accounts', 'user', 'other'].includes(k));
  for (const [k, v] of Object.entries(o)) {
    if (!keys.includes(k)) return `key ${k} not allowlisted`;
    const good = { atok: v === false, matches: Number.isInteger(v), skipped: Number.isInteger(v),
      refused: typeof v === 'string' && /^[a-z:_-]{1,40}$/.test(v),
      status: Number.isInteger(v), del_status: Number.isInteger(v),
      contentType: typeof v === 'string' && v.length <= 64, del_contentType: typeof v === 'string' && v.length <= 64,
      success: typeof v === 'boolean', error: typeof v === 'string' && /^[A-Za-z0-9]{1,40}$/.test(v),
      id8: typeof v === 'string' && /^[0-9a-f]{8}$/.test(v),
      groups: Array.isArray(v) && v.every(groupGood), policies: Array.isArray(v) && v.every(polGood) }[k];
    if (!good) return `value of ${k} not allowlisted`;
  }
  return null;
}
function leakOf(out, world) {
  for (const s of SENTINELS) if (out.includes(s)) return 'a synthesized secret or full id';
  for (const s of WINDOWS) if (out.includes(s)) return 'a 12-character window of the value or atok';
  if (/[0-9a-f]{9,}/i.test(out.replace(/"id8":"[0-9a-f]{8}"/g, ''))) return 'a hex run longer than 8';
  for (const line of world.pageConsole) for (const s of SENTINELS) if (line.includes(s)) return 'page console';
  if (world.pageConsole.length) return 'page console not empty';
  return null;
}

const rows = [];
const row = (name, fn) => rows.push({ name, fn });

async function exec(body, args, world, { nodeFetch, code, ctxOut } = {}) {
  const out = await runCode(code || compose(SRC[body], args), world, nodeFetch || sinkStub(world), ctxOut);
  const shape = shapeOk(out, KEYS[body]);
  if (shape) throw new Error(`P-shape: ${shape}`);
  const leak = leakOf(out, world);
  if (leak) throw new Error(`P-leak: ${leak}`);
  return JSON.parse(out);
}
// Key order is not part of a return's contract: compare and print with sorted keys.
const canon = (v) => JSON.stringify(v, (k, x) => (x && typeof x === 'object' && !Array.isArray(x)
  ? Object.fromEntries(Object.keys(x).sort().map((q) => [q, x[q]])) : x));
const eq = (a, b) => canon(a) === canon(b);
const must = (cond, why) => { if (!cond) throw new Error(why); };
const want = (r, w) => must(eq(r, w), `want ${canon(w)} got ${canon(r)}`);
const nothingSent = (w) => must(w.gotos.length === 0 && w.log.length === 0 && w.deletes.length === 0 && w.sinkCalls.length === 0, 'a request was made before the refusal');
const listed = (list, name) => list.filter((t) => t.name === name).length;
// The late-atok rows: one bounded, interval-polled wait on the atok itself. Its position after the last goto is
// pinned by the stub (a goto drops the atok) and mutants XW5/XW6, not by an assertion here.
const waitedOnce = (w) => {
  must(w.waits.length === 1, `waitForFunction calls: ${w.waits.length}`);
  const x = w.waits[0];
  must(x.resolved === true, 'the wait condition never resolved (resolved:false)');
  // Bounded, not pinned: a timeout near the measured ~283 ms delay would bring the false {atok:false} back.
  must(Number.isFinite(x.timeout) && x.timeout >= 1000 && x.timeout <= 30000, `wait timeout ${x.timeout} is not in [1000, 30000] ms`);
  must(typeof x.polling === 'number' && x.polling > 0 && x.polling < x.timeout, `wait polling ${x.polling} is not an interval below the timeout`);
  // The condition itself, on fresh pages: false with no atok (a throw counts as false, as Playwright rejects), true with one.
  const holds = (win) => { try { return !!vm.runInContext(`(${x.src})`, vm.createContext({ window: win }))(x.arg === undefined ? undefined : JSON.parse(JSON.stringify(x.arg))); } catch { return false; } };
  must(!holds({}) && !holds({ bootstrap: {} }) && !holds({ bootstrap: { atok: '' } }) && holds({ bootstrap: { atok: 'x' } }),
    'the wait condition is not "window.bootstrap.atok is set"');
};

// ---- p5-mint.js --------------------------------------------------------------------------------------------
const MINT_P = { owner: 'account', account_id: NA, zone_id: NZ, name: 'cf_api_token_pagerules_read-soleur-20261204',
  zone_groups: ['Page Rules Read'], account_groups: [], expires_on: EXP,
  sink_url: 'http://127.0.0.1:41234/AbCdEfGhIjKlMnOpQrStUv' };
const MINT_A = { ...MINT_P, name: 'cf_api_token_audit-soleur-20261204',
  zone_groups: ['Zone Settings Read', 'DNS Read', 'SSL and Certificates Read', 'Firewall Services Read'],
  account_groups: ['Account Settings Read', 'Notifications Read'] };
const MINT_U = { ...MINT_P, owner: 'user', refuse_ids: ['86aa993e', 'dd6d1427', '5993721f'] };
const ID8 = NEW_FULL.slice(0, 8);
const JS = 'application/json';
const posts = (w) => w.log.filter((l) => l.method === 'POST');
// The token POST went through page.request (the edge refuses an in-page write, 2026-11-28), exactly once, with a
// JSON body, no redirect followed and no throw on a 4xx; its answer was never read as text and was disposed.
const nodeSidePost = (w) => {
  must(!w.log.some((l) => l.method === 'POST' && l.via === 'page'), 'an in-page POST');
  const p = posts(w);
  must(p.length === 1 && p[0].via === 'node' && p[0].ctJson, 'the token POST is not one Node-side JSON POST');
  must(p[0].maxRedirects === 0, `the token POST maxRedirects is ${p[0].maxRedirects}, not 0`);
  must(p[0].failOnStatusCode === false, 'the token POST does not set failOnStatusCode:false');
  must(w.postText === 0, 'the token POST answer was read as text');
  must(w.postDisposed === 1, 'the token POST answer was not disposed');
};
const userLogin = () => makeWorld({ userTokens: OTHER.slice(0, 7).map((id, i) => ({ id, name: `other-${i}`, status: 'active' })) });

row('M1 pagerules mint: one zone policy on the zone key, scope-resolved group (decoy listed first), value to the sink once', async () => {
  const w = makeWorld();
  must(w.groups[0].name === 'Page Rules Read' && w.groups[0].scopes[0] === 'com.cloudflare.api.user', 'instrument: the decoy is not listed first');
  const r = await exec('mint', MINT_P, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
  must(w.gotos[0] === `${DASH}/profile/api-tokens`, 'no goto to /profile/api-tokens first');
  const p = posts(w); must(p.length === 1 && p[0].xatok && p[0].xcss && p[0].path === `/api/v4/accounts/${NA}/tokens`, 'POST count, path or headers');
  nodeSidePost(w);
  const b = JSON.parse(p[0].body);
  must(eq(b.policies, [{ effect: 'allow', permission_groups: [{ id: G.pagerules }], resources: { [ZK]: '*' } }]), 'policies');
  must(b.expires_on === MINT_P.expires_on && b.name === MINT_P.name, 'name/expiry');
  must(w.sinkCalls.length === 1 && w.sinkCalls[0].body === VALUE && w.sinkCalls[0].url === MINT_P.sink_url && w.sinkCalls[0].method === 'POST', 'sink hand-off');
  must(w.sinkCalls[0].redirect === 'error', 'the sink fetch does not refuse redirects');
  must(w.deletes.length === 0, 'a delete on the happy path');
});
row('M2 audit mint: zone groups on the zone key, account groups on the account key only', async () => {
  const w = makeWorld();
  const r = await exec('mint', MINT_A, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
  const b = JSON.parse(posts(w)[0].body);
  must(b.policies.length === 2, 'two policies');
  must(eq(b.policies[0].resources, { [ZK]: '*' }) && eq(b.policies[0].permission_groups.map((g) => g.id), [G.zonesettings, G.dns, G.ssl, G.fw]), 'zone policy');
  must(eq(b.policies[1].resources, { [AK]: '*' }) && eq(b.policies[1].permission_groups.map((g) => g.id), [G.acctsettings, G.notif]), 'account policy');
});
row('M3 signed out -> {atok:false}, nothing minted', async () => {
  const w = makeWorld({ atok: null });
  const r = await exec('mint', MINT_P, w);
  want(r, { atok: false }); must(posts(w).length === 0 && w.sinkCalls.length === 0, 'minted');
});
row('M4 a missing group name -> {refused:groups, matches:n-1}, nothing minted', async () => {
  const w = makeWorld(); w.groups = w.groups.filter((g) => g.name !== 'Notifications Read');
  const r = await exec('mint', MINT_A, w);
  want(r, { refused: 'groups', matches: 5 }); must(posts(w).length === 0, 'minted');
});
row('M5 an ambiguous zone-scoped name -> refused groups', async () => {
  const w = makeWorld(); w.groups.push({ id: gid('pagerules-2'), name: 'Page Rules Read', scopes: ['com.cloudflare.api.account.zone'] });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'groups', matches: 0 }); must(posts(w).length === 0, 'minted');
});
row('M6 one token per exact name: a token already carrying the name -> {refused:name-exists}, nothing minted', async () => {
  const w = makeWorld(); const twin = `bb${hex(15)}`; SENTINELS.push(twin);
  w.acctTokens.push({ id: twin, name: MINT_P.name, status: 'active' });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'name-exists', matches: 1 }); must(posts(w).length === 0, 'minted');
});
row('M6b one token per exact name: the same key with another date suffix does not block the mint', async () => {
  const w = makeWorld(); const prior = `bc${hex(15)}`; SENTINELS.push(prior);
  w.acctTokens.push({ id: prior, name: 'cf_api_token_pagerules_read-soleur-20261101', status: 'active' });
  const r = await exec('mint', MINT_P, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
});
row('M6c no total_count, two pages, the same-name token on page 2 -> {refused:name-exists}', async () => {
  const w = makeWorld({ noTotal: true }); const twin = `bd${hex(15)}`; SENTINELS.push(twin);
  w.acctTokens.push({ id: twin, name: MINT_P.name, status: 'active' });
  must(w.acctTokens.length === 7 && w.acctTokens.findIndex((t) => t.id === twin) >= w.pageCap, 'instrument: the twin is not on page 2');
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'name-exists', matches: 1 });
  must(w.log.filter((l) => l.path === `/api/v4/accounts/${NA}/tokens` && l.method === 'GET').length === 2, 'did not read page 2');
  must(posts(w).length === 0, 'minted');
});
row('M6d a list that never ends within 20 pages -> {refused:listing}, nothing minted', async () => {
  const w = makeWorld({ endless: true });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'listing' }); must(posts(w).length === 0, 'minted');
});
const READBACK_OK = { refused: 'readback', id8: ID8, status: 200, contentType: JS, matches: 0, success: true };
const readbackRow = (tag, why, mutate, args = MINT_P) => row(`M7${tag} read-back fails (${why}) -> new token deleted, sink never called`, async () => {
  const w = makeWorld({ mutateStored: mutate });
  const r = await exec('mint', args, w);
  want(r, READBACK_OK);
  must(w.sinkCalls.length === 0, 'the value reached the sink');
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${NEW_FULL}`, 'cleanup DELETE');
  must(!w.acctTokens.some((t) => t.id === NEW_FULL), 'token still listed');
});
readbackRow('a', 'zone group on the account-wide key', (t) => { t.policies[0].resources = { [AK]: '*' }; });
readbackRow('b', 'an extra group', (t) => { t.policies[0].permission_groups.push({ id: G.dnsedit }); });
readbackRow('c', 'effect deny', (t) => { t.policies[0].effect = 'deny'; });
readbackRow('d', 'a non-"*" resource value', (t) => { t.policies[0].resources = { [ZK]: { x: '*' } }; });
readbackRow('e', 'expiry drift', (t) => { t.expires_on = isoDays(61); });
readbackRow('f', 'a wildcard key', (t) => { t.policies[0].resources = { 'com.cloudflare.api.account.zone.*': '*' }; });
readbackRow('g', 'an account group missing', (t) => { t.policies[1].permission_groups.pop(); }, MINT_A);
readbackRow('h', 'name drift', (t) => { t.name = 'cf_api_token_pagerules_read-soleur-20991231'; });
readbackRow('i', 'the zone key names another 32-hex zone', (t) => { t.policies[0].resources = { [`com.cloudflare.api.account.zone.${'ab'.repeat(16)}`]: '*' }; });
readbackRow('j', 'the account key names another account, value "*"', (t) => { t.policies[1].resources = { [`com.cloudflare.api.account.${'cd'.repeat(16)}`]: '*' }; }, MINT_A);
readbackRow('k', 'status not active', (t) => { t.status = 'disabled'; });
const sinkRow = (tag, why, mode) => row(`M${tag} sink ${why} -> new token deleted, {refused:sink}`, async () => {
  const w = makeWorld({ sinkMode: mode });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'sink', id8: ID8, status: 200, contentType: JS, matches: 0, success: true });
  must(w.deletes.length === 1 && !w.acctTokens.some((t) => t.id === NEW_FULL), 'cleanup DELETE');
});
sinkRow('8', 'down', 'down');
sinkRow('9', 'refuses (403)', 'refuse');
sinkRow('9b', 'answers 200 without the "ok" body', 'notok');
row('M9c the sink answers 307 to another 127.0.0.1 listener -> {refused:sink}, no second request, token deleted', async () => {
  const hitsB = [];
  const B = http.createServer((q, s) => { hitsB.push(q.method); q.resume(); s.writeHead(200, { 'content-type': 'text/plain' }); s.end('ok'); });
  await new Promise((res) => B.listen(0, '127.0.0.1', res));
  const hitsA = [];
  const A = http.createServer((q, s) => { hitsA.push(q.method); q.resume(); s.writeHead(307, { location: `http://127.0.0.1:${B.address().port}/BbBbBbBbBbBbBbBbBbBbBb` }); s.end(); });
  await new Promise((res) => A.listen(0, '127.0.0.1', res));
  try {
    const w = makeWorld();
    const r = await exec('mint', { ...MINT_P, sink_url: `http://127.0.0.1:${A.address().port}/AaAaAaAaAaAaAaAaAaAaAa` }, w, { nodeFetch: globalThis.fetch });
    want(r, { refused: 'sink', id8: ID8, status: 200, contentType: JS, matches: 0, success: true });
    must(hitsA.length === 1, `first listener hits ${hitsA.length}`);
    must(hitsB.length === 0, 'the redirect carried the value to a second listener');
    must(w.deletes.length === 1, 'cleanup DELETE');
  } finally { A.close(); B.close(); }
});
row('M10 the POST answers a JSON 403 and stores nothing -> {refused:mint, status:403}, re-list clean, no DELETE', async () => {
  const w = makeWorld({ mintResp: () => json(403, { success: false, errors: [{ code: 9109 }] }) });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'mint', status: 403, contentType: JS, matches: 0, success: true });
  const i = w.log.findIndex((l) => l.method === 'POST');
  must(w.log.slice(i + 1).some((l) => l.method === 'GET' && l.path === `/api/v4/accounts/${NA}/tokens`), 'no re-list after the POST');
  must(w.deletes.length === 0 && w.sinkCalls.length === 0, 'cleanup DELETE or sink');
  nodeSidePost(w);
});
row('M10b the Node-side POST answers an HTML 403 (the edge refusal, measured in-page 2026-11-28) -> {refused:mint, 403 text/html}, re-list clean', async () => {
  const w = makeWorld({ mintResp: () => html(403) });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'mint', status: 403, contentType: 'text/html', matches: 0, success: true });
  must(w.deletes.length === 0 && w.sinkCalls.length === 0, 'cleanup DELETE or sink');
  nodeSidePost(w);
});
row('M11 a POST that stores the token but answers no value -> {refused:mint-shape}, deleted by name', async () => {
  const w = makeWorld({ mintResp: (create) => { create(); return json(200, { success: true, result: { id: NEW_FULL, name: MINT_P.name } }); } });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'mint-shape', id8: ID8, status: 200, contentType: JS, matches: 0, success: true });
  must(w.deletes.length === 1 && w.sinkCalls.length === 0 && listed(w.acctTokens, MINT_P.name) === 0, 'cleanup');
});
row('M12 a throw after the mint -> {error:e.name, id8,...} and the token deleted', async () => {
  const w = makeWorld({ throwOnReadback: true });
  const r = await exec('mint', MINT_P, w);
  want(r, { error: 'TypeError', id8: ID8, status: 200, contentType: JS, matches: 0, success: true });
  must(w.deletes.length === 1 && w.sinkCalls.length === 0, 'cleanup');
});
row('M13 a page off dash.cloudflare.com -> {refused:origin}', async () => {
  const w = makeWorld({ origin: 'https://evil.example' });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'origin' }); must(posts(w).length === 0, 'minted');
});
const badArgs = [['account_id', { account_id: 'xyz' }], ['zone_id', { zone_id: 'not-a-zone' }], ['name', { name: 'soleur-pagerules' }],
  ['zone_groups', { zone_groups: ['DNS Write'] }], ['zone_groups', { zone_groups: [] }],
  ['account_groups', { account_groups: ['Account Settings Read', 'Account Settings Read'] }],
  ['expires_on', { expires_on: '2027-02-20' }], ['sink_url', { sink_url: 'http://10.0.0.1:4000/AbCdEfGhIjKlMnOpQrStUv' }],
  ['sink_url', { sink_url: 'https://127.0.0.1:4000/AbCdEfGhIjKlMnOpQrStUv' }], ['owner', { owner: undefined }], ['owner', { owner: 'zone' }],
  ['refuse_ids', { refuse_ids: ['86aa993e'] }], ['refuse_ids', { owner: 'user' }], ['refuse_ids', { owner: 'user', refuse_ids: [] }],
  ['refuse_ids', { owner: 'user', refuse_ids: ['86AA993E'] }], ['unknown', { refuseids: ['86aa993e'] }]];
badArgs.forEach(([field, over], i) => {
  row(`M14${String.fromCharCode(97 + i)} bad ${field} ${JSON.stringify(over).slice(0, 40)} -> {refused:args:${field}} before any request`, async () => {
    const w = makeWorld();
    const args = JSON.parse(JSON.stringify({ ...MINT_P, ...over }));
    const r = await exec('mint', args, w);
    want(r, { refused: `args:${field}` }); nothingSent(w);
  });
});
row('M15 args not an object -> {refused:args:object}', async () => {
  const w = makeWorld(); const r = await exec('mint', null, w);
  want(r, { refused: 'args:object' }); nothingSent(w);
});
row('M16a the cleanup DELETE answers HTML 403 -> success:false, token still listed, sink never called', async () => {
  const w = makeWorld({ mutateStored: (t) => { t.policies[0].effect = 'deny'; }, deleteResp: (reply) => reply(403, 'text/html', '<html>no</html>') });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'readback', id8: ID8, status: 200, contentType: JS, del_status: 403, del_contentType: 'text/html', matches: 1, success: false });
  must(listed(w.acctTokens, MINT_P.name) === 1 && w.sinkCalls.length === 0, 'token gone or sink called');
});
row('M16b the cleanup DELETE answers JSON 403 -> success:false, token still listed, sink never called', async () => {
  const w = makeWorld({ mutateStored: (t) => { t.policies[0].effect = 'deny'; }, deleteResp: (reply) => reply(403, 'application/json', '{"success":false,"errors":[{"code":9109}]}') });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'readback', id8: ID8, status: 200, contentType: JS, del_status: 403, del_contentType: JS, matches: 1, success: false });
  must(listed(w.acctTokens, MINT_P.name) === 1 && w.sinkCalls.length === 0, 'token gone or sink called');
});
row('M16c the POST stores the token and answers 200 non-JSON -> {refused:mint}, the cleanup by name deletes it', async () => {
  const w = makeWorld({ mintResp: (create) => { create(); return new Response('<html>ok</html>', { status: 200, headers: { 'content-type': 'text/html' } }); } });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'mint', status: 200, contentType: 'text/html', matches: 0, success: true });
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${NEW_FULL}` && listed(w.acctTokens, MINT_P.name) === 0, 'cleanup by name');
  must(w.sinkCalls.length === 0, 'sink called');
});
row('M16d the POST stores the token and then throws -> {error:TypeError}, the cleanup by name deletes it', async () => {
  const w = makeWorld({ mintResp: (create) => { create(); throw new TypeError('network'); } });
  const r = await exec('mint', MINT_P, w);
  want(r, { error: 'TypeError', matches: 0, success: true });
  must(w.deletes.length === 1 && listed(w.acctTokens, MINT_P.name) === 0 && w.sinkCalls.length === 0, 'cleanup by name');
});
row('M16e the POST stores the token but answers an id that is not 32-hex -> {refused:mint-shape}, deleted by name', async () => {
  const w = makeWorld({ mintResp: (create) => { create(); return json(200, { success: true, result: { id: 'not-an-id', name: MINT_P.name, value: VALUE } }); } });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'mint-shape', status: 200, contentType: JS, matches: 0, success: true });
  must(w.deletes.length === 1 && listed(w.acctTokens, MINT_P.name) === 0 && w.sinkCalls.length === 0, 'cleanup by name');
});
row('M16f the atok is gone at cleanup -> success:false (never an absent key), nothing deleted', async () => {
  const w = makeWorld({ mutateStored: (t) => { t.policies[0].effect = 'deny'; }, onGetToken: (x) => { x.win.bootstrap = {}; } });
  const r = await exec('mint', MINT_P, w);
  want(r, { refused: 'readback', id8: ID8, status: 200, contentType: JS, success: false });
  must(w.deletes.length === 0 && w.sinkCalls.length === 0, 'delete or sink');
});
row('M17 expires_on 29 days out -> {refused:args:expires_on} before any request', async () => {
  const w = makeWorld(); const r = await exec('mint', { ...MINT_P, expires_on: isoDays(29) }, w);
  want(r, { refused: 'args:expires_on' }); nothingSent(w);
});
row('M17b expires_on 31 days out is accepted', async () => {
  const w = makeWorld(); const r = await exec('mint', { ...MINT_P, expires_on: isoDays(31) }, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
});
row('M18a owner user: list, POST, read-back at /user/tokens; account groups keep the account key', async () => {
  const w = userLogin();
  const r = await exec('mint', { ...MINT_A, owner: 'user', refuse_ids: MINT_U.refuse_ids }, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
  const p = posts(w); must(p.length === 1 && p[0].path === '/api/v4/user/tokens', 'POST path');
  nodeSidePost(w);
  must(w.userTokens.some((t) => t.id === NEW_FULL) && !w.acctTokens.some((t) => t.id === NEW_FULL), 'stored under the wrong owner');
  must(w.log.some((l) => l.method === 'GET' && l.path === `/api/v4/user/tokens/${NEW_FULL}`), 'no user read-back');
  must(!w.log.some((l) => l.path === `/api/v4/accounts/${NA}/tokens` || l.path.startsWith(`/api/v4/accounts/${NA}/tokens/${ID8}`)), 'touched the account token endpoints');
});
row('M18b owner user signed in as the old owner (a listed id starts with a refuse_ids pin) -> {refused:old-owner-login}', async () => {
  const w = makeWorld();
  const r = await exec('mint', MINT_U, w);
  want(r, { refused: 'old-owner-login', matches: 1 }); must(posts(w).length === 0, 'minted');
});
row('M18c owner user read-back failure -> the cleanup deletes on /user/tokens', async () => {
  const w = userLogin(); w.mutateStored = (t) => { t.policies[0].effect = 'deny'; };
  const r = await exec('mint', MINT_U, w);
  want(r, READBACK_OK);
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/user/tokens/${NEW_FULL}` && listed(w.userTokens, MINT_P.name) === 0, 'user cleanup');
});

// ---- p5-revoke.js ------------------------------------------------------------------------------------------
const REV = { pin: PIN_P, old_id: PIN_P, new_id: ID8, new_name: 'cf_api_token_pagerules_read-soleur-20261204', scope: 'user' };
const REV_A = { pin: 'dd6d1427', old_id: 'dd6d1427', new_id: ID8, new_name: 'cf_api_token_audit-soleur-20270215', scope: 'account', account_id: NA };
const DEL_OK = { status: 200, contentType: JS, success: true };
const withLive = (w, name = REV_A.new_name) => { w.acctTokens.push({ id: NEW_FULL, name, status: 'active' }); return w; };
row('R1 user-scope revoke over paged lists: Node-side DELETE of the one prefix match with both headers', async () => {
  const w = makeWorld();
  const r = await exec('revoke', REV, w);
  want(r, DEL_OK);
  must(w.gotos[0] === `${DASH}/profile/api-tokens`, 'no goto first');
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/user/tokens/${OLD_P}`, `delete ${JSON.stringify(w.deletes.map((d) => d.okHdr))}`);
  must(w.log.filter((l) => l.path === '/api/v4/user/tokens').length === 2, 'did not page through the list');
  must(!w.log.some((l) => l.method === 'DELETE'), 'an in-page DELETE');
});
row('R1b no total_count, the target on page 2 -> found and deleted', async () => {
  const w = makeWorld({ noTotal: true });
  must(w.userTokens.findIndex((t) => t.id === OLD_P) >= w.pageCap, 'instrument: the target is not on page 2');
  const r = await exec('revoke', REV, w);
  want(r, DEL_OK);
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/user/tokens/${OLD_P}`, 'delete');
});
row('R1c a list that never ends within 20 pages -> {refused:listing}, nothing deleted', async () => {
  const w = makeWorld({ endless: true });
  const r = await exec('revoke', REV, w);
  want(r, { refused: 'listing' }); must(w.deletes.length === 0, 'deleted');
});
row('R2 pin != old_id -> {refused:pin} before any request', async () => {
  const w = makeWorld(); const r = await exec('revoke', { ...REV, pin: 'dd6d1427' }, w);
  want(r, { refused: 'pin' }); nothingSent(w);
});
row('R3 old_id == new_id -> {refused:same-id} before any request', async () => {
  const w = makeWorld(); const r = await exec('revoke', { ...REV, new_id: PIN_P }, w);
  want(r, { refused: 'same-id' }); nothingSent(w);
});
row('R4 the match carries the new token name -> {refused:name}, nothing deleted', async () => {
  const w = makeWorld(); w.userTokens.find((t) => t.id === OLD_P).name = REV.new_name;
  const r = await exec('revoke', REV, w);
  want(r, { refused: 'name' }); must(w.deletes.length === 0, 'deleted');
});
row('R4b the name match ignores case and spacing', async () => {
  const w = makeWorld(); w.userTokens.find((t) => t.id === OLD_P).name = `  ${REV.new_name.toUpperCase()} `;
  const r = await exec('revoke', REV, w);
  want(r, { refused: 'name' }); must(w.deletes.length === 0, 'deleted');
});
row('R4c user scope: a target with a replacement-shaped name (-soleur-<8 digits>) -> {refused:soleur-name}', async () => {
  const w = makeWorld(); w.userTokens.find((t) => t.id === OLD_P).name = 'cf_api_token_dns_read-soleur-20261204';
  const r = await exec('revoke', REV, w);
  want(r, { refused: 'soleur-name' }); must(w.deletes.length === 0, 'deleted');
});
row('R5 zero prefix matches -> {matches:0}', async () => {
  const w = makeWorld(); w.userTokens = w.userTokens.filter((t) => t.id !== OLD_P);
  const r = await exec('revoke', REV, w);
  want(r, { matches: 0 }); must(w.deletes.length === 0, 'deleted');
});
row('R5b two prefix matches -> {matches:2}', async () => {
  const w = makeWorld(); const twin = `${PIN_P}${hex(12)}`; SENTINELS.push(twin); w.userTokens.push({ id: twin, name: 'twin' });
  const r = await exec('revoke', REV, w);
  want(r, { matches: 2 }); must(w.deletes.length === 0, 'deleted');
});
row('R6 signed out -> {atok:false}', async () => {
  const w = makeWorld({ atok: null }); const r = await exec('revoke', REV, w);
  want(r, { atok: false }); must(w.deletes.length === 0, 'deleted');
});
row('R7 account scope with the live replacement listed: lists and deletes on /accounts/<acct>/tokens only', async () => {
  const w = withLive(makeWorld());
  const r = await exec('revoke', REV_A, w);
  want(r, DEL_OK);
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${OLD_A}`, 'account delete path');
  must(!w.log.some((l) => l.path === '/api/v4/user/tokens'), 'read the user list');
});
row('R7b account scope, no token starts with new_id -> {refused:new-token}, nothing deleted', async () => {
  const w = makeWorld(); const r = await exec('revoke', REV_A, w);
  want(r, { refused: 'new-token' }); must(w.deletes.length === 0, 'deleted');
});
row('R7c account scope, the new_id token carries another name -> {refused:new-token}', async () => {
  const w = withLive(makeWorld(), 'cf_api_token_audit-soleur-20991231'); const r = await exec('revoke', REV_A, w);
  want(r, { refused: 'new-token' }); must(w.deletes.length === 0, 'deleted');
});
row('R7d account scope, two tokens start with new_id -> {refused:new-token}', async () => {
  const w = withLive(makeWorld()); const twin = `${ID8}${hex(12)}`; SENTINELS.push(twin);
  w.acctTokens.push({ id: twin, name: REV_A.new_name });
  const r = await exec('revoke', REV_A, w);
  want(r, { refused: 'new-token' }); must(w.deletes.length === 0, 'deleted');
});
[['scope', { scope: 'zone' }, 'args:scope'], ['account_id missing', { scope: 'account' }, 'args:account_id'],
  ['account_id with user', { account_id: NA }, 'args:account_id'], ['pin', { pin: '86AA993E' }, 'args:pin'],
  ['old_id', { old_id: '86aa993e00' }, 'args:old_id'], ['new_id', { new_id: '' }, 'args:new_id'], ['new_name', { new_name: 'x' }, 'args:new_name'],
  ['mode', { mode: 'purge' }, 'args:mode'], ['unknown key', { force: true }, 'args:unknown'],
  ['retire_name in revoke mode', { retire_name: REV.new_name }, 'args:retire_name']].forEach(([tag, over, w8], i) => {
  row(`R8${String.fromCharCode(97 + i)} bad ${tag} -> {refused:${w8}} before any request`, async () => {
    const w = makeWorld(); const r = await exec('revoke', { ...REV, ...over }, w);
    want(r, { refused: w8 }); nothingSent(w);
  });
});
row('R8u user scope, old_id not a committed old pin -> {refused:unpinned} before any request', async () => {
  const w = makeWorld(); const r = await exec('revoke', { ...REV, pin: 'aa000001', old_id: 'aa000001' }, w);
  want(r, { refused: 'unpinned' }); nothingSent(w);
});
row('R8v mode "revoke" spelled out behaves as the default', async () => {
  const w = makeWorld(); const r = await exec('revoke', { ...REV, mode: 'revoke' }, w);
  want(r, DEL_OK);
});
row('R9 the list answers 403 -> {status:403, success:false}', async () => {
  const w = makeWorld({ listFail: true }); const r = await exec('revoke', REV, w);
  want(r, { status: 403, contentType: JS, success: false }); must(w.deletes.length === 0, 'deleted');
});
row('R10 the DELETE answers a JSON 403 -> {status:403, success:false}', async () => {
  const w = makeWorld({ deleteResp: (reply) => reply(403, 'application/json', '{"success":false,"errors":[{"code":9109}]}') });
  const r = await exec('revoke', REV, w);
  want(r, { status: 403, contentType: JS, success: false });
});
row('R11 the DELETE answers HTML -> {contentType:text/html, success:false}', async () => {
  const w = makeWorld({ deleteResp: (reply) => reply(403, 'text/html', '<html>no</html>') });
  const r = await exec('revoke', REV, w);
  want(r, { status: 403, contentType: 'text/html', success: false });
});
row('R12 a page off dash.cloudflare.com -> {refused:origin}', async () => {
  const w = makeWorld({ origin: 'https://evil.example' }); const r = await exec('revoke', REV, w);
  want(r, { refused: 'origin' }); must(w.deletes.length === 0, 'deleted');
});
// retire mode (D8): the bad NEW token, by id8 and exact name.
const RET = { mode: 'retire', pin: ID8, retire_name: 'cf_api_token_pagerules_read-soleur-20261204', scope: 'user' };
const withBad = (w, list = 'userTokens', name = RET.retire_name) => { w[list].push({ id: NEW_FULL, name, status: 'active' }); return w; };
row('R13a retire, user scope: deletes the one token with that id8 and exact name on /user/tokens', async () => {
  const w = withBad(makeWorld()); const r = await exec('revoke', RET, w);
  want(r, DEL_OK);
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/user/tokens/${NEW_FULL}`, 'retire delete');
});
row('R13b retire, account scope: deletes on /accounts/<acct>/tokens', async () => {
  const w = withBad(makeWorld(), 'acctTokens'); const r = await exec('revoke', { ...RET, scope: 'account', account_id: NA }, w);
  want(r, DEL_OK);
  must(w.deletes.length === 1 && w.deletes[0].path === `/api/v4/accounts/${NA}/tokens/${NEW_FULL}`, 'retire delete');
});
row('R13c retire, the token name differs from retire_name (exact match) -> {refused:retire-name}', async () => {
  const w = withBad(makeWorld(), 'userTokens', RET.retire_name.toUpperCase()); const r = await exec('revoke', RET, w);
  want(r, { refused: 'retire-name' }); must(w.deletes.length === 0, 'deleted');
});
row('R13d retire, pin is a committed old pin -> {refused:old-pin} before any request', async () => {
  const w = makeWorld(); const r = await exec('revoke', { ...RET, pin: PIN_P }, w);
  want(r, { refused: 'old-pin' }); nothingSent(w);
});
row('R13e retire, zero prefix matches -> {matches:0}', async () => {
  const w = makeWorld(); const r = await exec('revoke', RET, w);
  want(r, { matches: 0 }); must(w.deletes.length === 0, 'deleted');
});
[['old_id', { old_id: ID8 }], ['new_id', { new_id: ID8 }], ['new_name', { new_name: RET.retire_name }],
  ['retire_name', { retire_name: undefined }], ['retire_name', { retire_name: 'soleur-x' }]].forEach(([field, over], i) => {
  row(`R13f${String.fromCharCode(97 + i)} retire with bad ${field} -> {refused:args:${field}} before any request`, async () => {
    const w = makeWorld(); const r = await exec('revoke', JSON.parse(JSON.stringify({ ...RET, ...over })), w);
    want(r, { refused: `args:${field}` }); nothingSent(w);
  });
});

// ---- p5-read.js --------------------------------------------------------------------------------------------
const onlyGets = (w) => must(w.log.every((l) => l.method === 'GET') && w.deletes.length === 0, 'a non-GET request');
const GROUPS_OUT = GROUPS.map((g) => ({ name: g.name, scopes: g.scopes, id8: g.id.slice(0, 8) }));
row('D1 read groups, account scope: names, scopes and id8 of every group, GET only', async () => {
  const w = makeWorld(); const r = await exec('read', { what: 'groups', scope: 'account', acct: NA }, w);
  want(r, { success: true, groups: GROUPS_OUT, skipped: 0 });
  must(w.log.length === 1 && w.log[0].path === `/api/v4/accounts/${NA}/tokens/permission_groups` && w.log[0].xatok && w.log[0].xcss, 'request');
  onlyGets(w);
});
row('D2 read groups, user scope -> /user/tokens/permission_groups', async () => {
  const w = makeWorld({ userGroups: [{ id: G.analytics, name: 'Analytics Read', scopes: ['com.cloudflare.api.account.zone'] }] });
  const r = await exec('read', { what: 'groups', scope: 'user' }, w);
  want(r, { success: true, groups: [{ name: 'Analytics Read', scopes: ['com.cloudflare.api.account.zone'], id8: G.analytics.slice(0, 8) }], skipped: 0 });
  must(w.log.length === 1 && w.log[0].path === '/api/v4/user/tokens/permission_groups', 'request path');
});
row('D3 read groups: a non-hex id drops only id8; a name or scope outside the alphabet is skipped', async () => {
  const w = makeWorld({ groups: [{ id: 'g-not-hex', name: 'DNS Read', scopes: ['com.cloudflare.api.account.zone'] },
    { id: G.dns, name: '<b>DNS Read</b>', scopes: ['com.cloudflare.api.account.zone'] },
    { id: G.ssl, name: 'SSL and Certificates Read', scopes: [`com.cloudflare.api.account.zone.${NZ}`] }] });
  const r = await exec('read', { what: 'groups', scope: 'account', acct: NA }, w);
  want(r, { success: true, groups: [{ name: 'DNS Read', scopes: ['com.cloudflare.api.account.zone'] }], skipped: 2 });
});
const POLICY_TOKEN = (w) => {
  const t = w.userTokens.find((x) => x.id === OLD_P);
  t.policies = [
    { id: 'p1', effect: 'allow', resources: { [ZK]: '*' }, permission_groups: [{ id: G.pagerules, name: 'Page Rules Read' }] },
    { id: 'p2', effect: 'allow', resources: { [AK]: '*' }, permission_groups: [{ id: G.acctsettings, name: 'Account Settings Read' }, { id: G.notif, name: '<x>' }] },
    { id: 'p3', effect: 'deny', resources: { 'com.cloudflare.api.account.zone.*': '*', [AK]: { 'com.cloudflare.api.account.zone.*': '*' }, 'com.cloudflare.api.user.x': '*' },
      permission_groups: [{ id: G.dns, name: 'DNS Read' }] },
  ];
  return w;
};
row('D5 read policies, user scope: effect, group names, resource counts and key kinds only, GET only', async () => {
  const w = POLICY_TOKEN(makeWorld());
  const r = await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w);
  want(r, { success: true, policies: [
    { effect: 'allow', groups: ['Page Rules Read'], resources: 1, kinds: ['zone'] },
    { effect: 'allow', groups: ['Account Settings Read'], resources: 1, kinds: ['account'] },
    { effect: 'deny', groups: ['DNS Read'], resources: 3, kinds: ['account-nested', 'all-zones', 'user'] },
  ], skipped: 1 });
  must(w.log.some((l) => l.path === `/api/v4/user/tokens/${OLD_P}`), 'no token GET');
  onlyGets(w);
});
row('D6a read policies, zero tokens start with pin -> {matches:0}', async () => {
  const w = makeWorld(); const r = await exec('read', { what: 'policies', scope: 'user', pin: 'aa000001' }, w);
  want(r, { matches: 0 }); onlyGets(w);
});
row('D6b read policies, two tokens start with pin -> {matches:2}', async () => {
  const w = makeWorld(); const twin = `${PIN_P}${hex(12)}`; SENTINELS.push(twin); w.userTokens.push({ id: twin, name: 'twin' });
  const r = await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w);
  want(r, { matches: 2 });
});
row('D6c read policies, no total_count, the token on page 2 -> found', async () => {
  const w = POLICY_TOKEN(makeWorld({ noTotal: true }));
  const r = await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w);
  must(r.success === true && Array.isArray(r.policies) && r.policies.length === 3, `got ${JSON.stringify(r)}`);
});
row('D6d read policies, a list that never ends -> {refused:listing}', async () => {
  const w = makeWorld({ endless: true }); const r = await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w);
  want(r, { refused: 'listing' });
});
row('D7 read: signed out -> {atok:false}; off-origin -> {refused:origin}; list 403 -> {status:403, success:false}', async () => {
  let w = makeWorld({ atok: null }); want(await exec('read', { what: 'groups', scope: 'account', acct: NA }, w), { atok: false });
  w = makeWorld({ origin: 'https://evil.example' }); want(await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w), { refused: 'origin' });
  w = makeWorld({ listFail: true }); want(await exec('read', { what: 'policies', scope: 'user', pin: PIN_P }, w), { status: 403, contentType: JS, success: false });
});
// ---- the late atok (2026-11-28): window.bootstrap.atok is set ~283 ms after DOMContentLoaded --------------
row('L1 read groups, atok set only after DOMContentLoaded -> the normal groups answer, not {atok:false}', async () => {
  const w = makeWorld({ lateAtok: true }); const r = await exec('read', { what: 'groups', scope: 'account', acct: NA }, w);
  must(r.success === true, `got ${canon(r)}`); // short: the full want below is longer than the 400-char FAIL text
  want(r, { success: true, groups: GROUPS_OUT, skipped: 0 });
  waitedOnce(w);
});
row('L2 mint, atok set only after DOMContentLoaded -> minted, value to the sink once', async () => {
  const w = makeWorld({ lateAtok: true }); const r = await exec('mint', MINT_P, w);
  want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
  must(w.sinkCalls.length === 1 && w.sinkCalls[0].body === VALUE, 'sink hand-off');
  waitedOnce(w);
});
row('L3 revoke, atok set only after DOMContentLoaded -> the one match deleted', async () => {
  const w = makeWorld({ lateAtok: true }); const r = await exec('revoke', REV, w);
  want(r, DEL_OK);
  must(w.deletes.length === 1 && w.deletes[0].okHdr && w.deletes[0].path === `/api/v4/user/tokens/${OLD_P}`, 'delete');
  waitedOnce(w);
});
[['object', null], ['unknown', { what: 'groups', scope: 'user', extra: 1 }], ['what', { what: 'tokens', scope: 'user' }],
  ['scope', { what: 'groups', scope: 'zone' }], ['acct', { what: 'groups', scope: 'account' }], ['acct', { what: 'groups', scope: 'user', acct: NA }],
  ['pin', { what: 'groups', scope: 'user', pin: PIN_P }], ['scope', { what: 'policies', scope: 'account', pin: PIN_P }],
  ['pin', { what: 'policies', scope: 'user', pin: '86AA993E' }], ['acct', { what: 'policies', scope: 'user', pin: PIN_P, acct: NA }]].forEach(([field, args], i) => {
  row(`D8${String.fromCharCode(97 + i)} read with bad ${field} ${JSON.stringify(args).slice(0, 40)} -> {refused:args:${field}} before any request`, async () => {
    const w = makeWorld(); const r = await exec('read', args, w);
    want(r, { refused: `args:${field}` }); nothingSent(w);
  });
});

// ---- composed run files (P-compose) and the real sink (integration) -----------------------------------------
if (process.env.P5_RUNFILE_REVOKE) {
  row('C1 the runbook-composed revoke run file runs and equals (<body>)(JSON.parse(<json string>))', async () => {
    const code = fs.readFileSync(process.env.P5_RUNFILE_REVOKE, 'utf8');
    must(code === compose(SRC.revoke, JSON.parse(process.env.P5_ARGS_REVOKE)), 'the runbook composition differs from (<body>)(JSON.parse(<json string>))');
    const w = makeWorld(); const r = await exec('revoke', null, w, { code });
    want(r, DEL_OK);
  });
}
if (process.env.P5_RUNFILE_MINT) {
  row('C2 the runbook-composed mint run file runs and equals (<body>)(JSON.parse(<json string>))', async () => {
    const code = fs.readFileSync(process.env.P5_RUNFILE_MINT, 'utf8');
    must(code === compose(SRC.mint, JSON.parse(process.env.P5_ARGS_MINT)), 'the runbook composition differs from (<body>)(JSON.parse(<json string>))');
    const w = makeWorld(); const r = await exec('mint', null, w, { code });
    must(r.success === true && w.sinkCalls.length === 1, `got ${JSON.stringify(r)}`);
  });
}
if (process.env.P5_INJECT) {
  // label=body=path, comma-separated: each run file came from the runbook line fed a JavaScript-expression argument.
  for (const spec of process.env.P5_INJECT.split(',')) {
    const [label, body, file] = spec.split('=');
    row(`C3-${label} a JavaScript-expression argument is data: no side effect, refused or thrown`, async () => {
      const w = makeWorld(); const holder = {};
      let r = null; let threw = null;
      try { r = await exec(body, null, w, { code: fs.readFileSync(file, 'utf8'), ctxOut: holder }); } catch (e) { threw = e; }
      must(holder.ctx && holder.ctx.P5_PWNED === undefined, 'the argument ran as JavaScript (P5_PWNED set)');
      must(threw ? /SyntaxError/.test(String(threw && threw.name)) : (r && typeof r.refused === 'string' && r.refused.startsWith('args:')),
        `neither refused nor a parse error: ${threw ? String(threw.name) : JSON.stringify(r)}`);
      must(w.log.length === 0 && w.deletes.length === 0, 'a request was sent');
    });
  }
}
if (MODE === 'integration') {
  rows.length = 0;
  row('I1 mint -> the real p5-sink.py over 127.0.0.1: file holds the value byte-exact', async () => {
    const w = makeWorld();
    const r = await exec('mint', { ...MINT_P, sink_url: process.env.P5_SINK_URL }, w, { nodeFetch: globalThis.fetch });
    want(r, { status: 200, contentType: JS, success: true, id8: ID8 });
    must(fs.readFileSync(process.env.P5_OUT, 'utf8') === VALUE, 'file content differs from the minted value');
    must(w.deletes.length === 0, 'cleanup on the happy path');
  });
}

for (const r of rows) {
  if (ONLY.length && !ONLY.some((o) => r.name.startsWith(`${o} `))) continue;
  try { await r.fn(); ok(r.name); } catch (e) { bad(r.name, String(e && e.message).slice(0, 400)); }
}
process.exit(failures ? 1 : 0);
HARNESS

H_OUT="$SB/h.out"
harness() { # <mint> <revoke> <read> [env...] -> prints harness lines into $H_OUT, appends to ALL_OUT
  local m="$1" r="$2" d="$3"; shift 3
  env "$@" node "$SB/harness.mjs" "$m" "$r" "$d" "$SENT" > "$H_OUT" 2>&1
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
# Runs the sink under test (P5_REAL_SINK) with os.fsync raising EIO: the write-failure path.
cat > "$SB/fsync-fail.py" <<'FSYNC'
import os, runpy, sys
def _eio(fd):
    raise OSError(5, "synthetic EIO")
os.fsync = _eio
real = os.environ["P5_REAL_SINK"]
sys.argv = [real] + sys.argv[1:]
runpy.run_path(real, run_name="__main__")
FSYNC
SVAL="SYNTHsinkvalue$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s' "$SVAL" > "$SB/sval"; chmod 600 "$SB/sval"
printf '%s\n' "$SVAL" >> "$SB/sink-sentinels"
SINK_PID=""; SINK_URL=""
sink_start() { # <out> [sink path] [timeout] [real sink]; sets SINK_PID SINK_URL; sink stdout -> $SB/sink.<n>.out
  local out="$1" src="${2:-$SINK}" to="${3:-30}" real="${4:-$SINK}"
  SINK_N=$(( ${SINK_N:-0} + 1 )); SINK_LOG="$SB/sink.${SINK_N}.${BASHPID:-$$}.out"
  P5_REAL_SINK="$real" python3 -I "$src" --out "$out" --timeout "$to" > "$SINK_LOG" 2>&1 &
  SINK_PID=$!; SINK_URL=""
  printf '%s\n' "$SINK_PID" >> "$PIDS"
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

run_sink_rows() { # <sink path>
  local S="$1" d
  d="$SB/sinkrows.$RANDOM$RANDOM"; mkdir -m 700 "$d"
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
  # S3: wrong path, Origin header, GET, short Content-Length, bad body: each refused with its reason, no file.
  local tag how reason
  for tag in path origin method length body; do
    sink_start "$d/s-$tag.tok" "$S" || { fail "S-$tag sink did not start"; continue; }
    case "$tag" in
      path)   OUT="$(client "${SINK_URL%/*}/wrongnoncewrongnonce" - - POST "$SB/sval")"; reason=path ;;
      origin) OUT="$(client "$SINK_URL" - https://dash.cloudflare.com POST "$SB/sval")"; reason=origin ;;
      method) OUT="$(client "$SINK_URL" - - GET -)"; reason=method ;;
      length) printf 'SYNTHshort' > "$d/short"; OUT="$(client "$SINK_URL" - - POST "$d/short")"; reason=length ;;
      body)   printf 'SYNTH bad value with spaces\n' > "$d/bad"; OUT="$(client "$SINK_URL" - - POST "$d/bad")"; reason=body ;;
    esac
    sink_wait
    [[ "$SINK_RC" -eq 1 && ! -e "$d/s-$tag.tok" ]] && grep -qx "SOLEUR_P5_SINK result=refused reason=$reason" "$SINK_LOG"
    check "S3-$tag the first request refused reason=$reason, no file" $?
  done
  # S4: no request within --timeout -> result=timeout, exit 3, no file.
  if sink_start "$d/s4.tok" "$S" 1; then
    sink_wait
    [[ "$SINK_RC" -eq 3 && ! -e "$d/s4.tok" ]] && grep -qx 'SOLEUR_P5_SINK result=timeout' "$SINK_LOG"
    check "S4 no request within --timeout -> result=timeout, exit 3, no file" $?
  else
    fail "S4 sink did not start"
  fi
  # S8: the fsync fails -> the partial file is unlinked, reason=write, exit 1, the client gets 500.
  if sink_start "$d/s8.tok" "$SB/fsync-fail.py" 30 "$S"; then
    OUT="$(client "$SINK_URL" - - POST "$SB/sval")"; local cout="$OUT"
    sink_wait
    OUT="$cout $(tr '\n' ' ' < "$SINK_LOG")"
    [[ "$cout" == status=500* && "$SINK_RC" -eq 1 && ! -e "$d/s8.tok" ]] && grep -qx 'SOLEUR_P5_SINK result=refused reason=write' "$SINK_LOG"
    check "S8 a failed fsync -> reason=write, exit 1, the partial file unlinked" $?
  else
    fail "S8 sink did not start"
  fi
  # S7: --out refusals before binding (a .git directory and a .git FILE both mark a work tree).
  : > "$d/exists"
  mkdir -p "$d/g/.git" "$d/g/sub" "$d/gf/sub"
  printf 'gitdir: %s/nowhere\n' "$d" > "$d/gf/.git"
  for how in "exists:$d/exists" "relative:rel.tok" "in-git:$d/g/sub/t.tok" "in-git:$d/gf/sub/t.tok" "parent:$d/nodir/t.tok"; do
    OUT="$(python3 -I "$S" --out "${how#*:}" --timeout 2 2>&1)"; local rc=$?
    printf '%s\n' "$OUT" >> "$ALL_OUT"
    [[ "$rc" -eq 2 && "$OUT" == "SOLEUR_P5_SINK result=refused reason=out-${how%%:*}" ]]
    check "S7-${how%%:*} --out ${how#*:"$d"/} refused (exit 2) before binding" $?
  done
}

# --- P-pin ---------------------------------------------------------------------------------------------------
echo "== P-pin: manifest and runbook citations =="
MDIR="$(dirname "$MANIFEST")"
OUT="$(cd "$MDIR" && sha256sum -c p5-browser.sha256 2>&1)"; check "p5-browser.sha256 verifies (sha256sum -c)" $?
OUT="$(awk '{print $2}' "$MANIFEST" | sort | tr '\n' ' ')"
[[ "$OUT" == "p5-mint.js p5-read.js p5-revoke.js p5-sink.py " ]]; check "the manifest lists exactly p5-mint.js, p5-read.js, p5-revoke.js, p5-sink.py" $?
[[ "$(awk 'NF!=2 || $1 !~ /^[0-9a-f]{64}$/' "$MANIFEST" | wc -l)" -eq 0 ]]; check "every manifest line is <sha256>  <file>" $?
cite_check() { # <runbook>: sets cites, bad_cite, OUT
  local rb="$1" f h have all64
  cites=0; bad_cite=0; OUT="runbook unreadable: $rb"
  if [[ -r "$rb" ]]; then
    OUT=""
    while read -r f h; do
      cites=$((cites + 1))
      have="$(sha256sum "$MDIR/$f" 2>/dev/null | awk '{print $1}')"
      [[ -n "$have" && "$h" == "$have" ]] || { bad_cite=1; OUT="runbook cites $f sha256=$h, the file is $have"; }
    done < <(perl -ne 'while (/\b(p5-(?:mint\.js|revoke\.js|read\.js|sink\.py))`?\s+\(?sha256=([0-9a-f]{64})\b/g) { print "$1 $2\n" }' "$rb")
    # Every 64-hex value in the runbook must be such a citation, so none can sit outside the check.
    all64="$(grep -aoE '[0-9a-f]{64}' "$rb" | wc -l)"
    [[ "$cites" -eq "$all64" ]] || { bad_cite=1; OUT="the runbook carries ${all64} 64-hex values, ${cites} of them <body> sha256=<hex> citations"; }
    [[ "$cites" -ge 5 ]] || { bad_cite=1; OUT="only ${cites} sha256 citations in the runbook (floor 5)"; }
  else
    bad_cite=1
  fi
}
cite_check "$RUNBOOK"
[[ "$bad_cite" -eq 0 ]]; check "the runbook is readable and its ${cites} sha256 citations (>= 5, both forms, every 64-hex value) each equal the file's sha256" $?
# The archived plan's Operator Holds must keep the runbook's section 6 hold wording verbatim, except for an exact
# sha256=<64 hex> value (CTO F5): the archived plan is never edited, so a body re-pin leaves it quoting a superseded
# sha. The runbook's sha values are checked against the files by the citation check above; the plan's are not.
holds_norm() { grep -a '^- Hold:' "$1" | sed -E 's/sha256=[0-9a-f]{64}/sha256=<pinned>/g'; }
PLAN_FILE="$(find "${REPO_ROOT}/knowledge-base/project/plans" -name '*2026-11-27-chore-cf-phase5-old-login-token-remint-plan.md' | head -1)"
OUT="plan unreadable: ${PLAN_FILE:-none}"
if [[ -r "$PLAN_FILE" && -r "$RUNBOOK" ]]; then
  ph="$(holds_norm "$PLAN_FILE" || true)"; rh="$(holds_norm "$RUNBOOK" || true)"
  OUT="plan holds=$(grep -c . <<<"$ph") runbook holds=$(grep -c . <<<"$rh")"
  [[ -n "$rh" && "$ph" == "$rh" ]]
else
  false
fi
check "the plan's Operator Holds lines equal the runbook's section 6 hold lines (${OUT})" $?
for f in "$MINT" "$REVOKE" "$READ"; do
  OUT="$(tail -c 2 "$f" | od -An -c | tr -d ' ')"
  [[ "$OUT" == '}\n' ]]; check "$(basename "$f") ends in the function's closing brace (no trailing ;) for the composition line" $?
  OUT="$(grep -c 'console\.' "$f")"; [[ "$OUT" -eq 0 ]]; check "$(basename "$f") never calls console" $?
  OUT="$(grep -c 'JSON.parse(<string>)' "$f")"; [[ "$OUT" -ge 1 ]]; check "$(basename "$f") SHAPE note names the JSON.parse(<string>) run file (D9)" $?
done
OUT="$(grep -nE 'print\(' "$SINK")"
[[ -z "$OUT" ]]; check "p5-sink.py has no print() (its only output is say())" $?

# --- P-compose: the runbook's own composition line ---------------------------------------------------------
# The one runbook line that cats a body from "$D/" into a .run.js file; placeholders <B>, <repo>, <body>, <x>
# and <ARGS-JSON> are filled, and it runs in a sandbox copy of the spec directory.
CR="$SB/compose-repo"; CD="$CR/spec"; mkdir -p "$CD"
cp "$MINT" "$REVOKE" "$READ" "$SINK" "$MANIFEST" "$CD/"; : > "$CD/bootstrap.sh"
compose_line() { [[ -r "$RUNBOOK" ]] && awk 'index($0, ".run.js") && index($0, "cat \"$D/")' "$RUNBOOK"; }
run_compose() { # <x> <args-json> -> rc of the line; the run file (if any) at $CR/.playwright-mcp/p5-<x>.run.js
  local x="$1" line
  rm -f "$CR/.playwright-mcp/p5-$x.run.js"
  line="$(compose_line | P5B="$CD/bootstrap.sh" P5R="$CR" P5X="$x" P5A="$2" perl -pe 's/<B>/$ENV{P5B}/g; s/<repo>/$ENV{P5R}/g; s/<body>/p5-$ENV{P5X}.js/g; s/<x>/$ENV{P5X}/g; s/<ARGS-JSON>/$ENV{P5A}/g')"
  (cd "$CR" && bash -c "$line") >> "$ALL_OUT" 2>&1
}
EXP_SH="$(python3 -I -c 'import datetime; print((datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=60)).strftime("%Y-%m-%dT00:00:00Z"))')"
RA='{"pin":"86aa993e","old_id":"86aa993e","new_id":"c0ffee12","new_name":"cf_api_token_pagerules_read-soleur-20261204","scope":"user"}'
MA='{"owner":"account","account_id":"66d4f93f7397f196544e9fe84c3557c2","zone_id":"951ce525552201ec6c696b24251abed7","name":"cf_api_token_pagerules_read-soleur-20261204","zone_groups":["Page Rules Read"],"account_groups":[],"expires_on":"'"$EXP_SH"'","sink_url":"http://127.0.0.1:41234/AbCdEfGhIjKlMnOpQrStUv"}'
compose_rows() {
  echo "== P-compose: the runbook's composition line =="
  OUT="$(compose_line)"
  [[ "$(printf '%s\n' "$OUT" | grep -c .)" -eq 1 ]]; check "the runbook carries exactly one composition line (cat \"\$D/...\" > ....run.js)" $?
  run_compose revoke "$RA"; local rr=$?
  cp "$CR/.playwright-mcp/p5-revoke.run.js" "$SB/p5-revoke.run.js" 2>/dev/null
  run_compose mint "$MA"; local rm_=$?
  cp "$CR/.playwright-mcp/p5-mint.run.js" "$SB/p5-mint.run.js" 2>/dev/null
  OUT="revoke rc=$rr mint rc=$rm_"; [[ "$rr" -eq 0 && "$rm_" -eq 0 && -s "$SB/p5-revoke.run.js" && -s "$SB/p5-mint.run.js" ]]
  check "the composition line exits 0 and writes both run files" $?
  # Injection payloads: each must be refused at jq (non-zero, no run file) or reach the body as data.
  local inject="" label body payload n=0 refused_at_jq=0
  while IFS='|' read -r label body payload; do
    n=$((n + 1))
    if run_compose "$body" "$payload" && [[ -s "$CR/.playwright-mcp/p5-$body.run.js" ]]; then
      cp "$CR/.playwright-mcp/p5-$body.run.js" "$SB/inject-$label.run.js"
      inject="${inject:+$inject,}$label=$body=$SB/inject-$label.run.js"
    else
      refused_at_jq=$((refused_at_jq + 1)); pass "C3-$label a JavaScript-expression argument is data: refused at jq"
    fi
  done <<'PAYLOADS'
obj|revoke|{"a":1,"b":globalThis.P5_PWNED=1}
comma|revoke|{"a":1},globalThis.P5_PWNED=1
paren|revoke|{"pin":"86aa993e","old_id":"86aa993e","new_id":"c0ffee12","new_name":"x)(globalThis.P5_PWNED=1)(","scope":"user"}
array|read|[1]
PAYLOADS
  OUT="payloads=$n"; [[ "$n" -eq 4 ]]; check "four injection payloads were fed to the composition line" $?
  harness "$MINT" "$REVOKE" "$READ" P5_ONLY=C1,C2,C3-obj,C3-comma,C3-paren,C3-array P5_RUNFILE_REVOKE="$SB/p5-revoke.run.js" P5_ARGS_REVOKE="$RA" \
    P5_RUNFILE_MINT="$SB/p5-mint.run.js" P5_ARGS_MINT="$MA" P5_INJECT="$inject"; relay
  OUT="$(grep -c '^ok C[12] ' "$H_OUT")"; [[ "$OUT" -eq 2 ]]; check "both composition rows ran green" $?
}

if [[ "$MODE" == full ]]; then
  echo "== P-shape / P-leak / P-revoke / P-mint / P-read: bodies under the run_code emulation =="
  harness "$MINT" "$REVOKE" "$READ"; relay

  compose_rows

  echo "== P-sink =="
  run_sink_rows "$SINK"

  echo "== integration: p5-mint.js -> the real p5-sink.py =="
  d="$SB/integ"; mkdir -m 700 "$d"
  if sink_start "$d/cf_api_token_pagerules_read.tok"; then
    harness "$MINT" "$REVOKE" "$READ" P5_MODE=integration P5_SINK_URL="$SINK_URL" P5_OUT="$d/cf_api_token_pagerules_read.tok"; relay
    sink_wait
    [[ "$SINK_RC" -eq 0 && "$(stat -c %a "$d/cf_api_token_pagerules_read.tok")" == 600 ]]; check "I1 the sink wrote the minted value at mode 0600 and exited 0" $?
  else
    fail "I1 sink did not start"
  fi

  echo "== P-leak: every captured line =="
  awk -v s="$SVAL" 'BEGIN { print s; for (i = 1; i + 11 <= length(s); i++) print substr(s, i, 12) }' >> "$SB/sink-sentinels"
  cat "$SENT" "$SB/sink-sentinels" > "$SB/all-sentinels"
  [[ "$(wc -l < "$SB/all-sentinels")" -ge 60 ]]; check "the sentinel list is populated, 12-character windows included (instrument)" $?
  OUT="$(grep -cF -f "$SB/all-sentinels" "$ALL_OUT")"
  [[ "$OUT" -eq 0 ]]; check "no synthesized value, atok, 12-char window of either, or full id in any captured output ($(wc -l < "$ALL_OUT") lines)" $?
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
killed_row() { # <mint> <revoke> <read> <row> <expected text>: the row is RED and its FAIL text names <expected text>
  harness "$1" "$2" "$3" P5_ONLY="$4"
  local fl
  ! grep -q "^ok $4 " "$H_OUT" || return 1
  fl="$(grep "^FAIL $4 " "$H_OUT" || true)"
  grep -qF -- "$5" <<<"$fl"
}
SCORED="R1,R1b,R2,R3,R4,R4c,R7b,R8u,R13c,R13d,M1,M6,M6c,M7a,M7h,M9c,M16a,M16c,M16f,M17,M18a,M18b,D5,L1,L2,L3,D7,M3,R6"
harness "$MINT" "$REVOKE" "$READ" P5_ONLY="$SCORED"
if [[ "$(grep -c '^ok ' "$H_OUT")" -ne 29 ]] || grep -q '^FAIL ' "$H_OUT"; then
  printf 'HARNESS: a scored row is RED on the pristine bodies:\n' >&2; grep -v '^ok ' "$H_OUT" | cut -c1-300 >&2; exit 2
fi
SINK_PRISTINE="$SB/sink-pristine.err"
( FAIL=0; run_sink_rows "$SINK" >/dev/null 2>"$SINK_PRISTINE"; [[ "$FAIL" -eq 0 ]] ) || {
  printf 'HARNESS: a sink row is RED on the pristine sink:\n' >&2; cut -c1-300 "$SINK_PRISTINE" >&2; exit 2; }
pass "every scored row and every sink row is GREEN on the pristine bodies"

M="$SB/mut"; mkdir -m 700 "$M"
mut() { # <id> <label> <body:mint|revoke|read> <from> <to> <row> <expected text>
  local id="$1" label="$2" which="$3" src dst m="$MINT" r="$REVOKE" d="$READ"
  case "$which" in mint) src="$MINT" ;; revoke) src="$REVOKE" ;; read) src="$READ" ;; esac
  dst="$M/$id.js"
  mutate "$src" "$dst" "$4" "$5"; check "$id lands" $?
  case "$which" in mint) m="$dst" ;; revoke) r="$dst" ;; read) d="$dst" ;; esac
  killed_row "$m" "$r" "$d" "$6" "$7"; check "$id ($label) turns $6 RED naming $7" $?
}
mut XR1 "pin guard deleted" revoke "if (a.pin !== a.old_id) return safe({ refused: 'pin' });" "" R2 '"refused":"pin"'
mut XR2 "same-id guard deleted" revoke "if (a.old_id === a.new_id) return safe({ refused: 'same-id' });" "" R3 '"refused":"same-id"'
mut XR3 "name guard deleted" revoke "if (typeof target.name === 'string' && norm(target.name) === norm(a.new_name)) return safe({ refused: 'name' });" "" R4 'want {"refused":"name"}'
mut XR4 "old-pin allowlist deleted" revoke "if (a.scope === 'user' && !OLD_PINS.includes(a.old_id)) return safe({ refused: 'unpinned' });" "" R8u '"refused":"unpinned"'
mut XR5 "soleur-name guard deleted" revoke "if (a.scope === 'user' && /-soleur-\\d{8}\$/.test(norm(target.name))) return safe({ refused: 'soleur-name' });" "" R4c '"refused":"soleur-name"'
mut XR6 "live-replacement check deleted" revoke "return safe({ refused: 'new-token' });" "" R7b '"refused":"new-token"'
mut XR7 "paging ends on the requested per_page" revoke "if (j.result.length < per && !more)" "if (j.result.length < PER && !more)" R1b 'want {"contentType":"application/json","status":200,"success":true}'
mut XR8 "retire-name guard deleted" revoke "if (target.name !== a.retire_name) return safe({ refused: 'retire-name' });" "" R13c '"refused":"retire-name"'
mut XR9 "retire old-pin guard deleted" revoke "if (isOld(a.pin)) return safe({ refused: 'old-pin' });" "" R13d '"refused":"old-pin"'
mut XM1 "account key accepted for zone groups" mint "if (k === zoneKey) {" "if (k === zoneKey || k === acctKey) {" M7a '"refused":"readback"'
mut XM2 "one-token-per-exact-name deleted" mint "if (same !== 0) return safe({ refused: 'name-exists', matches: same });" "" M6 '"refused":"name-exists"'
mut XM3 "cleanup verdict starts true" mint "const out = { success: false };" "const out = { success: true };" M16f '"success":false}'
mut XM4 "a cleanup DELETE starts as ok" mint "let ok = false;" "let ok = true;" M16a '"del_status":403'
mut XM5 "no cleanup after a non-JSON POST" mint "if (notOk(mr)) return await failAfterPost('mint');" "if (notOk(mr)) return safe({ refused: 'mint', ...postInfo, success: false });" M16c '"matches":0,"refused":"mint"'
mut XM6 "sink redirect followed" mint "body: secret, redirect: 'error'," "body: secret," M9c '"refused":"sink"'
mut XM7 "mint paging ends on the requested per_page" mint "if (lr.json.result.length < per && !more)" "if (lr.json.result.length < PER && !more)" M6c '"refused":"name-exists"'
mut XM8 "30-day expiry floor deleted" mint "|| Date.parse(a.expires_on) < Date.now() + 30 * 86400000" "" M17 '"refused":"args:expires_on"'
mut XM9 "old-owner-login refusal deleted" mint "if (old !== 0) return safe({ refused: 'old-owner-login', matches: old });" "" M18b '"refused":"old-owner-login"'
mut XM10 "owner user posts to the account endpoint" mint "const base = a.owner === 'account' ?" "const base = a.owner ?" M18a 'want {"contentType":"application/json","id8":"c0ffee12","status":200,"success":true}'
mut XM11 "cleanup by name only, not the answered id" mint "const ours = (t) => !!t && (t.name === a.name || (id !== null && t.id === id));" "const ours = (t) => !!t && t.name === a.name;" M7h 'cleanup DELETE'
# The Node-side token POST (2026-11-28): the dashboard edge answers an in-page write with an HTML 403.
mut XM12 "the token POST sent in-page again" mint "const mr = await postNode(base, {" "const mr = await call('POST', base, {" M1 'want {"contentType":"application/json","id8":"c0ffee12","status":200,"success":true}'
mut XM13 "the token POST follows redirects" mint "data: body, failOnStatusCode: false, maxRedirects: 0," "data: body, failOnStatusCode: false," M1 'maxRedirects is undefined'
mut XM14 "the token POST answer read as text" mint "parsed = await r.json();" "parsed = JSON.parse(await r.text());" M1 'read as text'
# Instrument rows: the P-shape/P-leak check and the page-serialization emulation must each catch a real slip.
mut XL1 "a revoke return bypasses the guard and carries the atok" revoke "return safe({ status: r.status(), contentType, success });" "return { status: r.status(), contentType, success, atok: l.atok };" R1 'P-shape'
mut XL2 "an in-page function closes over a Node-side variable" revoke "if (t.id.startsWith(prefix)) hits.push" "if (t.id.startsWith(a.pin)) hits.push" R1 'ReferenceError'
mut XL3 "a read return bypasses the guard with resource keys" read "return safe({ success: true, policies, skipped });" "return { success: true, policies, skipped, keys: t.policies.map((p) => Object.keys(p.resources)) };" D5 'P-shape'
# The late-atok wait (2026-11-28): each body's wait is load-bearing, and its .catch keeps signed-out a refusal.
WAIT_LINE="    await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});
"
mut XW1 "the read wait deleted" read "$WAIT_LINE" "" L1 '"atok":false'
mut XW2 "the mint wait deleted" mint "$WAIT_LINE" "" L2 '"atok":false'
mut XW3 "the revoke wait deleted" revoke "$WAIT_LINE" "" L3 '"atok":false'
mut XW4 "the read wait's .catch dropped" read "polling: 100 }).catch(() => {});" "polling: 100 });" D7 '"error":"TimeoutError"'
GOTO_LINE="    await page.goto(\`\${DASH}/profile/api-tokens\`, { waitUntil: 'domcontentloaded' });
"
mut XW5 "the read wait moved above its goto" read "$GOTO_LINE$WAIT_LINE" "$WAIT_LINE$GOTO_LINE" L1 '"atok":false'
mut XW6 "a second goto after the revoke wait" revoke "$WAIT_LINE" "$WAIT_LINE$GOTO_LINE" L3 '"atok":false'
mut XW7 "the read wait timeout 15 ms" read "timeout: 15000, polling: 100" "timeout: 15, polling: 100" L1 'wait timeout 15 '
mut XW8 "the read wait polls 'raf'" read "timeout: 15000, polling: 100" "timeout: 15000, polling: 'raf'" L1 'wait polling raf'
mut XW9 "the read wait called with two arguments" read "window.bootstrap.atok), null, { timeout" "window.bootstrap.atok), { timeout" L1 'wait timeout undefined'
mut XW10 "the read wait condition true before the atok" read "() => !!(window.bootstrap && window.bootstrap.atok), null" "() => !!window.bootstrap, null" L1 'the wait condition is not'
mut XW11 "the mint wait's .catch dropped" mint "polling: 100 }).catch(() => {});" "polling: 100 });" M3 '"error":"TimeoutError"'
mut XW12 "the revoke wait's .catch dropped" revoke "polling: 100 }).catch(() => {});" "polling: 100 });" R6 '"error":"TimeoutError"'
# Hold-wording parity (CTO F5): the sha-normalized compare still sees an edit AFTER the sha on a sha-bearing hold,
# so a normalization that ate the rest of the line would be RED here.
cp "$RUNBOOK" "$M/XH1.md"
FROM=', signed in as the old-account-owner login, only after' TO=', only after' perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$M/XH1.md"
! cmp -s "$RUNBOOK" "$M/XH1.md"; check "XH1 lands" $?
OUT="plan holds vs mutated runbook holds"
[[ -r "$PLAN_FILE" && "$(holds_norm "$PLAN_FILE")" != "$(holds_norm "$M/XH1.md")" ]]
check "XH1 (a runbook hold's wording edited) turns the hold compare RED" $?
# Citation coverage: a sha written outside the <body> (sha256=<hex>) form is not silently uncited.
cp "$RUNBOOK" "$M/XC1.md"
FROM='retire the bad token with `p5-revoke.js` (sha256=' TO='retire the bad token with `p5-revoke.js` at sha256=' perl -0pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$M/XC1.md"
! cmp -s "$RUNBOOK" "$M/XC1.md"; check "XC1 lands" $?
cite_check "$M/XC1.md"
[[ "$bad_cite" -ne 0 && "$OUT" == *"64-hex values"* ]]; check "XC1 (a runbook sha outside the citation form) turns the citation check RED" $?
# Sink mutants: scored only when the named row's FAIL line appears.
sink_mut() { # <id> <label> <from> <to> <row FAIL prefix>
  local err="$M/$1.err"
  mutate "$SINK" "$M/$1.py" "$3" "$4"; check "$1 lands" $?
  ( FAIL=0; run_sink_rows "$M/$1.py" >/dev/null 2>"$err" )
  OUT="$(cut -c1-200 "$err" | tr '\n' ' ')"
  grep -qF -- "[FAIL] $5" "$err"; check "$1 ($2) turns $5 RED" $?
}
sink_mut XS1 "sink peer check deleted" 'if self.client_address[0] != "127.0.0.1":' 'if False:' "S2b reason=peer"
sink_mut XS2 "sink keeps a partial file on a failed fsync" 'os.unlink(out)' 'pass' "S8 a failed fsync -> reason=write"

# --- anti-vacuity floor: EXACT counts (reported directly, never through fail()) -----------------
TOTAL=$((PASS + FAIL))
SELFTEST_PASSES=1
EXPECT_FULL=257
EXPECT_MUTANTS=100
case "$MODE" in full) want_n="$EXPECT_FULL" ;; *) want_n="$EXPECT_MUTANTS" ;; esac
if [[ $((TOTAL - SELFTEST_PASSES)) -ne "$want_n" ]]; then
  printf '  [FAIL] anti-vacuity floor: %s assertions ran in %s mode, the exact floor is %s\n' "$((TOTAL - SELFTEST_PASSES))" "$MODE" "$want_n" >&2
  printf 'Total: %s assertions, %s failed\n' "$TOTAL" "$((FAIL + 1))"
  exit 1
fi
echo "Total: ${TOTAL} assertions, ${FAIL} failed (mode=${MODE})"
[[ "$FAIL" -eq 0 ]]
