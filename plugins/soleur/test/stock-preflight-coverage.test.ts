// Stock-preflight coverage guard (#6453) — AC3.
//
// WHAT THIS PREVENTS: a 6th destroy-shaped `apply_target` shipping without the stock
// preflight. A terraform `-replace` DESTROYS before it creates, so if the target
// server_type has no stock in the target DC the destroy succeeds, the create fails
// `resource_unavailable`, and the fleet strands with no rollback. That is #6393, which
// froze the web-1 prod deploy leg ~10h (PIR corrected 2026-07-14, #6400).
//
// WHY NOT A COUNT CHECK: the plan's original AC3 was `grep -c 'stock_preflight' >= 4`.
// That does NOT bind a preflight to a PATH — four calls inside one job would pass it
// while three paths shipped unguarded. This test instead enumerates the
// `apply_target.options` enum (the authoritative list of dispatchable paths) and resolves
// each option to the JOB that runs it via that job's `if:` condition, then asserts the
// gate is in that job's body. A new option is therefore auto-enrolled: it must either
// carry the gate or be explicitly declared in EXCLUSION_ALLOWLIST. Silence is not an
// option — which is the whole point.
//
// WHY THE `if:` CONDITION IS THE MAPPING: each dispatch path is a separate job guarded by
// `inputs.apply_target == '<option>'`. That string IS the binding between the menu option
// an operator picks and the code that runs. Matching on the fully-quoted literal (not a
// bare substring) keeps `inngest-host` from matching `inngest-host-replace`.
//
// HCLOUD_TOKEN COUPLING (the P0 this locks down): every gate call site's step `env:` is
// `DOPPLER_TOKEN` only, and the sourced gate runs OUTSIDE the `doppler run` wrapper. A
// gated job that does not first read HCLOUD_TOKEN from Doppler would fail-closed on EVERY
// dispatch — a gate that always fails is an outage, not a tripwire, and it was the single
// most damaging defect this plan's review found. So a job carrying the gate MUST also
// carry the token read. Asserted per-job below so the defect cannot silently return.
//
// DOCUMENTED LIMITATION: this guard is one-directional in the same sense as its model
// (terraform-target-parity.test.ts). It proves every dispatchable option is gated-or-
// declared; it does NOT prove the gate is reached at runtime (a step-level `if:` that
// skips it, or an early `exit 0` above it, is not modelled). It also cannot see paths
// that are not `apply_target` options at all — notably web-3, which is born by an
// operator-local full apply outside CI (apply-web-platform-infra.yml:454) and adds zero
// options; that gap is structural and belongs to #6459.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync } from "fs";
import { parse as parseYaml } from "yaml";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);

// Options that legitimately do NOT need the stock preflight. Each entry is a DECLARED
// exclusion with a reason — an undeclared option fails the coverage test, so an author
// adding a path must make a conscious call rather than silently skipping the gate.
//
// NOTE ON SHAPE: modelled on terraform-target-parity.test.ts:79, but that allowlist holds
// terraform RESOURCE names — a different axis. Borrow the shape, not the set.
const EXCLUSION_ALLOWLIST = new Map<string, string>([
  [
    "manual-rerun",
    // The per-merge / allow-list re-run path (job `apply`). It performs no destroy, and
    // gating it would be actively harmful: a fail-closed check on the merge path would let
    // a Hetzner API blip wedge EVERY merge. That is the #6285 lesson, and it is exactly why
    // the plan rejected a terraform `data` source + precondition in favour of a shell gate
    // confined to the paths that destroy.
    "no destroy; fail-closed on the merge path would wedge every merge (#6285)",
  ],
  [
    "inngest-host",
    // Additive net-new host (job `inngest_host`). It does create a server, so stock can
    // still make the apply fail — but nothing is destroyed first, so a failed create leaves
    // the fleet intact and is a plain recoverable terraform error, not a strand. This gate
    // exists to prevent destroy-then-fail, not to pre-validate every create.
    "additive create; nothing destroyed first, so a stock miss is recoverable, not a strand",
  ],
  [
    "workspaces-luks-cutover",
    // #6604 first provision (job `workspaces_luks_cutover`). It creates a VOLUME + attachment +
    // secrets — NO hcloud_server — so stock-preflight-gate.sh (which `select(.type ==
    // "hcloud_server")`) hits its legitimate-empty out-of-scope branch and cannot fire. And its
    // OWN gate (workspaces_luks_cutover_gate) asserts web1_server_touched==0 + old_volume_touched
    // ==0 + resource_deletes==0 — additive-only, structurally incapable of destroying first, so a
    // failed create leaves the fleet intact (recoverable, not a strand). Same class as inngest-host.
    "additive volume create (no server → stock-preflight is a no-op); its own gate forbids any destroy, so a miss is recoverable, not a strand",
  ],
]);

