---
type: bug-fix
lane: cross-domain
created: 2026-07-19
revision: 3 (operator ruling on UC-1 — Half B cut to a follow-up)
branch: feat-one-shot-6712-6718-web1-birth-path-coherence-guards
issues: [6718]
design_record_only: [6712]
umbrella: 6178
adrs: [ADR-068, ADR-080, ADR-096, ADR-100, ADR-114, ADR-115]
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
cpo_signoff: SIGN OFF WITH CONDITIONS (C1, C2, C3 folded in; C4 moot after the Half B cut)
---

# fix(infra): close the unguarded web-1 birth path in warm_standby (Refs #6718, #6712)

## Enhancement Summary

**Plan-reviewed + deepened + amended:** 2026-07-19. **Panel:** dhh, kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer (eng, escalated by the `single-user incident`
threshold) + cto (devex) + cpo (threshold sign-off).

### Revision 3 — operator ruling on UC-1

**Half B (#6712 resolver extraction) is CUT to a follow-up.** The operator upheld the panel's
finding and independently confirmed the zombie verification. This PR is now **one change**: wire
the existing `host_creates` HALT into `warm_standby`. The plan file was renamed to match
(`…-coherence-guards-plan.md` → `…-warm-standby-web1-birth-halt-plan.md`); the plural
"coherence guards" framing overclaimed once the second half was removed.

See "Operator Decision — Half B cut" below for the evidence trail, deliberately retained in the
artifact rather than deleted along with the code.

### Corrections to this plan's own claims (each re-verified independently before adoption)

1. **The prescribed fail-open fixture was impossible.** The jq filter emits `host_creates`
   unconditionally (`[…] | length`); no tfplan input can omit it. Verified. The AC that depended
   on it would have blocked `/work`. **Deleted** — and a fixture would have proven the bash
   *mirror*, not the workflow, so the structural YAML grep is the only valid proof (SE-5).
2. **The load-bearing precondition's grep returned a false negative** — found **1 of 4**
   `for_each = var.web_hosts` sites because two use aligned whitespace. The hard STOP would have
   read as failed. Regex corrected.
3. **R-A5's mechanism was inverted.** `-target` closes over dependencies, not dependents — its
   mitigation would have shipped exactly the false comment this PR exists to prevent.
4. **A justification cited a lint that does not apply** — `lint-infra-no-human-steps.py` scans
   only `.md` under `SCAN_DIRS`, never workflow YAML. Withdrawn; AC5 now *preserves* the
   break-glass instead of deleting it.
5. **The Observability `alert_target` was false** — `deploy-script-tests` is advisory, not
   required. Corrected, **and** the load-bearing test moved into the required shard.
6. **"Half B has one real call site" was false** — `web_2_recreate` is a zombie for the same
   reason `warm_standby` is. This finding is what drove the revision-3 cut.
7. **[deepen] The brief's secret-scan premise had flipped.** PR #6717 merged 20:59:35Z; main went
   green 20:59:38Z; #6706 is closed. Carrying the "not yours, don't chase it" dismissal forward
   would have suppressed a real finding. See P5 / R-X1.

### Still open for you

**UC-2** (extract the guard to a shared lib — CTO's recommendation, declined here on blast-radius
grounds) and **UC-3** (CPO's conditions, all folded in) remain recorded in
`knowledge-base/project/specs/<branch>/decision-challenges.md`. The operator has explicitly not
overridden the inline-vs-shared-lib reasoning. **UC-1 is resolved** (Option 2 — cut).

**ACs were renumbered 1–17 in revision 3** after the Half B criteria were removed.

---

## Overview

**One change: `warm_standby` can transitively birth web-1 with no host-creation tripwire, against
a mutable image tag.** web-1 is the sole web host (web-2 retired 2026-07-17, #6538), so a bricked
birth is a total platform outage, not a degraded replica.

The mechanism is one boot check. `local.host_scripts_content_hash` is computed from the repo's
host-script files, injected into `user_data`, and **recomputed and compared at boot** in
`cloud-init.yml` under `set -e`:

```
[ "$GOT" = "$HOST_SCRIPTS_HASH" ] || exit 1
```

`runcmd` is one `/bin/sh` and runs **once per instance**. A mismatch aborts the *entire* runcmd at
`stage=verify` — no cloudflared, no webhook, no monitors, no egress firewall — permanently for
that instance. Meanwhile `var.image_name` defaults to the **mutable**
`ghcr.io/jikig-ai/soleur-web-platform:latest`.

### The thesis

Both cited issues describe one composite exposure, and the composition is the part neither issue
states:

- `warm_standby` `-target`s `hcloud_server_network.web["web-1"]`. `-target` **is transitive at the
  resource level**, so `hcloud_server.web["web-1"]` is in that job's plan graph.
- `warm_standby` passes **no `-var image_name`** (verified: its plan step passes only
  `-var="ssh_key_path=…"` plus six `-target`s). `apply` and `web_2_recreate` both pin; this job
  does not.
- So a transitive web-1 birth there uses the **default `:latest`** — #6712's failure mode reached
  through #6718's hole.

The HALT is therefore the single change that closes the reachable risk. It is ~5 lines of YAML;
the rest of this document is the evidence that those are the right 5 lines.

**Reason about the tripwire, never about `-target` membership.** "web-1 appears in no `-target=`"
proves nothing and is a recorded invalid inference (ADR-114 2026-07-19 amendment item 5;
`nic-wait-gate.test.sh` header, "TWO CORRECTIONS"). The create guarantor is the `host_creates > 0`
HALT.

---

## Operator Decision — Half B cut (revision 3)

**Decision: ship Half A alone; #6712's resolver extraction moves to a follow-up.** Recorded here
so the reasoning survives the removal of the code.

**What was cut:** a `resolve-image-digest.sh` extraction (lifting the inline
`docker buildx imagetools inspect … --format '{{.Manifest.Digest}}'` block out of the
`web_2_recreate` pin step), its test suite, and its runner registration.

**Evidence that drove the cut:**

1. **Five of seven reviewers independently recommended it.** dhh ("cut entirely" — the block is 6
   lines and the same step already calls an extracted script, so "inline-only" is cosmetic),
   code-simplicity ("drop, not defer" — extracting now means guessing an interface for a caller
   that does not exist), architecture-strategist, cto, and spec-flow all converged.
2. **Its only call site is dead.** `web_2_recreate` keys every address off `web-2`, which
   `var.web_hosts` no longer contains (RETIRED 2026-07-17, #6538, recorded in `variables.tf`), and
   its gate requires `web2_server_replaced==1` — unsatisfiable when the instance is absent from
   state. Verified by the panel and confirmed independently by the operator.
3. **The refactor's blast radius was wrong for its value.** It rewrites a step inside the
   `-replace`-the-sole-web-host path for zero behaviour change.

**Design record preserved for the follow-up** (so the next author does not re-derive it):

> The correct shape is **two scripts, not one**. `web2-recreate-preflight.sh` is a *pure verifier*
> whose header states the invariant — *"resolved ONCE upstream; AC3b TOCTOU — this script does NOT
> re-resolve a tag."* Generalizing it to accept a mutable ref would move the TOCTOU closure from
> "structurally cannot re-resolve" to "the caller faithfully consumes the emitted value", and make
> its digest `die` branch dead code on the mutable arm — a weaker guarantee sold as a
> generalization. Keep the verifier byte-unchanged; add a separate resolver; callers compose
> resolve → verify → `plan -var image_name=<pinned>`, and an AC must pin that the *same* variable
> feeds both the preflight and `-var image_name` (the composition is where the closure now lives).
> GHCR is a **private** package — anonymous `imagetools inspect` 401s; log in with
> `--password-stdin` so the token never lands in argv. Digest = integrity, **never** provenance;
> no `cosign verify` exists on this path and the image is unsigned there by design.

**#6712 does not close in this PR.** It keeps `Refs #6712` plus this design record. Its
substantive content — *the sole web host has no verified, executable birth path* — is carried by
the CPO C2 issue (Deferrals, row 3), which is the correct vehicle: #6712 as written asks for a
preflight, but the panel established there is no create path for a preflight to guard.

---

## Research Reconciliation — Spec vs. Codebase

Rows marked **[R2]** were added or corrected by the plan review; **[R3]** by the operator ruling.
Each was independently re-verified against source before adoption.

| Claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "#6718 is WIRING; the counter already exists" | **True.** `destroy-guard-filter-web-platform.jq` defines `host_creates` (`select(.type == "hcloud_server" or .type == "hcloud_volume")` + `index("create")`). | Reuse verbatim. No second detector. |
| "warm_standby has no host_creates HALT" | **True, measured.** Flag-based awk over the job block → `grep -c host_creates` = **0**; `apply` block ≥ 1. | The change. |
| "web2-recreate-preflight.sh requires a pinned ref and dies otherwise" | **True.** Header: *"resolved ONCE upstream; AC3b TOCTOU — this script does NOT re-resolve a tag."* | **[R3]** Not touched at all this PR. Reasoning preserved in the design record above. |
| "The fix must cover fresh/`-replace` web-1 creates, not just the recreate path" | **No executable create path exists to wire a preflight into.** The `apply_target` list has no full-apply option; the ADR-096 operator-local apply is prose only; the force-replace dispatch is out of scope. | **[R3]** Closed by **prevention** (the HALT), not verification. The absence of any birth path is itself the finding — carried by the C2 issue. |
| **[R2]** An earlier draft prescribed a fixture whose filter output **omits** `host_creates` | **Impossible.** The filter builds a jq object literal and `host_creates` is a total expression (`[…] \| length`). Verified: `echo '{"resource_changes":[]}' \| jq -f …` emits the key. | **Fixture deleted.** The load-bearing proof is a structural grep over the YAML. |
| **[R2]** An earlier draft claimed the fail-closed property would be "proven by fixture, not inspection" | **False.** `_run_host_creates_gate` is a hand-maintained **bash mirror** of the workflow block (its own header says so). A fixture proves the mirror, never the YAML. Parse-failure coverage **already exists** as `t_host_creates_parse_failure_fails_closed` (T32). | The **structural YAML grep is the only thing that can prove `warm_standby`'s regex.** Phase 1 is one test. |
| **[R2]** An earlier draft's Phase 0 P1 grep `for_each = var.web_hosts` | **False negative.** Verbatim returns **1** hit; the two resources the precondition most needs use aligned whitespace. Corrected regex returns **4**. | Regex corrected in P1. |
| **[R2]** An earlier draft's R-A5 said subnet transitivity "can reach other servers" | **Mechanism inverted.** `-target` closes over **dependencies**, not dependents. Those servers are dependents and are **not in warm_standby's plan graph**. Would have shipped a false comment. | R-A5 rewritten. Reachable countable set = `hcloud_server.web["web-1"]` **+** `hcloud_volume.workspaces["web-1"]` (via `server.tf`'s `workspaces_volume_id`). |
| **[R2]** An earlier draft justified an absolute "no repo path births a web host" via `lint-infra-no-human-steps.py` | **Out of scope for that lint** — it filters `if not name.endswith(".md")` and walks only `SCAN_DIRS`. It does **not** scan `.github/workflows/`. | Justification withdrawn. AC5 **preserves** the break-glass. |
| **[R2]** An earlier draft's Observability said `alert_target: … (required check)` | **False.** `deploy-script-tests` is advisory — absent from `ruleset-ci-required.tf`. | Corrected; the load-bearing test moved into the required shard. |
| **[R2]/[R3]** An earlier draft called `web_2_recreate` Half B's "one real call site" | **False.** Zombie for the same reason `warm_standby` is. | **Drove the revision-3 cut.** |
| **[R2]** The plan enumerated 2 transitive reachers of `hcloud_server.web` | **Incomplete — there is a 4th.** `workspaces_luks_cutover` `-target`s `hcloud_volume_attachment.workspaces_luks`, and `workspaces-luks.tf` has `server_id = hcloud_server.web["web-1"].id`. It passes **no `-var image_name`** either. Closed only *incidentally*: the gate's `positive` set happens to include `create`. | Enumerated + pinned by P6. |
| Brief: AGENTS.md always-loaded is over its 22k threshold | Respected. | **No AGENTS.md edit. No new rule anywhere.** |
| Brief: user_data 22,388 B / budget 22,450 → 62 B headroom | **Re-derived live: 22,388 B / 22,450 → 62 B.** | **Zero cloud-init bytes added.** |

---

## User-Brand Impact

**If this lands broken, the user experiences:** `app.soleur.ai` returns nothing at all — it is a
hard-pinned singleton A record to web-1. A web-1 birth on an incoherent image aborts the entire
cloud-init `runcmd` at `stage=verify`, so the host comes up with no cloudflared connector, no
deploy webhook, no monitors and no egress firewall; because `runcmd` is once-per-instance, no
reboot repairs it. There is no failover partner (web-2 retired; #6459 unbuilt), so recovery is a
fresh host build.

**If this leaks, the user's data is exposed via:** the same failure path — a host born without the
egress firewall the aborted runcmd never installed, serving as a tunnel connector replica unable
to reach any origin-relative ingress target (the ADR-114 I1/I2 coupling). This change introduces
no new data surface; the exposure is the *absence* of a control, not a new channel.

**If this lands correctly:** accidental web-1 birth becomes impossible on every automated path.
That is the intended outcome **and** it hardens an existing gap — there is already no working
automated birth path (the `apply` HALT predates this PR). See R-X4 for the DR posture, which CPO
required be stated rather than left implicit.

- **Brand-survival threshold:** single-user incident

---

## Hypotheses

The network-outage checklist gate fires on the `timeout` token and on `terraform apply` against
`hcloud_server.web`, which carries SSH `provisioner`/`connection` blocks. Evaluated and recorded
as a **no-op**: this is not a connectivity diagnosis. No hypothesis proposes an sshd or fail2ban
change, no firewall/egress-IP verification is prerequisite to any phase, and the plan performs
**no SSH and no prod write** — the guard fires *before* `terraform apply`. The L3→L7 ordering the
checklist enforces has nothing to order.

The one open empirical question is **P2**; the design is correct under either outcome, and **AC9
discriminates the two** rather than merely recording the answer.

---

## Open Code-Review Overlap

**None.** Queried `gh issue list --label code-review --state open --limit 200` (61 open); zero
mention any path in Files to Edit. The open backlog is entirely app/product-side.

---

## Implementation Phases

### Phase 0 — Preconditions (measure; do NOT inherit)

- **P1 (load-bearing hard STOP).** Re-verify `var.web_hosts` holds **only** `web-1`, and that
  `hcloud_server.web` / `hcloud_server_network.web` / `hcloud_volume.workspaces` are all
  `for_each = var.web_hosts`. If a second key returns, **STOP**: a verbatim HALT would then abort
  `warm_standby` on its own legitimate volume create, and the guard must be scoped to
  `hcloud_server` only. Commands (**the regex form is load-bearing — the naive
  `for_each = var.web_hosts` returns 1 of 4 hits**):
  ```
  awk '/variable "web_hosts"/,/^}/' apps/web-platform/infra/variables.tf | grep -A3 'default = {'
  grep -cE 'for_each[[:space:]]*=[[:space:]]*var\.web_hosts' \
    apps/web-platform/infra/server.tf apps/web-platform/infra/network.tf   # expect 3 and 1
  ```
- **P2 (open question — discriminated by AC9, not merely recorded).** Determine whether
  `terraform plan -target` on an unresolvable `for_each` key **warns** or **errors**. If it
  **errors**, the plan step dies *before* the guard block and the new HALT is **present but
  unreachable** — structurally green, provably dead. The PR must not claim closure in that case.

  **RESOLVED 2026-07-20 → WARNS. The HALT is executable; the risk is closed.** Measured
  empirically on Terraform **v1.10.5** (the pinned CI version) with a credential-free local
  reproduction — a `for_each` map containing only `web-1`, planned twice:

  | `-target` | exit | output |
  |---|---|---|
  | `local_file.web["web-1"]` (resolvable) | **0** | normal plan |
  | `local_file.web["web-2"]` (unresolvable key) | **0** | `No changes.` + the generic "Resource targeting is in effect" warning — **no error, no mention of the missing key** |

  Terraform **silently ignores** a `-target` whose `for_each` instance key is absent. So
  `warm_standby`'s plan step survives its three stale `web-2` targets, reaches the guard block,
  and the new HALT executes. AC9 resolves to the *warn* arm.

  **Byproduct finding (out of scope, filed not fixed):** because unresolvable targets are silently
  dropped, `warm_standby`'s "additive 6-target set" is really a **3-target set** — the three
  `web-2` addresses (`hcloud_server_network.web["web-2"]`, `hcloud_volume.workspaces["web-2"]`,
  `hcloud_volume_attachment.workspaces["web-2"]`) have been dead no-ops since web-2's retirement
  (2026-07-17, #6538). This does **not** weaken the HALT — `hcloud_server.web["web-1"]` is still
  transitively in the graph via the surviving `hcloud_server_network.web["web-1"]` target, which
  is what the tripwire counts. It is evidence for the `warm_standby`-is-a-zombie issue (AC11).
- **P3.** Re-derive cloud-init headroom: `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts`.
- **P4.** Confirm the baseline as **presence/absence**, not an exact count (an exact count is a
  brittle magic constant that drifts on any comment edit): warm_standby `host_creates` **absent**,
  `apply` **present**.
- **P5. [PREMISE FLIPPED — re-verified at deepen time; do not inherit the brief here.]** The brief
  states secret-scan is red on main and "not yours", citing #6706 with the fix in **draft** PR
  #6717. **That measurement (2026-07-19T20:46Z) is stale.** Verified live: **PR #6717 MERGED at
  20:59:35Z**, and the next `secret-scan` run on main (20:59:38Z, `48b8bc4a`) was **success**;
  #6706 is **CLOSED**. The two failures at 20:23Z / 20:37Z both predate the merge.
  **Consequence: a red secret-scan on this branch is no longer pre-dismissible.** Re-derive:
  ```
  gh run list --workflow=secret-scan.yml --branch=main --limit 3 \
    --json conclusion,createdAt,headSha -q '.[] | .conclusion + "  " + .headSha[0:8]'
  ```
  If main is green and this branch is red, **it is ours — investigate, do not wave it through.**
- **P6 (4th reacher).** Assert `workspaces-luks-cutover-gate.sh`'s `positive` set still includes
  `create`, so `web1_server_touched` continues to close that path. Its stated rationale is about
  *destroy*, so a future narrowing would silently reopen a `:latest` web-1 birth path.

### Phase 1 — RED: one structural test

**One test, four greps.** An earlier draft prescribed three tests; two were deleted (an
unconstructible fixture, and a parity test asserting an equivalence Phase 2 deliberately breaks).

**Home: the required shard, not the advisory job.** `nic-wait-gate.test.sh` runs only in
`infra-validation.yml`'s `deploy-script-tests`, which is **advisory** — placing the guard there
would make the thing that stops someone deleting the HALT weaker than the HALT. Put it in
`tests/scripts/test-destroy-guard-counter-web-platform.sh` (registered in `scripts/test-all.sh`'s
`scripts` shard → the required `test` context), which already reads the workflow.

Extract the `warm_standby` block with the **flag-based awk** idiom (SE-1), assert block
non-emptiness **first**, then use a **here-string** (SE-2):

1. the block contains `host_creates=$(echo "$counts" | jq -r`
2. the `^[0-9]+$` validation line contains `host_creates` ← **the load-bearing assert**
3. the block contains `[[ "$host_creates" -gt 0 ]]`
4. the HALT's `::error::` text contains a **routing instruction**, not just the counter name
   (AC14 — a HALT with no next action is a dead end)

### Phase 2 — GREEN: wire the HALT (~5 lines)

In `warm_standby`'s existing destroy-guard block:

1. `host_creates=$(echo "$counts" | jq -r '.host_creates')`
2. **Extend the numeric-validation regex to include `host_creates`.** This is the load-bearing
   edit; the comparison is merely the visible one. `jq -r` on a missing key yields the string
   `null`, and `[[ "null" -gt 0 ]]` resolves an unset name to `0` and **passes** — verified
   empirically. Without this line the guard fails **open**.
3. The `-gt 0` HALT, placed to mirror `apply`'s ordering — **for parity, not severity.** (An
   earlier draft claimed "a birth is the more severe finding"; on the sole live origin
   `reboot_updates` is more severe. Both exit 1 before any write, so ordering is cosmetic.)
4. Keep the parse **below** the `set -e` re-enable.
5. **Remediation text** naming this path, with an explicit routing instruction and an explicit
   statement that **there is no bypass on this dispatch** — `[skip-web-platform-apply]` and
   `[ack-destroy]` are merge-commit mechanisms scanned in `preflight`, and a `workflow_dispatch`
   run has no merge commit to annotate. A deliberate dead end that announces itself is not a dead
   end; an undocumented one is.
6. Do **not** touch `apply`'s guard logic (its remediation *text* is Phase 3.2).

### Phase 3 — Doc coherence (these become FALSE on merge)

1. **`destroy-guard-filter-web-platform.jq`** — the header says *"Only the `apply` job reads
   host_creates"* (**split across two lines** — a single-line `grep` cannot match it) and
   *"the apply / warm_standby / manual-rerun consumers … stay byte-unchanged"*. Both falsified.
   Correct **all** occurrences; normalize newlines before asserting.
2. **The `apply` job's HALT remediation** — it routes host births to `-f apply_target=warm-standby`,
   which will HALT after this change. Rewrite. **Preserve the break-glass branch** (the
   legitimate-new-web-host guidance and the `[skip-web-platform-apply]` UNWEDGE line) — see AC5.
   Note `inngest_host` exists *to* birth a host, so "web" must do real work in any absolute claim.
3. **`nic-wait-gate.test.sh`** — prose-only update: its "KNOWN GAP … tracked in #6718" note now
   records the gap as closed. It deliberately never asserted the unguarded state, so no assert
   changes.
4. **The `apply_target` menu description** — still advertises warm-standby as an *"additive
   6-target apply + web-2 deploy fan-out"* to a host retired 2026-07-17. One line, zero risk, in a
   file already being edited. Per `hr-menu-option-ack-not-prod-write-auth` the dropdown **is** the
   authorization surface; offering a guaranteed-red option described as live degrades the ack.
5. **[CPO C3]** Reconcile `server.tf`'s "cx33-unrebuildable web-1" against #6538's table
   (`hel1 → rebuildable_in_place_today: YES`). One is wrong; a coherence PR must not leave it.

### Phase 4 — Record status; file the deferrals

1. **ADR-114** — factual status note on its 2026-07-19 amendment: #6718's gap closed; #6712's
   residual **prevented, not verified**, and its resolver deferred. Status, not a decision.
2. **ADR-068** — factual status note: web-2 is retired and both its warm-standby/recreate dispatch
   jobs are unrunnable, so its Phase 3 premise is dead. Without this, ADR-068 misleads a future
   reader — the ADR gate's own test.
3. **File the `warm_standby` zombie-job issue.**
4. **[CPO C2 — blocking] File "web-1 has no executable birth path."** A *distinct* DR issue,
   **not** #6459. CPO verified #6459 is blocked by #6570, whose own blocker is Hetzner **stock
   availability** — "revisit when #6459 lands" is a chain with no committed end. Trigger: *next
   web-host loss, or any change to `local.host_script_files`.* Must record that web-1's live host
   was armed by SSH `terraform_data` provisioners while a reborn host would be armed by cloud-init
   — a path that can now never execute, is therefore never validated, and drifts silently until a
   real DR event. **This issue is the vehicle for #6712's substance.**
5. **Comment on #6712** with the Operator Decision design record (two-scripts shape, TOCTOU
   reasoning, GHCR-private, digest≠provenance) and cross-link the C2 issue. In the *issue*, not a
   caller-less code comment.

### Phase 5 — Exit gate

`bash scripts/test-all.sh` (sharded in CI: `webplat`/`bun`/`scripts`) + `infra-validation.yml`.

---

## Files to Edit

| Path | Change |
|---|---|
| `.github/workflows/apply-web-platform-infra.yml` | `warm_standby`: +5 lines (parse, regex, HALT, remediation). `apply`: rewrite HALT remediation (preserve break-glass). `apply_target`: menu text. |
| `tests/scripts/test-destroy-guard-counter-web-platform.sh` | The one structural test (4 greps, flag-based awk, here-string). |
| `tests/scripts/lib/destroy-guard-filter-web-platform.jq` | Correct the now-false header claims. **Filter logic unchanged.** |
| `apps/web-platform/infra/nic-wait-gate.test.sh` | Prose-only: "KNOWN GAP" → closed. |
| `apps/web-platform/infra/server.tf` | **Comment only** (CPO C3 rebuildability reconciliation). No resource change. |
| `knowledge-base/engineering/architecture/decisions/ADR-114-*.md`, `ADR-068-*.md` | Factual status notes. |

## Files to Create

**None.** (Revision 3: the resolver script and its suite were cut with Half B.)

**No changes to:** `cloud-init.yml`, `soleur-host-bootstrap.sh`, any `local.host_script_files`
member, `web2-recreate-preflight.sh`, `scripts/test-all.sh`, any `.tf` **resource**, `AGENTS.md`.

---

## Acceptance Criteria

*(Renumbered 1–17 in revision 3 after the Half B criteria were removed.)*

### Pre-merge (PR)

- **AC1** — `awk '$0 ~ "^  warm_standby:" {b=1; next} b && /^  [A-Za-z_]/ {b=0} b && /^[A-Za-z]/ {b=0} b' .github/workflows/apply-web-platform-infra.yml | grep -q 'host_creates' && echo warm_standby_halt_present || echo warm_standby_halt_ABSENT`
  outputs `warm_standby_halt_present`. (Measured pre-fix: `warm_standby_halt_ABSENT`.)
- **AC2** — the `warm_standby` **`^[0-9]+$` validation line contains `host_creates`**, proven by
  the Phase 1 structural grep over the YAML. *(Explicitly NOT proven by a counts fixture: the
  suite's `_run_host_creates_gate` is a hand-maintained bash mirror, so a fixture proves the
  mirror, not the workflow. T32 already covers the mirror's parse-failure arm.)*
- **AC3** — the HALT is below the `set -e` re-enable, and ordered to mirror `apply`. Verified by
  line-offset assert within the extracted block, not by eyeball.
- **AC4** — `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` passes and the
  measured byte count is **unchanged** from P3.
- **AC5** — the `apply` HALT remediation (a) no longer routes births to `warm-standby`, (b)
  **preserves** the legitimate-new-web-host break-glass and the `[skip-web-platform-apply]`
  UNWEDGE line, and (c) **[CPO C1]** records that the no-automated-birth-path state violates
  `hr-fresh-host-provisioning-reachable-from-terraform-apply` and names the AC13 issue as owner.
  Any absolute claim scopes to **web** hosts (`inngest_host` exists to birth a host).
- **AC6** — **no** occurrence of the now-false `host_creates`-consumer claims survives in the jq
  header. Assert after `tr '\n' ' '` newline-normalization — the canonical text is **split across
  two lines** and a line-based `grep` cannot match it.
- **AC7** — the PR body uses `Refs #6718` and `Refs #6712`. **No `Closes`/`Fixes` keyword appears
  anywhere for any issue** — not in the PR body and not in any commit body (the squash reads
  both). `#6441` in particular carries no closing keyword (it holds the ADR-114 §I2 residual and
  the `WEB_HOST_PRIVATE_IPS` single-sourcing item).
- **AC8** — the PR body does **not** assert web-1 is unreachable from `-target=`; it reasons about
  the tripwire. It makes **no provenance claim** (digest = integrity only). It does **not** claim
  #6712 is closed or that a resolver shipped.
- **AC9** — **[discriminating]** the PR body states whether P2 resolved to *warn* (HALT executable
  → risk closed) or *error* (HALT present but **unreachable** → risk closed only once the job is
  revived). AC1 and the structural test pass identically in both cases, so this is the only
  criterion that can tell them apart.
- **AC10** — `bash scripts/test-all.sh` green; `infra-validation.yml` green.
- **AC11** — the `warm_standby` zombie-job issue exists and is linked.
- **AC12** — #6712 carries the Operator Decision design record and a cross-link to the AC13 issue.
- **AC13** — **[CPO C2]** the "web-1 has no executable birth path" issue exists, is **distinct**
  from #6459, and its trigger is **not** gated on #6459.
- **AC14** — the `warm_standby` HALT's `::error::` output contains a **routing instruction** and an
  explicit "no bypass on this dispatch" statement.
- **AC15** — the `apply_target` menu description no longer describes warm-standby as a live
  web-2 fan-out.
- **AC16** — `workspaces-luks-cutover-gate.sh`'s `positive` set still includes `create` (P6).

### Sequencing gate (records a condition; requires no action on this PR)

This PR itself needs **no post-merge operator action**: both changes are CI/dispatch-side guards,
and `apps/web-platform/infra/*.tf` has no **resource** change (comment-only), so the
merge-triggered auto-apply performs no work on this PR's account.

- **AC17** — **restate the force-replace gate in the PR body.** The original sequencing gated the
  inngest-host force-replace on *"#6712 + #6718 closed"*. **Under the revision-3 decision #6712
  stays open, so that gate can never clear as written.** It restates to:

  > **the `warm_standby` `host_creates` HALT is live on `main`, AND the "web-1 has no executable
  > birth path" issue (AC13) is filed.**

  Both conditions are objectively checkable — the first by AC1's command run against `main`, the
  second by the issue URL. This is the single thing most likely to be got wrong downstream: a
  reader tracking the old wording would wait indefinitely on an auto-close of #6712 that this
  plan deliberately never emits.

---

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO — required by threshold). Product/UX Gate
tier: **NONE** — no path in Files to Edit/Create matches any UI-surface term or glob; the
mechanical UI-surface override did not fire.

### Engineering (CTO) — **Status:** reviewed

Assessed twice (plan draft + review panel). Adopted: the `-var image_name` thesis, the
numeric-validation-regex fail-open bug, the stale remediation text, the zombie-job discovery, the
correction that Half B had **zero** live call sites (which drove the revision-3 cut), and the
correction that "the HALT is worth more because the job is a zombie" is inflated — on the normal
path web-1 is in state, so the HALT is inert; it fires only in the disaster case. The accurate
framing, now used: *the HALT is cheap and correct regardless of the job's health.*

**Recorded disagreement — CTO recommends extracting the guard to a shared lib; the plan keeps it
inline.** CTO's evidence is strong (re-counted at deepen — CTO said "11 gate libs across 7 files";
the accurate figure is **7 distinct gate libs across 22 source-sites**, which does not weaken the
point). See the Precedent Diff below. The plan declines **only** because extraction requires
editing the `apply` job's guard — the per-PR merge gate for the whole repo, where a defect halts
every merge or fails open. That is a materially larger blast radius than "wire an existing counter
into a sibling job." Persisted as **UC-2**; the operator has explicitly not overridden it.

### Product (CPO) — **Status:** reviewed. **Verdict: SIGN OFF WITH CONDITIONS**

CPO independently verified the load-bearing facts and confirmed `single-user incident` is correct
(if anything the vocabulary understates it — web-1 is a hard-pinned singleton, so an incident is
all-users). Reframed the trade correctly: this PR does **not** trade away a working DR path —
**there is no working automated birth path today**; it closes the last accidental hole in a
posture already chosen. C1 → AC5, C2 → AC13, C3 → Phase 3.5. C4 (resolver seam purity) is **moot**
after the revision-3 cut.

**Agents invoked:** cto, cpo, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer. **Skipped specialists:** none.

---

## Infrastructure (IaC)

**No Terraform resource changes; no apply fires.** No new resource, provider, variable, secret,
vendor, DNS record or persistent process. The only `.tf` edit is a comment (CPO C3).
`var.image_name`'s `:latest` default is deliberately kept — changing it would drift every apply.
No vendor tier gate, no recurring expense.

---

## Observability

```yaml
liveness_signal:
  what:          the structural warm_standby-HALT test (4 greps over the job block)
  cadence:       every PR touching these paths, and every push to main
  alert_target:  job failure in scripts/test-all.sh's `scripts` shard -> the REQUIRED `test`
                 context. (NOT deploy-script-tests: that job is ADVISORY, explicitly absent from
                 ruleset-ci-required.tf — an earlier draft claimed it was required, which is why
                 the load-bearing test was moved into the required shard.)
  configured_in: scripts/test-all.sh (+ .github/workflows/infra-validation.yml for the advisory
                 prose-only nic-wait-gate suite)

error_reporting:
  destination:   GitHub Actions ::error:: annotations on the dispatch run, read by the operator who
                 dispatched it. No Sentry/Better Stack layer is added — the guard is
                 CI/dispatch-time, not host-runtime, so there is no running surface to emit from.
                 (Layer citation: the GitHub Actions run log + annotation, the same layer every
                 sibling guard in this workflow reports through.)
  fail_loud:     true — every arm exits non-zero; no silent fallback, no continue-on-error

failure_modes:
  - mode:        warm_standby plan would birth a host/volume
    detection:   host_creates > 0 in the plan-step guard
    alert_route: ::error:: with a routing instruction + "no bypass on this dispatch" (AC14),
                 BEFORE terraform apply — no prod write occurs
  - mode:        counter absent/non-numeric -> guard fails OPEN ([[ "null" -gt 0 ]] passes)
    detection:   the ^[0-9]+$ validation line, proven by the structural YAML grep (AC2)
    alert_route: ::error:: "destroy-guard counter parse failed" + exit 1
  - mode:        the HALT ships present but UNREACHABLE (P2 resolves to "error")
    detection:   AC9 — the only criterion that discriminates; AC1 and the structural test pass
                 identically either way
    alert_route: recorded in the PR body as "closes once the job is revived", not "closed"
  - mode:        the 4th reacher (workspaces_luks_cutover) reopens if its gate narrows
    detection:   P6 asserts `positive` still includes `create`
    alert_route: AC16 failure
  - mode:        a downstream reader waits on an auto-close of #6712 that is never emitted
    detection:   AC17 restates the force-replace gate in objectively-checkable terms
    alert_route: PR body / review

logs:
  where:         GitHub Actions run logs; $GITHUB_STEP_SUMMARY for the warm-standby summary
  retention:     90 days (GitHub default)

discoverability_test:
  command:       bash tests/scripts/test-destroy-guard-counter-web-platform.sh
  expected_output: 0 failed
```

**Revised at ship-time (#6725 preflight Check 10).** The original command was an
`awk … | grep -q … && echo … || echo …` pipeline. Check 10 executes the declared command in a
scrubbed `env -i` sandbox and **refuses any command containing shell-active tokens** (`|`, `&&`,
`||`, `$(`, backticks) — so the documented probe could never actually be run by the gate that
exists to run it. Replaced with a single invocation of the suite itself, which is strictly
stronger: it proves the HALT **behaviourally** (T52 executes the workflow's own guard bytes
against real tfplan fixtures), not merely that the string `host_creates` appears in the job block.

**Verified:** executed in Check 10's exact sandbox
(`env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=$HOME timeout 15s bash -c …`) → `62 passed, 0 failed`, exit 0. The
pre-fix tree returned a failing count for the same command, so the probe discriminates. Previously
still runnable, since it targets the half that survived the cut. Real, always-exits-0, output
discriminates, no `ssh `. `expected_output` is the post-fix value. **Known limitation:** it greps
source, not execution — AC9 covers the reachability question it cannot see.

No post-deploy time-gated close criterion is declared, so no Follow-Through Enrollment deliverable
is required.

---

## Architecture Decision (ADR/C4)

**No new ADR.** The change mirrors an existing guard into a sibling job — a defect fix, recorded in
the jq header and workflow comment.

**Status notes only, to two ADRs that would otherwise misstate themselves** (the gate's own test:
*would a competent engineer reading the ADRs be misled?* — for both, yes):

- **ADR-114** names #6718 as a surfaced-not-closed gap and #6712 as the §I2 residual.
- **ADR-068** owns the warm-standby Phase 3 premise; web-2 is retired and both its dispatch jobs
  are unrunnable.

**ADR-080 amendment deferred**, not skipped: if resolve-then-pin becomes the standing rule for
every host-birth path, ADR-080 (*runtime plugin deploys via image rebuild*) owns the image-bake
staleness trap and is the right vehicle — **not** ADR-114, which is an ingress-topology decision.
Deferred until an enforcement point exists; the revision-3 cut makes that strictly later.

**No new ADR ordinal is claimed**, so `adr-ordinals` carries no collision risk. (`ship/SKILL.md`
still calls it "not a required check" — **stale**, it IS required; irrelevant here only because no
ordinal is minted.) **#6441 stays OPEN**, never referenced with a closing keyword.

### C4 views — no C4 impact, enumeration cited

Read all three model files rather than grepping the feature's own noun. **(a) External human
actors:** the dispatching operator — already via the `github` system. **(b) External systems:**
GHCR (`model.c4`, `ghcr = system "GitHub Container Registry"`), zot (`zotRegistry`), sigstore —
all three already modelled and already in both `views.c4` include lists. **(c) Containers:** the
`hetzner` web cluster, whose description already documents the first-boot GHCR pull + `docker cp`
of baked bootstrap scripts (ADR-080, #5921) — unchanged and **not falsified**. **(d) Access
relationships:** `hetzner -> ghcr` and `hetzner -> zotRegistry`, both already modelled. No element
added; no description falsified. *(An earlier draft proposed an "optional, cheap" edge-description
enrichment — cut: optional work that ships with two mandatory C4 validation runs attached is
neither. The revision-3 cut removes even the pretext.)*

---

## Risks & Mitigations

| ID | Risk | Mitigation |
|---|---|---|
| **R-A1** | **Guard fails OPEN.** Copying the comparison without extending the numeric-validation regex: `jq -r` on a missing key yields `null`, and `[[ "null" -gt 0 ]]` resolves an unset name to `0` and **passes**. (Verified empirically. Single-bracket `[ ]` would error rc=2 and fail *closed* — the fail-open property is specific to `[[ ]]`, which is what is there.) | Phase 2.2 + AC2's structural grep on the validation line. |
| **R-A2** | **`warm_standby` is a guaranteed-red zombie.** Its attach-proof asserts two `["web-2"]` addresses destroyed 2026-07-17, and `WEB_HOST_PRIVATE_IPS: "10.0.1.10"` yields `ROSTER_COUNT=1` against a `-ne 2` hard gate. Today it can only apply-then-fail. | Not fixed here; filed (Phase 4.3). The HALT is **cheap and correct regardless of the job's health**, and fires before the apply. |
| **R-A3** | **A coherence PR shipping new false comments.** | Phase 3 (five doc-coherence items) + AC5/AC6/AC15. This plan already hit the trap once — R-A5 below. |
| **R-A4** | **A second inline guard copy drifts from the first.** | Accepted for now; the parity test an earlier draft proposed was **cut** (it asserted an equivalence Phase 2 deliberately breaks, and is the same string-matching failure class as SE-3). The real fix is extraction — UC-2, Precedent Diff below. |
| **R-A5** | **[CORRECTED]** An earlier draft claimed subnet transitivity reaches inngest/registry/git-data and instructed documenting the guard as covering them. **The mechanism was inverted:** `-target` closes over **dependencies**, not dependents. Executing that mitigation would have shipped a false comment. | Correct statement: the counter is **type-scoped by design**, but warm_standby's **reachable** countable set is `hcloud_server.web["web-1"]` + `hcloud_volume.workspaces["web-1"]` (via `server.tf`'s `workspaces_volume_id` reference). Document the reachable set, not the type scope. |
| **R-A6** | **P1 inverts** (a second `web_hosts` key returns). | Phase 0 P1 hard STOP with a named alternative. |
| **R-A7** | **Capability removal, accepted:** if `hcloud_volume.workspaces["web-1"]` is ever lost while the server survives, warm_standby could previously recreate it; post-HALT it aborts. Almost certainly correct (a blank volume mounted where worktrees were is worse), but it is a real removal. | Recorded as an accepted trade. |
| **R-A8** | **[R3] The cut leaves #6712 open, and a downstream reader may wait on a close that never comes** — the original force-replace sequencing said "#6712 + #6718 closed". | AC17 restates the gate in objectively-checkable terms; AC12 puts the design record on the issue; the C2 issue (AC13) carries the substance. |
| **R-X1** | **[CORRECTED at deepen]** Mis-dismissing a signal that IS ours. The brief pre-dismisses `secret-scan` as red-on-main; **that premise flipped** — #6717 merged 20:59:35Z, #6706 is closed, main went green 20:59:38Z. Carrying the dismissal forward would suppress a genuine finding on this branch. | Re-derive per P5 **before** dismissing. Still valid to ignore: the #6443 drift signal (always alarms) and the zot veto (correct — leave it). |
| **R-X2** | The follow-through hook fires on the literal token anywhere in the PR body, including prose calling it a false positive. | Avoid the token; if unavoidable, add `<!-- gate-override: soak-followthrough-enrollment -->` + a one-line justification. |
| **R-X3** | Touching already-shipped work. | The ADR-114 §I1 first-boot NIC gate (merged/deployed 2026-07-19) and the merged observability half are **not** touched. Sentry if ever needed: org `jikigai-eu`, project `web-platform`, host `de.sentry.io`. |
| **R-X4** | **[CPO] DR posture, stated rather than left implicit.** After this PR web-1 has no automated birth path. **Corrected at review:** an earlier revision said "it had none before either". That overstated — pre-PR, `warm_standby` and `apply-deploy-pipeline-fix.yml` *would* have birthed web-1 successfully whenever `:latest` matched HEAD's host-script bytes, since the boot-time `host_scripts_content_hash` compare only fails on image drift. So a **conditional** path existed and this PR knowingly removes it; the honest claim is that the removed path was unpinned and unreliable, not that it was absent. Recovery now runs the **cloud-init** arming path, which can never execute automatically, is therefore never validated, and drifts against the SSH-provisioner path that armed the live host. Discovered only during a real DR event. | AC13's issue (#6730) owns it. Acceptable to hold **knowingly**; it was not acceptable to hold unrecorded — or to overstate. |

### Precedent Diff — inline guard vs. sourced gate lib

The plan prescribes a **pattern-bound behavior** (a plan-step destroy-guard) for which this repo
has an established canonical form. Precedent is stated rather than assumed, so a reviewer can
weigh the deviation:

| | **Canonical form (7 gate libs, 22 source-sites)** | **This plan (inline, 2nd copy)** |
|---|---|---|
| Location | `tests/scripts/lib/<job>-gate.sh`, `source`d by the job | inline in the job's `run:` block |
| Users | `web_2_recreate`, `inngest_host_replace`, `registry_host_replace`, `registry_region_migrate`, `git_data_host_replace`, `workspaces_luks_cutover`, `stock-preflight` | `apply` (pre-existing), `warm_standby` (new) |
| Counter validation | **loop over all counters** — `web2-recreate-gate.sh`: `for v in "$oos" "$ndel" "$rupd" "$replaced"; do if [[ ! "$v" =~ ^[0-9]+$ ]]` | **per-counter regex**, hand-extended each time (this is R-A1) |
| Test drives | the **same bytes** CI runs (`web2-recreate-gate.sh` header: *"no re-derived inline copy to drift"*) | a hand-maintained bash **mirror** (SE-5) |

**Deviation justified, not accidental.** Extraction is the better end state — it would dissolve
R-A1 structurally (the loop form validates every counter, including ones added later) and remove
the need for any drift guard. It is declined here **only** because the shared lib must also be
wired into `apply`, the per-PR merge gate for the whole repo, where a defect halts every merge or
fails open. That blast radius exceeds "wire an existing counter into a sibling job". Carried as
**UC-2** and as the second Deferrals row, with this diff as its evidence.

---

## Sharp Edges

- **SE-1 — job-block extraction MUST be flag-based awk, never a range.** `awk '/^  warm_standby:/,/^  [a-z-]+:/'` **self-matches**: the end pattern is satisfied by the start line, so it returns the heading only and any `grep -c` over it silently reads 0 — an AC that passes on an empty body. Use the `job_block()` idiom from `web-1-swap-concurrency-parity.test.sh` (TS twin: `extractJobBlock` in `terraform-target-parity.test.ts`). **Assert block non-emptiness first.**
- **SE-2 — never `printf "$block" | grep -q`.** Under `set -o pipefail` a matching `grep -q` closes the pipe → SIGPIPE 141 → false negative on large blocks (#6178). Use a here-string.
- **SE-3 — a string-matching parity test passes when both copies are equally wrong.** `terraform-target-parity.test.ts` string-matches this same workflow and strips `["key"]`, so the three dead `["web-2"]` targets stay green forever. Do **not** read its green as evidence the target set is live. This is why the proposed parity test was cut rather than added.
- **SE-4 — `[[ "null" -gt 0 ]]` is TRUE-shaped and evaluates FALSE.** Any counter guard without `^[0-9]+$` validation fails open. The single most likely way this PR ships broken-but-green.
- **SE-5 — a fixture proves the mirror, not the SUT.** `_run_host_creates_gate` is a hand-maintained bash reimplementation of the workflow block; nothing enforces the mirror. Only a grep over the YAML can prove the workflow's regex. Any AC saying "proven by fixture" about workflow behaviour is false.
- **SE-6 — a plan-quoted fact is a claim to verify — including a reviewer's, and including the brief's.** Revisions 2–3 corrected seven claims (impossible fixture, false-negative grep, inverted `-target` direction, out-of-scope lint, non-required check, false "one real call site", and the brief's own stale secret-scan premise), each caught only by re-running the command. Every number here was measured 2026-07-19 and is not a constant.
- **SE-7 — digest is integrity, never provenance.** No `cosign verify` exists on this path; the image is unsigned there by design. **No provenance claim anywhere** (AC8) — this survives the Half B cut because the PR body still describes the `:latest` mechanism.
- **SE-8 — explicit registration is coverage.** Both runners list suites with no glob; an unregistered suite is zero coverage, silently and greenly. Also: `grep -c` exits 1 on zero, so ACs using it need `|| true` under `set -euo pipefail`.
- **SE-9 — plan-time preflight.** Check 10 runs `discoverability_test.command` via `bash -c` (prose exits 127) — the command above is real and was executed post-amendment. Check 6 needs the canonical `- **Brand-survival threshold:** <label>` bullet, present verbatim in User-Brand Impact.

---

## Out of Scope

**#6500** (zot client enrollment), **#6466** (host-addressability), the held `INNGEST_BASE_URL`
repoint in draft PR **#6348**, **#6710**, **#6711**, the operator force-replace dispatch, the
ADR-114 **§I2 residual**, the zot veto, the #6443 drift signal, the #6441 NIC gate, and
**AGENTS.md**. **[R3]** Also now out of scope: the `resolve-image-digest.sh` extraction and any
change to `web2-recreate-preflight.sh`.

### Deferrals (each gets a tracking issue)

| Deferred | Why | Re-evaluation trigger |
|---|---|---|
| **[R3] #6712's resolver extraction** (Half B) | Five of seven reviewers converged; its only call site (`web_2_recreate`) is a zombie; operator ruled Option 2. Design record preserved in "Operator Decision" above. | **#6459** lands a real web-host create path → compose resolver → preflight → `plan -var image_name=<pinned>`. Recorded on **#6712**, which stays OPEN. |
| Extract the guard to a shared lib (UC-2) | Requires editing `apply` — the per-PR merge gate. Blast radius beyond the brief. Operator did not override. | Next counter added to the jq filter. |
| **web-1 has no executable birth path** (CPO C2) — **the vehicle for #6712's substance** | No automated path can birth the sole web host, and the cloud-init arming path has never executed. #6712 asks for a preflight; the panel established there is no create path for one to guard, so the real issue is the missing path itself. | **Next web-host loss, or any change to `local.host_script_files`.** Deliberately **not** gated on #6459. |
| `warm_standby` zombie state — fix or delete | Deleting implicates ADR-068 Phase 3; the HALT is independently valuable pre-apply. | Next warm-standby dispatch. |
| `terraform-target-parity.test.ts` cannot detect retired `for_each` keys (SE-3) | Needs its own design. | Any host key add/remove. |
