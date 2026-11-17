#!/usr/bin/env bash
# exec-placement-probe.sh — discoverability probe for the #9137 placement-aware
# Inngest step-call execution (plan Observability discoverability_test):
#
#   bash apps/web-platform/scripts/exec-placement-probe.sh   ->   "exec-placement: ok"
#
# Exercises the REAL decision module end to end — module load plus one
# decidePlacement call per decision-table row — through `bun -e` (the same
# bun-eval shape as agent-outer-wrap-debug.sh). Vitest-free, network-free,
# env-free: every fact is fed in literally, so the probe verifies the decision
# TABLE's rows in <15 s on a cold checkout. Non-zero exit names the row that
# broke; only the ok line goes to stdout on success.
set -euo pipefail

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$APP_DIR"

if ! command -v bun >/dev/null 2>&1; then
  printf 'exec-placement-probe: bun not on PATH\n' >&2
  exit 3
fi

bun -e '
const {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_URL,
  EXEC_HOST_PRIVATE_IP,
  classifyFnId,
  decidePlacement,
  gatherPlacementFacts,
  refuseResponse,
} = await import("./server/inngest/exec-placement.ts");

const facts = (over) => ({
  method: "POST",
  hasProbe: false,
  fnId: "soleur-runtime-agent-on-spawn-requested", // volume-bound
  marked: false,
  isExec: false,
  hasSignature: true,
  hostIp: null,
  ...over,
});

// One real decidePlacement call per decision-table row.
const rows = [
  ["non-POST executes",        facts({ method: "GET" }),                                  { action: "execute" }],
  ["probe executes",           facts({ hasProbe: true }),                                 { action: "execute" }],
  ["portable executes",        facts({ fnId: "soleur-runtime-cron-anthropic-cost-report" }), { action: "execute" }],
  ["pinned on exec executes",  facts({ isExec: true }),                                   { action: "execute" }],
  ["pinned non-exec forwards", facts({}),                                                 { action: "forward", target: EXEC_FORWARD_URL }],
  ["unsigned refuses",         facts({ hasSignature: false }),                            { action: "refuse", reason: "missing_signature" }],
  ["identity-missing refuses", facts({ isExec: "unknown" }),                              { action: "refuse", reason: "exec_identity_missing" }],
  ["marked non-exec refuses",  facts({ marked: true }),                                   { action: "refuse", reason: "marked_on_nonexec" }],
  ["marked on exec executes",  facts({ marked: true, isExec: true }),                     { action: "execute" }],
  ["no-fnId forwards",         facts({ fnId: null }),                                     { action: "forward", target: EXEC_FORWARD_URL }],
  ["-failure inherits",        facts({ fnId: "soleur-runtime-agent-on-spawn-requested-failure" }), { action: "forward", target: EXEC_FORWARD_URL }],
];

let failed = 0;
const fail = (name, got) => {
  failed += 1;
  console.error(`exec-placement-probe: row "${name}" -> ${JSON.stringify(got)}`);
};
for (const [name, f, want] of rows) {
  const d = decidePlacement(f);
  if (
    d.action !== want.action ||
    (want.target !== undefined && d.target !== want.target) ||
    (want.reason !== undefined && d.reason !== want.reason)
  ) fail(name, d);
}

// One real env-gathered round-trip through gatherPlacementFacts: non-exec
// host + the loop-guard marker -> refuse, 403 refuseResponse wire shape.
process.env.SOLEUR_HOST_PRIVATE_IP = "10.0.1.11";
const marked = new Request("https://app.soleur.ai/api/inngest", {
  method: "POST",
  headers: { [EXEC_FORWARD_HEADER]: "1", "x-inngest-signature": "t=1&s=x" },
});
const d2 = decidePlacement(gatherPlacementFacts(marked));
if (d2.action !== "refuse" || d2.reason !== "marked_on_nonexec") fail("gather-round-trip", d2);
else if (refuseResponse(d2).status !== 403) fail("refuse-shape", refuseResponse(d2).status);

// The pin and the classifier are load-bearing too.
if (EXEC_HOST_PRIVATE_IP !== "10.0.1.10") fail("exec-pin", EXEC_HOST_PRIVATE_IP);
if (EXEC_FORWARD_URL !== "https://10.0.1.10:8445/api/inngest") fail("forward-url", EXEC_FORWARD_URL);
if (classifyFnId("soleur-runtime-agent-on-spawn-requested") !== "volume-bound") {
  fail("classify", classifyFnId("soleur-runtime-agent-on-spawn-requested"));
}

if (failed) {
  console.error(`exec-placement: FAIL (${failed} row(s))`);
  process.exit(1);
}
console.log("exec-placement: ok");
'
