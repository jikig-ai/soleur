---
title: "encryption-posture #6897 — verify ledger current + legal-doc reconciliation (#6897 stays OPEN)"
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

# encryption-posture #6897 — verify ledger current + legal-doc reconciliation (#6897 stays OPEN)

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
5. **~~Issue count minimized to 3 (Option B)~~ — SUPERSEDED by operator decision (2026-07-24):
   keep #6897 OPEN, file ZERO trackers, net-issue-flow = 0.** The "must #6897 close at all?"
   user-challenge was resolved by the operator in favor of keeping the umbrella open (its residual
   items are ongoing bounded exceptions, not one-time fixes). Phase 1's tracker creation + Phase 2's
   ref re-homing are CUT; the ledger/C4 `#6897` refs correctly stay.
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
cutover-teardown, out of scope.

**DISPOSITION (operator-decided 2026-07-24): #6897 STAYS OPEN — net 0, no new trackers.** Deliverable =
a reviewed, merged PR that **`Ref #6897` (NOT `Closes`)** and reconciles the legal copy. #6897 remains
the umbrella that homes these *ongoing* bounded exceptions (superseded volumes pending teardown; zot
HTTP by-design; host-posture measurement) — they are not one-time fixes, so the honest end-state is
that #6897 stays on the board until they genuinely resolve.

