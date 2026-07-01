---
title: "Tasks — dogfood domain-model drift analyzer & triage into register (#5882)"
issue: 5882
branch: feat-one-shot-5882-domain-model-drift-triage
lane: procedural
plan: ../../plans/2026-07-01-chore-dogfood-domain-model-drift-triage-plan.md
---

# Tasks — #5882 domain-model drift triage

> Derived from `2026-07-01-chore-dogfood-domain-model-drift-triage-plan.md` (post Engineering domain review).
> No spec.md preceded this plan; `lane: procedural` is the plan author's classification (solo engineering
> register-curation, not cross-domain). Register = `knowledge-base/engineering/architecture/domain-model.md`.
>
> **North star:** intended residual is `Undocumented (1) — public`, **exit 1** (not 0). NEVER write the word
> "public" into the register — it silences the whole-schema guard.

## Phase 1 — Preconditions & evidence (read-only)

- [ ] 1.1 Run `bash scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md`; archive the exact output (expect exit 1: stale 0, undoc 3, blind 47).
- [ ] 1.2 Confirm stale = 0 with a **non-truncated** grep: `grep -n "resolveActiveWorkspace" apps/web-platform/server/workspace-resolver.ts` shows the definition at line 398 (NO `| head`).
- [ ] 1.3 Capture triage evidence: `bash scripts/domain-model-drift.sh extract --repo . | jq '.facts, .blind_spots'`; enumerate the collapsed `public.*` set + the 47 blind-spot files/details.
- [ ] 1.4 Confirm the 3 tokens are absent as lowercase whole-words: `for t in conversations public storage; do grep -cwE "$t" <register>; done` → `0 0 0`.

## Phase 2 — Triage `conversations` → BR-CONV-1

- [ ] 2.1 (Recommended, `conversations`-only) Exercise `write-row --anchor "075_conversation_visibility.sql › conversations.conversations_owner_select" --statement "<candidate>"` to populate `## Auto-inferred (unreviewed)`; **verify exactly one row landed** (a repeat call dedups to a no-op → vacuous soak evidence). `storage` has no extract anchor (098 policies are blind spots) → BR-STORAGE-1 is hand-authored, no write-row demo.
- [ ] 2.2 Human-promote: add curated `BR-CONV-1` to `## Business Rules` + a `Conversation` entity row (key `conversations.id`) to `## Entities`; remove the Auto-inferred row (keep the content anchor).
- [ ] 2.3 **R2 guard:** scope "owner-only write" to `conversations.user_id`; cross-reference BR-WS-3 so BR-CONV-1 does not reintroduce the retired single-owner *workspace* model. Cite `075_conversation_visibility.sql` (+032/017/041) by ADR-076 §3 anchors.
- [ ] 2.4 Ensure the statement carries the lowercase whole-word `conversations`.

## Phase 3 — Triage `storage` → BR-STORAGE-1

- [ ] 3.1 Add curated `BR-STORAGE-1` (storage-object workspace/tenant tenancy) citing migration *files* 019/042/068/071/098 (NOT extract anchors — 098 quoted policies are blind spots, R3).
- [ ] 3.2 **R5:** resolve + record the Storage-entity question (add a `Storage object` entity OR declare `storage.objects` Supabase-managed infra); record the "1-table (promote storage) vs ~20-tables (flag public)" asymmetry rationale.
- [ ] 3.3 Ensure the statement carries the lowercase whole-word `storage` (e.g. `storage.objects`).

## Phase 4 — Triage `public` → LEAVE FLAGGED (extraction defect)

- [ ] 4.1 **Do NOT write "public" into the register** (would silence the whole-schema guard). Keep all citations to filenames, never `public.<table>` forms.
- [ ] 4.2 Enumerate the collapsed `public.*` set; spot-check each for a material access/tenancy invariant not already curated; record the per-table disposition on #5871/PR body.
- [ ] 4.3 Escalate to #5871 as a **correctness bug**: `gh issue comment 5871` recording (a) the schema-qualifier collapse + blast radius, (b) manual-triage cost, (c) `public` deliberately left flagged pending the extractor fix. `Ref #5882`; #5871 stays open.
- [ ] 4.4 (Advisory, optional) note the schema-qualifier known-limitation as an amendment to ADR-076 via `/soleur:architecture` — the fix itself is #5871's scope.

## Phase 5 — Blind-spot spot-check (47)

- [ ] 5.1 Group the 47 blind spots (43 dynamic SQL / 3 quoted-name policy / 1 SECURITY DEFINER) by file/detail.
- [ ] 5.2 Apply the disposition rule (promote only if a new principal→resource scoping / consent / erasure invariant no existing BR entails): 111/102 email_triage → disclose (BR-WS-2); 110 comember_reconcile → disclose (BR-WS-3); 079/080 workspace_repo → BR-REPO-1 (extend citation if it adds a transfer invariant).
- [ ] 5.3 **Promote byok_delegation (083/084) → `BR-BYOK-1`** (consent-gated, withdrawable; GDPR Art. 7). Cite `083_byok_delegation_consent_gate.sql` / `084_byok_delegation_withdrawals.sql`.
- [ ] 5.4 Give DSAR/erasure row-scoping (`dsar_export_jobs` / `audit_byok_use`, Art. 17) a curated home or record why not.
- [ ] 5.5 Record confirmation that no remaining spot-checked blind spot hides an un-named material invariant.

## Phase 6 — Re-run, idempotency, verification

- [ ] 6.1 Re-run `drift` with explicit exit-code capture (`… > /tmp/drift.out; rc=$?; [ "$rc" -eq 1 ]`) so the intended non-zero is read as success not failure (`hr-when-a-command-exits-non-zero-or-prints`): confirm stale 0, **undocumented 1 (`public`)**, `rc == 1`, blind 47 — the intended residual. `rc == 0` = FAILURE (public leaked → AC4); `rc == 2` = source-not-analyzable.
- [ ] 6.2 Re-run a second time; confirm byte-identical output (`diff` of two captures empty). Idempotency = byte-identical output, NOT exit 0.
- [ ] 6.3 Confirm `## Auto-inferred (unreviewed)` is empty (demo row promoted, not stranded); `## Business Rules` shape hand-authored (no machine-edit).
- [ ] 6.4 Verify ACs: AC4 `grep -cwE public <register>` == 0; AC8 `grep -oE 'BR-[A-Z]+-[0-9]+' <register> | sort | uniq -d` empty; AC9 #5871 comment filed.

## Phase 7 — Ship

- [ ] 7.1 PR body embeds the before/after drift output + the per-token triage decisions + the collapsed-`public` disposition; `Closes #5882`, `Ref #5871`.
- [ ] 7.2 Run `/soleur:ship` lifecycle (commit register + plan/tasks artifacts, capture learnings).
