---
title: "fix: the registry user_data budget gate measures a payload terraform never renders"
type: fix
date: 2026-08-06
lane: cross-domain
issue: null  # DESCOPED — closes nothing; #7299 belongs to PR #7300
refs: [7247, 7287, 7278, 7299, 7300, 7302, 7309, 7310]
brand_survival_threshold: aggregate pattern
---

# fix: the registry user_data budget gate measures a payload terraform never renders

> ## ⚠️ DESCOPED 2026-08-06 — the gate fix moved to PR #7300
>
> This plan was authored without noticing that a parallel session was **already fixing the same
> defect**: PR #7300 (branch `feat-one-shot-7299-registry-userdata-over-cap`, opened 2026-08-05
> 21:39Z) rewrites `registry-userdata-budget.sh` for the identical cause, and had already run its
> agent review pass and applied the findings (commits prefixed `review:`) by the time this plan's
> implementation was underway. To be precise, since this claim was load-bearing for the descope:
> #7300 is still an OPEN **draft** with `reviews: []` on GitHub — it has NOT been approved. What
> made duplicating it wasteful was that its implementation was complete and reviewed, not that it
> was merge-ready.
>
> The collision was missed because `one-shot`'s Step 0a.5 gate ran against the INVOKED issues
> (#7247 / #7287 / #7278) and cleared them; the planning phase then correctly re-diagnosed the
> real defect and re-targeted **#7299**, which no gate had checked. A target discovered *after*
> the collision gate runs is not covered by it.
>
> **What was dropped from this PR** (all of it duplicated #7300):
> `apps/web-platform/infra/registry-userdata-budget.sh`, the accompanying
> `registry-render-strip-parity.test.sh`, and the `.github/workflows/infra-validation.yml`
> changes (suite registration + removing `continue-on-error`, which #7300 also removes).
>
> **What this PR still ships** — not in #7300, and correct whichever gate implementation lands:
> 1. The recut runbook's `user_data` precondition, which hard-coded a measurement the gate got
>    wrong and told operators the recut "must not be dispatched at all".
> 2. ~~`scripts/lint-diagnosis-claims.sh` — scope widened~~ — **also split out, to #7310.** The
>    widening works, but once it does it correctly flags the message #7300 deletes, taking a
>    BLOCKING lint's census above its ratchet until #7300 merges. Every measurement is on #7310.
> 3. The **#7287 body + comment corrections** and the **two follow-up filings (#7309, #7310)** —
>    Phase 3 and Phase 4 of `tasks.md`. Both shipped and are live on the tracker.
>
> **Which phases below still describe this PR.** Numbering differs between this plan and
> `tasks.md`; this list uses THIS file's numbering. Phases 1, 2 and 2b are **superseded by
> #7300**. Phase 2c is **not** superseded by #7300 (it never touched
> `scripts/lint-diagnosis-claims.sh`) — it moved to **#7310**. Phase 3 (the runbook) shipped.
> Everything superseded is retained only as the record of how the defect was measured, including
> the *Files to Edit* / *Files to Create* / *Observability* blocks and AC1–AC13, which still
> describe the dropped gate work. Read the measurements, not the checkboxes — and note the
> checkboxes that track what this PR actually shipped live in `tasks.md`, not here.
>
> One divergence worth naming: this plan specifies `rc=3` for "unmeasured" and a `strip_applied`
> JSON field. **PR #7300 ships neither** — it uses exit `2` for unmeasured and a `stripped_bytes`
> field. The runbook in this PR follows the SHIPPED script, so where the two disagree the plan is
> the stale one.

Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed); there is no
`knowledge-base/project/specs/feat-one-shot-7247-zot-crash-loop-recovery/spec.md`.

**Revised after 6-agent plan review (v2), then deepened (v3).** See *Plan Review Revisions* and
*Research Insights* for what changed and why.

## Enhancement Summary

**Deepened on:** 2026-08-06 · **Gates run:** 4.5 (network-outage, fired), 4.6 (user-brand, pass),
4.7 (observability, pass — 5/5 fields, no shell-access command), 4.8 (PAT-shaped, pass — no
matches), 4.9 (UI wireframe, skipped — no UI surface), 4.10 (encryption posture, trigger does not
fire after R3 removed the `.tf` edit), 4.55 (downtime/cutover, does not fire — no serving resource
is touched and AC12 pins that the render is unchanged).

### Key improvements from the deepen pass

1. **Both new-arm dependencies are already provisioned in the registration target.** The
   `deploy-script-tests` job (`.github/workflows/infra-validation.yml:339`) already pins
   `hashicorp/setup-terraform@5e8dbf3c…` and already apt-installs `cloud-init` — with a comment
   noting cloud-init "serves TWO consumers in this job, both of which SKIP or fail". So B7
   (terraform-absent) and B9 (`cloud-init schema`) need **no new setup steps**, and the job already
   carries the skip-vs-fail discipline those arms depend on. This removes the largest execution risk
   the reviews raised.
2. **The continuation-comment arm is non-vacuous and currently clean.** Measured:
   **0** occurrences of a comment directly after a line continuation in `cloud-init-registry.yml`,
   against **11** line-continuation lines present. The at-risk shape is real; the defect is not there
   yet. B1.11 guards the gap ADR-152's "comments are now free" belief would otherwise open.
3. **Every negative claim in the plan was probed** rather than asserted (Phase 4.45). See *Research
   Insights → Verified negatives*.

## Overview

`apps/web-platform/infra/registry-userdata-budget.sh` is the offline gate that decides whether the
registry host can be re-provisioned. It answers **`OVER CAP by 3,636 bytes` (rc=1)**, and three
surfaces treat that as a hard stop: the recut runbook
(`registry-luks-recut-6929.md:64` — *"the recut must not be dispatched at all"*), issue #7287's
precondition (c) (*"currently BREACHED and is a hard blocker"*), and issue #7299 (OPEN, P1).

**That verdict is a measurement artifact.** The script renders

```hcl
rendered = templatefile("${DIR}/cloud-init-registry.yml", local.vars)   # registry-userdata-budget.sh:85
stored   = base64gzip(local.rendered)                                   # :86
```

while `hcloud_server.registry` renders

```hcl
user_data = base64gzip(replace(templatefile("${path.module}/cloud-init-registry.yml", {
  … }), local.registry_rationale_strip, ""))                            # zot-registry.tf:451 … :494
```

The script omits the `replace(…)` wrapper, so it measures an artifact terraform never produces.

**Measured on this branch (base `546294c1f`) with terraform's own `base64gzip`:**

| Render | `base64gzip` length | vs. 32,768 B cap |
|---|---|---|
| **un-stripped** (what the gate measures) | **36,404 B** | −3,636 B — OVER |
| **stripped** (what `zot-registry.tf:451-494` renders) | **9,404 B** | **+23,364 B headroom** |

Corroborated independently: `plugins/soleur/test/cloud-init-user-data-size.test.ts` models the strip
correctly, its comment at `:165` says *"~9 KB"*, and it is green (38 pass / 0 fail). Two gates, one
invariant, opposite verdicts — and the wrong one is the one every recovery surface cites.

**Scope honesty:** this clears **one of four** blockers on #7287's ordered path, and the blocker it
clears is *documentary*, not mechanical — no workflow job calls this gate as a precondition (the
`registry_luks_recut` job does not invoke it; the CI job that does runs `continue-on-error: true`).
The durable value is Phases 1-2 (the gate stops lying); the unblocking value is Phase 3 (the prose
that quotes it stops lying). Both are worth doing; they are not the same thing.

### Why it is on the critical path of the #7247 deploy freeze

`hcloud_server.registry` carries no `lifecycle.ignore_changes = [user_data]` — deliberately
(`zot-registry.tf:426`, `:496`) — and ADR-096 makes the host cloud-init-only (no `remote-exec`, no
inbound shell, no config webhook; `push-infra-config.sh` targets web-1 and its `DEST_SPEC` allowlist
holds no registry path). So a `cloud-init-registry.yml` change reaches the host **only** by
destroy-and-recreate, and `registry-luks-recut` is an atomic 3-way `-replace` of
`hcloud_volume.registry` + `hcloud_volume_attachment.registry` + `hcloud_server.registry` whose
CREATE runs *after* the DESTROY, subject to the 32,768 B cap.

Consequently **two already-merged fixes are inert in production** — #7274's widened crash-cause
capture and #7283's zot v2.1.20 pin — and the live telemetry proves it.

### Measured live state (2026-08-05 23:00Z, `hr-no-dashboard-eyeball-pull-data-yourself`)

Pulled via `doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 12h
--grep SOLEUR_ZOT_DISK`. The channel is allow-listed and live — the newest row was 2 minutes old, so
an empty result was never at risk of reading as an all-clear.

- `zot_restarts` 12,087 → 12,668 over 12 h (~4.0/min); `boot_id`
  `c60e54b7-41f2-4ff5-92e9-0a6e8f215cac` unchanged — no reboot, no replace.
- `ping_rc=0`, `state_status=running`, `oom_killed=false`, `zot_oom_kills=0`, `exit_code=0` — the
  non-OOM signature holds.
- **`pcent` climbed 96 → 99 → 100 between 20:35Z and 22:00Z** and stayed at 100. The store
  filesystem is now full — a material change from the 89% in the #7247 thread at 14:20Z.
- **No `zot_uptime_s`, no `zot_last_err_src`, no `zot_image_digest` in the emitted line.** Those
  were added by #7274 (`8565210d6`) and #7283 (`6720f2ae0`) — off-host proof the host predates both.
- `zot_last_err` carries routine chatter, truncated **mid-token at the start** — the `tail -c`
  signature #7274 replaced with `head -c`. The panic header is still discarded.

## Premise Validation (Phase 0.6)

| Premise as given | Verification | Verdict |
|---|---|---|
| *"widening the `zot_last_err` tail is the cheapest next diagnostic"* | `cloud-init-registry.yml:311-355` — ranked tiers, `--since 12m`, `head -c 300`, `zot_last_err_src` | **STALE — shipped in #7274.** The gap is *delivery*, not authorship. |
| #7274 merged against #7247 | `gh pr view 7274` | HOLDS |
| #7283 closed #7282; #7290 closed #7277 | `closedBy:[7283]`, `closedBy:[7290]`; D10 PASS at `scripts/registry-pull-path-health.sh:538` | HOLDS |
| *"#7280 fixed the cap … the recut lever should now render a valid payload"* | Gate says `headroom:-3636`, rc=1; real render measures 9,404 B | **PARTLY STALE.** The strip *is* applied and the payload *is* valid; the gate certifying it was never updated. |
| #7247, #7287, #7278 OPEN, zero closing PRs | `gh issue view` ×3 → `closedBy:[]` | HOLDS |
| *"verify the GitHub environment's required-reviewer set is non-empty"* | `registry_luks_recut` job has **no `environment:`**, deliberately (an unprovisioned environment silently auto-approves, DP-11 F8) | **NOT APPLICABLE.** Authorization is menu-ack + typed `confirm` + volume id-pin + CODEOWNERS. |
| #7299's *"extend `registry_rationale_strip` to recover ≥3,636 B"* | The strip is already applied; applying it yields 9,404 B | **FALSIFIED.** |
| #7302's body: *"That PR … dropped `continue-on-error: true`"* | `.github/workflows/infra-validation.yml:1194` still carries it | **FALSIFIED** — #7302 records as shipped a change that never shipped (drives Phase 2b). |

## Research Reconciliation — Spec vs. Codebase

| Claim carried in | Codebase reality | Plan response |
|---|---|---|
| ARGUMENTS: widen `zot_last_err` | Merged (#7274) and inert | Re-scope to the delivery blocker. |
| #7299: real payload over cap | ~9.4 kB stripped | Fix the model. **DESCOPED — owned by PR #7300; this PR does NOT close it.** |
| #7287 (c) BREACHED | Measurement artifact | Correct the runbook **and #7287's body**. |
| `zot-registry.tf:383-386` *"nothing here to keep equal"* | Stays **true** post-fix — the `.sh` will extract, not restate | **Do not edit** (see Revisions R3). |
| ARGUMENTS: environment reviewer set | No `environment:` by design | Drop that check. |
| ARGUMENTS: disk 89% | `pcent=100` | Record as state; do not promote to cause. |

## Problem Statement

A gate whose verdict does not describe the artifact it claims to describe is worse than no gate: an
authoritative stop sign in front of an open road. It compounds three ways: it is a false stop on the
recovery path; it has already generated derived work on a false premise (#7299's remedy would trim
prose production does not need); and it is invisible in CI, because
`.github/workflows/infra-validation.yml:1194` carries `continue-on-error: true`, swallowing rc=1 on
every run.

The closest prior art is the same file and host —
`knowledge-base/project/learnings/2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md`
(#7280): *"extraction pins what the expression **is**, and says nothing about whether `user_data`
**applies** it."* That is why the `.ts` gate grew `registryStripIsApplied`. This plan is the inverted
half: the `.sh` gate has neither the expression nor the application.

## Proposed Solution

Make the gate measure what `zot-registry.tf` renders, deriving the decision from the `.tf` rather
than restating it — the discipline `cloud-init-user-data-size.test.ts` already applies, and the
local convention `registry-userdata-budget.sh:43-52` already uses for `zot_image_amd64`
(*"Same fact, same parse rule, everywhere"*). Four properties:

1. **Extract, never restate.** Read `local.registry_rationale_strip` from `zot-registry.tf`,
   **comment-stripped first**, exactly-once, `(?m)`-anchored, slash-delimited; fail closed (exit 2)
   on each violation. Paste the **whole assignment line verbatim** into a separate `strip.tf` in the
   scratch dir rather than unescaping the regex body into a shell variable — terraform merges locals
   across files in a directory (verified), so terraform sees byte-identical source and the
   heredoc backslash-halving class (`registry-userdata-budget.sh:59` is an unquoted heredoc;
   `git-data-render-strip-parity.test.sh:67-76` documents the hazard) never arises.
2. **Apply it iff production applies it, judged positionally and comment-blind.** The extracted
   expression must be the **second argument of the `replace()` that wraps `templatefile(`** inside
   `base64gzip(` — mirroring `registryStripIsApplied`'s paren-balancing (`:453-472`), not merely
   "referenced somewhere in the resource block". Determine this over the **same comment-stripped
   source** as extraction. Both refinements close permissive-direction holes: a mere-presence check
   is satisfied by the inline-literal mutation the `.ts` file names as the likely real edit
   (`:556-565`), and a comment-blind check is required because rationale prose quoting the wrapper
   would otherwise pin applied-ness `true` forever.
3. **Never report a verdict it did not measure.** `terraform` absent currently exits **0** with no
   JSON (`:38-41`) — on a pre-DESTROY precondition, "could not check" reads as "all clear". Exit a
   distinct **3** with `{"skipped":true,"reason":"terraform-absent"}`, and hard-fail under `CI=true`.
4. **Two failure causes, two exits** (ADR-166 — a message may only name a cause the job measured).
   Over-cap *with* the strip applied is a payload-size problem ("trim prose"); strip *not applied* is
   a code defect in `zot-registry.tf`, where "trim prose" is wrong advice. The current single message
   asserts *"#7280's `registry_rationale_strip` is the fix"* when the strip is already applied.

### Alternatives considered

| Alternative | Why not |
|---|---|
| Trim ≥3,636 B more prose (#7299's suggestion) | Solves a problem production does not have; leaves the gate lying. |
| Byte-equality between the `.sh` and `.ts` gates | Non-equivalent by design (terraform `base64gzip` vs node `gzipSync(level 9)`; `git-data-userdata-budget.sh` forbids `-9` as headroom-overstating). Assert the same *modelling decision* and *identical verdicts over a fixture matrix*, never the same number. |
| Hard-code the regex in the `.sh` | The two-copy drift this plan exists to remove. `git-data-userdata-budget.sh:52` shows exactly what that looks like. |
| Delete the `.sh`, rely on the `.ts` | The `.sh` is the credential-free offline probe the runbook and #7287 cite before a destructive dispatch. The role is real. |
| Re-implement the `.tf`'s properties in bash (original A1/A2/A5/A6) | Already asserted by `cloud-init-user-data-size.test.ts:397-473`, `:579-593`, `:617-663`, which runs on **every** PR via `ci.yml` — unlike `infra-validation.yml`, which is paths-filtered. Duplicating them enforces *less*, in a third parser. Cut (R1). |
| Move the render into a provider-free `modules/registry-userdata/` | Deletes the parity problem outright (one render expression, one application). Right direction, wrong moment: it changes `${path.module}` resolution on a ForceNew `user_data` for the sole pull path, mid-freeze, with a destructive recut pending. Deferred with a tracker (R8). |
| Fire `registry-luks-recut` | Out of scope; not ready. See *Out of Scope*. |

## Hypotheses

Triggered by the shell-access term in the work description (Phase 1.4,
`hr-ssh-diagnosis-verify-firewall`).

**Standing discipline: the identity of the zot panic is `UNKNOWN` and this plan does not name a
cause.** The deciding datum is the panic header, which the live host's `tail -c 300` capture
discards; the `head -c` fix exists only in #7274, undelivered. Any verdict would reason past an
invisible discriminator.

- **L3 firewall / L3 DNS-routing** — `[not verified; not this plan's claim]`. Deny-all public ingress
  by design (`zot-registry.tf:593`); pull transport is private-net only. Partial evidence against a
  total L3 fault, from the host's own telemetry: the Better Stack POST succeeded on every 5-minute
  tick (egress OK) and `ping_rc=0` on every row (the host reaches zot on its private IP). Says
  nothing about web-host→registry reachability, open separately as **#7267** / **#7262**. This plan
  changes no firewall or routing.
- **L7 TLS/proxy** — `[not applicable]`. The gate is an offline local render with no network I/O.
- **L7 application (zot)** — `[UNKNOWN]`. The panic is in `scheduler.(*Scheduler).poolWorker`; which
  task panics is not established. Two facts held without fusing them into a verdict: `pcent=100`,
  and `gcInterval: 1h` is the only reclamation lever (zot v2.1.20 exposes no on-demand gc endpoint,
  measured under #7282). A full store is a plausible antecedent for a GC/dedupe panic; it is **not**
  measured as the cause. Naming it would repeat the failure ADR-166 exists to prevent.

**Opt-out:** no L3 artifact is produced because no hypothesis in the deliverable depends on one —
the change touches no network path, firewall, or host.

## Implementation Phases

### Phase 1 — RED: pin what only the `.sh` can be wrong about

New `apps/web-platform/infra/registry-render-strip-parity.test.sh`. Every arm asserts a property of
**the gate script**, never of `zot-registry.tf`/`cloud-init-registry.yml` (those belong to the `.ts`
gate, which runs more often — see *Alternatives*).

**Seam:** the script resolves `DIR` from `BASH_SOURCE` (`:33`) and reads `$DIR/zot-registry.tf` and
`$DIR/cloud-init-registry.yml`; there is no override and none is added. Each arm copies
`registry-userdata-budget.sh` + a (possibly mutated) `zot-registry.tf` + `cloud-init-registry.yml`
into one `mktemp -d` and runs the copy. No production script grows a test-only hook.

| Arm | Fixture | Expected |
|---|---|---|
| **B1** positive control | pristine | stripped figure, `strip_applied: true`, **exit 0** |
| **B2** wrapper unwired | `replace()` removed | un-stripped figure, **non-zero**, message names the *code defect*, not "trim prose" |
| **B3** inline literal | `replace()` kept, strip passed as an inline literal, local left as decoration | non-zero (positional check rejects it) |
| **B4** comment-quotes-the-wrapper **and** unwired | B2 plus a comment carrying `user_data = base64gzip(replace(templatefile(` and the assignment shape | same as B2 — comment-blindness on **both** paths |
| **B5** duplicate declaration | assignment twice | **exit 2**, names the duplicate |
| **B6** non-`(?m)` literal | anchor removed | **exit 2**, names the anchoring requirement |
| **B7** terraform absent | `PATH` without terraform | **exit 3**, `{"skipped":true}`, and a hard `fail` under `CI=true` |
| **B8** no restated literal | pristine | comment-stripped script contains no strip regex in any spelling (`\\{1,2}t` tolerant) |
| **B9** cloud-config validity | pristine stripped render | `cloud-init schema --config-file` exits 0 |
| **B10** cross-gate agreement | B1/B2/B3/B5/B6 fixtures | the `.sh` verdict and the `.ts` predicates agree on **every** fixture (same verdict, never same bytes) |

B1 is the load-bearing RED assertion: the unfixed script reports un-stripped/non-zero on *every*
fixture, so B2 alone cannot discriminate a correct fix from no fix. Non-vacuity floor: a fixed
assertion count only a fully-tooled run can reach; terraform and `cloud-init` absence are hard
failures under `CI=true` (mirroring `git-data-render-strip-parity.test.sh:150-155`), never silent
skips — `run-registered-suites.sh:41-45` prints `PASS` for a self-skip.

B9 uses the official validator, verified during planning: `cloud-init` 26.1, `Valid schema` on the
stripped render, rc 0 valid / rc 1 invalid. It asserts a property nothing else asserts — the
stripped payload has **never booted** (the live host predates the strip).

**Registration is part of Phase 1, not an afterthought.** `run-registered-suites.sh:121-124` derives
its execute set by grepping `run: bash apps/web-platform/infra/<name>.test.sh` out of
`.github/workflows/infra-validation.yml`; `.github/scripts/test/test-infra-suite-registration.sh`
hard-fails any unregistered suite and runs in a **required** check. Register the suite as a
single-line `run:` step in `deploy-script-tests` (mirror `:1062`, which already pins
`setup-terraform`). Unregistered, the suite runs nowhere and AC "test-all green" passes vacuously.

### Phase 2 — GREEN: fix the gate

`apps/web-platform/infra/registry-userdata-budget.sh`:

- Comment-strip `zot-registry.tf` once; reuse that source for the existing `zot_image_amd64` read
  (`:48`) so one file has one parse rule. Every new extraction step carries its own `|| exit 2` —
  the script runs `set -uo pipefail` without `-e`, so an empty pipeline result otherwise flows on.
- Extract the assignment line; write it verbatim into `$TFDIR/strip.tf`; render
  `replace(templatefile(…), local.registry_rationale_strip, "")` when applied, current form when not.
- Positional, comment-blind applied-ness (Proposed Solution §2).
- `terraform` absent → exit 3 + `{"skipped":true,"reason":"terraform-absent"}` (§3).
- Two failure exits with distinct, measured messages (§4).
- `--json`: add `strip_applied`, plus `git_sha` and `dirty` and the sha256 of the two source files —
  a stale or dirty checkout is the realistic route to a false CLEAR being read as authorization.
  **Drop `strip_source`**: it can only ever be `zot-registry.tf`, so it carries no information.
  Keep `raw_bytes`/`stored_bytes`/`cap`/`headroom`/`zot_image` unchanged (no consumer parses them
  today — verified — but three surfaces name them).
- **Mirror every disclosure into the human-readable output.** The runbook invokes the script
  *without* `--json` (`registry-luks-recut-6929.md:64`), so a `--json`-only field is invisible on the
  documented operator path. Put the stakes on the verdict line in **both** directions, e.g.
  `CLEAR — 9,404 B / 32,768 B (23,364 B headroom), strip applied. Measured against the CREATE that
  runs AFTER the recut's DESTROY.`

### Phase 2b — stop swallowing the verdict

Drop `continue-on-error: true` from `.github/workflows/infra-validation.yml:1194` and rewrite the
job header, which still says the check "cannot be a hard gate YET" because it is RED on `main` — a
premise this PR removes. Safe and non-deferrable:

- after the fix the gate is green (9,404 B), so nothing fails;
- `registry-userdata-budget` is in neither `scripts/required-checks.txt` nor
  `infra/github/ruleset-ci-required.tf`, and no job `needs:` it — it cannot deadlock a PR or the
  merge queue;
- **#7302's body already asserts this was done.** Deferring it would leave #7302 a tracker
  certifying a change that never shipped — this plan's own defect class, one layer up.

Promotion to a *required context* stays deferred to #7302 (genuinely gated on the `paths:` filter,
#6480).

### Phase 2c — widen the one gate that generalises

Extend `scripts/lint-diagnosis-claims.sh`'s path scope to `apps/web-platform/infra/`. The lint
(ADR-166 — *a CI message may only name a cause the job measured*) already exists, already blocks, and
ratchets via `scripts/lint-diagnosis-claims.highwater`, so widening cannot big-bang. The registry
gate's current *"#7280's `registry_rationale_strip` is the fix"* is precisely what it detects. This
is the only deliverable here that is not another instance fix.

### Phase 3 — correct the derived claims, without minting a new one

- `registry-luks-recut-6929.md` §*"And check the `user_data` budget FIRST"*: the current paragraph
  hard-codes a measured figure that rotted. **Do not replace it with another byte count** — record
  the **command and the verdict shape** (`strip_applied: true` and `headroom > 0`), a re-run
  instruction, and the terraform prerequisite (rc=3 means *unmeasured*, not clear). Also fix the
  boundary: the runbook says `headroom` must be **≥ 0** while the gate fails at `-ge cap`, i.e. `= 0`
  fails. And remove the falsified *"#7299 owns the fix (`registry_rationale_strip`…)"* sentence,
  which AC on the old byte string alone would leave standing.
- **`zot-registry.tf` is not edited.** The *"ONE COPY … there is nothing here to keep equal"* claim
  stays **true** after the fix (the `.sh` will extract, not restate), the phrase is line-wrapped so
  the obvious grep was vacuous, and editing that comment block is the single most likely trigger for
  the applied-ness permissive hole (Proposed Solution §2). See Revisions R3.

### Phase 4 — verification and hand-back

- `bash scripts/test-all.sh`; `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`;
  `bash .github/scripts/test/test-infra-suite-registration.sh`.
- `gh issue edit` **#7287's body** to correct precondition (c) in place — the body still reads
  *"(c) is currently BREACHED"* with figures (34,800 / 36,072) that no runbook grep covers — keeping
  the Blocking-conditions table and adding one line: *"(c) clearing does not clear #7278 or Hetzner
  stock."* Post the measurement as a comment for the audit trail. A comment alone would advertise one
  blocker cleared beside a body that still says blocked.
- **File the `cpx22` repin-decision issue** via `gh issue create` and link it from #7287. The live
  probe recorded in `zot-registry.tf:438-442` shows `hel1-dc2 cx23 ✗ cpx22 ✓` — an available type in
  the registry's own location — and `variables.tf:197-203` already derives arch and the ADR-062
  memory cap from `registry_server_type`, so the architecture supports the swap. This is the only
  walkable lever past the terminal blocker and it is currently owned by **no issue**, which
  contradicts this plan's own "nothing deferred without a tracker" and
  `wg-when-deferring-a-capability-create-a`.
- File the trackers named in *Out of Scope* (R8) and reference them there.

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/registry-userdata-budget.sh` | Comment-blind extraction + positional applied-ness; verbatim assignment into a scratch `strip.tf`; exit 3 on unmeasured; two failure exits; `strip_applied`/provenance in `--json` **and** in human output |
| `.github/workflows/infra-validation.yml` | Register the new suite in `deploy-script-tests`; drop `continue-on-error: true` (`:1194`); rewrite the stale job header |
| `scripts/lint-diagnosis-claims.sh` | Extend path scope to `apps/web-platform/infra/` |
| `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` | Command + verdict shape (not a byte count); terraform prerequisite; `> 0` boundary; drop the falsified #7299 sentence |

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/registry-render-strip-parity.test.sh` | B1-B10 — properties of the gate script only |

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `bash apps/web-platform/infra/registry-userdata-budget.sh --json` yields
      `headroom > 0` **and** `strip_applied == true`, parsed from the JSON. Assert the *parsed
      fields*, never the exit code alone — the pre-fix script can exit 0 having measured nothing.
- [ ] **AC2** — B1 (positive control) is RED before Phase 2 and GREEN after. This is the criterion
      that distinguishes a correct fix from no fix; B2 alone cannot, because the unfixed script
      reports un-stripped/non-zero on every fixture.
- [ ] **AC3** — B2, B3, B4 each report the un-stripped figure and exit non-zero, and the message
      names a **code defect**, not "trim prose".
- [ ] **AC4** — B5 and B6 exit **2** with a named diagnosis; B7 exits **3** with
      `{"skipped":true,...}` and hard-fails under `CI=true`.
- [ ] **AC5** — B8: `grep -vE '^[[:space:]]*#' <script> | grep -cE '\(\?m\)\^\[ \\{1,2}t\]\*#'`
      returns 0 (`|| true` — `grep -c` exits 1 on zero matches). Comment-stripped and
      escaping-tolerant: the sibling `git-data-userdata-budget.sh:52` restates its strip through an
      unquoted heredoc with **doubled** backslashes, which a single-backslash pattern misses. This is
      a non-regression guard, not proof of the fix — AC2 is that.
- [ ] **AC6** — B9: `cloud-init schema --config-file <stripped render>` exits 0; first line is
      `#cloud-config`; shebang count `> 0`; `write_files` and `runcmd` non-empty.
- [ ] **AC7** — B10: the `.sh` and `.ts` predicates return identical verdicts on every fixture.
- [ ] **AC8** — `bash apps/web-platform/infra/run-registered-suites.sh --list` names
      `registry-render-strip-parity.test.sh`, reports zero orphans, and
      `bash .github/scripts/test/test-infra-suite-registration.sh` exits 0.
- [ ] **AC9** — `.github/workflows/infra-validation.yml` no longer contains `continue-on-error` in
      the `registry-userdata-budget` job, and that job is green.
- [ ] **AC10** — `scripts/lint-diagnosis-claims.sh` scans `apps/web-platform/infra/` (assert a
      seeded false-cause string in a scratch file under that path is detected) and the highwater
      ratchet is not regressed.
- [ ] **AC11** — **SUPERSEDED.** The original first clause (`! grep -q '36,404 B stored'`) is
      deliberately NOT satisfied: the retracted measurement is retained inside an explicit
      "superseded measurement" caution so a future reader learns why a byte count does not belong
      here. What must hold instead: the figure appears ONLY inside that caution block, never as a
      live instruction. Remaining original clause: **and**
      `! grep -q '#7299 owns the fix' <runbook>` **and** the section still names
      `registry-userdata-budget.sh` and now names the terraform prerequisite and `headroom > 0`.
- [ ] **AC12** — `git diff --name-only origin/main...HEAD` does **not** include
      `apps/web-platform/infra/zot-registry.tf` or `apps/web-platform/infra/cloud-init-registry.yml`
      (the render is untouched, so no ForceNew replace is armed).
- [ ] **AC13** — `bash scripts/test-all.sh` green and
      `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` green (38+ pass, 0 fail),
      running each gate's **own** invocation (`cq-assert-anchor-not-bare-token`).
- [x] **AC14** — **SUPERSEDED.** The PR body must carry NO `Closes` line: #7299 is fixed by PR
      #7300, not here. Use `Ref #7247 #7287 #7299 #7300 #7309 #7310`.

### Post-merge (automated via `gh`, not operator steps)

- [ ] **AC15** — #7287's **body** is edited so precondition (c) reads CLEAR with the command and
      verdict shape, the Blocking-conditions table is preserved, and one line states that (c)
      clearing does not clear #7278 or Hetzner stock. The measurement is also posted as a comment.
- [ ] **AC16** — the `cpx22` repin-decision issue exists, is linked from #7287, and the *Out of
      Scope* trackers (R8) exist.

## Test Scenarios

> **SUPERSEDED — none of these ran for this PR.** Every scenario below exercises the
> `registry-userdata-budget.sh` gate and its `registry-render-strip-parity.test.sh` suite, both
> descoped to PR #7300. This PR's diff is markdown only, so `/qa` had nothing executable and was
> not run; the checks that DID gate it were `scripts/lint-diagnosis-claims.sh` (green, census 1 =
> baseline 1), `scripts/lint-diagnosis-claims.test.sh` (11/11), `bun test
> plugins/soleur/test/cloud-init-user-data-size.test.ts` (38/0), the full `scripts/test-all.sh`,
> and a 4-agent review panel. Retained as the record of what the descoped work was to prove.
>
> Note also that scenario 4's `exit 3` / `{"skipped":true}` contract was **not** what shipped:
> #7300 uses exit `2` for unmeasured, and keeps `SKIP` + exit `0` for a local run.

- Given the pristine tree, when the gate runs, then `strip_applied: true`, `headroom > 0`, exit 0
  (B1). Given the **pre-fix** script on the same tree, exit 1 at 36,404 B — the state this removes.
- Given `replace()` unwired / an inline literal / a comment quoting the wrapper while unwired, the
  gate reports un-stripped and exits non-zero naming a code defect (B2, B3, B4).
- Given a duplicated or non-`(?m)` declaration, exit 2 with a named diagnosis (B5, B6).
- Given no terraform on `PATH`, exit 3 with `{"skipped":true}`; under `CI=true` the suite fails (B7).
- Given the stripped render, `cloud-init schema` exits 0 and the `#cloud-config` header and all
  shebangs survive (B9).
- Edge: the strip must not eat `#cloud-config` (`#` followed by `c`) or `#!` (`!` is not space/tab) —
  asserted positively by B9, not assumed from the regex. A template referencing an un-provided var
  must still fail loudly (`:96-100` `RENDER FAILED` preserved).

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **Permissive-direction failure of the applied-ness check** — a mere-presence or comment-blind-less check returns `true` while the render applies something else; the gate then says 9.4 KB and the recut destroys, then fails the CREATE at 36 KB. | Positional (2nd arg of the `replace()` wrapping `templatefile(` inside `base64gzip(`) **and** comment-stripped on both paths; B3 and B4 are the mutation arms. `zot-registry.tf` is not edited at all (R3), removing the most likely trigger. |
| **The gate reports a verdict it did not measure** (terraform absent → exit 0 today). | Exit 3 + `{"skipped":true}` + `CI=true` hard-fail (B7); the runbook names the prerequisite. |
| **The stripped render has never booted.** The live host predates the strip; the first boot will be the recut's, into an already-degraded situation, stacking: first stripped payload, first `head -c` capture, first v2.1.20, LUKS recut of a full fs, and the idempotent `crypto_LUKS` re-provision arm. The only instrument that could diagnose a failed boot is inside the payload that failed to boot. | B9 (official validator) is the cheap interim, plus the structural equivalence verified during planning (`write_files` 11/11, `runcmd` 14/14, 4 shebangs, every payload `bash -n` clean, each payload's content exactly `strip(original)`). A **registry runcmd rehearsal** on the git-data model is the real answer and is named as a deliverable on #7287's pre-first-fire REQUIRED list (R8) — not left to B9 to carry. |
| Corrected verdict misread as "the recut is safe to fire". | The Overview states this clears **1 of 4** blockers and that the blocker is documentary; AC15 puts the same sentence in #7287's body next to the Blocking-conditions table. |
| Phase 3 mints a new figure that rots exactly as the old one did. | The runbook records the command and verdict shape, never a byte count. |
| `raw_bytes`/`stored_bytes` change meaning across the merge boundary (74,603→23,879 and 36,404→9,404), so the branch-vs-merge-base delta method in `…2026-08-04-chore-zot-image-pin-bump…-plan.md:705` yields a bogus ~−27 KB. | Note the discontinuity where the runbook records the change; emit both figures in human output. |
| `pcent=100` may worsen while this ships. | This PR does not change disk behaviour; the state belongs to #7247. Note for triage: **the recut destroys and recreates the volume, so an empty store is `pcent≈0` — the recut *is* the disk lever**, and the same dispatch would deliver the crash-cause telemetry. |

## Out of Scope

Each item is owned by an open issue; trackers marked **(file in Phase 4)** do not exist yet.

- **Firing `registry-luks-recut`** — #7287. Not ready: #7278 is a declared *rollback dependency*,
  `cx23` was probed unorderable in `hel1-dc2`, and five pre-fire re-verifications are REQUIRED. A
  destructive production dispatch is not a one-shot code deliverable.
- **The in-place zot restart lever** — #7278 (plan exists; transport decision unresolved).
- **Promoting `registry-userdata-budget` to a required context** — #7302 (gated on the `paths:`
  filter, #6480). The CTO review notes the `infra-validate-required` aggregator is a simpler route
  than a second ruleset context; #7302's body also needs correcting (it records Phase 2b as shipped).
- **Naming the zot panic's task** — blocked on delivering #7274; `UNKNOWN`.
- **Disk-pressure remediation** — #7247.
- **`allow_unmirrored_reason`** — deliberately unused: it publishes a blocked draft without putting
  the image in zot, so the deploy still would not land. Not a mirror-gate false positive.
- **(file in Phase 4)** `cpx22` repin decision for `hel1-dc2` — the only walkable lever past the
  terminal stock blocker; currently owned by nobody.
- **(file in Phase 4)** Self-discovering `user_data` budget-coverage enumerator. Five `.tf` files
  render `base64gzip(templatefile(…))`; `inngest-host.tf:261` and `grok-dogfood.tf:30` have **no**
  gate at all — and the breach that started this family happened precisely on the host that had no
  arm. Recipe: `knowledge-base/project/learnings/2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md`.
- **(file in Phase 4)** Move the registry render into a provider-free `modules/registry-userdata/`,
  with the exit criterion *"`registry-render-strip-parity.test.sh` is deleted as unnecessary"* — which
  makes the new suite explicitly temporary scaffolding rather than a permanent per-host guard.
- **(file in Phase 4)** Registry runcmd rehearsal (git-data has two; the registry has none), to be
  named on #7287's pre-first-fire REQUIRED list.
- **(file in Phase 4)** ADR-096 amendment recording single-delivery-path as an accepted architectural
  risk: delivery availability ≡ Hetzner stock in one datacenter, with #7278 as the named mitigation.

## Plan Review Revisions (v1 → v2)

Six reviewers: dhh, kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, cto.

| # | Change | Source |
|---|---|---|
| **R1** | Cut A1/A2/A5/A6 — they re-implement `cloud-init-user-data-size.test.ts:397-473`, `:579-593`, `:617-663` in a third parser, and that suite runs on every PR while `infra-validation.yml` is paths-filtered. New suite now asserts only properties of the **gate script**. | dhh P0-1, simplicity HIGH |
| **R2** | Register the suite in `.github/workflows/infra-validation.yml` — infra suites are **derived**, not globbed (`run-registered-suites.sh:121-124`), and `test-infra-suite-registration.sh` hard-fails in a required check. Unregistered, the suite runs nowhere and "test-all green" passes vacuously. | all six |
| **R3** | **Drop the `zot-registry.tf` comment edit.** The "ONE COPY" claim stays true post-fix; the old AC was vacuous (the phrase is line-wrapped — verified `grep -c` = 0 today); and the edit was the most likely trigger for the applied-ness permissive hole. Both panels fired on the same scope → cut. Dissolves 4 ACs, 1 arm, 1 risk row. | dhh, simplicity, kieran P0-2, architecture P0-1 |
| **R4** | Positional + comment-blind applied-ness; added B3 (inline literal) and B4 (comment quotes the wrapper). Mere presence is satisfied by the mutation the `.ts` names as most likely. | architecture P0-1, P1-1 |
| **R5** | `terraform` absent must exit **3**, not 0 — the pre-DESTROY precondition currently returns success having measured nothing, contradicting the plan's own `fail_loud`. | spec-flow P0, architecture P0-2, cto F8, kieran P1-6 |
| **R6** | B1 positive control added: the unfixed script reports un-stripped/non-zero on *every* fixture, so the mutation arm alone was GREEN pre-fix and could not discriminate. | kieran P1-4 |
| **R7** | ACs rewritten: old AC3 was vacuous *and* blind to the doubled-backslash restatement `git-data-userdata-budget.sh:52` actually uses; old AC10/AC11 were vacuous or unfalsifiable; ceremonial ACs cut. `grep -c` returns rc=1 on zero matches → `! grep -q`. | kieran P0-1/P0-2/P2, dhh P1-3, spec-flow |
| **R8** | Deferred items now have trackers filed in Phase 4 — `cpx22` repin (the terminal blocker, owned by nobody), coverage enumerator, module extraction, runcmd rehearsal, ADR-096 amendment. v1 claimed "none deferred without a tracker" while the decisive one had none. | spec-flow P1, cto F4/F5, architecture P1-5 |
| **R9** | Phase 2b (drop `continue-on-error`) folded in — #7302's body already claims it shipped, so deferring would leave a tracker certifying a change that never happened. | cto F3 |
| **R10** | Phase 2c (widen `lint-diagnosis-claims.sh` to `apps/web-platform/infra/`) — the one deliverable that is not another instance fix, in a family with ~30 instances in two weeks. | cto F6.1 |
| **R11** | Disclosure mirrored into human output (the runbook invokes without `--json`); `strip_source` dropped as a constant; provenance (`git_sha`/`dirty`/sha256) added; two failure exits per ADR-166. | cto F2, simplicity MEDIUM |
| **R12** | Phase 3 records the command and verdict shape, not a new byte count — v1 re-instantiated the exact defect (a hard-coded figure that rots) on the pre-destroy precondition. Also fixes the `≥ 0` vs `= 0` boundary and the falsified #7299 sentence. | spec-flow P1, cto F7, kieran P2 |
| **R13** | AC15 edits #7287's **body**, not only a comment — the body still says BREACHED with different figures, and it is the only place enumerating the remaining blockers. | spec-flow P1 |
| **R14** | Overview states this clears **1 of 4** blockers and that the blocker is documentary, not mechanical (no workflow job calls the gate). | architecture Q2, spec-flow P2 |
| **R15** | Verbatim assignment line into a scratch `strip.tf` rather than unescaping the regex body — terraform merges locals across files (verified), eliminating the heredoc backslash-halving class outright. | dhh P1-2 |
| **R16** | Scratch-copy seam named explicitly (copy all three files to `mktemp -d`; `BASH_SOURCE` follows) — v1 asserted mutation arms with no mechanism to point the gate at a scratch `.tf`. | kieran P1-5, dhh P1-1 |

Not adopted, recorded in `knowledge-base/project/specs/feat-one-shot-7247-zot-crash-loop-recovery/decision-challenges.md`:
the provider-free module extraction (cto F5 / architecture — right direction, wrong moment), the
coverage enumerator inline (cto F4 — would go RED on two ungated hosts and needs its own allowlist),
and the mutation meta-harness (cto F6.3).

## Domain Review

**Domains relevant:** engineering

**Status:** reviewed. Infrastructure verification-tooling change, no runtime surface. The class —
a verification artifact diverging from the artifact production uses — is the same one the git-data
strip-parity suite guards for the sibling host and the same as the two most recent registry
learnings (#7280, #7290). No new dependency, no new infrastructure, no deployed byte changes.

**Product/UX Gate:** not run. Product assessed NONE and the mechanical UI-surface override did not
fire — no path in *Files to Edit*/*Create* matches `components/**`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface glob.

## Open Code-Review Overlap

**None.** 64 open `code-review` issues matched with standalone `jq --arg` (never `gh --jq --arg`)
against `title + body` for every planned path, plus a broadened pass on bare stems and on
`userdata budget`, `OVER CAP`, `32768`. Zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — `app.soleur.ai` is UP. The
  exposure is second-order: a gate made permissive in the wrong direction would green-light a recut
  that DESTROYs the store and host and then fails the Hetzner CREATE, leaving the sole container
  pull path dark and converting a deploy freeze into an inability to deploy at all.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. The script renders
  with stub values only (`registry-userdata-budget.sh:62-82` builds a stub token and stub heartbeat
  URLs via `join()` so no real secret or heartbeat-shaped literal enters the file), performs no
  network I/O, reads no credentials, and touches no state.
- **Brand-survival threshold:** `aggregate pattern` — a deploy-capability regression, not a per-user
  incident; production stays up and no user data is reachable from this surface.

The directional asymmetry above is why applied-ness is derived positionally and comment-blind rather
than stripping unconditionally: an unconditional strip *is* the permissive-direction error.

## Observability

```yaml
liveness_signal:
  what:          "infra-validation job `registry-userdata-budget` (runs the gate, blocking after Phase 2b) + `deploy-script-tests` step running registry-render-strip-parity.test.sh + the registry cap arm of plugins/soleur/test/cloud-init-user-data-size.test.ts"
  cadence:       "per pull_request; the .ts arm on every PR via ci.yml, the two infra jobs on PRs touching apps/web-platform/infra/** (paths-filtered)"
  alert_target:  "GitHub Actions check on the PR; the gate prints the verdict and byte figures to the job log"
  configured_in: ".github/workflows/infra-validation.yml:1189 (budget job) and its deploy-script-tests job (suite registration); plugins/soleur/test/cloud-init-user-data-size.test.ts:537"

error_reporting:
  destination:   "GitHub Actions job log + the gate's own exit code (no runtime service, so no Sentry surface)"
  fail_loud:     "rc=1 over cap WITH strip applied (payload-size cause); rc=2 extraction/render defect with a named diagnosis; rc=3 UNMEASURED (terraform absent) carrying {\"skipped\":true} so no caller can read a headroom. After Phase 2b these reach the PR check instead of being swallowed by continue-on-error."

failure_modes:
  - mode:        "the render-time strip is unwired, or replaced by an inline literal, while the gate keeps stripping"
    detection:   "registry-render-strip-parity.test.sh B2 (unwired) and B3 (inline literal) — positional applied-ness, not mere presence"
    alert_route: "infra-validation PR check + scripts/test-all.sh"
  - mode:        "rationale prose quoting the wrapper or the assignment pins applied-ness true forever"
    detection:   "B4 — comment-quoting fixture with the real wrapper unwired must still report un-stripped and exit non-zero"
    alert_route: "infra-validation PR check"
  - mode:        "local.registry_rationale_strip renamed, duplicated, or non-(?m)-anchored"
    detection:   "B5, B6 — exit 2 with a named diagnosis"
    alert_route: "infra-validation PR check"
  - mode:        "the gate runs where terraform is absent and reports success having measured nothing"
    detection:   "B7 — exit 3 plus {\"skipped\":true}; hard fail under CI=true, never a silent skip (run-registered-suites.sh prints PASS for a self-skip)"
    alert_route: "infra-validation PR check + the runbook's stated prerequisite"
  - mode:        "a future strip widening eats the #cloud-config header or a shebang"
    detection:   "B9 — cloud-init schema --config-file on the stripped render, plus header/shebang/non-empty structural assertions"
    alert_route: "infra-validation PR check + scripts/test-all.sh"
  - mode:        "the two gates drift apart again"
    detection:   "B10 — identical verdicts across the fixture matrix (never identical bytes)"
    alert_route: "infra-validation PR check"
  - mode:        "the real payload genuinely crosses 32,768 B"
    detection:   "the corrected gate reports negative headroom with strip_applied true; the .ts REGISTRY_GZIP_BUDGET band trips independently"
    alert_route: "infra-validation PR check; the recut runbook precondition"

logs:
  where:         "GitHub Actions run logs for `Infra Validation`; locally the gate's own stdout"
  retention:     "GitHub Actions default retention (90 days); local runs ephemeral"

discoverability_test:
  command:       "bash apps/web-platform/infra/registry-userdata-budget.sh --json"
  expected_output: "rc=0 with headroom > 0 and strip_applied true — e.g. {\"raw_bytes\":23832,\"stored_bytes\":9404,\"cap\":32768,\"headroom\":23364,\"strip_applied\":true,\"git_sha\":\"<sha>\",\"dirty\":false,\"zot_image\":\"ghcr.io/project-zot/zot-linux-amd64:v2.1.20@sha256:95a837a0...\"}. rc=3 means UNMEASURED, never clear."
```

Every command runs locally; none reaches a host (`hr-no-ssh-fallback-in-runbooks`,
`hr-observability-layer-citation`). Note `terraform validate` requires
`terraform init -backend=false` (a provider download), so it is not offline — it is not used as an
acceptance criterion here.

## Encryption Posture

**Not applicable — skipped with reason.** Detection fires on the `\.tf$` / `cloud-init.*\.ya?ml$`
patterns, but the documented skip condition holds: no persistent data store and no new
cross-component or network connection is introduced. After R3 the plan does not edit any `.tf` at
all. `hcloud_volume.registry`'s guest-side LUKS posture (#6926) is untouched and unre-declared.

## Infrastructure (IaC)

**Not applicable.** No server, systemd unit, cron, vendor account, DNS record, TLS cert, secret,
firewall rule, or monitoring webhook is introduced. No host shell session, no manual secret write, no
`terraform import`, no vendor-console step appears in any phase. Every action is a local file edit or
a `gh` CLI call. The `registry-luks-recut` dispatch is discussed only as the downstream consumer and
is out of scope, owned by #7287 — so this plan adds **no** `### Post-merge (operator)` step
(`hr-ship-message-no-operator-checklist`, `wg-block-pr-ready-on-undeferred-operator-steps`).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Architecture Decision (ADR/C4)

**No ADR for the gate fix.** It is a defect fix in a measurement harness against already-decided
architecture: ADR-152 (render-time strip), ADR-096 (cloud-init-only host), ADR-080 (base64gzip-first
under the cap), ADR-166 (a CI message may only name a cause the job measured), ADR-169 (recut gate
independence). None is reversed or extended. The architecture review's proposed ADR-096 *amendment*
— recording single-delivery-path as an accepted risk — is real but belongs to the class this fix
keeps revealing, not to this fix; filed as a tracker in Phase 4 (R8).

### C4 views

**No C4 impact.** All three model files read in full — `model.c4` (633 lines), `views.c4` (62),
`spec.c4` (54). (a) no external human actor added (`founder`, `emailSender`, `betaContact`,
`contributor` unchanged); (b) no external system/vendor added — `projectZot` (`:270`) and `ghcr`
(`:266`) exist, Hetzner is deliberately the in-boundary container `platform.infra.hetzner` (`:180`)
rather than a top-level `#external`, and the 32,768 B cap is already prose in `ghcr`'s description
(`:268`); (c) no container/data store — `zotRegistry` (`:274`) already carries the
cloud-init/user_data/LUKS-recut narrative, and scripts and test files are deliberately not elements
(there is no `git-data-userdata-budget.sh` element either); (d) no actor↔surface access relationship
— `github` (`:230`) already carries `github -> zotRegistry` (`:521`), `-> ghcr` (`:519`),
`-> tunnel` (`:462`), `-> betterstack` (`:549`), `-> sentry` (`:567`). `spec.c4` needs no new kind or
tag, and `c4-count-parity.test.sh` (#7209) pins cron-monitor counts this change does not touch.

## Research Insights

### Network-Outage Deep-Dive (Phase 4.5)

The gate fired on the shell-access term. Layer-by-layer status, with the verification artifact each
claim rests on — no layer is asserted from reasoning alone.

| Layer | Status | Artifact |
|---|---|---|
| **L3 firewall allow-list** | **not verified — and no hypothesis in this deliverable depends on it** | `hcloud_firewall.registry` is deny-all on public ingress by design (`zot-registry.tf:593`). Partial contrary evidence from the host's own telemetry, not inference: the `SOLEUR_ZOT_DISK` POST to Better Stack succeeded on **every** 5-minute tick across the 12 h window pulled 2026-08-05 23:00Z (egress OK), and `ping_rc=0` on every row (the host reaches zot on its own private IP). Says nothing about web-host→registry reachability — open separately as **#7267** / **#7262**. |
| **L3 DNS / routing** | **not verified — out of scope** | The mirror resolves the registry over the private network; #7262 records that the consumer probe's "private net down" branch has never fired. No routing change is proposed. |
| **L7 TLS / proxy** | **not applicable** | The gate is an offline local render performing no network I/O — measured: it runs to a verdict with no credentials and no reachable network dependency beyond `terraform` on `PATH`. |
| **L7 application (zot)** | **UNKNOWN — discriminator unavailable** | The panic is in `scheduler.(*Scheduler).poolWorker`; which task panics is not obtainable until #7274's `head -c` capture reaches the host. `pcent=100` and `gcInterval: 1h`-only reclamation are held as facts, not fused into a verdict. |

**Ordering discipline honoured:** unverified layers are listed first, L3→L7, and no service-layer fix
is proposed. The deliverable changes no firewall rule, no routing, and touches no host — so the
opt-out is not "unlikely", it is "no hypothesis here depends on any of these layers".

### Verified negatives (Phase 4.45 verify-the-negative pass)

Every load-bearing negative claim was probed against the tree rather than asserted.

| Claim in the plan | Probe | Result |
|---|---|---|
| `registry-userdata-budget` is in neither `scripts/required-checks.txt` nor `infra/github/ruleset-ci-required.tf` (so Phase 2b cannot deadlock the merge queue) | `grep -c` both files | **0 and 0 — confirms** |
| No job `needs:` the budget job | `grep -n 'needs:.*registry-userdata-budget' infra-validation.yml` | **no match — confirms** |
| No consumer parses the `--json` keys (so adding `strip_applied` and dropping `strip_source` is safe) | repo-wide grep for `registry-userdata-budget.*--json` outside `knowledge-base/` | **only the script's own usage line — confirms** |
| Zero continuation-followed-by-comment occurrences in `cloud-init-registry.yml` today | python scan for a line ending `\` followed by a `^\s*#` line | **0 hits against 11 continuation lines — confirms, and the arm is non-vacuous** |
| The `"there is nothing here to keep equal"` grep was vacuous | `grep -c` on `zot-registry.tf` | **0 on an unmodified tree — confirms the v1 AC could never have flipped (drives R3)** |
| `36,404 B stored` genuinely exists in the runbook (so AC11's first clause is non-vacuous) | `grep -c` on `registry-luks-recut-6929.md` | **1 — confirms it flips** |
| The stripped payload is valid cloud-config | `cloud-init schema --config-file` (cloud-init 26.1) on both renders | **`Valid schema` for stripped *and* un-stripped**; rc 0 valid / rc 1 invalid on control fixtures. Note this is an *absolute* validity assertion, not a stripped-vs-un-stripped discriminator — its job is to guard future strip widenings. |

### Implementation realism confirmed against the registration target

`.github/workflows/infra-validation.yml:339` (`deploy-script-tests`) already provides everything the
new suite needs — no new setup step is required:

- `hashicorp/setup-terraform@5e8dbf3c6d9deaf4193ca7a8fb23f2ac83bb6c85 # v4.0.0`, pinned to
  `env.TERRAFORM_VERSION` (B1-B6, B10 need terraform);
- an `Install cloud-init (render-leg schema check + infra-template fixtures)` step via
  `sudo apt-get` (B9 needs `cloud-init schema`);
- a comment at that step stating cloud-init "serves TWO consumers in this job, **both of which SKIP
  or fail**" — the job already carries the skip-vs-fail discipline B7 depends on, so B7's
  `CI=true` hard-fail follows an established local convention rather than inventing one.

The sibling registration to mirror is at `:1062`
(`run: bash apps/web-platform/infra/git-data-render-strip-parity.test.sh`) — a **single-line** `run:`,
which matters: `run-registered-suites.sh:121-124` greps for exactly that shape, so a `run: |` block
registers in CI while staying invisible to the local runner.

### Terraform mechanics verified during planning

- **Locals merge across `.tf` files in a directory.** Probe: a scratch dir with `strip.tf` holding
  only `locals { registry_rationale_strip = … }` plus a `main.tf` referencing
  `local.registry_rationale_strip` in a `replace()` evaluated correctly under `terraform console`.
  This is what makes R15 (paste the assignment line verbatim into `$TFDIR/strip.tf`) work, and it
  removes the heredoc backslash-halving class outright rather than guarding it.
- **The measurement itself**, re-derived independently of the script: un-stripped `base64gzip`
  36,404 B, stripped 9,404 B, stripped raw 23,832 B, against the 32,768 B cap. Structural check on
  the stripped render: first line `#cloud-config`, 4 shebangs preserved, `yaml.safe_load` OK,
  `write_files` 11, `runcmd` 14.

### Precedent diff (Phase 4.4)

`apps/web-platform/infra/git-data-render-strip-parity.test.sh` is the canonical form and it **passes
today** (measured: 10 assertions, 0 failed, anti-vacuity floor 9). Its three-arm shape and the
divergence from this case:

| Precedent arm | git-data | registry (this plan) |
|---|---|---|
| Compare the strip expression byte-for-byte across two hand-mirrored copies | Required — `main.tf` and `git-data-userdata-budget.sh` each declare it | **Not applicable** — one declaration, and after the fix the `.sh` extracts rather than restates. Arm dropped. |
| Compare the **application count** (`replace(file(` occurrences must match, 9 each) | Added after a measured mutation left the suite 8/8 green while CI measured 22,920 B against a shipped 20,448 B | **This is the load-bearing analogue** — B2/B3/B4 assert the gate applies the strip iff production does, positionally. |
| Render and assert shebangs survive + `bash -n` clean + strip is not a no-op + continuation-comment guard | Nine payloads | **B9 + B1.11** — one payload, plus the official `cloud-init schema` validator the precedent does not use. |

No precedent exists for a budget script that *conditionally* mirrors a render-time transform — that
part is novel and is why B1 (positive control) and B3 (inline literal) carry the weight.

## References

**Internal:** `registry-userdata-budget.sh:33` (`BASH_SOURCE` seam), `:38-41` (the exit-0 SKIP),
`:43-52` (the extract-don't-restate precedent), `:59` (unquoted heredoc), `:85-86` (the defect),
`:96-100` (`RENDER FAILED`), `:131` (the false-cause message) · `zot-registry.tf:388`, `:426`,
`:438-442` (the stock probe incl. `hel1-dc2 cpx22 ✓`), `:451`/`:494`, `:496`, `:593` ·
`cloud-init-user-data-size.test.ts:397-421`, `:433-438`, `:453-473`, `:537`, `:556-565` ·
`git-data-render-strip-parity.test.sh:64-76`, `:122-147`, `:150-155` ·
`run-registered-suites.sh:41-45`, `:121-124` · `.github/scripts/test/test-infra-suite-registration.sh` ·
`infra-validation.yml:1062`, `:1189`, `:1194` · `variables.tf:197-203`, `:248-252` ·
`registry-luks-recut-6929.md:64`, `:67`, `:69` · `scripts/registry-pull-path-health.sh:538` ·
`scripts/lint-diagnosis-claims.sh` + `.highwater` · ADR-152, ADR-096, ADR-080, ADR-166, ADR-169.

**Learnings:** `2026-08-04-my-guard-certified-a-string-in-a-file-not-the-render-that-boots.md` (same
file, same host — extraction ≠ application) · `2026-08-05-every-green-signal-certified-something-other-than-what-it-claimed.md`
(`assertion_certifies_a_different_property`) · `2026-07-29-every-guard-i-fixed-this-session-was-narrower-than-the-claim-it-carried.md`
· `2026-08-03-four-guards-were-satisfied-by-the-comment-i-wrote-to-explain-them.md` (drives B4) ·
`2026-07-26-cloud-init-comment-is-a-live-host-input-and-an-unreadable-vendor-limit-decays.md`
(drives AC12) · `2026-06-07-self-discovering-parity-guard-for-cross-producer-drift.md` (drives the
R8 enumerator).

**Related:** Closes **nothing** (see the DESCOPED banner — #7299 is PR #7300's). Refs **#7247**,
**#7287**, **#7278**, **#7299**, **#7300**, **#7302**, **#7309**, **#7310**, **#7267**, **#7262**.
Undelivered to the host: **#7274** (`8565210d6`), **#7283** (`6720f2ae0`). Load-bearing merged work:
**#7280** (`d0295964f`), **#7290** (`546294c1f`).
