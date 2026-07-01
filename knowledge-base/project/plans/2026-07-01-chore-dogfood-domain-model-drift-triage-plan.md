---
title: "chore: dogfood /soleur:sync domain-model analyzer — triage drift findings into the register"
issue: 5882
branch: feat-one-shot-5882-domain-model-drift-triage
lane: procedural
brand_survival_threshold: none
type: chore
detail_level: MORE
related: [5754, 5871, 5872, ADR-076]
---

# chore: dogfood the domain-model drift analyzer and triage its findings into the register 🧹

## Enhancement Summary

**Deepened on:** 2026-07-01
**Gates cleared:** 4.6 User-Brand Impact (present, threshold none, non-sensitive `.md`), 4.7 Observability
(pure-docs skip), 4.8 PAT-shaped (no hits), 4.9 UI-wireframe (no UI surface).
**Reviewers:** architecture-strategist (Engineering domain), spec-flow-analyzer (verification flow),
code-simplicity-reviewer (YAGNI).

### Key improvements folded in

1. **`public` is an extraction defect, not a suppressible artifact (architecture-strategist R1/R4).** Naming
   "public" in the register would permanently blind undocumented-table detection for the whole schema (~20
   tables collapse to one token). Intended residual reversed from exit-0/undoc-0 to **exit-1/undoc-1 (`public`)**;
   the `public` decision-record lives on #5871, never the register.
2. **BR-CONV-1 / BR-WS-3 collision guard (R2), storage citation-source fix (R3/R5), and BR-BYOK-1** (byok
   delegation consent, GDPR Art. 7) surfaced from the blind-spot spot-check with a concrete disposition rule.
3. **Verification hardening (spec-flow):** fixed a real internal contradiction (Test Scenarios said "exit 0"),
   added explicit `rc==1` capture so the intended non-zero isn't misread as failure (P1-1), a `public`-leak
   inverse guard (P0-2), the #5871 ship-gate ordering hand-off (P1-2), the write-row "exactly-one-row" positive
   assertion (P1-4), and the human-audited-only + "N tables" mislabel notes (P2).
4. **Simplification (code-simplicity):** cut the duplicate advisory ADR-076 amendment, resolved R5 to a
   one-liner, bounded the LARP tail of AC6.

### New considerations discovered

- Because `public` stays permanently flagged (exit 1), **#5871's future ship gate must land the extractor
  schema-qualifier strip first OR allowlist the known `public` residual** — otherwise it hard-blocks every ship.
- No current CI/ship/preflight step runs the analyzer (verified), so this permanent exit-1 blocks nothing today.

## Overview

First real use ("dogfood") of the `/soleur:sync domain-model` drift analyzer (shipped in #5754,
recorded in [`ADR-076`](../../engineering/architecture/decisions/ADR-076-domain-model-drift-extraction.md)).
#5754 exercised the *detector* as a smoke test but never closed the *maintenance loop*: the register's
`## Auto-inferred (unreviewed)` section is empty and the analyzer's findings against our own repo were
never triaged.

