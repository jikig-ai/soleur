---
title: "infra(inngest): build the gated inngest-volume-recut apply_target and recut /mnt/data as LUKS"
date: 2026-09-02
slug: infra-inngest-volume-recut-luks
branch: feat-one-shot-7695-inngest-volume-recut-luks
issue: 7695
tracks: [7695, 7674, 6894]
type: infra
lane: cross-domain
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The dedicated Inngest host cannot leave its terminal `rolled-back` cutover state because arming
reaches a monotonic flush latch on `/mnt/data` that no repository mechanism can clear. This plan
builds the gated `inngest-volume-recut` apply_target that clears it, and recuts the volume as
LUKS rather than plaintext ext4 in the same change.

No spec.md exists for this branch — spec lacks valid `lane:`, defaulted to `cross-domain` (TR2
fail-closed).

## Research Insights

### Premise Validation (Phase 0.6) — every cited reading re-measured 2026-09-02

All measurements taken this session via `doppler run -p soleur -c prd_terraform -- bash
scripts/betterstack-query.sh`, the Hetzner API, `doppler secrets get`, and `gh api`. No SSH.

**CONFIRMED as briefed:**

| Premise | Live reading |
|---|---|
| Host dark, never served | `SOLEUR_INNGEST_SERVER_PROBE` @19:44:46Z: `server_active=inactive http_code=000 vector_active=active redis_active=active uptime_s=1191133 boot_id=cb4e3bb0-b625-45d4-8da1-dde39e4a7dbe cutover_flag=rolled-back` |
| Doppler flags | `soleur-inngest/prd`: `INNGEST_CUTOVER_FLIP=rolled-back`, `INNGEST_DIAGNOSTIC_BOOT=1` |
| `rolled-back` is terminal | `inngest-cutover-flip.sh` header: "`done / rolled-back / aborted / unset` idempotent no-op, exit 0" |
| Latch path + mount gate | `LATCH_FILE="${INNGEST_CUTOVER_LATCH:-/mnt/data/inngest-cutover/flip-done.latch}"`, `LATCH_REQUIRE_MOUNT="${INNGEST_CUTOVER_LATCH_MOUNT-/mnt/data}"` |
| Volume predates the flip, never recut | Hetzner `106261946`: `created=2026-07-07T23:51:07Z size=10 format=ext4 server=162809678 location=hel1` |
| G3.7 fails open | Measured L (flush-latch evidence, 365d) = **0**; H (flip-FSM liveness, 15m) = **20**. `flush_latch_decide(0,20)` → `clear` → gate **PASSES** |
| Live scheduler is web-1 | `function.finished` over 2h: **18 rows, 18/18 `host_name=soleur-web-platform`, 0 from soleur-inngest** |
| Nothing clears the latch today | `apply_target` options list has no inngest volume recut; `inngest-wiped-volume-verify.sh` `DATA_DIR="${INNGEST_DATA_DIR:-/var/lib/inngest}"` |
| Reviewer set non-empty | `gh api .../environments/inngest-cutover` → one required reviewer, `deruelle` (54279). Terraform-backed: `github_repository_environment.inngest_cutover` `reviewers { users = [54279] }` |

**CORRECTED — six premises did not survive measurement (four from the brief, two from my own
first-pass reasoning):**

1. **G3.7's blindness is RETENTION, not an ingestion stoppage.** The brief says "Better Stack
   ingestion for that channel stopped 2026-08-14". It has not: H=20 rows arrived in the last 15
   minutes. Measured warehouse floor — whole table, ungrepped: `oldest=2026-08-13 15:14:14`,
   `newest=2026-09-02 20:15:16`, `n=2855466`. Retention is **~20 days**. The flip completed
   2026-07-23/24, roughly **20 days before the oldest retained row**. The conclusion is not
   merely preserved, it is *strengthened*: L can **never** observe that flip, and no narrowing of
   `FLUSH_LATCH_SINCE` recovers it, because the row is not in the warehouse at all. G3.7's own
   text already concedes this — "Better Stack retention against a 365d window is UNMEASURED". This
   plan measures it.

