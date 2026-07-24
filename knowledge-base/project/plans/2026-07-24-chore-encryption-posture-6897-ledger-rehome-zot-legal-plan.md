---
title: "encryption-posture #6897 — re-home residual bounded exceptions + legal-doc reconciliation"
date: 2026-07-24
type: chore
issue: 6897
parents: [6893, 6588]
lane: cross-domain
brand_survival_threshold: single-user incident
plan_time_signoff: CLO   # Product=NONE; legal-claim risk axis. user-impact-reviewer runs at review.
live_infra_mutation: none
deepened: 2026-07-24
---

# encryption-posture #6897 — re-home residual bounded exceptions + legal-doc reconciliation

## Enhancement Summary

**Deepened on:** 2026-07-24
**Review panel:** architecture-strategist, spec-flow-analyzer, code-simplicity-reviewer (3-agent
panel, proportionate to a P3 ledger/docs change at `single-user incident` threshold).

### Key improvements folded from review
1. **Repo-wide sweep, not ledger-only (spec-flow HIGH / arch P2).** `#6897` is a live tracking
   pointer in the C4 model too (`model.c4:216,220` + `model.likec4.json` ×9), not just the ledger.
   Closing #6897 with a ledger-only sweep leaves the architecture diagram citing a closed issue for
   open work — undercutting the plan's own bounding-integrity thesis. Phase 2 now sweeps every
   **live** artifact and Phase 4's AC is repo-scoped.
2. **Historical carve-out named explicitly (arch P3 / spec-flow).** The dated audit doc and two
   planning artifacts (`…r2-provider-soc2…-plan.md`, `…encryption-at-rest-in-transit-design-default/tasks.md`)
   are immutable point-in-time records — left untouched, and the AC allowlists them so a reviewer
   does not "helpfully" desync the record.
3. **Line-57 homing corrected (arch P2 / spec-flow MEDIUM).** Ledger line 57 is the *encrypted*
   `git_data_luks` store's Layer-B posture note (no `exception`, no `reevaluate_when`) — a
   posture-*measurement* concern, not the plaintext DL-2 wipe. Re-homed to the posture issue.
4. **Legal defer→block for a material over-claim (spec-flow MEDIUM).** A published claim the
   measured posture *falsifies* must be corrected **before** `Closes #6897` (it is the #6588 P1
   shape). Only a large **non-falsifying** structural addition may defer.
5. **Issue count minimized to 3 (Option B; simplicity + arch).** Consolidated the same-class
   remediations; recorded the A-vs-B taste + the "must #6897 close" user-challenge to
   `decision-challenges.md`.
6. **Frontmatter contradiction fixed (simplicity).** `requires_cpo_signoff` dropped — Product=NONE;
   the plan-time sign-off is **CLO**, `user-impact-reviewer` runs at review.
7. **New-issue-body + durable-handoff ACs added (spec-flow LOW).**

### New consideration discovered (tracked, not fixed here)
- **Class gap:** Layer A lint validates `tracking_issue` shape (`^#\d+$`) only — never open/closed
  state (`scripts/lint-encryption-posture.py:530-534`). The new trackers are equally closable, so
  the orphaning could recur invisibly. Tracked as a note on the open parent **#6893** (Phase 1),
  per `wg-when-a-workflow-gap-causes-a-mistake-fix`.

---

## Overview

Issue #6897 is the P3 consolidation issue for the lower-severity findings of the 2026-07-23
encryption-posture audit (`knowledge-base/engineering/architecture/encryption-posture-audit-2026-07-23.md`).
Its three checkboxes: (1) ledger the two superseded plaintext volumes `hcloud_volume.workspaces`
(`apps/web-platform/infra/server.tf:1569`) + `hcloud_volume.git_data` (`git-data.tf:196`), both
`format = "ext4"` (web-1 `/mnt/data` now runs on the LUKS `workspaces_luks` mapper, cutover
certified 2026-07-23, verify run 30040444418); (2) keep the zot registry `cert_verification: off`
HTTP-by-design connection exception current (`10.0.1.30:5000`, private net, cosign digest-pinning);
(3) run `/soleur:legal-audit` so `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
encryption claims are *substantiated*, not asserted.

**Operator safety framing (load-bearing):** zero live-infra mutation. `git_data` is the rollback
backstop pending the DL-2 wipe and MUST stay; `workspaces` removal is a separate future
cutover-teardown, out of scope. Deliverable = a reviewed, merged PR that `Closes #6897` — it
ledgers reality and reconciles legal copy only.