**Central finding.** The ledger rows the issue asks for **already exist and are accurate** (authored
by PR #6885, merged `51d2646bc`), and every one references `#6897` as its `tracking_issue`.
**Because #6897 stays OPEN, those references are correct and are LEFT UNCHANGED** — the bounded-exception
contract holds (they point at a live tracker). There is NO re-homing, NO ledger `#6897`-ref edit, and
NO C4 `#6897`-ref edit. The superseded `redis.session_store`/`git_data_luks` Layer-B notes and the C4
`#6897` pointers likewise stay. This removes the entire re-home/genericize workstream.

**The actionable deliverable is checkbox 3 — legal-doc reconciliation** — plus a read-only verification
that the ledger rows (volumes + zot) and Layer A are current. Checkboxes 1 & 2 are already satisfied by
#6885's ledger rows (verified current here); they get checked off on #6897 via an issue comment while
#6897 itself stays open for the ongoing exceptions.

This is a **ledger + C4-prose + legal-copy + issue-hygiene** change: no code, no `.tf` edits, no
migrations, no infra mutation.

### The complete `#6897` footprint (verified `git grep -l '#6897'`)

| Artifact | Refs | Class | Disposition |
|---|---|---|---|
| `scripts/encryption-posture-ledger.json` | 8 (lines 57,74,77,97,100,259,262,290) | **live SoT** | **LEAVE UNCHANGED** — #6897 stays open, so the `tracking_issue: #6897` refs correctly bound the exceptions. Verify each row is current/accurate (read-only); no edit expected. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | 2 (216 git-data, 220 session-store) | **live diagram source** | **LEAVE UNCHANGED** — `tracking #6897` correctly points at the open umbrella. No edit. |
| `…/diagrams/model.likec4.json` | 9 embeds (compiled) | **live compiled** | **LEAVE UNCHANGED** — no `model.c4` edit → no regenerate. |
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

### Phase 1 — (REMOVED per operator disposition) — no trackers, #6897 stays open
The Option-B 3-tracker creation is **cut**. #6897 stays OPEN as the umbrella; its ledger/C4 `#6897`
references are correct and stay. No new GitHub issues are filed by this PR (net-issue-flow = 0).

**Class-gap note on #6893 (KEEP — still valuable):** comment on the open parent #6893 that Layer A
lint validates `tracking_issue` **shape** only (`^#\d+$`), never open/closed state
(`scripts/lint-encryption-posture.py:530-534`) — so a bounded exception silently unbounds if its
tracker ever closes. Propose a Layer A/B `expires_on`-staleness or `gh`-open-state check as the durable
fix (`wg-when-a-workflow-gap-causes-a-mistake-fix`). This is a single advisory comment on an existing
open issue — NOT a new issue (keeps net-issue-flow at 0). Since #6897 now stays open, the gap is not
currently triggered, but the note remains a real latent finding worth recording on #6893.

### Phase 2 — Verify the ledger + zot rows are current (READ-ONLY; no re-home, no ref edits)
1. **Ledger** (`scripts/encryption-posture-ledger.json`): confirm the `hcloud_volume.workspaces`,
   `hcloud_volume.git_data`, and zot-registry-link rows exist and their evidence/mechanism/
   defends/does_not_defend/`tracking_issue: #6897`/`expires_on` fields are accurate against the code
   (`server.tf`, `git-data.tf` volume declarations + attachments; the zot `10.0.1.30:5000` link).
   **Leave every `#6897` reference UNCHANGED.** Only if a field is provably STALE/WRONG (not merely
   pointing at the still-open #6897) is a correction in scope — otherwise no ledger edit.
2. **C4 source + compiled:** LEAVE UNCHANGED (no `model.c4` edit → no `model.likec4.json` regenerate).
3. Re-run Layer A lint → `PASS` (0 unledgered, 0 failing) to confirm the read-only verification did not
   perturb the ledger.
4. **Do NOT touch** the immutable historical set (audit doc, r2 sibling plan, design-default tasks.md).

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
    — MUST be **folded (corrected inline)** before merge. It may NOT be deferred; a live false
    encryption claim reproduces #6588 regardless of whether #6897 stays open.
  - Only a **large, non-falsifying structural** need (new disclosure section, reorganization — the
    existing claims are true, more detail is merely desirable) may be **deferred** to a tracked
    follow-up (`Ref #6893`).
- Record the audit's verdict (substantiated / corrected-inline / follow-up-filed) in the PR body.

### Phase 4 — Verify + ship
- Layer A lint `PASS`; if any legal doc was edited, run `legal-doc-consistency.test.ts` +
  `legal-doc-shas-guard.test.ts` (source↔Eleventy-mirror parity) AFTER the edit.
- Broken-citation sweep on the plan: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <plan> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN {}'`.
- **No `#6897`-absent gate** — #6897 stays open, so the ledger/C4 `#6897` refs are EXPECTED to remain.
- PR body: **`Ref #6897`** (NOT Closes — stays open); `Ref #6588`; `Ref #6893`; the legal-audit verdict
  + the `decision-challenges.md` render. **No operator/post-merge checklist.** Check off #6897's
  checkboxes 1 & 2 (ledger current) via an issue comment; box 3 checked iff legal reconciliation lands.

## Acceptance Criteria

All pre-merge (no post-merge operator step — no `terraform apply`, no migration, no live mutation).
**#6897 STAYS OPEN (Ref, not Closes); NO new issues filed (net-issue-flow = 0).**

- [ ] `python3 scripts/lint-encryption-posture.py --repo-sweep` → `... 0 unledgered, 0 failing checks -> PASS`.
- [ ] Ledger `#6897` refs UNCHANGED (`git diff scripts/encryption-posture-ledger.json` shows no `#6897`-ref change); the `workspaces`/`git_data`/zot rows verified current (evidence/mechanism/`tracking_issue: #6897`/`expires_on` accurate against code). Any edit is limited to a provably-stale field, not a ref re-home.
- [ ] `model.c4` + `model.likec4.json` UNCHANGED (no C4 diff).
- [ ] `server.tf` / `git-data.tf` UNCHANGED (no `.tf` in the diff); zero live-infra mutation.
- [ ] `#6893` carries the class-gap note (Layer A doesn't check tracker open-state) — via a single comment on the existing open issue, NOT a new issue.
- [ ] NO new GitHub issue created by this PR (`net-issue-flow.sh <PR>` → NET ≤ 0).
- [ ] `git diff --name-only origin/main` touches ONLY: `docs/legal/*.md` + its Eleventy mirror (iff Phase 3 folds a correction), and `knowledge-base/project/{plans,specs}/…` — plus `scripts/encryption-posture-ledger.json` ONLY if a stale field was corrected. **No** `.tf`, no migration, no server/src code, no `model.c4`/`model.likec4.json`.
- [ ] `/soleur:legal-audit` ran; verdict recorded in PR body. Any **material over-claim was folded inline** (not deferred).
- [ ] PR body: `Ref #6897` (stays open); `Ref #6588`; `Ref #6893`; legal verdict; decision-challenges rendered; no operator/post-merge checklist.

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
not match this PR's Files-to-Edit. The PR **verifies** the **current** posture of already-existing
stores and leaves their bounded-exception tracker (#6897) OPEN and unchanged; it adds no persistent
store and no cross-component connection. The ledger is the authoritative `## Encryption Posture`
artifact and stays Layer-A-green (`plaintext-exception` rows keep `exception{justification,
tracking_issue, reevaluate_when, expires_on}`, bounded by the still-open #6897).

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