// Sentinel: 7 options today (manual-rerun, inngest-host, inngest-host-replace,
// registry-host-replace, registry-region-migrate, git-data-host-replace,
// workspaces-luks-cutover).
// reason: 9 -> 7. warm-standby and web-2-recreate were REMOVED with the web-2
// dispatch sweep (#6575, 2026-07-20) after web-2 retired; both hard--targeted
// addresses that no longer exist. This floor is lowered to match a real deletion,
// NOT to make a failing assertion pass. `>=` so adding an option raises the count
// without a brittle exact-match edit — the coverage assertion is what enforces correctness. This
// only guards the parser silently collapsing to zero, which would make every assertion below vacuous.
const MIN_APPLY_TARGET_OPTIONS = 7;

// Sentinel for the same reason, on the other side of the ledger.
// reason: 5 -> 4. web-2-recreate was the fifth gated target; its job and its gate
// (tests/scripts/lib/web2-recreate-gate.sh) were both deleted by #6575.
const MIN_GATED_TARGETS = 4;

type Job = { if?: string; steps?: Array<{ name?: string; run?: string }> };

let options: string[] = [];
let jobs: Record<string, Job> = {};

/** The job that runs `option`, resolved via its `if:` guard. */
function jobFor(option: string): [string, Job] | undefined {
  // Fully-quoted literal so `inngest-host` cannot match `inngest-host-replace`.
  const needle = `inputs.apply_target == '${option}'`;
  const hits = Object.entries(jobs).filter(([, j]) =>
    (j.if ?? "").includes(needle),
  );
  return hits.length === 1 ? hits[0] : undefined;
}

/** Concatenated `run:` bodies of a job's steps. */
function jobBody(job: Job): string {
  return (job.steps ?? []).map((s) => s.run ?? "").join("\n");
}

const callsGate = (job: Job) => /\bstock_preflight_gate\s+tfplan\.json\b/.test(jobBody(job));
// Anchored on the `source` COMMAND, never the bare filename. Every call site carries a
// `# shellcheck source=tests/scripts/lib/stock-preflight-gate.sh` directive immediately
// above the real `source` line, so a bare `.includes("stock-preflight-gate.sh")` is
// satisfied by the COMMENT alone — deleting all five real `source` lines left this suite
// green. That blind spot maps to the worst runtime failure this gate has: unsourced =>
// `stock_preflight_gate` is undefined => rc 127 => `if !` => abort on EVERY dispatch of all
// five destroy paths. A gate that always fails is an outage, not a tripwire.
const sourcesGate = (job: Job) =>
  /^\s*source\s+\S*stock-preflight-gate\.sh/m.test(jobBody(job));
const readsToken = (job: Job) =>
  /doppler secrets get HCLOUD_TOKEN\b/.test(jobBody(job)) &&
  /\bexport HCLOUD_TOKEN\b/.test(jobBody(job));

beforeAll(() => {
  const wf = parseYaml(readFileSync(WORKFLOW, "utf8"));
  // `on:` is the YAML 1.1 boolean `true` after parsing — hence the `?? wf.on` fallback.
  const on = wf[true] ?? wf.on;
  options = on.workflow_dispatch.inputs.apply_target.options;
  jobs = wf.jobs;
});

