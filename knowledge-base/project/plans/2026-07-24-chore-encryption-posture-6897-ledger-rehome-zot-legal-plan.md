---
title: "encryption-posture #6897 — re-home residual bounded exceptions + legal-doc reconciliation"
date: 2026-07-24
type: chore
issue: 6897
parents: [6893, 6588]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
live_infra_mutation: none
---

# encryption-posture #6897 — re-home residual bounded exceptions + legal-doc reconciliation

## Overview

Issue #6897 is the P3 consolidation issue for the lower-severity findings of the 2026-07-23
encryption-posture audit (`knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`).
Its three checkboxes are:

1. **Superseded plaintext volumes still declared** — `hcloud_volume.workspaces`
   (`apps/web-platform/infra/server.tf:1569`) and `hcloud_volume.git_data`
   (`apps/web-platform/infra/git-data.tf:196`), both `format = "ext4"`. web-1 `/mnt/data` now
   runs on the LUKS `workspaces_luks` mapper (cutover certified 2026-07-23, verify run
   30040444418). **Ledger their live attachment state** as bounded plaintext exceptions — do
   NOT remove the resource declarations, do NOT touch live infra.
2. **zot registry link is plain HTTP by design** (`10.0.1.30:5000`, private net; integrity via
   cosign digest-pinning) — a real `cert_verification: off` connection exception; keep its ledger
   exception current.
3. **Legal-doc reconciliation** — run `/soleur:legal-audit` against the audit's measured postures
   so `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md` encryption claims
   are *substantiated*, not asserted.

**Operator safety framing (load-bearing):** this PR must NOT destroy or `terraform apply`-remove
any live volume. `git_data` is explicitly a rollback backstop pending the DL-2 wipe and MUST
stay. `workspaces` removal is a separate future cutover-teardown, out of scope. Deliverable = a
reviewed, merged PR that `Closes #6897`, with **zero live-infra mutation** — it ledgers reality
and reconciles legal copy only.