2. **Layer B does not exist.** The brief says "Layer B is `cron-encryption-posture-reconcile.ts`".
   `git ls-files | grep encryption-posture` returns no such file, and **ADR-141** (`status:
   adopting`) records Layer B as **deliberately deferred** ("no runner-reachable live signal
   today"). Only **Layer A** (`scripts/lint-encryption-posture.py --repo-sweep`) plus the ledger
   row are in scope. Registering the new store in a Layer B reconciler is **cut**.

3. **R2 header escrow is explicitly REJECTED for this store.** The brief names
   `workspaces-luks-header.tf` as a precedent to copy. **ADR-142** rejects escrow here by name:
   "No key escrow (git-data-lean shape)… Escrowing the header would **add** a sensitive artifact
   (which, with the Doppler passphrase, yields full plaintext decrypt of user prompts/agent
   output) — a net **increase** in confidentiality attack surface for a durability gain this
   transient store does not need." Copying it would silently reverse an accepted ADR. See
   Decision Challenges.

4. **Uptime is 13.8 days, not three weeks.** `uptime_s=1191133` ⇒ boot ≈ 2026-08-20 00:52, which
   matches the flip channel's oldest row (`2026-08-20 00:53:27`) to the minute. The host is a
   **replacement** provisioned 2026-08-20; the latch was written by its **predecessor** in July and
   rode the re-attached volume across. The narrow claim (this host has not rebooted and has not
   served since 2026-08-20) holds — but see correction 5 for what it does **not** license.

5. **"Never served" is measured over the WRONG WINDOW — my own overreach, and the brief's.**
   The brief reasons "the host has not rebooted and has never served" and uses it to retire the
   risk that the July flip left recoverable state. It cannot. The current host **booted
   2026-08-20**; the flip completed **2026-07-23/24**, on a *previous host generation*. The
   evidence window therefore begins ~4 weeks **after** the window of concern, and extending it
   backward is exactly the failure mode
   `2026-08-25-i-wrote-the-evidence-down-and-then-concluded-the-opposite.md` records. The
   `server_active=inactive` reading is true and useful; it simply does not speak to July.
   **Consequence:** the question "was a FLUSHALL ever performed on this volume?" remains
   **UNMEASURED**, and the historical form of it is unanswerable (Better Stack retention is ~20d;
   July dispatch outcomes are gone by construction). The plan replaces it with the present-tense
   question, which is answerable and sufficient — see Phase 1.

6. **The CI-side `L` signal is already 0, so it is not a second blocker.** A design review raised
   that destroying the volume cannot decrement G3.7's `L` (Better Stack rows are immutable), and
   that a remediation leaving half the blocker standing is no remediation. The reasoning is sound
   but the premise is not: **L is measured at 0 today**, so G3.7 already returns `clear` and is
   already passing. The only standing blocker is the on-host latch. `L` is a weak pre-filter that
   can only ever ADD a refusal, and it decays by age-out, never by remediation. Recorded so the
   next reader does not mistake it for a second thing to fix.

**MECHANISM-vs-ADR conflict (Phase 0.6 step 4) — the load-bearing finding.**
**ADR-142** (`status: accepted`) decides an **additive blue-green byte-copy** migration for this
exact volume and forbids the briefed mechanism outright: "A `-replace` of
`hcloud_volume.inngest_redis` is ForceNew → a new empty volume → **every in-flight job lost**."
**ADR-100** §What remains open (later) blesses the destructive path conditionally: the
`inngest-volume-recut` design, "five guard layers including a 'host is dark' pre-flight refusal
absent from the `workspaces-luks-recut` template it is modelled on".

ADR-142's premise (sole-copy *live* in-flight data) is **in doubt but NOT falsified** — correction 5
above is precisely why. The resolution is therefore not "override ADR-142" but "**measure the thing
ADR-142 assumed, and make the answer a gate**": the destructive path is authorized only on a
measured-empty store, and ADR-142's byte-copy remains mandatory otherwise. Both the ADR-142
addendum and the new ADR recording that bound are deliverables of this plan (Phase 2.10), not
follow-ups.

### The blocker is exactly ONE arm — traced, not assumed

`flush_already_performed()` is a **disjunction over two** records, which the brief does not mention.
Both must be false for an arm to proceed:

- **Arm (a) — `/mnt/data/inngest-cutover/flip-done.latch`.** Append-only, monotonic, and on the
  volume *specifically so it survives a host replace*. This is the standing blocker, and only a
  recut (or an equivalent authorized clear) removes it.
- **Arm (b) — `/var/lock/inngest-cutover-flip.state` with `.flag == "done"`.** **Already false**,
  for two independent reasons the source states outright: `emit_state()` stamps the slot on *every*
  branch, and *"the `rolled-back` arm writes `{"flag":"rolled-back"}` straight over the `done`
  record"* — which is the live value today. Separately, *"`/var/lock` is the ephemeral root disk, so
  a host replace wiped the slot."*

So the recut plus the host replace clear both arms, and arm (b) needs no work. This also settles a
tempting wrong turn the source flags explicitly: relocating the erasable slot onto the durable
volume — *"the obvious 'make the latch survive a replace' fix"* — would make things **strictly
worse** by persisting the erasure, *"converting a latch that fails safe by amnesia into one that
fails unsafe by false memory."* The plan does not touch arm (b).

Corollary, and the reason Phase 1 is not optional: since arm (b) is already false and arm (a) is
invisible off-host, **nobody can currently tell whether the system is blocked at all.** The
measured `L = 0` means G3.7 passes, so the CI side is not blocking either. The entire question
reduces to one unreadable file — which is exactly what Phase 1 makes readable.

### Property List (Phase 0.6b)

- **P1** A standing `/mnt/data` flush latch can be cleared by an in-repo mechanism.
- **P2** The cutover FSM can leave terminal `rolled-back` without aborting into `aborted`.
- **P3** The AOF volume holding user prompts/agent output is encrypted at rest, flipping the
  ledger row from `plaintext-exception` before its `expires_on: 2026-10-22`.
- **P4** The destructive capability cannot fire without human authorization, and cannot fire by
  typo or mis-dispatch.
- **P5** The destructive capability cannot fire against a host that is actually serving.

### Cut List (Phase 0.6b) — mechanisms removed before research

| Mechanism | Property it would buy | Why cut |
|---|---|---|
| `cron-encryption-posture-reconcile.ts` registration | posture reconciled against live state | File does not exist; ADR-141 defers Layer B deliberately. Grepped the authority (`git ls-files`), not a consumer. |
| R2 header-escrow bucket (copy of `workspaces-luks-header.tf`) | LUKS header survives header-region corruption | ADR-142 rejects it for this store by name, on confidentiality grounds. Pending CTO ruling; see Decision Challenges. |
| Webhook latch readback (`cat-inngest-cutover-state.sh` behind a webhook id) | latch readable off-host | ADR-100 Decision 6a stands unamended; declined 2026-08-25 in favour of the Vector→Better Stack substitution. **Also moot:** a recut clears the latch unconditionally, so its prior state stops being a question you must answer. |
| New reviewer-gated environment | human authorization | Already exists — `github_repository_environment.inngest_cutover`, reviewer set verified non-empty. Reuse. |

### Reusable precedents (do not invent new shapes)

- **Escape hatch:** `apply_target=workspaces-luks-recut` in
  `.github/workflows/apply-web-platform-infra.yml` — `environment:` gate + typed `confirm` +
  `terraform plan -replace=<vol> -target=<vol> -target=<attachment>`. `server.tf` documents why
  `prevent_destroy` is omitted from the recut target: "*it collides with the
  `apply_target=workspaces-luks-recut` `-replace` escape hatch (prevent_destroy errors on
  -replace)*".
- **Destroy guard:** `tests/scripts/lib/workspaces-luks-recut-gate.sh` — sourced by BOTH the
  workflow step and its test so the decision logic is the same bytes. Carries the fail-closed
  `plan-gate-preamble.sh` (`assert_readable` / `assert_classifiable` / `assert_numeric`), an
  **ID-PIN** binding destruction to an operator-supplied physical volume id, named-live backstop
  counters, a 4-verb positive-action filter, and a **recovery bare-create arm** (`before == null`)
  for a stranded destroy-before-create.
- **LUKS volume:** `hcloud_volume.workspaces_luks` — **deliberately no `format` attribute**, so the
  device is raw and `blkid -o value -s TYPE` is a sound discriminator ("format only a device with
  NO filesystem signature"). `format = "ext4"` would make a fresh volume byte-indistinguishable
  from a populated one.
- **Ledger row:** `scripts/encryption-posture-ledger.json`, `hcloud_volume.workspaces_luks` —
  `device_binding{volume,attachment,mapper}` + `at_rest{mechanism,evidence,defends_against,
  does_not_defend,disclosed_as,live_verification}`. `lint-encryption-posture.py` resolves the
  citation structurally (attachment's `volume_id` must literally reference the volume; a
  co-located `random_password` + `doppler_secret` pair; a real `luksFormat`/`luksOpen` apparatus;
  mount evidence) — never by name similarity.
- **ADR-142 apparatus scope** already enumerates the intended resources:
  `random_password.inngest_redis_luks` (len 40, `special=false`), `doppler_secret.
  inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on the existing isolated `soleur-inngest/prd`,
  and the mapper name `inngest-redis`.

### Institutional learnings that change the design

| Learning | What it forces here |
|---|---|
| `2026-07-17-workflow-env-gate-references-unprovisioned-environment-auto-approves.md` | A YAML `environment:` line is not an environment. A missing/zero-reviewer environment **auto-approves silently**. Verified non-empty live AND Terraform-backed; add an assertion so it stays non-empty. |
| `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md` | Authorize by **physical id**, not terraform address — state corruption makes every address counter read 0 while the wrong volume dies. Also: accept the bare-create recovery shape or re-dispatch loops forever. |
| `2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` | Encrypting is necessary, not sufficient: the consumer must **re-assert the mount and fail loud** before serving, or a failed encryption boot degrades silently onto the root disk. |
| `2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it.md` | `luksFormat`+`luksOpen` without `mkfs` leaves a mapper with no filesystem; an unguarded `mount` under `set -uo pipefail` **without `-e`** swallows it. Guard each fs op explicitly. |
| `2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md` | A heartbeat proves the timer fired, nothing else — this host beat green for 12 days while serving zero dispatches. Any new liveness assertion must name the port/process, not the timer. |
| `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist.md` | Every new `logger -t <tag>` must be added to `vector.toml` Source 4 `include_matches.SYSLOG_IDENTIFIER` **and** its drift fixture in the same change, or the marker never leaves the deny-all-public box. |
| `2026-08-20-making-op-arm-idempotent-opened-the-window-the-refusal-was-holding-shut.md` | The `armed` value sits inside `inngest-server-flip-guard.sh`'s prod-start allowlist; removing a refusal opens states other guards' allowlists still accept. |
| `2026-07-07-immutable-redeploy.md` | A server `-replace` must also `-target` its attachments (`hcloud_server_network`, `hcloud_volume_attachment`, `hcloud_firewall_attachment`); a fresh host may boot with its private NIC down. |

### Registration sites for a new `apply_target` (all FIVE, or the gate is silently partial)

1. `.github/workflows/apply-web-platform-infra.yml` — the `options:` list **and** the job. Issue
   #7695 requires these be **bound**, so the option cannot exist without its guarded job.
2. `plugins/soleur/test/terraform-target-parity.test.ts`.
3. `plugins/soleur/test/stock-preflight-coverage.test.ts` (`EXCLUSION_ALLOWLIST`).
4. `scripts/test-all.sh` — `run_suite "tests/scripts/<name>-gate" bash tests/scripts/test-<name>-gate.sh`.
5. **`.github/workflows/infra-validation.yml`** — the site the four-site list I first derived
   **missed**, and the one issue #7695 calls out by name: *"Ship a `*.test.sh`, **registered in
   `.github/workflows/infra-validation.yml`** — an unregistered infra suite silently never gates."*
   Confirmed real: that workflow already registers `cutover-inngest-workflow.test.sh`,
   `inngest-dedicated-host-classify.test.sh`, `workspaces-luks-verify-workflow.test.sh` and others
   by name. An `apps/web-platform/infra/*.test.sh` that is not listed there never runs in CI.

The full-suite exit gate, not the touched-file loop, is what catches a missed registration — and
site 5 is exactly the orphan-suite class that gate exists for.

### The design is already written — inherit it, do not re-derive it

`knowledge-base/project/plans/archive/20260825-134550-2026-08-25-fix-inngest-host-not-serving-and-latch-gate-blindness-plan.md`
§Phase 3 carries the complete `inngest-volume-recut` design, deferred to "the PR that opens the
cutover window" — which is this one. Constraints taken from it verbatim rather than reinvented:

- **Name it `-volume-`, not `-luks-`.** `hcloud_volume.inngest_redis` is `format = "ext4"` with zero
  LUKS apparatus, so inheriting the template's name would assert a posture the volume does not have.
- **A typed confirm literal distinct from every existing one** (`RECUT-WORKSPACES-LUKS`,
  `RECUT-REGISTRY-LUKS`, …), so a token typed for another target cannot authorize this one. This
  plan uses `RECUT-INNGEST-VOLUME`.
- **A distinctly-named `expected_inngest_volume_id` input**, matched `^[0-9]+$` — not a shared id
  input, because sharing one across targets makes a wrong-volume mis-dispatch a typo rather than an
  impossibility.
- **Input budget:** `workflow_dispatch` caps at **10 inputs and 7 are used**;
  `expected_inngest_volume_id` spends slot 8, leaving two. The workflow's own convention note says
  the next per-target input *pair* should split into a dedicated workflow rather than spend the
  last two slots — so this target must not add a second input.
- **A job-level `concurrency` mutex.**
- **No `[ack-destroy]` bypass.** The environment reviewer approval is the authorization
  (`hr-menu-option-ack-not-prod-write-auth`); the typed token and the id pin are *typo-guards* and
  must be labelled as such.
- **Inherited cost, stated rather than discovered later:** a reviewer gate on this workflow has
  previously left apply runs `waiting` up to 13h while holding the workflow-level concurrency group
  (`cancel-in-progress: false`), blocking sibling applies. `workspaces_luks_recut` already accepts
  this trade; so does this target.
- **The dark-check reads the FLAG as well as the probe:** refuse unless the flag is readable **and
  outside `{armed, flipping, flushed, done}`** — every value in `inngest-server-flip-guard.sh`'s
  prod-start allowlist — *and* the latest probe row shows the host not serving.

### Conventions carried forward

- `hr-no-ssh-fallback-in-runbooks` / `hr-no-dashboard-eyeball-pull-data-yourself`: every reading
  above came from a scripted query, and the plan's probes must too.
- `hr-menu-option-ack-not-prod-write-auth`: a commit trailer is not authorization for a prod write;
  the environment reviewer gate is.
- `hr-tf-variable-no-operator-mint-default`: the LUKS passphrase is a `random_password`, never an
  operator-minted variable.
- `cq-test-fixtures-synthesized-only`: guard fixtures are synthesized plan JSON, never captured
  production plans.

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Measured reality | Plan response |
|---|---|---|
| "Better Stack ingestion for that channel stopped 2026-08-14" | Channel is live (H=20 rows in 15m). Warehouse floor is `2026-08-13 15:14:14` — **~20d retention**, table-wide. | Reframe G3.7's blindness as a **retention floor**, not an outage. The 2026-07-23/24 flip is ~20d outside retention, so L is structurally incapable of seeing it. Record the measured floor in ADR-100, which currently calls it "UNMEASURED". |
| "Layer B is `cron-encryption-posture-reconcile.ts`" | No such file. ADR-141 (`status: adopting`) **defers** Layer B — "no runner-reachable live signal today". | **Cut.** Scope reduces to Layer A (`lint-encryption-posture.py --repo-sweep`) + the ledger row. |
| "the R2 header-escrow bucket in workspaces-luks-header.tf" is a precedent to copy | ADR-142 **rejects** escrow for this store by name, on confidentiality grounds. | **Cut**, pending the CTO ruling recorded below. Raised as a decision-challenge, not silently reversed. |
| "Same boot_id as three weeks ago" | `uptime_s=1191133` ⇒ boot ≈ 2026-08-20 00:52, matching the flip channel's oldest row to the minute. **13.8 days.** | Corrected. The host is a **replacement**; the latch rode the re-attached volume from its predecessor. Material claim (never rebooted, never served) stands. |
| "Mirror the workspaces-luks-recut escape hatch" | That gate requires the passphrase be **UNTOUCHED** (it reuses an existing header). Here the passphrase is a **first provision**. | The gate is a **hybrid**: volume-replace semantics from `workspaces-luks-recut-gate.sh`, passphrase-**first-create** semantics from `workspaces-luks-cutover-gate.sh`. Stated explicitly so the inversion is not copied wrong. |

## User-Brand Impact

**If this lands broken, the user experiences:** a destroy-guard scoped one address too wide fires a
`terraform -replace` against `hcloud_volume.workspaces["web-1"]` — the live, sole-copy `/workspaces`
volume holding every user's repositories and agent working state — and the product is gone with no
backup. The nearer-term failure is milder but still user-visible: a LUKS mount that fails open
leaves Redis writing its AOF to the ephemeral root disk, so the next host replace silently discards
every queued job and armed reminder, and scheduled work stops firing with no error surface.

**If this leaks, the user's data is exposed via:** the AOF on this volume holds **in-flight job
payloads — user prompts and agent output** (ADR-142, the encryption-posture ledger's
highest-sensitivity row). Today it is plaintext ext4: a seized, RMA'd, or snapshot-imaged Hetzner
block volume yields those payloads directly. A LUKS passphrase written to the wrong Doppler project,
or a header escrowed next to its own key, converts an at-rest control into a single-artifact
compromise.

**Brand-survival threshold:** single-user incident

Consequences of that threshold, per the plan skill's staging model: `requires_cpo_signoff: true` in
frontmatter; `user-impact-reviewer` is invoked at review time; the eng plan-review panel escalates
to include `architecture-strategist` and `spec-flow-analyzer`.

## Open Code-Review Overlap

**None.** Queried all 63 open `code-review` issues (`gh issue list --label code-review --state open
--json number,title,body --limit 200`) against every path in Files to Edit / Files to Create —
`inngest-host.tf`, `cloud-init-inngest.yml`, `apply-web-platform-infra.yml`,
`encryption-posture-ledger.json`, `cutover-inngest.sh`, `inngest-cutover-flip.sh`, `test-all.sh`.
Zero bodies matched any path.

## Architecture Decision (ADR/C4)

This plan **changes an accepted architectural decision**, so the ADR work is a deliverable here, not
a follow-up (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR

Two distinct instruments, because this repo's convention — visible in both ADR-100 and ADR-142 —
is **addenda for observations, new ADRs for decisions**. Conflating them is what would leave the
encryption-posture ledger's provenance pointing at a document that no longer says what it said.

**(a) Addendum-in-place to ADR-142 — records measured fact, changes no decision.** ADR-142's
Context is written in the present tense about a live queue with armed reminders at arbitrary future
fire-times. That premise is now materially in doubt: the host has not served across the whole
observable window, `INNGEST_CUTOVER_FLIP=rolled-back` is terminal, and the store's occupancy is
**unmeasured**. A reader today would size the quiesce/canary work against a premise that may be
empty. The addendum states what is measured and what is not — including that the historical
"was a FLUSHALL ever performed" question is unanswerable at ~20d retention. It does **not** touch
ADR-142's `## Decision`. Small.

**(b) A NEW ADR for the decision this plan actually makes** — provisionally **ADR-198**, the next
free ordinal measured across all **64** `origin/*` refs (highest seen: ADR-197):

> *No-SSH authorized clearance of the inngest monotonic flush latch, bounded by a measured
> empty-store precondition.*

Its Decision: the destructive recut is authorized **only** when the store is *measured* empty and
the host *measured* dark on the same probe row; ADR-142's byte-copy remains mandatory otherwise.
This is not a reversal of ADR-142 — it is the branch ADR-142 never had to consider, because when
ADR-142 was written the store was presumed live. The two coexist: ADR-142 governs a populated
store, ADR-198 governs a provably empty one, and the gate decides which world you are in **at
dispatch time** rather than at authoring time.

**Why the bound, and not a blanket override.** The reasoning that "a re-flip `FLUSHALL`s Redis
anyway, so a recut and a latch-clear converge" is correct *only if the store is empty or its
contents are about to be flushed regardless*. It does **not** license destroying unmeasured state:
dormancy is a property of the host and is reversible (a host replace re-attaches this same volume);
a `-replace` is a property of the bytes and is not. So the plan does not assert the store is
empty — it **builds the channel that can say**, and makes the answer a precondition.

Also recorded in the new ADR:
- The measured Better Stack **retention floor (~20 days)**, retiring ADR-100's "retention against a
  365d window is UNMEASURED" with a number and the command that produced it.
- That `L`'s polarity **inverts** between `op=arm` (L≥1 ⇒ REFUSE) and `op=resume` (L≥1 ⇒ G2
  precondition SATISFIED), so any change to latch semantics must be reasoned through both.
- The escrow ruling (below), so the next reader does not re-litigate it.

The ADR-198 ordinal is **provisional**. `/ship`'s ADR-Ordinal Collision Gate must re-derive it
against freshly-fetched refs immediately before merge, and any renumber must sweep this plan,
`tasks.md`, and every AC naming the ordinal **in the same edit** — a renumber that reaches only the
ADR body leaves an AC asserting a nonexistent file.

### Escrow — ADR-142 wins, categorically

The brief names `workspaces-luks-header.tf`'s R2 header escrow as a precedent to copy. It is not
one. ADR-142 rejected escrow for **this** store by name and the reasoning is undisturbed: the
inngest AOF's total-loss recovery is already built and proven (`inngest-wiped-volume-verify.sh` —
functions re-sync from Postgres, the SDK re-registers, reminders enumerate/re-arm), so escrow's
specific job (surviving header corruption while the passphrase is intact) has a blast radius equal
to the bounded loss the queue-with-retry architecture already tolerates. Against that, the header
**plus** the Doppler passphrase yields full plaintext decrypt of user prompts and agent output — a
CWE-522-class net increase in confidentiality surface for a durability gain this store does not
need. `/workspaces` escrows because its loss is unrecoverable *by the user*; this store's is not.

This is the same template-inheritance error #7695 already caught one layer up when it refused the
`-luks-` name for a volume that is not yet LUKS — inheriting the template's escrow is that mistake
again with a security cost attached.

### C4 views

Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,
spec.c4}` — in full, not a keyword grep, and enumerate for this change:

- **External human actors:** none added or changed. The recut is an infrastructure lifecycle
  operation with no new correspondent, reviewer, or recipient.
- **External systems / vendors:** none added. Hetzner (block volume), Doppler (passphrase), Better
  Stack (probe transport) are all already modeled; this change introduces no new vendor edge. The
  R2 escrow bucket that *would* have added one is cut.
- **Containers / data stores touched:** `hcloud_volume.inngest_redis` — an **existing** store whose
  at-rest mechanism changes plaintext → LUKS. If the C4 model carries an at-rest or encryption
  annotation on this store (or describes it as plaintext), that description is falsified by this
  change and must be corrected.
- **Actor↔surface access relationships:** unchanged. No sharing, ownership, or trust-boundary move.

A "no C4 impact" conclusion is only permissible **after** that enumeration is actually performed
against all three files and each item above is confirmed already-modeled; record which. If the
model annotates this volume's encryption state, edit `.c4` directly and re-run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (a `view … include`
referencing an undefined element fails there, not at `tsc`).

### Sequencing

The ADR amendment is authored **in this PR**, describing the target state. It is not gated on the
cutover window actually being opened — the decision is true when the capability and its bound ship,
not when someone dispatches it.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis
    mechanism: luks
    evidence: >-
      apps/web-platform/infra/cloud-init-inngest.yml (cryptsetup luksFormat --batch-mode --type
      luks2 --key-file - / cryptsetup luksOpen --key-file - <dev> inngest-redis, guarded by the
      blkid TYPE discriminator); key: random_password.inngest_redis_luks +
      doppler_secret.inngest_redis_luks_key (apps/web-platform/infra/inngest-redis-luks.tf);
      mount gate: the findmnt re-assertion in the inngest-redis unit's ExecStartPre
    defends_against: >-
      a seized, RMA'd, or snapshot-imaged Hetzner block volume: the Inngest queue and run-state
      AOF — in-flight job payloads, i.e. user prompts and agent output — are unreadable without
      the Doppler-held LUKS passphrase
    does_not_defend: >-
      a leaked Doppler credential (the passphrase lives there, so a Doppler compromise is a key
      custody compromise), any read on the live host where the mapper is already unlocked, or an
      application-layer read through the Inngest control API
    disclosed_as: not-publicly-claimed
    live_verification: >-
      unavailable:the Hetzner API is blind to guest-side LUKS and no inngest-host posture probe
      exists (the workspaces luks-monitor.sh analogue is not built for this host)
in_transit:
  - connection: inngest-server -> host-local Redis
    tls: none
    cert_verification: n/a
    does_not_defend: an on-host process reading the loopback socket
    disclosed_as: not-publicly-claimed
    note: >-
      loopback-only (`bind 127.0.0.1`, ADR-100 Decision 6a); no network path exists to intercept,
      so this is not a plaintext-exception requiring an expiry
exception: none
```

**Citations must RESOLVE or `/ship` preflight Check 12 fails.** Check 12 fires on this diff — its
scope regex is `\.tf$|supabase/migrations/.*\.sql$|cloud-init.*\.ya?ml$|docker-compose.*\.ya?ml$`
and this PR touches both `.tf` and `cloud-init-inngest.yml`. It shells out to
`scripts/lint-encryption-posture.py --repo-sweep` and relays the exit code; the check does **not**
reimplement the logic, so the only way to pass is to satisfy the linter's structural resolution:
the attachment's `volume_id` must **literally** reference the volume resource, a `random_password`
+ `doppler_secret` pair must be **co-located in the same file**, a real `luksFormat`/`luksOpen`
apparatus must resolve to the named mapper, and mount evidence must exist for that mapper.

Two ledger-hygiene items carried from the legal review:

- The **existing** row's evidence string cites `apps/web-platform/infra/inngest-host.tf:288` — a
  bare line number, which violates `cq-cite-content-anchor-not-line-number`. The rewrite replaces
  it with a content anchor, matching the `hcloud_volume.git_data_luks` row's style.
- The row's `exception` block (`tracking_issue: #6894`, `expires_on: 2026-10-22`) is **removed**,
  not edited, and #6894 closes when the recut is verified. If the recut slips past 2026-10-22,
  re-date the exception with a fresh justification rather than letting it lapse silently — a
  lapsed exception is evidentially worse than an honest extension.
- **No retained plaintext backstop row is needed.** The destructive recut leaves no second volume;
  had this followed ADR-142's additive path, the retained plaintext volume would have required its
  own ledger row with its own exception and expiry, exactly like `hcloud_volume.workspaces` and
  `hcloud_volume.git_data`.

## Guard Contract

### Guard 1 — `inngest_volume_recut_gate` (terraform plan destroy-guard)

**Property.** No `terraform apply` reachable from `apply_target=inngest-volume-recut` destroys,
detaches, or replaces any resource other than **the inngest AOF volume and its attachment** — in
particular `hcloud_server.inngest` shows **zero actions** — and the volume it destroys is the exact
physical Hetzner volume the dispatch named.

The allow-set is therefore exactly two addresses: `hcloud_volume.inngest_redis` (a genuine replace,
or the recovery bare-create) and `hcloud_volume_attachment.inngest_redis` (a create). Everything
else, `hcloud_server.inngest` included, is named-live or out-of-scope.

**Assembly.** The guard quantifies over **every element of `.resource_changes[]` in the
`terraform show -json` document** produced by the recut job's own plan step — not over a list of
addresses known today. The chokepoint is that single plan document: the workflow step and
`tests/scripts/test-inngest-volume-recut-gate.sh` both `source
tests/scripts/lib/inngest-volume-recut-gate.sh` and call the same function, so CI's decision logic
is the same bytes the test exercises. There is exactly one chokepoint and no second injection site;
the guard's closure property is that any address **not** in the allow-set and **not** in the
named-live set trips `out_of_scope`, so a resource nobody enumerated still aborts.

**Mutation matrix** (each row MUST drive the guard RED; derived from the design, written before the
guard):

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Plan additionally shows `hcloud_volume.workspaces["web-1"]` with `["delete","create"]` | The live sole-copy `/workspaces` volume. `old_volume_touched` ≥ 1. |
| 2 | Plan shows `hcloud_server.web["web-1"]` replaced | cx33 is unrebuildable; `web1_server_touched` ≥ 1. |
| 3 | `.change.before.id` on the inngest volume is `999999999`, dispatch pinned `106261946` | ID-PIN: address resolves to a different physical volume than authorized. `luks_id_mismatch` ≥ 1. |
| 4 | Plan shows `doppler_secret.inngest_redis_luks_key` with `["update"]` | Passphrase **first create** is legal here; an update/delete/forget rotates the header key and strands the store. |
| 5 | Plan shows a second, un-enumerated resource (`hcloud_volume.git_data`) with `["delete"]` | `resource_deletes` catches any delete outside the two legitimately-replaced addresses. |
| 5b | Plan shows `hcloud_server.inngest` with `["delete","create"]` | The recut must **not** replace the host — that is `inngest-host-replace`'s job, under its own guard. `inngest_server_touched` ≥ 1. This row is what pins the three-dispatch split. |
| 6 | **Guard's own dispatch** — the workflow step is edited so the gate function is never called (the `source` line removed) | Anti-vacuity: a guard that reports "0 checked" and exits 0 is vacuous. The job must fail when the gate does not run. |
| 7 | A second inngest-adjacent resource is added to the plan after a compliant first (`hcloud_volume_attachment.git_data` created) | A check that stops at the first member is itself the defect class. The quantifier must reach member two. |
| 8 | Plan JSON is truncated / unparseable | `plan_gate_assert_readable` — "I could not check" must not read as "it is fine". |
| 9 | A counter evaluates to the empty string | `plan_gate_assert_numeric` — `[[ "" -gt 0 ]]` is FALSE under bash coercion, silently satisfying every threshold. |

**Harness rows** (mutate the SUITE, not the guard):

| # | Mutation | Why it must redden |
|---|---|---|
| H1 | Delete one fixture from `test-inngest-volume-recut-gate.sh` and leave the pass count assertion | The suite must assert a **floor on its own case count**, or dropping a case is invisible. |
| H2 | Replace the gate function body with `return 1` (reject everything) | Must be caught by a **must-PASS** row, not a RED row — RED rows cannot detect a guard that rejects everything. |
| H3 | **must-PASS, non-canonical:** the recovery bare-create shape (`["create"]` with `before == null`, no `expected_id` supplied) | A legal shape that is NOT the canonical replace. If only the canonical fixture passes, the guard is `diff <fixture> <canonical>` in disguise and a stranded destroy-before-create re-dispatch would loop forever. |

Fixtures are **synthesized** plan JSON, never captured production plans (`cq-test-fixtures-synthesized-only`).

### Guard 2 — `inngest_host_dark_gate` (the fifth layer, absent from the workspaces template)

**Property.** The recut cannot be dispatched against an inngest host that is currently serving.

**Property (full form).** The recut cannot be dispatched unless, on **one single probe row** from
the **current** host, the store is measured empty and the host measured dark.

**Assembly.** Quantifies over `SOLEUR_INNGEST_SERVER_PROBE` rows for the dedicated host inside a
**90-minute** window (the probe's cadence is hourly; a shorter window makes a healthy host look
silent), read through `scripts/betterstack-query.sh` — the same no-SSH transport
`_flip_query_rows` / `_flush_latch_count` already use, so no new transport, credential, or fixture
class is introduced. **All six conditions, and all field reads from the SAME row — never joined
across rows:**

1. Row count in the window **≥ 1**. Zero rows ⇒ verdict `silent` ⇒ REFUSE — distinct from
   `unreadable`, and never `dark`.
2. Counts validated by an explicit `^[0-9]+$` predicate. A non-decimal or unparsed count ⇒
   `unreadable` ⇒ REFUSE. (`[[ "" -gt 0 ]]` is FALSE under bash coercion — the documented
   empty-count bypass class.)
3. `server_active=inactive` **and** `http_code` non-200. `server_active` alone is a systemd claim;
   `http_code` is the claim that matters — this host once reported a started unit that had failed
   to bind its port.
4. **`boot_id` on that row equals the `boot_id` on the newest row.** Without this, "dark" can be a
   fact about a host that no longer exists. This condition is absent from every existing gate on
   this surface and is what makes the other five sound.
5. **`redis_keys == 0`**, from `INFO keyspace` across **all** databases — **not `DBSIZE`**, which
   is db-0 only while `FLUSHALL` spans every db. The shipped post-flush assert already carries that
   asymmetry; it must not be inherited into a gate that authorizes destruction.
6. The live Hetzner attachment's volume id equals the id the dispatch pinned.

Independently, `function.finished` rows carrying `host_name=soleur-inngest` must be **zero**.

**Nothing extra is needed to enforce the Phase 1 → Phase 3 ordering.** The two phases ship in the
same PR, so in principle someone could dispatch the recut first — but Guard 2 makes that
self-defeating rather than dangerous. Before Phase 1's emitter is live, probe rows exist but carry
**no `redis_keys` field**; the read yields an empty string, condition 2's `^[0-9]+$` predicate
fails, and the verdict is `unreadable` ⇒ REFUSE. The ordering is enforced by the gate's own
fail-closed parse, not by documentation asking for patience. This is deliberate: an ordering
constraint that lives only in prose is not a constraint.

**If `redis_keys > 0` the destructive path is REFUSED outright, no exceptions** — and note that
enumeration is then unavailable, because `inngest-enumerate-reminders.sh` queries
`127.0.0.1:8288`, which is not bound on a dark host. Non-empty **and** non-enumerable means
ADR-142's preserve-and-copy is the only lawful path, and the dispatch must route there.

**The decision function is a positive allowlist.** It proceeds only on the literal `dark`; every
other token — including `unreadable` — aborts. This is deliberate and inverts G3.7's posture: G3.7
is a *pre-filter* that may only ADD a refusal, so a read failure there degrades safely to the
on-host latch. Here the gate is *authorizing an irreversible destroy*, so an unreadable signal must
abort. A gate that cannot see the host must never conclude the host is dark.

**Mutation matrix:**

| # | Mutation | Why it must redden |
|---|---|---|
| 1 | Probe rows report `server_active=active` | The host is serving; the recut destroys live queue state. |
| 2 | Probe rows report `http_code=200` with `server_active=inactive` | Disagreeing signals are not "dark". Both must agree. |
| 3 | One or more `function.finished` rows carry `host_name=soleur-inngest` | The host is executing functions regardless of what the probe says. |
| 4 | The Better Stack read returns non-zero / `__UNREADABLE__` | Fail-closed: unreadable ≠ dark. |
| 5 | Zero probe rows in the window (host silent, not proven dark) | **Silence is not evidence of darkness** — this is the exact G3.7 fail-open class, and this gate must not repeat it. |
| 6 | **Guard's own dispatch** — the gate call is removed from the job | Anti-vacuity floor. |
| 7 | `redis_keys=3` with every other condition satisfied | The store is populated; the destructive path is refused outright. |
| 8 | `redis_keys` sourced from `DBSIZE` instead of `INFO keyspace`, with keys present only in db-1 | `DBSIZE` reads db-0 only and would report 0 on a populated store — a false `dark`. |
| 9 | The row satisfying conditions 3+5 carries a `boot_id` differing from the newest row's | Reading a pre-replace host. "Dark" about a host that no longer exists. |
| 10 | Conditions 3 and 5 satisfied but on **two different rows** | Fields must come from one row, or the gate authorizes on a state that never simultaneously existed. |

**Harness rows:**

| # | Mutation | Why it must redden |
|---|---|---|
| H1 | Remove a fixture, keep the count assertion | Case-count floor. |
| H2 | Make the decision function always return `dark` | Caught only by a must-FAIL row pairing; assert the reason token, never just rc. |
| H3 | **must-PASS, non-canonical:** probe rows present and dark, `function.finished` rows present but **all** `host_name=soleur-web-platform` | The real production shape — a busy fleet with a dark inngest host — must PASS, or the gate is unusable exactly when it is needed. |

**Why layer 5 exists at all:** every other layer authorizes *by intent* (a human approved, a token
was typed, the plan shape matched). Only this one checks the *world*. The measured facts that make
this recut safe (host dark, scheduler elsewhere) are facts about the world at dispatch time, and a
plan that assumes them without checking is a plan that was correct on 2026-09-02 and silently wrong
afterwards. Encoding the premise as a gate is what stops this plan's own reasoning from rotting —
the failure mode this feature's history is a case study in.

## Observability

```yaml
liveness_signal:
  what: >-
    SOLEUR_INNGEST_LUKS_STAGE — a boot-stage marker emitted by the cloud-init LUKS block, mirroring
    the existing inngest-boot-phone-home.sh SOLEUR_INNGEST_BOOT_STAGE emitter, carrying
    stage (key-fetch|blkid-probe|luksFormat|luksOpen|mkfs|mount|fstab), rc, and the blkid TYPE read
  cadence: once per boot, per stage
  alert_target: Better Stack Logs (same source table as SOLEUR_INNGEST_SERVER_PROBE)
  configured_in: >-
    apps/web-platform/infra/cloud-init-inngest.yml (emitter) and
    apps/web-platform/infra/vector.toml Source 4 include_matches.SYSLOG_IDENTIFIER (allowlist)
error_reporting:
  destination: Better Stack via the on-host Vector journald shipper; the boot-stage HTTP emitter is
    the independent fallback for failures that precede Vector
  fail_loud: >-
    yes — the LUKS stage runs under `set -euo pipefail` inside its own exec'd child with an ERR
    trap, and every fs operation (luksFormat, luksOpen, mkfs, mount) is individually rc-checked.
    No `|| true` on any step that can leave /mnt/data on the root disk.
failure_modes:
  - mode: cryptsetup luksOpen fails (wrong/empty passphrase from Doppler)
    detection: SOLEUR_INNGEST_LUKS_STAGE stage=luksOpen with non-zero rc
    alert_route: Better Stack; the host never reaches the mount stage and Redis must not start
  - mode: LUKS mount fails open, leaving /mnt/data as a root-disk directory
    detection: >-
      the inngest-redis unit's ExecStartPre findmnt re-assertion refuses to start, emitting a FATAL
      marker; independently, the flip FSM's own mountpoint gate emits
      `latch-unrecordable detail=not-a-mountpoint`
    alert_route: Better Stack; both markers are on the allowlisted tag set
  - mode: blkid reports a filesystem signature on a device the recut expected to be raw
    detection: SOLEUR_INNGEST_LUKS_STAGE stage=blkid-probe with the observed TYPE; the guard
      refuses to format a populated device
    alert_route: Better Stack; boot halts loudly rather than overwriting a populated store
  - mode: the recut lands but the flip FSM can no longer record its latch
    detection: >-
      `"reason":"latch-unrecordable"` rows — the same literal G3.7 already keys on. This is the
      coupling the legal review surfaced: the latch's re-arm path depends on /mnt/data being a
      genuine mountpoint on the NEW volume.
    alert_route: Better Stack; the FSM drives the flag to terminal `aborted`, halting the poll
discoverability_test:
  command: >-
    doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 6h
    --grep SOLEUR_INNGEST_LUKS_STAGE --limit 20
  expected_output: >-
    one JSON row per boot stage with rc=0 through stage=fstab, and a subsequent
    SOLEUR_INNGEST_SERVER_PROBE row reporting redis_active=active
  credentials_required: >-
    BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD} from Doppler prd_terraform — the log warehouse has
    no unauthenticated read surface, so no unauthenticated probe verifies this property
```

**Vector allowlist coupling is load-bearing.** `vector.toml` Source 4 matches
`SYSLOG_IDENTIFIER` by **exact-value equality** (`sd_journal_add_match`), not prefix or regex — a
tag typo silently matches nothing and the marker never leaves this deny-all-public host. The new
tag must be added to the Source 4 allowlist **and** to the drift fixture
`apps/web-platform/test/infra/vector-pii-scrub.test.sh` **in the same change**. "It rides the
already-shipped shipper" is a claim, never a fact.

**Do not build a heartbeat.** This host beat green for 12 days while serving zero dispatches
(`2026-08-04-my-probe-passed-against-the-outage-it-was-built-to-detect.md`). Every signal above
names a stage, an rc, or a port — never a timer firing.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Issued a binding ruling that **refused the destructive recut as briefed** — not on
ADR-142 doctrine, but on two code-level grounds. Both were adopted, one after correction.

- **Adopted — the premise is unmeasured.** Nobody has read
  `/mnt/data/inngest-cutover/flip-done.latch`. ADR-100's "latch intact" is a
  survival-by-construction claim about host replaces, not an observation. Dispatching a destructive
  target against an unmeasured premise inverts the evidence ordering the rest of this surface
  enforces. **This restructured the plan**: Phase 1 now builds the read channel, and the gate makes
  the measurement a precondition rather than an assumption.
- **Adopted — "already dead" is not sufficient grounds.** Dormancy is a property of the host and is
  reversible (a host replace re-attaches this same volume); a `-replace` is a property of the bytes
  and is not. The correct test is never "is it currently functioning" but "is its content
  enumerable, and is it empty or reproducible elsewhere." The plan no longer argues from dormancy.
- **Adopted — my "never served" evidence covers the wrong window.** See Research Insights
  correction 5. Owned, not deflected.
- **Adopted in full — the escrow ruling**, the `INFO keyspace`-not-`DBSIZE` correction, the
  `boot_id` pin, the `silent`≠`unreadable` split, and the six-site cross-consumer sweep including
  `L`'s polarity inversion between `op=arm` and `op=resume`.
- **Corrected — "the recut clears only one of two blockers."** The ruling held that destroying the
  volume cannot decrement G3.7's `L` (log rows are immutable), and called this disqualifying. The
  mechanism is right; the premise is not. **`L` is measured at 0**, so G3.7 already returns `clear`
  and is not blocking. The ruling's own leading hypothesis predicts exactly this. Recorded as a
  caveat, not a blocker.
- **Re-scoped rather than accepted wholesale.** The ruling's recommended Option A (execute ADR-142's
  full byte-copy migration inside #7695) is itself the scope collision it warns against one
  paragraph earlier. The plan instead builds ADR-142's *shared apparatus* (passphrase, Doppler
  secret, raw volume, cloud-init LUKS block — inert on merge, common to both paths) plus the gated
  recut as a **bounded** cutover mechanism. The ruling's own words license this: *"If `redis_keys >
  0`: the destructive path is REFUSED outright"* — which is a precondition, not a prohibition, and
  *"if the store is empty now, risks (1) and (2) and the entire dormancy debate collapse to
  nothing."* The gate is that precondition made mechanical.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Advisory, draft, not legal advice. No legal blocker; no DPIA trigger (the change
reduces risk).

- **No public over-claim — affirmatively cleared.** Every at-rest claim in the published corpus
  (`docs/legal/privacy-policy.md` §11 ×2, §5.7) is scoped by its own text to *workspace git data*
  or *API keys*. None reaches this store. The August 2 re-scoping is what averted it. The plan
  states this affirmatively rather than leaving the question open.
- **Adopted — Art. 30 PA-13 is materially false and this change makes it conspicuous.** Limb (e)
  says "Self-hosted binary persists state in SQLite on the same Hetzner host" — wrong substrate
  (Redis AOF on a block volume) and wrong host (extracted to a dedicated host per ADR-100). Split
  per `wg-when-an-audit-identifies-pre-existing`: **correct (e) in-PR** (a one-line substrate fix on
  a file this PR already reasons about); **file a `compliance/` issue** for limb (f)'s harder
  cross-PA determination of whether the store is personal-data-bearing, which needs real analysis.
- **Adopted — ledger hygiene.** Five fields change, not one; the existing evidence string cites a
  bare line number (`inngest-host.tf:288`), violating `cq-cite-content-anchor-not-line-number`.
- **Adopted — verify `--history-retention` is actually set** against the unit file rather than
  assumed, or PA-13(f)'s published 30-day envelope is unevidenced.
- **Adopted — record the destruction.** An Art. 5(2) one-line record in
  `knowledge-base/legal/audits/` converts an undocumented wipe into evidence.
- **Rejected as stated, underlying insight adopted.** The review flagged CRITICAL that the recut
  "disarms the #7228 P0-5 re-flush guard" and must "carry the latch across." Carrying it across
  would defeat the entire purpose of #7695 — clearing that latch *is* the deliverable, and a
  latch that survives its own clearance mechanism is not a fix. But the underlying coupling is
  real and load-bearing, so the plan encodes it three ways: (i) `record_flush_latch` re-arms the
  guard automatically at the next successful flip, so the disarmed window is bounded by design;
  (ii) that re-arm depends on `/mnt/data` being a **genuine mountpoint** on the new LUKS volume —
  if the LUKS mount fails open, the FSM's own mountpoint gate fires `latch-unrecordable` and
  drives the flag to terminal `aborted`, which is fail-closed and correct, and the plan asserts
  the mountpoint property directly; (iii) the audit trail the review wanted is satisfied
  **off-host and immutably** — Phase 1's probe ships the verbatim latch record to Better Stack
  before anything is destroyed. That is a better record than an on-disk file, which the recut
  would destroy anyway.

### Product/UX Gate

Not applicable. The mechanical UI-surface override did not fire: no path in Files to Create or
Files to Edit matches the shared UI-surface term list or glob superset — the change is Terraform,
cloud-init, shell guards, a workflow job, a JSON ledger, and ADRs. Product assessed **NONE**.

### Finance

Not relevant under the chosen design. The recut **replaces** the volume rather than adding one, so
there is no new recurring vendor line (`wg-record-recurring-vendor-expense-before-ready` does not
fire). Had this followed ADR-142's additive path, the second 10 GB Hetzner volume retained as a
backstop would have been a new recurring cost requiring a ledger entry before PR-ready.

## Infrastructure (IaC)

### Terraform changes

| File | Change |
|---|---|
| `apps/web-platform/infra/inngest-redis-luks.tf` **(new)** | `random_password.inngest_redis_luks` (length 40, `special = false`, **no** `ignore_changes`) and `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on the **existing isolated** `soleur-inngest/prd`, `visibility = "masked"`. Co-located in one file because `lint-encryption-posture.py` requires the `random_password` + `doppler_secret` pair be co-located to resolve the citation. |
| `apps/web-platform/infra/inngest-host.tf` | Remove `format = "ext4"` from `hcloud_volume.inngest_redis` so a recut yields a **raw** device and `blkid -o value -s TYPE` becomes a sound discriminator. |
| `apps/web-platform/infra/cloud-init-inngest.yml` | Replace the plaintext mount block with a three-arm LUKS stage (below). **ForceNew on `hcloud_server.inngest`.** |

No new provider, no new version pin, no new no-default variable — the passphrase is a
`random_password`, never an operator-minted `TF_VAR_*` (`hr-tf-variable-no-operator-mint-default`),
and it lands in the existing isolated project read by the existing read/write boot token. No new
Doppler project, no new GitHub Actions secret, no new branch config.

**`format` removal is the highest-risk single line in the diff.** `format` is ForceNew on
`hcloud_volume`; removing it from config while state carries `"ext4"` may queue a **replace** on the
next plan. The inngest volume is **not** in the per-merge `-target=` allowlist, so no merge-apply
can act on it — but a queued replace that some broader dispatch picks up would destroy the volume
outside the gate. **Phase 0 must measure this**, not assume it: run `terraform plan` and read
whether the removal queues a replace. If it does, pin it behind `lifecycle { ignore_changes =
[format] }` until the recut dispatch, and record the reading in the plan.

### Apply path

**(b) cloud-init + gated dispatch** — never a merge-apply, and **three** dispatches, not two.

1. **Merge is inert.** Every touched resource is excluded from the per-PR CI `-target=` list; the
   workflow's own error text already routes `hcloud_server.inngest` to `-f apply_target=inngest-host`.
   Zero live mutation on merge.
2. **Dispatch A — `apply_target=inngest-host-replace`** (existing target, non-destructive to
   `/mnt/data`). Delivers the extended probe and the new three-arm cloud-init. The volume is still
   plaintext ext4, and the `ext4` arm mounts it as-is — so this step changes **no data**. Its whole
   purpose is to make the latch and the store's key count **readable**.
3. **Observe.** At least one probe row carrying `flush_latched`, `latch_flushed_at`, `latch_dbsize`
   and `redis_keys` must land in Better Stack. That row is both Guard 2's input **and** the only
   surviving audit record of what the recut destroys.
4. **Dispatch B — `apply_target=inngest-volume-recut`** (new), only if Guard 2's conditions hold.
   Replaces **the volume and its attachment ONLY**. `hcloud_server.inngest` shows **zero actions**.
5. **Dispatch C — `apply_target=inngest-host-replace`** again. The new host boots, the `blkid` arm
   sees a **raw** device, and luksFormats it.

**Why three and not two — a correction driven by the pre-written design.** The first draft of this
plan folded the host replace into the recut dispatch, on the reasoning that a fresh raw volume needs
the new cloud-init to format it. But the #7674 design's fourth guard layer asserts from the saved
plan that *"`hcloud_server.inngest` and every unrelated resource show **zero** actions"* — and
widening the most destructive target in the inngest surface to also permit a server replace would
destroy exactly that assertion. Splitting keeps each guard tight and **reuses `inngest-host-replace`,
which already has its own guard**, rather than growing a second host-replace path inside a
volume-recut target. Between dispatches B and C the running host holds a stale mount of a
now-destroyed volume; that is harmless precisely because the host is dark, and dispatch C resolves
it. Narrow guards plus one extra dispatch beats a wide guard.

Blast radius: the dedicated host and its AOF volume only. Both are excluded from every automatic
apply path. The host serves nothing (measured), so the outage window is zero user-visible minutes —
the co-located web-1 scheduler is unaffected because it is a different host with a different volume.

`hcloud_firewall_attachment.inngest` is **deliberately not `-target`ed**: `server_ids` is
update-in-place, not ForceNew, and `inngest-host.tf` explicitly instructs *"Do NOT add it to the
replace allow-set — an in-place update is not a replace."* The new host boots with no hcloud
firewall attached until the next drift apply reconciles it; blast radius is low because that
firewall is a zero-rule deny-all and the real control is host-local nftables.

### Distinctness / drift safeguards

- The passphrase lands on `soleur-inngest/prd`, **never** `soleur/prd` — a mutation-tested guard row.
- **No `lifecycle.ignore_changes` on the passphrase or its secret.** Rotation is
  `cryptsetup luksChangeKey`, **never** a `-replace`: a `-replace` mints a new passphrase without
  rekeying the LUKS header and strands the store. The gate asserts the passphrase is untouched at
  recut time for exactly this reason.
- `user_data` stays **out** of `ignore_changes` on `hcloud_server.inngest`, preserving the
  replace-to-reprovision path this host's delivery model depends on (#6780).
- Terraform state carries the passphrase in plaintext; the R2 backend is the existing encrypted
  tfstate bucket, and the escrow bucket that would have added a second sensitive artifact is cut.

### Vendor-tier reality check

None. No new vendor, no tier-gated resource, no free-tier limit in play — Hetzner block volumes,
Doppler secrets, and Better Stack log ingest are all existing, in-plan capabilities.

## Implementation Phases

### Phase 0 — Preconditions (measure, do not assume)

0.1 Re-run every Premise Validation reading; the plan's own history is a case study in a stale
    reading repeated as current. Confirm `cutover_flag=rolled-back`, host dark, `L`/`H`, and the
    Hetzner volume's `format` and id.
0.2 `terraform plan` and read whether removing `format = "ext4"` queues a replace of
    `hcloud_volume.inngest_redis`. Record the verbatim plan line. Decide `ignore_changes` on the
    measurement, not on expectation.
0.3 Confirm the `inngest-cutover` environment still has a **non-empty** reviewer set via
    `gh api repos/:owner/:repo/environments/inngest-cutover`. A zero-reviewer environment
    auto-approves silently.
0.4 Read all three `.c4` files and complete the enumeration the ADR/C4 gate requires.
0.5 Verify `--history-retention` on the inngest-server unit against the unit file.

### Phase 1 — The read channel (M0) — prerequisite for everything else

Extend the **existing** unconditional hourly `SOLEUR_INNGEST_SERVER_PROBE` emitter in
`inngest-bootstrap.sh` with `flush_latched`, `latch_flushed_at`, `latch_dbsize` (parsed from the
**last** line of the append-only record, matching `cat-inngest-cutover-state.sh`'s `tail -n 1`), and
`redis_keys` (from `INFO keyspace`, **all** dbs). Emit them from the `rolled-back` / `done` /
`aborted` no-op arms too — those currently ship an empty string.

This is **not** the webhook readback ADR-100 Decision 6a rejected and the operator declined. It adds
no inbound control plane and no new transport: it extends an emitter that already runs, already
reads Doppler, and already ships over the on-host Vector → Better Stack journald channel — which is
precisely the substitution ADR-100 records the operator choosing on 2026-08-25. Decision 6a stands
unamended.

### Phase 2 — LUKS apparatus (inert on merge)

`inngest-redis-luks.tf`; remove `format`; three-arm cloud-init LUKS stage:

| `blkid` TYPE | Arm | Rationale |
|---|---|---|
| `ext4` | mount as ext4, emit a `plaintext-awaiting-recut` marker | The pre-recut state. Must not format. |
| *(empty)* | `luksFormat` → `luksOpen` → `mkfs.ext4` → mount | The only formattable state. |
| `crypto_LUKS` | `luksOpen` → mount | Idempotent on every later boot. |
| anything else | **FATAL, halt** | Refuse to write to a device whose contents are unknown. |

Copy `cloud-init-git-data.yml`'s hardening verbatim in shape: run under an exec'd child with
`set -euo pipefail` and an ERR trap; accept `blkid` rc 0 **or** 2 and treat any other rc as fatal;
treat "status probe rc=1 but `blkid` still reports `crypto_LUKS`" as a **damaged header**, not a
blank volume; rc-check `luksFormat`, `luksOpen`, `mkfs`, and `mount` individually. **No `|| true`
on any step that could leave `/mnt/data` on the root disk**, and no `nofail` semantics that let a
failed open degrade silently — the current block's `mount … || true` plus `nofail` is exactly the
hazard the FSM's own mountpoint gate warns about.

Add an `ExecStartPre` `findmnt` re-assertion to the Redis unit so it refuses to serve off an
unmounted path. Encrypting the volume is necessary but not sufficient; a consumer that starts on the
empty fallback path degrades silently behind an otherwise-green liveness signal.

Register the new `SOLEUR_INNGEST_LUKS_STAGE` tag in `vector.toml` Source 4 **and** its drift fixture
in the same commit.

### Phase 3 — The gated apply_target

`apply_target=inngest-volume-recut` with all five guard layers: environment reviewer gate, typed
`confirm=RECUT-INNGEST-VOLUME`, plan destroy-guard with ID-PIN, the host-dark/store-empty gate
(Guard 2), and the named-live backstop counters. Write the **mutation matrices before the guards**.

Register in **all five** sites: workflow `options:` + job (bound, so the option cannot exist
without its guarded job), `terraform-target-parity.test.ts`, `stock-preflight-coverage.test.ts`,
`test-all.sh`, and **`infra-validation.yml`** — the orphan-suite site an infra `*.test.sh` silently
never gates without. Add the job-level `concurrency` mutex and the `expected_inngest_volume_id`
input (slot 8 of 10; do not add a second input).

### Phase 4 — Records

ADR-142 addendum; new ADR (provisionally ADR-198); ledger row rewrite (5 fields, content-anchored
evidence, exception block removed); Art. 30 PA-13(e) substrate correction; `compliance/` issue for
PA-13(f); destruction record template under `knowledge-base/legal/audits/`.

### Phase 5 — Verification

`bash scripts/test-all.sh` in full — the full-suite exit gate, not the touched-file loop, is what
catches a missed registration site. Plus `python3 scripts/lint-encryption-posture.py --repo-sweep`,
`terraform validate`, and `actionlint` on the workflow.

## Files to Create

| Path | Purpose |
|---|---|
| `apps/web-platform/infra/inngest-redis-luks.tf` | `random_password.inngest_redis_luks` + `doppler_secret.inngest_redis_luks_key`, co-located so the posture linter can resolve the citation |
| `tests/scripts/lib/inngest-volume-recut-gate.sh` | Sourced destroy-guard; the same bytes CI and the test both call |
| `tests/scripts/test-inngest-volume-recut-gate.sh` | Mutation matrix + harness rows for Guard 1 |
| `tests/scripts/lib/inngest-host-dark-gate.sh` | Guard 2 decision function (positive allowlist on `dark`) |
| `tests/scripts/test-inngest-host-dark-gate.sh` | Mutation matrix + harness rows for Guard 2 |
| `apps/web-platform/infra/inngest-redis-luks.test.sh` | LUKS apparatus guard: no `format` on the volume, key on `soleur-inngest` not `soleur`, blkid discriminator present, three-arm coverage |
| `knowledge-base/engineering/architecture/decisions/ADR-198-*.md` | New decision (ordinal provisional — re-derive before merge) |
| `knowledge-base/legal/audits/inngest-aof-destruction-record.md` | Art. 5(2) destruction record template |

## Files to Edit

| Path | Change |
|---|---|
| `apps/web-platform/infra/inngest-host.tf` | Remove `format = "ext4"` from `hcloud_volume.inngest_redis` |
| `apps/web-platform/infra/cloud-init-inngest.yml` | Three-arm LUKS stage replacing the plaintext mount; `ExecStartPre` findmnt re-assertion |
| `apps/web-platform/infra/inngest-bootstrap.sh` | Extend `SOLEUR_INNGEST_SERVER_PROBE` with `flush_latched`, `latch_flushed_at`, `latch_dbsize`, `redis_keys`; emit from the terminal no-op arms |
| `apps/web-platform/infra/vector.toml` | Add `SOLEUR_INNGEST_LUKS_STAGE` to Source 4 `include_matches.SYSLOG_IDENTIFIER` |
| `apps/web-platform/test/infra/vector-pii-scrub.test.sh` | Drift fixture for the new tag — same commit as the allowlist |
| `.github/workflows/apply-web-platform-infra.yml` | `inngest-volume-recut` in `options:` + the gated job |
| `plugins/soleur/test/terraform-target-parity.test.ts` | Register the new apply_target |
| `plugins/soleur/test/stock-preflight-coverage.test.ts` | `EXCLUSION_ALLOWLIST` entry |
| `scripts/test-all.sh` | `run_suite` lines for both new gate suites |
| `.github/workflows/infra-validation.yml` | Register `inngest-redis-luks.test.sh` — an unregistered infra suite silently never gates (#7695) |
| `scripts/encryption-posture-ledger.json` | Rewrite the `hcloud_volume.inngest_redis` row: 5 fields, content-anchored evidence, exception block removed |
| `knowledge-base/engineering/architecture/decisions/ADR-142-*.md` | Addendum recording measured fact |
| `knowledge-base/legal/article-30-register.md` | PA-13 limb (e) substrate correction |

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/test-all.sh` exits 0 — the **full** suite, not the touched-file loop, because an
   unregistered apply_target is only visible there.
2. `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 with the
   `hcloud_volume.inngest_redis` row resolving as `mechanism: luks`.
3. `grep -c 'inngest-host.tf:[0-9]' scripts/encryption-posture-ledger.json` returns `0` — no bare
   line-number citation survives (`cq-cite-content-anchor-not-line-number`).
4. `terraform validate` passes in `apps/web-platform/infra/`.
5. `actionlint .github/workflows/apply-web-platform-infra.yml` reports no new findings, and the
   job's `run:` body parses under `bash -n` when extracted.
6. `inngest-volume-recut` appears in **all five** registration sites, and
   `inngest-redis-luks.test.sh` is named in `.github/workflows/infra-validation.yml`. Verified by
   one command per site, each asserting a content anchor rather than a bare token
   (`cq-assert-anchor-not-bare-token`).
6b. The enum option and its guarded job are **bound**: a check fails if `inngest-volume-recut`
   appears in `options:` with no corresponding job, and vice versa.
6c. `RECUT-INNGEST-VOLUME` is distinct from every existing confirm literal —
   `grep -c 'RECUT-INNGEST-VOLUME' .github/workflows/apply-web-platform-infra.yml` returns ≥ 1 and
   no other target accepts it.
6d. The recut job declares a `concurrency` mutex and adds exactly **one** dispatch input
   (`expected_inngest_volume_id`), keeping the workflow at 8 of its 10-input cap.
7. Guard 1: every mutation row 1-9 and harness rows H1-H3 drive the suite RED (or PASS for H3),
   demonstrated by an **independent** re-mutation, not a self-graded battery.
8. Guard 2: every mutation row 1-10 and harness rows H1-H3 likewise.
9. Guard 2's decision function returns `dark` for **no** input other than the full six-condition
   satisfaction; `silent` and `unreadable` are distinct tokens and both abort.
10. `grep -c 'DBSIZE' tests/scripts/lib/inngest-host-dark-gate.sh` returns `0` — the gate reads
    `INFO keyspace`, never `DBSIZE`.
11. The cloud-init LUKS stage contains no `|| true` on any of `luksFormat`, `luksOpen`, `mkfs`,
    `mount`, and contains a `blkid` arm for each of the four TYPE cases including the fatal default.
12. `SOLEUR_INNGEST_LUKS_STAGE` appears in **both** `vector.toml` Source 4 and
    `vector-pii-scrub.test.sh`, asserted in the same commit.
13. The `inngest-cutover` environment reviewer set is asserted **non-empty** by a check that fails
    when it is emptied — not by a comment claiming it is non-empty.
14. ADR-142 carries the addendum; ADR-198 (or its re-derived ordinal) exists and every plan/tasks
    reference names the same ordinal. `grep -rn 'ADR-198' knowledge-base/project/{plans,specs}/`
    and the ADR filename agree.
15. Article 30 PA-13 limb (e) no longer says "SQLite"; a `compliance/` issue exists for limb (f).
16. PR body uses `Tracks #7695`, `Tracks #7674`, `Tracks #6894` — **never `Closes`**. The
    remediation executes post-merge at a dispatch, so `Closes` would auto-close a still-open state.

### Post-merge (gated dispatch — a separate operator decision at the window)

17. `apply_target=inngest-host-replace` dispatched; the new host boots and the probe emits
    `flush_latched`, `latch_flushed_at`, `latch_dbsize`, `redis_keys` on the hourly cadence.
    Verified by the discoverability command, not by a dashboard.
18. At least one probe row carrying the **verbatim latch record** has landed in Better Stack before
    any destructive dispatch. That row is the sole surviving audit record of what the recut
    destroys, and Guard 2's input. Absence of rows ⇒ REFUSE.
19. **Decision point.** If `redis_keys == 0`, the flag is outside `{armed, flipping, flushed,
    done}`, and the host is dark on that same row, the recut is authorized. If `redis_keys > 0`,
    the destructive path is refused outright and the work routes to ADR-142's byte-copy under #6894.
19b. Dispatch B's saved plan shows `hcloud_server.inngest` with **zero actions** — the recut
    replaces the volume and its attachment only. Dispatch C (`inngest-host-replace`) performs the
    host replace under its own guard.
20. Post-recut: `SOLEUR_INNGEST_LUKS_STAGE` shows rc=0 through `stage=fstab`; a subsequent probe
    row shows `redis_active=active` and `/mnt/data` as a genuine mountpoint on
    `/dev/mapper/inngest-redis`.
21. `scripts/followthroughs/inngest-host-not-serving-7674.sh` reads PASS before #7674 closes.
22. The Art. 5(2) destruction record is completed with what was observed on the volume.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **The store is not actually empty and the recut destroys recoverable armed reminders.** The historical question is unanswerable at ~20d retention. | Do not answer it. Guard 2 requires `redis_keys == 0` measured **now**, on the current `boot_id`. Non-empty ⇒ refused outright and routed to ADR-142. |
| **Removing `format = "ext4"` queues an unscheduled replace.** | Phase 0.2 measures it with `terraform plan` before anything else. The volume is outside every merge-apply `-target=` list, and Guard 1's ID-PIN binds any destroy to an operator-named physical id. |
| **The destroy guard is scoped one address too wide and reaches `hcloud_volume.workspaces["web-1"]`.** | Named-live backstop counters make that address independently load-bearing, plus the `out_of_scope` catch-all for anything nobody enumerated. Mutation rows 1 and 2 pin both. |
| **State corruption maps the correct address to the wrong physical volume.** | ID-PIN against `.change.before.id`; address-based counters all read 0 in exactly this scenario, which is why the pin exists. |
| **LUKS mount fails open; Redis writes plaintext AOF to the root disk.** | No `|| true` on the mount path; `ExecStartPre` findmnt re-assertion refuses to serve off an unmounted path; the FSM's own mountpoint gate independently emits `latch-unrecordable` and drives terminal `aborted`. |
| **The new tag never leaves the host** because Source 4 matches by exact value and a typo matches nothing. | Allowlist entry and drift fixture land in the same commit, asserted on both sides. |
| **The latch's re-arm path breaks**, so every future flip aborts `latch-unrecordable`. | AC20 asserts `/mnt/data` is a genuine mountpoint on the mapper post-recut — the property `record_flush_latch` depends on. |
| **A `-replace` strands the volume out of state** between destroy and create (no `create_before_destroy`). | Guard 1 accepts the recovery bare-create shape (`["create"]`, `before == null`), so a re-dispatch converges instead of looping. Harness row H3 pins it. |
| **Passphrase `-replace` mints a new key without rekeying the header**, stranding the store. | No `ignore_changes`; Guard 1 mutation row 4 reddens on any update/delete/forget. Rotation is `cryptsetup luksChangeKey`, documented in the ADR. |
| **The new host boots with its private NIC down** after replace. | Known class; converge is verified via Better Stack rows, never hand-verification. `hcloud_firewall_attachment` is deliberately not `-target`ed. |
| **This plan's own measurements rot.** | Phase 0.1 re-runs every reading. Guard 2 encodes the premise as a dispatch-time check, so the plan cannot be correct on 2026-09-02 and silently wrong later. |

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| **Execute ADR-142's full byte-copy migration inside #7695** | It clears the latch for free (the copy set is `redis/` only, so `inngest-cutover/` does not come across) and closes #6894 — genuinely attractive. Rejected as a **scope collision**: it folds quiesce/freeze/canary/mount-swap/backstop into a latch-clearing PR, and its three FATAL footguns buy nothing when the store is empty. It remains the mandatory path when `redis_keys > 0`, so it is not discarded — it is the other branch of the gate. |
| **A new FSM verb: append-only authorized latch clear** (write `flip-done.cleared`, predicate becomes "newest latch not superseded by a newer clear") | Genuinely cheaper and touches no volume. Rejected for this PR because it does **not** close the `plaintext-exception` expiring 2026-10-22, and because it adds a terminal state to a safety FSM whose `L` polarity already inverts between `op=arm` and `op=resume` — a change needing its own ADR and its own six-site sweep. Recorded as the fallback if Phase 0.2 shows the `format` removal is unsafe. |
| **Refine `flush_already_performed()`'s refusal instead of erasing its evidence** — refuse re-arm unless the store is provably empty and the host provably dark | The most elegant option: preserves #5450 exactly (a live prod queue has keys and serves 200), touches no volume, needs no destructive target. Rejected only because it needs the same Phase 1 read channel and interacts with `L`'s polarity inversion. **Worth re-grading at plan-review** — if it survives, it may dominate. |
| **R2 header escrow, mirroring `workspaces-luks-header.tf`** | Rejected by ADR-142 by name, on confidentiality grounds. See §Escrow. |
| **Webhook readback of the latch** | ADR-100 Decision 6a stands unamended; declined 2026-08-25. Phase 1 meets the intent over the already-adopted transport instead. |
| **Recut to plaintext ext4, defer LUKS** | Recreates a `plaintext-exception` the ledger wants closed, while paying the entire cost of a destructive recut. Strictly dominated. |

## Test Scenarios

Beyond the two mutation matrices (which are the primary deliverable — for a change whose deliverable
*is* guards, scenarios of the shape "command X → terminal Y" test the thing being guarded, not the
guard):

1. Guard 1 against a synthesized canonical recut plan → PASS.
2. Guard 1 against the recovery bare-create plan, no `expected_id` → PASS (non-canonical must-PASS).
3. Guard 1 against each of mutation rows 1-9 → ABORT, asserting the **reason token**, not just rc.
4. Guard 2 against a synthesized dark+empty row set → `dark`.
5. Guard 2 against a busy fleet (many `function.finished` from `soleur-web-platform`, none from
   `soleur-inngest`) with a dark inngest row → `dark` (non-canonical must-PASS).
6. Guard 2 against zero rows → `silent`, never `dark`.
7. Guard 2 against an unparseable count → `unreadable`, never `dark`.
8. Cloud-init three-arm dispatch: `ext4` → mounts, does not format; empty → formats; `crypto_LUKS`
   → opens only; `xfs` → FATAL halt.
9. `lint-encryption-posture.py --repo-sweep` fails when the `random_password`/`doppler_secret` pair
   is split across files — pinning that the linter's co-location requirement is actually satisfied
   rather than incidentally passing.

## Decision Challenges

Headless run — these are recorded here and in
`knowledge-base/project/specs/<branch>/decision-challenges.md` for `/ship` to render into the PR
body and file as an `action-required` issue. They are **not** applied silently.

1. **The brief's scope item 2 is narrowed.** The brief directs recutting as LUKS mirroring
   `workspaces-luks-recut` *including its R2 header escrow*. The escrow is **cut** — ADR-142
   rejects it for this store by name, and copying it would reverse an accepted ADR while adding a
   CWE-522-class artifact. The LUKS recut itself is retained.

2. **The destructive recut is now gated on a measurement that does not yet exist.** The brief
   treats "the host is dark, so the recut is cheap" as established. It is established for
   2026-08-20→now, but the flip that wrote the latch was in July on a previous host generation, so
   the evidence window begins after the window of concern. The plan therefore builds the read
   channel first and makes `redis_keys == 0` a hard precondition. **If the store turns out
   non-empty, this plan does not authorize the recut** — the work routes to ADR-142's byte-copy
   under #6894. That is a real possibility the brief does not contemplate.

3. **A cheaper option may dominate and should be graded at plan-review.** Refining
   `flush_already_performed()`'s refusal (empty-store + dark-host predicate) clears the blocker
   without any destructive target, without touching the volume, and without a new apply_target.
   It does not close the encryption exception, so it is not a full substitute — but if #6894 is
   going to run ADR-142's migration anyway, this plan may be building a destructive capability
   that the migration would make unnecessary.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled above with a
  concrete artifact and a concrete exposure vector.
- The ADR-198 ordinal is provisional and **will** move if a sibling PR claims it. Re-derive against
  freshly-fetched refs before merge and sweep this plan, `tasks.md`, and AC14 in the same edit.
- Guard fixtures must be **synthesized** plan JSON. A captured production plan would embed real
  volume ids and drift silently (`cq-test-fixtures-synthesized-only`).