describe("stock-preflight coverage over apply_target options (#6453 AC3)", () => {
  test("the options enum parses and did not collapse (non-vacuity)", () => {
    expect(Array.isArray(options)).toBe(true);
    expect(options.length).toBeGreaterThanOrEqual(MIN_APPLY_TARGET_OPTIONS);
    expect(new Set(options).size).toBe(options.length); // no dupes
  });

  test("every apply_target option resolves to exactly one job (non-vacuity)", () => {
    // If this collapses, every coverage assertion below would pass by finding nothing.
    // `manual-rerun` is deliberately included: it maps to `apply` via an `||` branch, so
    // this also proves the matcher survives a compound condition.
    const unresolved = options.filter((o) => !jobFor(o));
    expect(unresolved).toEqual([]);
  });

  test("every option is EITHER gated by the stock preflight OR a declared exclusion", () => {
    // The auto-enroll assertion. A new destroy-shaped apply_target that forgets the gate
    // lands here, not in production.
    const unguarded = options.filter((o) => {
      if (EXCLUSION_ALLOWLIST.has(o)) return false;
      const found = jobFor(o);
      return !found || !callsGate(found[1]);
    });
    expect(unguarded).toEqual([]);
  });

  test("at least the five known destroy-shaped targets are gated (non-vacuity)", () => {
    const gated = options.filter((o) => {
      const found = jobFor(o);
      return found ? callsGate(found[1]) : false;
    });
    expect(gated.length).toBeGreaterThanOrEqual(MIN_GATED_TARGETS);
  });

  test("the exclusion allowlist is not stale — every entry is still a real option", () => {
    // A removed/renamed option must not linger as a silent carve-out.
    const orphans = [...EXCLUSION_ALLOWLIST.keys()].filter(
      (o) => !options.includes(o),
    );
    expect(orphans).toEqual([]);
  });

  test("no excluded target carries the gate (the allowlist states the truth)", () => {
    // Guards the allowlist drifting into a lie: if someone gates an excluded target, the
    // reason recorded here ("additive, no destroy") is no longer why it is excluded.
    const contradictions = [...EXCLUSION_ALLOWLIST.keys()].filter((o) => {
      const found = jobFor(o);
      return found ? callsGate(found[1]) : false;
    });
    expect(contradictions).toEqual([]);
  });

  test("every gated job SOURCES the gate lib (no call to an undefined function)", () => {
    const missing = options.filter((o) => {
      const found = jobFor(o);
      return found && callsGate(found[1]) && !sourcesGate(found[1]);
    });
    expect(missing).toEqual([]);
  });

  test("every gated job reads HCLOUD_TOKEN from Doppler (P0 — else it fail-closes 100%)", () => {
    // The single most damaging defect this plan's review found. The step env: is
    // DOPPLER_TOKEN only and the gate runs outside `doppler run`, so without an explicit
    // read the gate aborts EVERY dispatch. That is an outage wearing a tripwire's clothes.
    const tokenless = options.filter((o) => {
      const found = jobFor(o);
      return found && callsGate(found[1]) && !readsToken(found[1]);
    });
    expect(tokenless).toEqual([]);
  });

  test("no [ack-destroy] bypass guards the stock preflight (AC4's structural half)", () => {
    // The gate's abort messages MENTION `[ack-destroy]` to say there is none, so a bare
    // token grep is useless here (it scores 10 on a diff that adds zero bypasses). Assert
    // the syntactic construct instead: no gated job branches on the commit message.
    const bypassed = options.filter((o) => {
      const found = jobFor(o);
      if (!found || !callsGate(found[1])) return false;
      return /if\s*\[\[.*HEAD_MSG.*ack-destroy/s.test(jobBody(found[1]));
    });
    expect(bypassed).toEqual([]);
  });
});