**Central finding (see Research Reconciliation):** the ledger rows the issue asks for **already
exist and are accurate** — they were authored by PR #6885 (the encryption-posture design-time
default, merged `51d2646bc`) and every one references `#6897` as its `tracking_issue`. The real
gap is therefore **not "create the rows"** but **"the rows are bounded by the very issue this PR
closes."** Closing #6897 while eight ledger references point at it would leave those exceptions
**unbounded** (pointing at a closed issue) — defeating the bounded-exception contract the ledger
exists to enforce. The task's own instruction — *"mirror the existing plaintext-exception rows
for `hcloud_volume.inngest_redis` (#6894) / `hcloud_volume.registry` (#6895)"* — names the fix:
those two rows point at **dedicated, still-open** per-item tracking issues. workspaces/git_data (and
session_store, and zot, and the git_data_luks Layer-B posture note) point at the consolidation
issue instead. The mirror-faithful resolution is to **re-home every residual `#6897` reference to
a dedicated open follow-up issue**, then close #6897 honestly.

This makes the PR a **ledger + legal-copy + issue-hygiene** change: no code, no `.tf` edits, no
migrations, no infra mutation.

## Research Reconciliation — Spec (issue body) vs. Codebase

| Issue-body / task claim | Codebase reality (verified this session) | Plan response |
|---|---|---|
| "Confirm these are detached and remove them, **or** ledger their live attachment." | Both volumes are **already ledgered** as `plaintext-exception` rows: `hcloud_volume.workspaces` (ledger lines 60-82), `hcloud_volume.git_data` (lines 83-105). Both `format = "ext4"` confirmed at `server.tf:1569` / `git-data.tf:196` (evidence lines **accurate**). Removal is explicitly out of scope (operator). | Do NOT create rows. **Verify currency** (done: evidence lines, mechanism, defends/does_not_defend, disclosed_as, expires_on `2026-10-22` all current). Close the **bounding** gap below. |
| workspaces/git_data exceptions should be "bounded by a tracking-issue reference — mirror #6894/#6895." | #6894 (inngest_redis) and #6895 (registry) point at **dedicated, open** per-item issues. workspaces/git_data point at **`#6897`** — the issue this PR closes. | **Re-home**: create dedicated open follow-up issues and re-point. This IS the gap to close. |
| zot connection exception "keep current." | Present and accurate: connection row (ledger lines 280-295), `tls: none`, `cert_verification: off`, cosign-digest-pinning justification. `tracking_issue: #6897`. | Verify currency (done). **Re-home** its `tracking_issue` off `#6897`. |
| Issue names only 3 checkboxes. | **#6897 also transitively tracks two things the checkboxes omit**: `redis.session_store` at-rest exception (ledger lines 250-266, `tracking_issue #6897`) and the `git_data_luks` Layer-B `live_verification` note (line 57, "tracked #6897"). Audit doc line 46/74 confirms session_store is a #6897 finding. | **Sweep ALL 8 `#6897` references** (ledger lines 57, 74, 77, 97, 100, 259, 262, 290), not just the 3 checkbox items — else #6897 cannot close cleanly. |
| privacy-policy:519 LUKS claim "must be substantiated." | Audit R5 (doc lines 61-69) already declares `privacy-policy.md:519` **substantiated** post-cutover (workspaces_luks + git_data_luks are LUKS; `disclosed_as` anchor present). Legal docs carry unconditional LUKS-at-rest claims (privacy-policy:515,519; DPD:44,98,410; gdpr-policy). | Run `/soleur:legal-audit` to **confirm** substantiation against the ledger's measured postures; fold small corrections, file follow-up if large. Highest-value check: the plaintext backstop caveat (below). |
| Layer A lint state | `python3 scripts/lint-encryption-posture.py --repo-sweep` → **PASS** (14 stores, 3 connections, 0 unledgered, 0 failing). Lint validates `tracking_issue` shape (`^#\d+$`) only — **not** open/closed state. | Re-pointing to new issue numbers keeps lint green; re-run after every edit. |

## User-Brand Impact

**If this lands broken, the user experiences:** a legal document (`privacy-policy.md`) that
asserts LUKS encryption-at-rest for their workspace/git data while the ledger's measured posture
would show an un-reconciled or over-claimed exception — i.e. the exact claim-vs-reality mismatch
that made the parent issue **#6588** a P1 ("privacy policy claims LUKS encryption-at-rest while
user source code is unencrypted").

**If this leaks, the user's data is exposed via:** a superseded plaintext volume
(`hcloud_volume.workspaces` / `hcloud_volume.git_data`) whose bounded exception has been silently
**unbounded** (re-pointed to a closed #6897, or dropped), so the tracked remediation — detach +
destroy / DL-2 wipe — never gets driven and pre-cutover plaintext workspace/git data persists on
a seizable disk indefinitely.

**Brand-survival threshold:** single-user incident.

> This PR does **not** change encryption reality (zero live-infra mutation); it reconciles claims
> and issue-tracking to already-measured reality, which **reduces** the #6588-class risk. The
> threshold reflects the *subject* (public encryption claims about user data at rest) and gates
> the review with `user-impact-reviewer` + CPO sign-off, catching an accidental over-claim
> introduced by a bad legal-copy or ledger edit.

**CPO sign-off:** required at plan time (`requires_cpo_signoff: true`). Headless one-shot — CPO is
invoked in the Domain Review gate below; `user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 0 — Preconditions (read-only; re-confirm at /work start)
- Re-run the Layer A baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → expect
  `PASS`. This is the invariant every later phase must preserve.
- Re-grep every `#6897` reference in the ledger to confirm the count/locations have not drifted:
  `grep -n '#6897' scripts/encryption-posture-ledger.json` (expect 8: lines ~57, 74, 77, 97, 100,
  259, 262, 290 — assert by content anchor, not line number).
- Confirm `server.tf:1569` and `git-data.tf:196` still declare the two `format = "ext4"` volumes
  and their `hcloud_volume_attachment` blocks (`server.tf:1581`, `git-data.tf:207`) — READ only,
  no `terraform`/`hcloud` mutation. (Read-only `terraform state show` / hcloud API read is
  permitted only if a live-attachment question genuinely cannot be answered from the `.tf`; it was
  not needed this session — the attachments are declared unconditionally.)

### Phase 1 — Create dedicated follow-up tracking issues (mirror #6894/#6895)
Create one dedicated, **open** GitHub issue per residual bounded exception so each is driven to
remediation independently. All `Ref #6893` (parent claim-unlock gate) + `Ref #6588` where the
user-data axis applies; labels `type/security`, `domain/engineering`, `priority/p3-low` (verify
labels exist via `gh label list` before use — they do). Capture each new number.

| New issue (title stem) | Re-homes ledger ref(s) | reevaluate_when it inherits |
|---|---|---|
| `encryption-posture: hcloud_volume.workspaces plaintext teardown (post-cutover detach + destroy)` | lines 74, 77 | "the workspaces_luks cutover is confirmed irreversible and the plaintext volume can be detached and destroyed" |
| `encryption-posture: hcloud_volume.git_data plaintext DL-2 wipe + git-data host posture probe` | lines 97, 100, **and 57** (git_data_luks Layer-B note — same host/volume family) | "the git_data_luks cutover is confirmed and the DL-2 wipe of the plaintext volume runs" |
| `encryption-posture: redis.session_store at-rest posture measurement` | lines 259, 262 | "the session-store host at-rest posture is measured (or LUKS applied)" |
| `encryption-posture: zot registry link TLS / private-net re-evaluation` | line 290 | "the registry is exposed beyond the private network, or TLS is added to the link" |

Body of each: 1-line statement, the ledger row it bounds, the measured posture, the
reevaluate_when, `Ref #6893` / `Ref #6588`, and a note that it was split out of #6897. Do NOT
`Closes` any parent.

> **Decision (Architecture — bounded-exception homing).** Default = **4 dedicated issues** (above),
> the faithful mirror of #6894/#6895 (per-item, per-trigger). *Alternatives* the plan-review /
> deepen-plan panel should weigh: (B) **consolidate** workspaces+git_data into one "plaintext
> backstop teardown" issue (2 triggers, 1 issue) → 3 issues total, less faithful to the per-volume
> #6894/#6895 pattern but lighter for a non-technical operator; (C) **re-point at open parents**
> (#6893 for the at-rest exceptions, a single new issue for zot which #6893's "plaintext at-rest"
> scope does not cover) → fewest new issues but loses the per-item re-evaluate granularity and does
> NOT mirror the dedicated-issue pattern the task names. Recommend (A); (B) acceptable if the panel
> judges 4 p3 issues excessive. Whichever wins, **every residual reference lands on an OPEN issue.**

### Phase 2 — Re-home the ledger references
Edit `scripts/encryption-posture-ledger.json` ONLY — re-point each of the 8 `#6897` references to
the corresponding new issue number from Phase 1, in both the `live_verification` `tracked #N`
suffix AND the `exception.tracking_issue` / `exception.reevaluate_when` fields. Leave `expires_on:
2026-10-22` unchanged (the exception clock started at the 2026-07-23 audit; re-homing the issue
does not reset expiry). Do NOT alter evidence lines, mechanisms, defends/does_not_defend, or
disclosed_as (all verified current). Re-run Layer A lint → expect `PASS` (0 unledgered, 0 failing).

### Phase 3 — Legal-doc reconciliation (checkbox 3)
- Run `/soleur:legal-audit` (skill — runs inline per `wg-plan-prescribed-skills-must-run-inline`)
  scoped to `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`, reconciling
  every encryption claim against the ledger's measured postures:
  - `privacy-policy.md:515` — "User API keys encrypted using AES-256-GCM" → substantiated by the
    BYOK app-layer encryption (and the `encrypted API keys (AES-256-GCM)` DPD:98,410 mirror).
  - `privacy-policy.md:519`, `DPD:44` — "workspace git data sits on a **LUKS-encrypted volume**" →
    audit R5 declares substantiated post-cutover (workspaces_luks + git_data_luks are LUKS).
  - **Highest-value reconciliation check:** the two **plaintext backstop volumes still exist and
    are attached** (rollback backstops). The public claim is about where live data "sits" (the LUKS
    mapper) — true — but a plaintext copy may persist on the backstop until teardown/DL-2 wipe. The
    audit judges the live-mount claim substantiated and the backstops transient+tracked; the
    legal-audit must **confirm** the public wording does not over-claim absolute at-rest encryption
    in a way the backstops falsify. Likely outcome: substantiated, no public-copy change (the
    backstop is an internal, now-bounded exception). If the auditor flags a material over-claim →
    that is a legal-copy correction.
- **Disposition:** if corrections are small (wording/anchor/date), fold them into THIS PR. If
  large (a substantive re-drafting of a disclosure section), file a tracked follow-up issue
  (`Ref #6893`, `type/security` + legal) and note it in the PR body — do NOT balloon this P3 PR.
- `/soleur:legal-audit` output is advisory + draft-requiring-professional-review; record its
  verdict in the PR body regardless of fold/defer.

### Phase 4 — Verify + ship
- Layer A lint `PASS`; `grep -c '#6897' scripts/encryption-posture-ledger.json` → **0** (all
  re-homed); every new issue number resolves (`gh issue view <N>` open).
- Broken-citation sweep on the plan itself: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan>
  | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'`.
- PR body: `Closes #6897`, `Ref #6588`, `Ref #6893`, list the 4 new issue numbers + the legal-audit
  verdict. **No operator/post-merge checklist** — nothing here is deferred to the operator
  (`hr-ship-message-no-operator-checklist`); issue creation + ledger edits + legal reconcile all
  happen in-PR via `gh` + skill, and there is no `terraform apply`.

## Acceptance Criteria

All criteria are pre-merge (this PR has **no** post-merge operator step — no `terraform apply`, no
migration, no live mutation; `Closes #6897` at merge is correct because the merge IS the
remediation).

- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` prints `... 0 unledgered, 0 failing checks -> PASS` (unchanged from baseline).
- [ ] `grep -c '#6897' scripts/encryption-posture-ledger.json` returns **0** — every residual reference re-homed.
- [ ] The 8 former `#6897` references now cite dedicated **open** issues (Phase 1 table); each `gh issue view <N> --json state` returns `OPEN`.
- [ ] `hcloud_volume.workspaces` (ledger) still: `mechanism: plaintext-exception`, `evidence` = `server.tf:1569 (format = "ext4"...)`, has `defends_against` + `does_not_defend` + `disclosed_as` + `exception{justification,tracking_issue,reevaluate_when,expires_on}` — only `tracking_issue`/`reevaluate_when` issue-number changed.
- [ ] `hcloud_volume.git_data` (ledger) same shape; only tracking-issue re-homed; **resource declarations in `server.tf` / `git-data.tf` are UNCHANGED** (`git diff --stat` shows no `.tf` files).
- [ ] zot connection row: `cert_verification: off`, cosign-digest-pinning `does_not_defend`, `exception.tracking_issue` re-homed off `#6897`.
- [ ] `git diff --name-only origin/main` touches ONLY `scripts/encryption-posture-ledger.json`, `docs/legal/*.md` (iff Phase 3 folds a small correction), `knowledge-base/project/{plans,specs}/...` — and **no** `apps/web-platform/infra/*.tf`, no migration, no server/src code.
- [ ] `/soleur:legal-audit` was run against the three legal docs; its encryption-claim verdict (substantiated / corrected-inline / follow-up-filed) is recorded in the PR body.
- [ ] PR body: `Closes #6897`; `Ref #6588`; `Ref #6893`; the 4 new issue numbers listed; no operator/post-merge checklist.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Product = **NONE** (no UI surface — no path
in Files-to-Edit matches `components/**`, `app/**/page.tsx`, or the UI-surface term list; the
mechanical UI-surface override does not fire).

### Engineering (CTO)
**Status:** to-run (deepen-plan / plan-review panel).
**Assessment (pre-review):** ledger + issue-hygiene change; the load-bearing invariant is Layer A
green + zero `.tf`/infra mutation. Risk surface is a mis-edited JSON reference or an accidental
`.tf` touch — both caught by the AC greps.

### Legal (CLO)
**Status:** to-run (Phase 3 `/soleur:legal-audit` = `legal-compliance-auditor`).
**Assessment (pre-review):** the encryption-at-rest LUKS claims are the #6588-class surface; the
audit R5 already substantiates the primary claim, so expect confirmation + at most a
plaintext-backstop wording check. `legal-compliance-auditor` is the domain-appropriate reviewer and
is invoked inline in Phase 3.

### Product/UX Gate
Not applicable — Product NONE. No `.pen` wireframe required (`wg-ui-feature-requires-pen-wireframe`
does not fire: no UI surface).

## Encryption Posture

**Gate status: satisfied — no new store or connection introduced.** Detection patterns
(`\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`) do
**not** match this PR's Files-to-Edit (`scripts/encryption-posture-ledger.json`, `docs/legal/*.md`,
`knowledge-base/**`). The PR ledgers the **current** posture of stores that already exist and only
re-homes their bounded-exception tracking issue; it adds no persistent store and no cross-component
connection. The ledger itself is the authoritative `## Encryption Posture` artifact and remains
Layer-A-green (`plaintext-exception` rows retain `exception{justification, tracking_issue,
reevaluate_when, expires_on}`, now bounded by open issues).

## Observability

**Skip — pure data + docs change.** No Files-to-Edit under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, or `plugins/*/scripts/`; no new infrastructure surface. The only executable
artifact in scope, `scripts/lint-encryption-posture.py`, is **run** (as the AC gate) but **not
edited**. Layer A lint failure is itself the CI-visible signal for a bad ledger edit.

## Infrastructure (IaC)

**Skip — no infrastructure introduced or mutated.** The IaC-routing detection set (SSH,
`terraform apply`, systemd units, Doppler secret writes, vendor-dashboard steps, new vendor
account) matches nothing here. The two `.tf`-declared volumes are **read** for currency only; their
declarations and attachments are explicitly left UNCHANGED (operator: zero live-infra mutation). No
`terraform apply`, no `-target`, no destroy.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Architecture Decision (ADR/C4)

**Skip — no new architectural decision.** The encryption-posture ledger + Layer-A gate architecture
is already recorded (ADR-140 / the 2026-07-23 audit). This PR operates *within* that architecture
(re-homing bounded-exception tracking, reconciling disclosures) and reverses/extends no ADR
Decision. The bounded-exception homing choice (Phase 1 Decision box) is a plan-local operational
decision, not an architecture-corpus change; no `.c4` actor/system/relationship changes (no new
external actor, vendor, data store, or access relationship — the stores and the zot link are
already modeled: `model.c4:218` session store, `model.c4:268` zot).

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` bodies contain no reference to
`scripts/encryption-posture-ledger.json` or `docs/legal/` (verified this session).

## Sharp Edges

- **The ledger rows already exist — do NOT re-author them.** The gap is the tracking-issue
  *bounding*, not row creation. Editing evidence lines, mechanisms, or `disclosed_as` (all verified
  current) is out of scope and risks regressing Layer A.
- **Sweep ALL 8 `#6897` references, not the 3 checkbox items.** `redis.session_store` (lines
  259/262) and the `git_data_luks` Layer-B note (line 57) are also `#6897`-tracked; missing them
  leaves #6897 un-closeable (orphaned bounded exceptions). `grep -c '#6897' == 0` is the gate.
