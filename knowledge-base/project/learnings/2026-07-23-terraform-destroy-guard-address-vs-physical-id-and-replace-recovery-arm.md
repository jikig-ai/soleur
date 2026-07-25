# Learning: a terraform-plan destroy-guard that authorizes by ADDRESS is blind to state corruption, and a `-replace` without `create_before_destroy` needs a recovery arm

## Problem

Building `workspaces-luks-recut` (#6855, the prerequisite for the #6812 re-cut): a gated
`apply_target` that does a scoped `terraform -replace=hcloud_volume.workspaces_luks` to destroy the
dead-man-orphaned LUKS volume and recreate it raw, on **sole-copy user data**. The destroy-guard
(`tests/scripts/lib/workspaces-luks-recut-gate.sh`) was authored — and mutation-tested 17/17 — as a
pure **plan-shape** gate: it partitions the `terraform show -json` resource_changes by terraform
ADDRESS (allow-set = the volume + attachment; each live/passphrase address pinned to zero actions;
`out_of_scope` catching everything else). `security-sentinel` adversarially confirmed it fails closed
against every dangerous plan-shape.

Two review P2s landed on the guard anyway — both outside the plan-shape model:

1. **Address→physical-id gap (user-impact-reviewer).** The guard authorizes destruction entirely by
   terraform ADDRESS, with zero binding to the physical Hetzner volume id. If state ever mapped
   `hcloud_volume.workspaces_luks` onto the LIVE volume's physical id (a bad `state mv`, an import
   error, R2 state corruption, or drift between plan-authoring and the operator's later dispatch), a
   `-replace` of the *correct address* destroys the *wrong physical volume* — and every address-based
   counter reads 0, so the guard PASSES. On sole-copy + irreversible data that is total loss.
2. **Destroy-before-create recovery (architecture-strategist).** `hcloud_volume` has no
   `create_before_destroy`, so `-replace` is destroy-then-create. An apply that fails between the
   delete and the create strands the volume OUT of state. A re-dispatch then plans a **bare create**
   (`-replace` on an absent address plans a plain create) — which the guard's "must be a genuine
   replace (delete AND create)" clause REJECTED. The shipped error message said "re-dispatch to
   recreate," which would have looped forever, stranding a non-technical operator on manual terraform.

## Solution

- **Id-pin (closes #1):** the operator supplies `expected_luks_volume_id` (the orphaned volume's
  Hetzner id, read from the drift run's `Refreshing state... [id=…]` line); the gate asserts the
  *replaced* volume's `.change.before.id` equals it. A mismatch ABORTS — binding destruction to the
  physical volume the operator named, not just an address the state resolves. The workflow validates
  the id is numeric in the confirm preflight and passes it as the gate's 2nd arg.
- **Recovery arm (closes #2):** `luks_volume_provisioned` accepts a genuine replace (delete AND
  create) **OR** a bare create when `.change.before == null` (the stranded-recovery shape — a fresh
  empty volume touches no live data; every data-safety counter is unchanged). Re-dispatch now
  auto-recovers (`hr-exhaust-all-automated-options`), and the id-pin is a correct no-op there
  (`before == null` → nothing to destroy). The messages were corrected to match.

## Key Insight

**A plan-shape guard proves "the plan does the right thing to the right ADDRESSES"; it cannot prove
"the addresses resolve to the right PHYSICAL objects."** For a destroy-guard on irreversible /
sole-copy data, that second question is the catastrophe axis, and it is invisible to address-based
counters *and* to an adversarial reviewer working within the address model (security-sentinel found
the guard sound; user-impact-reviewer, enumerating data-loss vectors, found the id gap). Mitigation:
**bind destruction to an operator-confirmed physical id** (`before.id` pin) — the "name the thing
you're destroying" discipline, standard for irreversible infra ops.

Corollary: **a scoped `-replace` on a resource without `create_before_destroy` has a
mid-apply-failure state where the resource is gone from state; the guard must accept the bare-create
recovery shape** or a re-dispatch loops and the operator is stranded on manual terraform. Requiring a
"genuine replace" is *too strict* — a bare create of a fresh volume is provably safe.

Secondary (recurring): **adding an `apply_target` choice has FOUR registration sites** — the workflow
`options:` list, the parity-test strip clause (`terraform-target-parity.test.ts`), the
stock-preflight `EXCLUSION_ALLOWLIST` (`stock-preflight-coverage.test.ts`), and the `test-all.sh`
suite line. The full-suite exit gate (not the touched-file loop) is what catches a missed
stock-preflight registration — run `test-all.sh` before shipping any new `apply_target`.

## Session Errors

- **Bare-repo `git ls-files` returned a stale/misleading listing** at the bare root (hid
  `workspaces-luks.tf` / the `workspaces-luks-*.yml` workflows). Recovery: cross-checked with `git
  grep main` and `git ls-tree main`. Prevention: at a bare root, trust `git grep <ref>` / `git
  ls-tree <ref>`, never `git ls-files` (already in learning 2026-05-19-bare-repo-grep-…).
- **Two planning subagents died** (API "connection closed mid-response"; then a 600s stall).
  Recovery: fell back to running `/plan` inline. Prevention: on repeated background-agent failure,
  switch to inline execution rather than re-spawning into the same instability.
- **`test-all.sh` foreground timed out at the 2-min tool limit.** Recovery: ran it via
  `nohup … &` + a Monitor watching for process exit + the log verdict. Prevention: always background
  `test-all.sh` (already in work SKILL.md; the nohup "exit 0" notification is the wrapper, not the
  suite — read the log's summary line).
- **Recut-gate mutation test failed 2/17 on first run** — synthesized JSON fixtures used raw
  `["web-1"]` whose inner quotes broke the JSON string. Recovery: escaped to `[\"web-1\"]` (matching
  the sibling cutover-gate test). Prevention: when synthesizing terraform-address fixtures with
  `printf '%s'`, escape the `["key"]` inner quotes.
- **stock-preflight-coverage test failed in the full suite** — the new `apply_target` option was not
  in `EXCLUSION_ALLOWLIST`. Recovery: added the entry (no `hcloud_server` in its targets → stock is a
  no-op, same as the cutover sibling). Prevention: the four-registration-sites insight above.
- **Two P2 review findings on my own guard** (address-vs-id; missing recovery). Recovery: fixed
  inline. Prevention: the Key Insight above — apply the physical-id-pin + recovery-arm lenses to any
  future terraform destroy-guard on irreversible data.

## Tags
category: security-issues
module: apps/web-platform/infra + tests/scripts/lib
refs: 6855, 6812, ADR-119