This is a **register-curation (pure-docs) task**. The only production artifact edited is
`knowledge-base/engineering/architecture/domain-model.md`. The analyzer itself, per-PR/continuous
enforcement (#5871), and a scheduled cron (#5872) are **explicitly out of scope** — all three are
verified OPEN/CLOSED and are not touched here.

The current drift run (`bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md`)
exits 1 and reports:

- **Stale register citations: 0** — `_none_`. The `resolveActiveWorkspace` citation (BR-WS-2) is live.
- **Undocumented source facts: 3 tokens** — `conversations`, `public`, `storage`.
- **Blind spots: 47** — 43 dynamic SQL (`DO $...$` / `EXECUTE format`), 3 unparseable quoted-name
  `CREATE POLICY`, 1 unresolved `SECURITY DEFINER`. Blind spots do NOT affect the exit code.

The task closes the loop: confirm stale stays 0, triage each of the 3 undocumented tokens (promote to a
curated `BR-*` row or record an "intentionally out of scope" decision), spot-check the 47 blind spots for
any material access/tenancy invariant the register should name, and re-run to confirm an idempotent
residual. It also generates the **soak evidence** #5871's re-evaluation asks for: *is manual triage
burdensome enough to justify mechanical enforcement?*

**Intended residual is exit 1, NOT exit 0** (Engineering-review correction — see Domain Review R1/R4).
`conversations` and `storage` are real tokens that get curated (undoc drops 3 → 1). `public` is a
schema-qualifier **extraction defect**: because every `public.*` anchor collapses to the single `public`
token, naming the word "public" anywhere in the register would permanently silence undocumented-table
detection for the *entire* public schema (~20 real tables) — that is *silencing*, not *documenting*. So
`public` is **deliberately left flagged** (its triage decision is recorded on #5871 + the PR body, NOT in
the register body), the extractor fix is escalated to #5871 as a correctness bug, and the honest idempotent
residual is `Undocumented (1) — public`, exit 1, byte-identical on re-run (ADR-076 §1 guarantees
byte-identical *output*, which is the real idempotency contract — not a green exit code).

## Research Reconciliation — Spec vs. Codebase

The issue frames the finding as "3 undocumented **tables**." Direct extract (`extract` mode JSON) shows
the reality is subtler and is itself the headline soak finding — the plan reflects reality, not the framing.

| Spec claim | Reality (verified via `extract` mode) | Plan response |
|---|---|---|
| "3 undocumented tables" | 3 pre-dot **tokens**, not 3 tables. The analyzer captures the token before the first `.` in a `schema.table` anchor (`domain-model-drift.sh:165`). | Triage all 3 tokens; reframe `public`/`storage` as schema tokens, not tables. |
| `conversations` is a table | ✅ Real bare-qualified table. RLS in `075_conversation_visibility.sql`; constraints in 017/032/041. | Promote to `BR-CONV-1` + add a `Conversation` entity row. |
| `public` is a table | ❌ Schema qualifier. Collapses ~20 real `public.*` tables (message_attachments, tc_acceptances, scope_grants, audit_byok_use, dsar_export_jobs, workspace_members, workspaces, organizations, messages, action_sends, template_authorizations, …) into ONE token. Some already curated as Entities; most are operational/audit/idempotency tables. | **Leave flagged (exit 1).** This is an extraction *defect*, not an artifact to suppress: naming "public" in the register silences the whole-schema guard forever. Escalate to #5871 as a correctness bug; enumerate the collapsed set + spot-check for uncurated material invariants; record the decision on #5871/PR body (NOT the register). |
| `storage` is a table | ❌ `storage.objects` schema token (Supabase-managed). Real tenancy RLS across 019/042/068/071/098. | Promote to `BR-STORAGE-1` (storage-object tenancy). |
| "Stale citations: 0 (confirm)" | ✅ Confirmed live. `resolveActiveWorkspace` **defined at `apps/web-platform/server/workspace-resolver.ts:398`** (`grep -n`, NOT head-truncated). | AC1 re-verifies with a non-truncated grep. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at runtime. The domain-model register is an
internal engineering catalogue with no user-facing surface and no execution path. A wrong BR statement
would only mislead a future engineer reading the register.

**If this leaks, the user's data is exposed via:** N/A. No user data is read, moved, or processed; the
edit is a static markdown documentation change. No new processing activity.

**Brand-survival threshold:** none.

> The diff touches only `knowledge-base/engineering/architecture/domain-model.md` (a `.md` doc), which is
> NOT a sensitive path per preflight Check 6 (no schema/migration/auth/API/`.sql`). No sensitive-path
> scope-out bullet is required.

## Implementation Phases

### Phase 0 — Preconditions & evidence capture (read-only)

1. Run the drift report and archive its exact output into the PR body / session record:
   `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md` (expect exit 1).
2. **Confirm stale = 0 with a NON-truncated existence grep** (honors learning
   `2026-07-01-existence-grep-must-not-be-head-truncated.md`):
   `grep -n "resolveActiveWorkspace" apps/web-platform/server/workspace-resolver.ts` — MUST show the
   definition (`export async function resolveActiveWorkspace(` at line 398). Do NOT pipe through `head`.
3. Capture the full triage evidence from `extract` mode:
   `bash scripts/domain-model-drift.sh extract --repo . | jq '.facts, .blind_spots'` — enumerate the
   collapsed `public.*` set and the 47 blind-spot files/details.
4. Confirm the 3 tokens are currently absent as lowercase whole-words:
   `for t in conversations public storage; do printf '%s ' "$t"; grep -cwE "$t" <register>; done` → `0 0 0`.

### Phase 1 — Triage token 1: `conversations` → promote to `BR-CONV-1`

Real Command Center conversation entity with an owner/shared-visibility access model.

1. **(Optional, recommended) Exercise the approval-gated write-row loop first** to generate end-to-end
   soak evidence of the machine-append path — **`conversations` only** (it has a parseable extract anchor;
   `storage`'s 098 policies are quoted-name blind spots with NO anchor, so BR-STORAGE-1 is authored directly,
   NOT via a write-row demo — P1-3):
   `bash scripts/domain-model-drift.sh write-row --register <register> --anchor "075_conversation_visibility.sql › conversations.conversations_owner_select" --statement "<candidate>"`
   → appends one escaped/secret-scanned/deduped row to `## Auto-inferred (unreviewed)`. **Verify exactly one
   row landed** before promoting (a repeat call `exit 0`s as a dedup no-op having written nothing — AC7). This
   demo is scoped to `conversations` ONLY: it has a parseable extract anchor. `storage`/BR-STORAGE-1 is
   hand-authored directly (its 098 policies are blind spots → no extract anchor exists to write-row/dedup on).
   - **P1-4 (guard against vacuous soak):** write-row `exit 0`s as a no-op if the anchor already exists
     (`grep -qF "$ANCHOR"`). Before promoting, positively assert exactly ONE new row landed
     (`grep -c 'conversations_owner_select' <register>` increased by 1) — otherwise the demo proved nothing
     and AC7 would pass vacuously. If it deduped, the append path was NOT exercised; drop the demo claim.
2. **Human-promote** (deliberate edit per ADR-076 §5): add a curated `BR-CONV-1` row to `## Business Rules`
   and a `Conversation` entity row to `## Entities`. Remove the corresponding Auto-inferred row (promotion
   moves it), keeping the content anchor so it is never re-proposed.
   - Draft `BR-CONV-1`: *"A conversation (`conversations.id`) is owned by its creating user
     (`conversations.user_id`); visibility is owner-private by default with opt-in workspace-shared read;
     write (insert/update/delete) is **conversation-row-owner-only**, and `UPDATE(visibility)` is REVOKE'd
     from direct `authenticated` (goes through a guarded RPC)."* Source: `075_conversation_visibility.sql`
     (+ 032 active_workflow_chk, 017/041 cost constraints — cite by ADR-076 §3 content anchors).
   - **R2 collision guard (load-bearing):** BR-WS-3 explicitly *supersedes the single-owner-strict model of
     migration 075* — but for **workspaces**. BR-CONV-1 cites the same migration file. Scope "owner-only
     write" strictly to **conversation-row** ownership (`conversations.user_id`) and cross-reference BR-WS-3
     so BR-CONV-1 cannot be read as reintroducing the retired single-owner *workspace* model.
   - The statement MUST contain the lowercase whole-word `conversations` (the table token) so the drift
     grep stops flagging it — see Sharp Edges.

### Phase 2 — Triage token 2: `storage` → promote to `BR-STORAGE-1`

The `storage.objects` schema token; real workspace/tenant-scoped RLS.

1. Add curated `BR-STORAGE-1` to `## Business Rules`: *"Access to `storage.objects` is workspace/tenant-scoped:
   attachment objects are readable by workspace co-members and writable by the owner; workspace-logo objects
   are member-read / owner-write; DSAR-export and ux-audit buckets are self/bot-scoped."* Source: migrations
   `019_chat_attachments.sql`, `042_dsar_exports_storage_bucket.sql`, `068_attachments_workspace_shared.sql`,
   `071_ux_audit_artifacts_bucket.sql`, `098_workspace_logos.sql`.
2. **R3 (do not imply analyzer-backing):** 3 of the 47 blind spots ARE the quoted-name logo policies in 098.
   BR-STORAGE-1 documents them from the **migration file** directly — cite the filenames, NOT extracted
   `extract`-mode anchors (the analyzer cannot statically parse the quoted policy names, so no anchor exists).
3. **R5 (entity decision — resolved):** do NOT add a `Storage object` entity row — `storage.objects` is
   Supabase-managed infra and the domain concepts (attachments/logos) are keyed elsewhere. BR-STORAGE-1 alone
   documents the tenancy. (The promote-`storage` / flag-`public` asymmetry — 1 real table vs ~20 — is already
   stated in the Overview + Research Reconciliation; no need to re-record it here.)
4. Statement MUST contain the lowercase whole-word `storage` (e.g., `storage.objects`) so the token is
   silenced — acceptable here (maps to one real, now-documented table).

### Phase 3 — Triage token 3: `public` → extraction defect, LEAVE FLAGGED (do NOT suppress)

`public` is NOT a table and MUST NOT be silenced by naming it in the register. Because every `public.*`
anchor collapses to the single `public` token, once the register body contains the word "public" the guard
(`grep -qE "\bpublic\b"`) matches forever — permanently blinding undocumented-table detection across ~20 real
tables. That is a silent, permanent reduction of the guard's power (Domain Review R1). The correct disposition:

1. **Do NOT write the word `public` into the register.** Keep BR citations to ADR-076 §3 filenames
   (`075_conversation_visibility.sql`), never schema-qualified `public.<table>` forms — otherwise the token is
   *accidentally* silenced (see Sharp Edges). The `public` token stays flagged; drift keeps exiting 1.
2. **Enumerate the collapsed `public.*` set** (from Phase 0 `extract`) and spot-check each for a material
   access/tenancy invariant not already curated — parity with the blind-spot rule (Phase 4). Any genuinely-material
   invariant is **promoted to its own `BR-*` row** (keyed to its real bare table name, e.g. `message_attachments`),
   NOT buried. Record the disposition for the remainder (already-curated Entities / operational-audit tables).
3. **Escalate to #5871 as a correctness bug (not merely soak evidence):** the fix strips the known schema
   qualifier (`public.` / `storage.`) before capturing the table token, so the ~20 tables surface individually.
   `gh issue comment 5871 --body-file <note>` recording: (a) the schema-qualifier collapse defect + its blast
   radius, (b) the manual-triage cost/burden, (c) that `public` is deliberately left flagged pending the fix,
   and (d) a **hand-off constraint for #5871's ship gate**: because `public` is a permanent exit-1 until the
   extractor fix lands, #5871's ship/CI drift gate MUST either (i) land the schema-qualifier strip first, or
   (ii) baseline the known `public` residual (allowlist the single expected token) — a naive "exit 0 or block"
   gate would hard-block every ship on this known defect. (Automatable; `Ref #5882` — #5871 stays open.)

### Phase 4 — Blind-spot spot-check (47)

**Spot-check disposition rule (Domain Review b):** promote a blind spot to a BR **only if it introduces a
principal→resource scoping, consent, or erasure invariant that no existing BR's *statement* already entails.**
If it merely applies an already-curated invariant to another table, leave it disclosed (the register's
completeness disclaimer §24-28 covers "absence ≠ unenforced"). Prioritise **consent / erasure / audit** blind
spots (regulated-data surfaces, `hr-gdpr-gate`).

1. Group the 47 blind spots by file/detail (from Phase 0 extract). Apply the rule to the tenancy-relevant set:
   - **111/102 `email_triage_items` workspace_shared** → instance of BR-WS-2 on another table → **disclose only**.
   - **110 comember_reconcile** → BR-WS-3 reconcile machinery → **disclose only**.
   - **079/080 workspace_repo_ownership** → BR-REPO-1, UNLESS it adds an ownership-record/transfer invariant
     beyond the `(install, repo)` binding → then **extend BR-REPO-1's citation** (do not mint a new BR).
   - **083/084 byok_delegation consent/withdrawal** → **PROMOTE to `BR-BYOK-1`** (Domain Review c). A distinct
     consent-gated, withdrawable BYOK-credential delegation invariant that no BR-WS/REPO/ORG statement entails,
     carrying GDPR Art. 7 weight. Cite `083_byok_delegation_consent_gate.sql` / `084_byok_delegation_withdrawals.sql`.
2. **Secondary (GDPR, Domain Review c/R6):** confirm the DSAR/erasure row-scoping on `dsar_export_jobs` /
   `audit_byok_use` has a curated home — BR-STORAGE-1 covers the DSAR *bucket* (042) but not the DB-side job-row
   tenancy + Art. 17 erasure. If promoted, give it **its own short BR** (keep Art. 17 erasure distinct from
   BR-BYOK-1's Art. 7 consent — do not conflate), else record why not.
3. Confirm no remaining spot-checked blind spot hides a material access/tenancy invariant the register should
   name that is not already covered. Record the confirmation.

### Phase 5 — Re-run & idempotency

1. Re-run `drift` with **explicit exit-code capture** (P1-1 — a bare non-zero exit trips `hr-when-a-command-exits-non-zero-or-prints`; an autonomous /work run would misread the intended residual as a failure and "remediate" it). Use:
   `bash scripts/domain-model-drift.sh drift --repo . --register <register> > /tmp/drift.out; rc=$?; [ "$rc" -eq 1 ] || echo "UNEXPECTED rc=$rc"`.
   Confirm the **intended residual**: stale = 0, **undocumented = 1 (`public` only)**, `rc == 1`.
   `conversations` and `storage` are gone (curated); `public` remains flagged by design (extraction defect,
   #5871). Blind spots remain 47 (disclosed, not counted). `rc == 1` is the *correct* success state — do NOT
   chase exit 0 by naming "public" (Domain Review R4). **Inverse-guard (P0-2):** an `rc == 0` / undoc 0 on the
   FINAL run is a FAILURE signal here — it means "public" leaked into the register and silenced the whole-schema
   guard; AC4's `grep -cwE public == 0` catches it.
2. Re-run a **second** time and confirm byte-identical output (no spurious diff) — ADR-076 §1 guarantees
   deterministic re-runs; idempotency is byte-identical *output*, not a green exit code. The register edit
   must not introduce churn on unrelated facts (only `conversations`/`storage` flip undocumented → documented).
3. Confirm the `## Auto-inferred (unreviewed)` table is empty again (the demo row was promoted, not left).

## Files to Edit

- `knowledge-base/engineering/architecture/domain-model.md` — add `Conversation` entity row; add `BR-CONV-1`,
  `BR-STORAGE-1`, and `BR-BYOK-1` (byok-delegation consent, from the blind-spot spot-check) to `## Business
  Rules`; resolve the Storage-entity question (R5); (transiently) exercise `## Auto-inferred (unreviewed)` via
  `write-row` then promote. **Do NOT write the word `public` into the register** (would silence the whole-schema
  guard — the `public` decision lives on #5871 + the PR body, not here).

## Files to Create

- None. (The soak-evidence body for the `gh issue comment 5871` is a transient scratch file, not a repo artifact.)

## Out of Scope (do not touch)

- `scripts/domain-model-drift.sh` / `scripts/lib/domain-model-lib.sh` — analyzer shipped in #5754. Even though
  triage surfaced the schema-inconsistent `public` extraction, **fixing the extractor is #5871's follow-up**,
  not this issue. Record it as soak evidence only.
- #5871 (enforcement gates) and #5872 (scheduled cron) — deferred, not built here.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (stale still 0, non-truncated):** `grep -n "resolveActiveWorkspace" apps/web-platform/server/workspace-resolver.ts`
      shows `export async function resolveActiveWorkspace(` at line 398 (no `head`); the drift report's
      "Stale register citations" section reads `(0)` / `_none_`.
- [ ] **AC2 (`conversations` triaged, WS-3-safe):** register contains a curated `BR-CONV-1` row + a `Conversation`
      entity row citing `075_conversation_visibility.sql`; "owner-only write" is scoped to `conversations.user_id`
      and cross-references BR-WS-3 (does not reintroduce single-owner *workspace*); `grep -cwE conversations <register>` ≥ 1.
- [ ] **AC3 (`storage` triaged):** register contains a curated `BR-STORAGE-1` row citing migration *files*
      019/042/068/071/098 (not `extract` anchors — the 098 quoted policies are blind spots); the Storage-entity
      question (R5) is resolved + recorded; `grep -cwE storage <register>` ≥ 1.
- [ ] **AC4 (`public` LEFT FLAGGED, not silenced):** the word `public` does NOT appear in the register
      (`grep -cwE public <register>` == 0 on the FINAL post-promotion register — the whole-schema guard stays
      live); the collapsed `public.*` set was enumerated and its per-table disposition recorded on #5871/PR body.
      Note (P2-2): because the extractor collapses all `public.*` to one token, naming an individual bare table
      neither drops the undoc count nor gets re-flagged — this enumeration is **human-audited only** (no
      analyzer-level cross-check) until #5871's extractor fix. Any material invariant found was promoted to a
      real-table `BR-*` (e.g. `BR-BYOK-1`), not buried.
- [ ] **AC5 (residual = 1, idempotent, rc-asserted):** the FINAL `drift` run is captured with `rc=$?` and
      **`rc == 1`** asserted explicitly (not read as a raw failure); it reports `Undocumented source facts (1 ...)`
      naming `public` and `Stale register citations (0)`; two consecutive runs are byte-identical (`diff` of the
      two captures is empty). `rc == 0` = FAILURE (public leaked); `rc == 2` = source-not-analyzable (assert
      `stack != unsupported`). The header literally prints "(1 **tables** …)" — that "tables" label is the
      analyzer's own imprecision (fixed by #5871), NOT a cue to edit the register. Exit 1 is success (Domain Review R4).
- [ ] **AC6 (blind-spot spot-check recorded):** the 47 blind spots are grouped; **each blind spot in the
      enumerated tenancy set (111/102/110/083/084/079/080) has a recorded disposition** per the spot-check rule;
      **byok_delegation (083/084) is promoted to `BR-BYOK-1`**; DSAR/erasure row-scoping (dsar_export_jobs/
      audit_byok_use) has a recorded home (its own row if promoted — NOT glued onto BR-BYOK-1, to keep Art. 7
      consent distinct from Art. 17 erasure) or a recorded reason-why-not.
- [ ] **AC7 (Auto-inferred clean, demo actually exercised):** if the optional `conversations` write-row demo ran,
      assert **exactly one row was appended** (not a dedup no-op — else the append path was never exercised and the
      "soak evidence" is vacuous) BEFORE promotion; after promotion `## Auto-inferred (unreviewed)` has no leftover
      row; the curated table shape is unchanged (no `## Business Rules` machine-edit — hand-authored per ADR-076 §5).
- [ ] **AC8 (immutable BR IDs):** `BR-CONV-1`, `BR-STORAGE-1`, `BR-BYOK-1` do not collide with existing IDs
      (`grep -oE 'BR-[A-Z]+-[0-9]+' <register> | sort | uniq -d` is empty).
- [ ] **AC9 (#5871 correctness-bug escalation filed):** a comment on #5871 records (a) the schema-qualifier
      collapse as a correctness bug + blast radius, (b) the manual-triage cost, (c) that `public` is deliberately
      left flagged pending the extractor fix. `Ref #5882`; #5871 stays open.

## Open Code-Review Overlap

None. (Register-curation task; no open code-review scope-outs touch `domain-model.md`. Verified against
`gh issue list --label code-review --state open`.)

## Observability

**Skipped (pure-docs).** Files-to-Edit is a single `.md` register + a `gh issue comment`; no code-class file
under `apps/*/server`, `apps/*/src`, `apps/*/infra`, or `plugins/*/scripts`, and no new infrastructure surface.
Phase 2.9 skip condition (pure-docs, no code/infra Files-to-Edit) applies.

**Phase 2.9.1 (soak follow-through) does NOT fire:** the "soak evidence" here is a **one-time qualitative record**
on #5871 (was manual triage burdensome?), not a time-gated probe that must hold for N days before an issue closes.
No `scripts/followthroughs/` script or `soleur:followthrough` directive is warranted; #5871 owns the recurring
re-evaluation.

## Architecture Decision (ADR/C4)

**Skipped — no new architectural decision.** This plan *documents* invariants that were already decided and
shipped (conversation visibility per migration 075; storage-object tenancy per 019/042/068/071/098; the
extractor's structural-not-semantic scope per ADR-076 §4). No ownership/tenancy boundary MOVES, no new substrate
or resolver/trust-boundary is introduced, and no existing ADR is reversed. Adding curated `BR-*` rows to a
markdown register is the deliverable itself, not a decision record. The register update carries its own ADR-anchored
citations; no `.c4` model edit is needed because no external actor, external system, container, or access
relationship changes (the Conversation entity and storage buckets are pre-existing runtime surfaces, not new C4
elements introduced by this change).

The `public`-collapse extraction defect (root: ADR-076 §3's content-anchor convention has no schema-qualifier
case) is captured once, in the AC9 escalation comment on #5871 — the issue chartered to *fix* it. No separate
advisory ADR amendment is authored here (it would duplicate a fact a live issue already owns and will soon make
stale).

## Test Scenarios

- **Happy path:** run drift (exit 1, 3 undoc) → triage 3 tokens (`conversations`/`storage` curated, `public`
  left flagged) → re-run drift (**exit 1, undoc = 1 — `public` only**) → re-run again (byte-identical). Blind
  spots stay 47 throughout. NOTE: exit 1 is the intended terminal state — do NOT rewrite this to exit 0.
- **write-row demo:** `write-row` appends exactly one Auto-inferred row; re-running the same `write-row` is a
  dedup no-op (anchor already present); after human-promotion the Auto-inferred table is empty.
- **Idempotency guard:** editing the register must not change the drift output shape on unrelated facts (only
  **2 tokens** — `conversations` + `storage` — flip undocumented → documented; `public` stays flagged).
- **`public`-leak guard (failure mode):** if the register accidentally names `public`, undoc drops 3→0 and drift
  **exits 0** — which, given the analyzer semantics, is a FAILURE here, not success. AC4 (`grep -cwE public == 0`
  on the final register) is the guard; a final drift run that exits 0 means `public` leaked.
- **Case-sensitivity guard:** confirm each triaged token appears as a *lowercase* whole-word (a BR-ID like
  `BR-STORAGE-1` alone does NOT satisfy the analyzer's case-sensitive `\bstorage\b` grep).

## Domain Review

**Domains relevant:** Engineering (architecture/register curation). Product NONE (no UI-surface file in Files
to Edit — a single `.md` register). Legal/GDPR: assessed — the triage *catalogues* pre-existing regulated-data
invariants (BYOK consent, DSAR/storage tenancy) but introduces **no new processing activity or data-handling
change**, so the full `/soleur:gdpr-gate` is not invoked; the outcome is compliance-*positive* (naming
consent/erasure invariants that were previously uncurated). The blind-spot rule prioritises consent/erasure
surfaces per `hr-gdpr-gate`.

### Engineering (architecture-strategist)

**Status:** reviewed

**Assessment (verdicts + risks folded into the phases/ACs above):**

- **`conversations` → BR-CONV-1 + Conversation entity — ENDORSED**, with the R2 caveat: scope "owner-only write"
  to conversation-row ownership (`conversations.user_id`) and cross-reference BR-WS-3 (which supersedes migration
  075's single-owner model for *workspaces*). Same-migration collision is the one real hazard. → Phase 1, AC2.
- **`storage` → BR-STORAGE-1 — ENDORSED (adjusted):** cite migration *files* not `extract` anchors (098 quoted
  policies are blind spots, R3); resolve the Storage-entity question (R5); record the "1-real-table (promote)
  vs ~20-real-tables (leave flagged)" asymmetry so promote-`storage`/flag-`public` reads consistently. → Phase 2, AC3.
- **`public` → suppress-by-naming REJECTED; leave FLAGGED (R1/R4).** Naming "public" permanently blinds
  undocumented-table detection for the whole public schema (~20 tables collapse to one token). Treat as an
  **extraction defect**, escalate to #5871 as a correctness bug, enumerate + spot-check the collapsed set,
  and accept exit 1 as the honest residual. This is the review's substantive correction. → Phase 3, AC4/AC5.
- **Blind-spot disposition rule (b):** promote only if the blind spot introduces a principal→resource scoping,
  consent, or erasure invariant no existing BR *statement* entails; else disclose. → Phase 4, AC6.
- **Missing invariant (c):** **BYOK delegation consent/withdrawal (083/084) → `BR-BYOK-1`** (GDPR Art. 7 weight),
  plus a home for DSAR/erasure row-scoping (dsar_export_jobs / audit_byok_use, Art. 17). → Phase 4, AC6.
- **BR-ID scheme:** `BR-CONV-1` / `BR-STORAGE-1` / `BR-BYOK-1` — no collision, immutability-compliant.
- **ADR/principles:** no new ADR for the triage (dogfoods under ADR-076). The *extraction fix* implied by R1 is
  an advisory amendment to ADR-076's content-anchor convention (schema-qualifier case) via `/soleur:architecture`;
  no principles-register (AP-NNN) deviation.

### Product/UX Gate

Not applicable — Product NONE (no UI-surface file). Gate skipped.

## Sharp Edges

- **`public` is a whole-schema kill switch — NEVER write the word "public" into the register.** The undoc grep
  is a case-sensitive lowercase whole-word substring (`domain-model-drift.sh:161`, `grep -qE "\bpublic\b"`) over
  the *entire* register body, and every `public.*` anchor collapses to one `public` token. So a single occurrence
  of "public" anywhere — even inside a citation like `public.conversations` or a prose aside — permanently silences
  undocumented-table detection for ~20 real tables. Cite ADR-076 §3 **filenames** (`075_conversation_visibility.sql`),
  never schema-qualified `public.<table>` forms. AC4 asserts `grep -cwE public <register>` == 0. The `public`
  decision-record lives on #5871 + the PR body, deliberately NOT in the register.
- **Exit 0 is NOT the success criterion; exit 1 with only `public` flagged is the honest residual** (Domain Review
  R4). ADR-076 §1's idempotency guarantee is byte-identical *output*, not a green exit code. Chasing exit 0 by
  naming "public" trades a permanent detection blind spot for a cosmetic checkmark.
- **The undoc grep silences a token once the register names it as a lowercase whole-word** — this is *desired* for
  `conversations` and `storage` (each maps to exactly one real, now-documented table) but *forbidden* for `public`
  (~20 tables). A `BR-STORAGE-1`/`BR-CONV-1` ID (uppercase) alone does NOT satisfy the case-sensitive grep — the
  statement text must carry the lowercase token (`conversations`, `storage.objects`). AC2/AC3 + the case-sensitivity
  test scenario guard this.
- **The collapsed `public.*` set (~20 tables) must be enumerated + spot-checked** (Phase 0 extract) exactly like the
  blind spots — confirm each is already curated / operational-out-of-scope, and promote any material invariant
  (e.g. `BR-BYOK-1`) to a real-table BR rather than leaving it invisible behind the flagged `public` token.
- **Do not machine-touch the curated `## Business Rules` table** (ADR-076 §5): `write-row` writes ONLY to
  `## Auto-inferred (unreviewed)`. Promotion to a `BR-*` id is a deliberate human edit. AC7 asserts the curated
  table shape stays hand-authored.
- **Keep the content anchor on promotion** (`<full-migration-filename> › <table>.<object>`, ADR-076 §3) so a
  promoted row is never re-proposed by a future drift run.
- **Existence greps must not be `head`-truncated** (learning `2026-07-01-existence-grep-must-not-be-head-truncated.md`):
  the #5754 plan falsely called `resolveActiveWorkspace` a stale citation because `| head -3` hid its definition at
  line 398. AC1 re-verifies with a non-truncated `grep -n`.
- **Fixing the extractor is out of scope** — the schema-inconsistent `public` collapse is real, but it belongs to
  #5871's follow-up. Record it as soak evidence; do not edit the analyzer here.
- **`Closes #5882` is fine** (not an ops-remediation; no post-merge apply). But #5871's soak comment uses `Ref`-style
  linkage, not `Closes` (#5871 stays open — it is the recurring re-evaluation).