- **Zero `.tf` mutation.** `git_data` is the pending-DL-2-wipe rollback backstop and `workspaces`
  teardown is out of scope. An AC asserts no `apps/web-platform/infra/*.tf` file appears in the
  diff. Do NOT `terraform apply`/`-replace`/destroy anything.
- **`expires_on` does not reset on re-homing.** Keep `2026-10-22` (the exception clock started at
  the 2026-07-23 audit). Re-pointing the issue number is not a fresh grant.
- **Layer A lint does not validate issue open/closed state** — it checks `tracking_issue` matches
  `^#\d+$`. Green lint after re-homing does NOT prove the new issues are open; the separate
  `gh issue view <N> --json state` AC does. Conversely, a bounded exception pointing at a *closed*
  issue passes lint but violates the bounded-exception contract — which is exactly the #6897 defect
  this PR fixes.
- **Legal-audit fold-vs-defer discipline.** If `/soleur:legal-audit` surfaces a substantive
  re-drafting need, file a tracked follow-up rather than expanding this P3 PR; a plaintext-backstop
  wording tweak is foldable, a disclosure-section rewrite is not.
- A plan whose `## User-Brand Impact` section is empty or placeholder-only fails `deepen-plan`
  Phase 4.6 — this one is filled (threshold `single-user incident`, CPO sign-off required).