**Central finding.** The ledger rows the issue asks for **already exist and are accurate** (authored
by PR #6885, merged `51d2646bc`), and every one references `#6897` as its `tracking_issue`. So the
real gap is not "create rows" but "the exceptions are bounded by the very issue this PR closes."
Closing #6897 while live artifacts still point at it leaves those exceptions **unbounded** (pointing
at a closed issue) — defeating the bounded-exception contract. The task's own instruction — *"mirror
the existing plaintext-exception rows for `inngest_redis` (#6894) / `registry` (#6895)"* — names the
fix: those point at **dedicated open** trackers. The residual `#6897` references (in the ledger AND
the C4 model) must be **re-homed to open follow-up issues** (ledger) or **genericized to the ledger
as SoT** (C4), then #6897 closes honestly.

**Why #6897 closes (sourced, per review):** the task directs it (*"Closes #6897"*). The bounded
exceptions survive the close via the open follow-ups (ledger) + the ledger-as-SoT pointer (C4).

This is a **ledger + C4-prose + legal-copy + issue-hygiene** change: no code, no `.tf` edits, no
migrations, no infra mutation.

### The complete `#6897` footprint (verified `git grep -l '#6897'`)

| Artifact | Refs | Class | Disposition |
|---|---|---|---|
| `scripts/encryption-posture-ledger.json` | 8 (lines 57,74,77,97,100,259,262,290) | **live SoT** | Re-home each to the new follow-up issue number. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | 2 (216 git-data, 220 session-store) | **live diagram source** | Genericize: drop the hardcoded `#6897`, point at the ledger exception row (the SoT for the current tracker). Robust against recurrence. |
| `…/diagrams/model.likec4.json` | 9 embeds (compiled) | **live compiled** | Mirror the `model.c4` prose edit (regenerate via the repo's likec4 export if one exists; else apply the identical string edit) + run the c4 validation tests. |
| `…/encryption-posture-audit-2026-07-23.md` | 6 | **immutable historical** | Leave untouched — a dated record of what was consolidated under #6897 at audit time (true even after close). Allowlisted in the AC. |
| `…/plans/2026-07-24-chore-r2-provider-soc2-…-plan.md` | 1 | **historical planning** | Leave untouched (sibling-plan provenance citation). Allowlisted. |
| `…/specs/feat-one-shot-encryption-at-rest-in-transit-design-default/tasks.md` | 1 | **historical planning** | Leave untouched (PR #6885's own spec). Allowlisted. |

## Research Reconciliation — Spec (issue body) vs. Codebase

| Issue-body / task claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "Confirm detached and remove them, **or** ledger their live attachment." | Both already ledgered as `plaintext-exception` rows (ledger 60-82 / 83-105); evidence lines `server.tf:1569` / `git-data.tf:196` **accurate**; removal out of scope. | Do NOT create rows / do NOT remove. Resolve **by re-homing** (checkbox 1 is satisfied by the ledger path + the open teardown tracker — stated explicitly per spec-flow MEDIUM). |
| "mirror #6894/#6895." | #6894/#6895 point at **dedicated open** per-item issues; workspaces/git_data point at **#6897**. | Re-home to dedicated open issues (Option B grouping — Phase 1). |
| zot "keep current." | Present + accurate (ledger 280-295). `tracking_issue: #6897`. | Re-home off #6897. |
| Issue names only 3 checkboxes. | #6897 also tracks `redis.session_store` (250-266) + the `git_data_luks` Layer-B note (57) + **the C4 model** (216/220). | Sweep ALL live refs (not just the ledger, not just the 3 checkboxes). |
| privacy-policy:519 LUKS claim. | Audit R5 declares it substantiated post-cutover; docs carry unconditional LUKS-at-rest claims (privacy-policy:515,519; DPD:44,98,410). | `/soleur:legal-audit` confirms vs measured postures; the plaintext-backstop over-claim check is the highest-value item. |
| Layer A lint. | `python3 scripts/lint-encryption-posture.py --repo-sweep` → PASS (14 stores, 3 conns, 0 unledgered). Validates `tracking_issue` **shape only**, not open/closed state (`:530-534`). | Re-home keeps lint green; the open-state class gap is tracked on #6893. |

## User-Brand Impact

**If this lands broken, the user experiences:** a legal document (`privacy-policy.md`) asserting
LUKS encryption-at-rest for their workspace/git data while the measured posture shows an
un-reconciled or over-claimed exception — the exact claim-vs-reality mismatch that made parent
issue **#6588** a P1.

**If this leaks, the user's data is exposed via:** a superseded plaintext volume
(`hcloud_volume.workspaces` / `git_data`) whose bounded exception was silently **unbounded**
(re-homed to a closed issue, or dropped), so the tracked remediation (detach+destroy / DL-2 wipe)
never gets driven and pre-cutover plaintext data persists on a seizable disk indefinitely.

**Brand-survival threshold:** single-user incident.

> This PR does not change encryption reality (zero live-infra mutation); it reconciles claims and
> issue-tracking to already-measured reality, which **reduces** the #6588-class risk. The threshold
> reflects the subject (public encryption claims about user data at rest).

**Plan-time sign-off: CLO** (legal domain owner) — Product = NONE (zero UI), so the risk axis is
legal-claims, not product; CPO sign-off would be the wrong lens (fixed per review). The
`single-user incident` threshold invokes **`user-impact-reviewer`** at review time.

## Implementation Phases

### Phase 0 — Preconditions (read-only; re-confirm at /work start)
- Layer A baseline: `python3 scripts/lint-encryption-posture.py --repo-sweep` → `PASS`. The invariant every phase preserves.
- Enumerate live refs: `git grep -l '#6897'` → expect the 6 files in the footprint table (assert by content anchor). Ledger has 8 (`grep -n '#6897' scripts/encryption-posture-ledger.json`); model.c4 has 2.
- Confirm `server.tf:1569` / `git-data.tf:196` volumes + attachments (`server.tf:1581`, `git-data.tf:207`) still declared — READ only, no `terraform`/`hcloud` mutation.

### Phase 1 — Create the follow-up trackers (Option B — 3 issues) + note the class gap on #6893
Create dedicated **open** GitHub issues so every residual exception is driven independently. Labels
`type/security`, `domain/engineering`, `priority/p3-low` (all verified to exist). Each body: 1-line
statement, the ledger row(s) it bounds, the measured posture, **its `reevaluate_when` trigger(s)
verbatim**, `Ref #6893` (+ `Ref #6588` where user-data), and "split out of #6897". Do NOT `Closes`
any parent. Capture each number.

| New issue (title stem) | Homes ledger + C4 ref(s) | reevaluate_when trigger(s) in body |
|---|---|---|
| `encryption-posture: superseded plaintext backstop teardown (workspaces detach+destroy; git_data DL-2 wipe)` | ledger 74,77,97,100 + model.c4:216 | (a) workspaces_luks cutover confirmed irreversible → plaintext detached+destroyed; (b) git_data_luks cutover confirmed → git_data plaintext DL-2 wipe runs |
| `encryption-posture: host at-rest posture measurement — session-store + git-data host (Layer-B probes)` | ledger 57,259,262 + model.c4:220 | (a) session-store host at-rest posture measured (or LUKS applied); (b) a git-data host posture probe exists to confirm the git_data_luks LUKS volume is the live store |
| `encryption-posture: zot registry link TLS / private-net re-evaluation` | ledger 290 | the registry is exposed beyond the private network, or TLS is added to the link |

**Class-gap note on #6893** (open parent, no new issue — `wg-when-a-workflow-gap-causes-a-mistake-fix`):
comment on #6893 that Layer A lint validates `tracking_issue` shape only, not open/closed state, so a
bounded exception can silently unbound when its tracker closes (the #6897 defect). Propose a Layer
A/B `expires_on`-staleness or `gh`-open-state check as the durable fix. (Fixing the linter is a
separate Layer-A enhancement, out of scope for this P3.)

**Durable handoff (spec-flow LOW):** give all three issues a shared discoverability handle — the
`encryption-posture:` title prefix + `type/security` label — so if the captured numbers are lost
mid-run, `gh issue list --label type/security --search 'encryption-posture in:title' --state open`
re-derives them before Phase 2.

> **Decision (recorded to `decision-challenges.md`).** Default = **Option B (3 issues)**, panel
> consensus minimal-correct. **A** (4 per-item, faithful to #6894/#6895) is acceptable if the
> operator prefers per-volume granularity. **C** (re-point to parents #6893/#6588) is rejected —
> a broad parent can close while a narrow child trigger is unresolved, recurring the #6897 defect.
> The "must #6897 close at all?" user-challenge is also recorded (operator directed the close).

### Phase 2 — Sweep every LIVE artifact
1. **Ledger** (`scripts/encryption-posture-ledger.json`): re-point all 8 `#6897` refs to the new
   numbers (Phase 1 table), in both the `live_verification` `tracked #N` suffix AND
   `exception.tracking_issue` / `exception.reevaluate_when`. Leave `expires_on: 2026-10-22`,
   evidence, mechanism, defends/does_not_defend, disclosed_as UNCHANGED.
2. **C4 source** (`model.c4:216,220`): genericize — replace `, tracking #6897)` → `)` so the prose
   reads "Ledgered exception (encryption-posture-ledger.json), pending …". The ledger is the SoT for
   the current tracker; the diagram points at it and never restates a specific (soon-stale) number.
   Prose-only: **no** element / relationship / view / tag change.
3. **C4 compiled** (`model.likec4.json`): regenerate from `model.c4` via the repo's likec4 export if
   one exists; otherwise apply the identical `, tracking #6897)` → `)` string edit (9 embeds).
4. Re-run Layer A lint → `PASS` (0 unledgered, 0 failing). Run the C4 validation tests
   (`apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`) — a prose-only description
   edit must keep them green.
5. **Do NOT touch** the immutable historical trio (audit doc, r2 sibling plan, design-default
   tasks.md) — their `#6897` is a true point-in-time record.

### Phase 3 — Legal-doc reconciliation (checkbox 3)
- Run `/soleur:legal-audit` (inline, `wg-plan-prescribed-skills-must-run-inline`;
  = `legal-compliance-auditor`) over the three legal docs, reconciling each encryption claim vs the
  ledger's measured postures:
  - `privacy-policy.md:515` / `DPD:98,410` — "API keys AES-256-GCM" → BYOK app-layer encryption.
  - `privacy-policy.md:519` / `DPD:44` — "workspace git data on a LUKS-encrypted volume" → audit R5
    substantiated post-cutover (workspaces_luks + git_data_luks are LUKS).
  - **Highest-value check:** the plaintext backstop volumes still exist + are attached. The public
    claim is about where live data *sits* (the LUKS mapper) — true — but a plaintext copy may persist
    on the backstop until teardown/DL-2 wipe. Confirm the wording does not over-claim absolute
    at-rest encryption in a way the backstops falsify.
- **Disposition (tightened per spec-flow):**
  - A **material over-claim** — a published claim the measured posture *falsifies* (the #6588 shape)
    — MUST be **folded (corrected inline)** before `Closes #6897`. It may NOT be deferred; a live
    false encryption claim at the moment #6897 closes reproduces #6588.
  - Only a **large, non-falsifying structural** need (new disclosure section, reorganization — the
    existing claims are true, more detail is merely desirable) may be **deferred** to a tracked
    follow-up (`Ref #6893`).
- Record the audit's verdict (substantiated / corrected-inline / follow-up-filed) in the PR body.

### Phase 4 — Verify + ship
- Layer A lint `PASS`; C4 tests green.
- **Repo-scoped bounding check (replaces the ledger-only grep):**
  `git grep -l '#6897'` returns ONLY the allowlisted historical set — the audit doc, the r2 sibling
  plan, the design-default `tasks.md`, and this feature's own plan/spec artifacts. Any **live**
  artifact (ledger, `model.c4`, `model.likec4.json`) still matching `#6897` is a gate failure.
- Broken-citation sweep on the plan: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'`.
- PR body: `Closes #6897`; `Ref #6588`; `Ref #6893`; the 3 new issue numbers + the legal-audit
  verdict + the `decision-challenges.md` render. **No operator/post-merge checklist** — issue
  creation + edits + legal reconcile all happen in-PR; no `terraform apply`
  (`hr-ship-message-no-operator-checklist`).

## Acceptance Criteria

All pre-merge (no post-merge operator step — no `terraform apply`, no migration, no live mutation;
`Closes #6897` at merge is correct because the merge IS the remediation).

- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` → `... 0 unledgered, 0 failing checks -> PASS`.
- [ ] `git grep -l '#6897'` returns ONLY the allowlisted historical + own-feature artifacts (audit doc, r2 plan, design-default tasks.md, this plan/spec) — **no** ledger, `model.c4`, or `model.likec4.json` hit.
- [ ] The C4 validation tests pass (`c4-code-syntax.test.ts`, `c4-render.test.ts`); `model.c4` + `model.likec4.json` no longer contain `#6897`; the edit is prose-only (no element/relationship/view/tag diff — `git diff` shows only description strings).
- [ ] The 3 new issues exist and each `gh issue view <N> --json state` = `OPEN`; each **body contains its `reevaluate_when` trigger(s) verbatim** (not just an open, contentless issue).
- [ ] `hcloud_volume.workspaces` + `hcloud_volume.git_data` (ledger) retain shape (`mechanism: plaintext-exception`, evidence, defends/does_not_defend, disclosed_as, `exception{…,expires_on: 2026-10-22}`); only `tracking_issue`/`reevaluate_when` issue-number changed. **`server.tf` / `git-data.tf` UNCHANGED** (no `.tf` in the diff).
- [ ] zot connection row: `cert_verification: off`, cosign-digest-pinning `does_not_defend`, `exception.tracking_issue` re-homed off `#6897`.
- [ ] `#6893` carries the class-gap note (Layer A doesn't check tracker open-state).
- [ ] `git diff --name-only origin/main` touches ONLY: `scripts/encryption-posture-ledger.json`, `model.c4`, `model.likec4.json`, `docs/legal/*.md` (iff Phase 3 folds a correction), `knowledge-base/project/{plans,specs}/…` — **no** `apps/web-platform/infra/*.tf`, no migration, no server/src code.
- [ ] `/soleur:legal-audit` ran; verdict recorded in PR body. Any **material over-claim was folded inline** (not deferred).
- [ ] PR body: `Closes #6897`; `Ref #6588`; `Ref #6893`; 3 new numbers; legal verdict; decision-challenges rendered; no operator/post-merge checklist.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO). Product = **NONE** (no UI surface — the
mechanical UI-surface override does not fire; no path in Files-to-Edit matches `components/**`,
`app/**/page.tsx`, or the UI-surface term list).

### Engineering (CTO)
**Status:** reviewed (architecture-strategist + spec-flow + code-simplicity, this deepen pass).
**Assessment:** ledger + C4-prose + issue-hygiene; load-bearing invariant = Layer A green + C4 tests
green + zero `.tf`/infra mutation. Panel APPROVED the approach; all P2/HIGH findings folded above.

### Legal (CLO)
**Status:** to-run (Phase 3 `/soleur:legal-audit` = `legal-compliance-auditor`), inline.
**Assessment:** the LUKS/AES-256 encryption-at-rest claims are the #6588-class surface; audit R5
substantiates the primary claim, so expect confirmation + the plaintext-backstop over-claim check. A
material over-claim blocks the close (Phase 3).

### Product/UX Gate
Not applicable — Product NONE. No `.pen` required (`wg-ui-feature-requires-pen-wireframe` does not fire).

## Encryption Posture

**Gate status: satisfied — no new store or connection introduced.** File detection
(`\.tf$`, `supabase/migrations/.*\.sql$`, `cloud-init.*\.ya?ml$`, `docker-compose.*\.ya?ml$`) does
not match this PR's Files-to-Edit. The PR ledgers the **current** posture of already-existing stores
and only re-homes their bounded-exception tracker; it adds no persistent store and no
cross-component connection. The ledger is the authoritative `## Encryption Posture` artifact and
stays Layer-A-green (`plaintext-exception` rows keep `exception{justification, tracking_issue,
reevaluate_when, expires_on}`, now bounded by open issues).

## Observability

**Skip — data + docs change.** No Files-to-Edit under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, `plugins/*/scripts/`; no new infra. `scripts/lint-encryption-posture.py` and the
c4 tests are **run** (AC gates), not edited. Layer A lint failure + a red c4 test are the CI-visible
signals for a bad edit.

## Infrastructure (IaC)

**Skip — no infrastructure introduced or mutated.** The IaC-routing detection set (SSH,
`terraform apply`, systemd units, Doppler secret writes, vendor-dashboard steps, new vendor account)
matches nothing. The two `.tf`-declared volumes are **read** for currency only; declarations +
attachments left UNCHANGED (operator: zero live-infra mutation). No `terraform apply`, `-target`,
or destroy.
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

## Architecture Decision (ADR/C4)

**No new architectural decision — but a real (prose-only) C4 edit.** Corrected from the pre-review
"no C4 impact": `model.c4` descriptions at :216 (git-data store) and :220 (session store) carry
`#6897` provenance pointers that Phase 2 **genericizes to the ledger** (drops the hardcoded issue
number). This is a **description-string** edit only — no external actor, system, data store, or
access relationship changes; no `view … include` change; the git-data + session-store elements and
their edges are already modeled and unchanged. So **no ADR** (ADR-140 already governs the
encryption-posture ledger + Layer-A gate; this PR operates within it and reverses no Decision) and
**no structural C4 change** — but the `.c4` source + compiled `model.likec4.json` ARE edited and the
c4 validation tests (`c4-code-syntax.test.ts`, `c4-render.test.ts`) MUST pass (Phase 2 / AC).
Enumeration checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): the only
`#6897` occurrences are the two `model.c4` descriptions above; `views.c4`/`spec.c4` carry none.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open` bodies contain no reference to
`scripts/encryption-posture-ledger.json`, `docs/legal/`, or the C4 diagrams (verified this session).

## Sharp Edges

- **Sweep every LIVE artifact, carve out the historical.** `#6897` lives in the ledger AND the C4
  model (live) plus the audit doc + 2 planning artifacts (historical). Re-home the live set;
  leave the historical set untouched; the AC's repo-scoped `git grep -l '#6897'` must return ONLY
  the historical + own-feature allowlist. A ledger-only sweep would ship `Closes #6897` while the
  architecture diagram cites a closed issue — the exact defect this PR fixes.
- **C4 edit is prose-only.** Genericize `, tracking #6897)` → `)` in `model.c4` + `model.likec4.json`;
  do NOT touch elements, relationships, views, or tags. Keep both files in sync (they carry the same
  description string). Run the c4 tests — a structural change would fail them; a prose change must not.
- **Ledger rows already exist — do NOT re-author them.** The gap is tracker *bounding*, not row
  creation. Editing evidence/mechanism/disclosed_as (all current) risks regressing Layer A.
- **Line 57 is the LUKS store's posture note, not a plaintext exception.** It has no
  `reevaluate_when` and homes to the *posture-measurement* issue, not the plaintext teardown.
- **Zero `.tf` mutation.** `git_data` is the pending-DL-2-wipe backstop; `workspaces` teardown is
  out of scope. An AC asserts no `apps/web-platform/infra/*.tf` in the diff.
- **`expires_on` does not reset on re-homing.** Keep `2026-10-22` (clock started at the 2026-07-23
  audit).
- **Layer A lint does not validate issue open/closed state** (`:530-534`, `^#\d+$` only). Green lint
  after re-homing does NOT prove the new issues are open (the `gh issue view --json state` AC does),
  and a tracker pointing at a *closed* issue passes lint while violating the bounded-exception
  contract — the #6897 defect. The class gap is noted on #6893.
- **Legal: a material over-claim blocks the close.** A published claim the measured posture
  falsifies must be folded inline, never deferred — deferring closes #6897 with a live #6588-shape
  over-claim still published.
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 —
  this one is filled (`single-user incident`, CLO sign-off).
