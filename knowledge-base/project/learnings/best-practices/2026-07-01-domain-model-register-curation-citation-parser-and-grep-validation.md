# Learning: curating the domain-model register — the citation parser cross-products backticked tokens, and BR prose must be grep-validated against the migration body

**Date:** 2026-07-01
**Context:** #5882 — first real dogfood of the `/soleur:sync domain-model` drift analyzer (ADR-076, shipped #5754). Triaged the 3 undocumented tokens (`conversations`, `storage`, `public`) into `knowledge-base/engineering/architecture/domain-model.md`.

## Problem

Promoting drift findings into curated `BR-*` rows looks like plain markdown editing, but three non-obvious traps bit in one session — all invisible to `tsc`/unit tests and only caught by re-running the analyzer + multi-agent review.

## Key insights

### 1. The stale-citation parser cross-products EVERY backticked `.sql`/`.ts` file × EVERY backticked bare identifier on the same table row

`dm_register_code_citations` (`scripts/lib/domain-model-lib.sh`) collects all backticked tokens on a `^|` row, buckets them into `files` (ending `.ts/.tsx/.sql`) and `syms` (matching `^[A-Za-z_][A-Za-z0-9_]*$`), then emits a citation for the **full cross-product** and greps each file for each symbol. So a BR row that backticks a migration filename **and** an unrelated identifier (`is_workspace_member`, `authenticated`, `user_id`) fabricates false "stale citation" drift (I self-inflicted 8).

**Rule:** cite migration files as **unbackticked prose** (`migration 075_conversation_visibility.sql`, matching the existing `migration 053` convention). Reserve backticked-`.sql` + backticked-identifier on the same row for a REAL (file → symbol-defined-in-file) citation, exactly like BR-WS-2's `workspace-resolver.ts` → `resolveActiveWorkspace`. Tokens containing `.`/`=`/spaces/parens (`conversations.id`, `ON DELETE SET NULL`) are ignored by the parser, so they stay safe backticked.

### 2. Register prose making claims about migrations must be grep-validated against the migration BODY, not authored from the plan's conceptual framing

This is the "legal-disclosure prose hallucinated against the migration" defect class ([[2026-05-23-legal-disclosure-prose-must-be-grep-validated-against-actual-migration]]) applied to the domain-model register. Four claims I wrote from the plan's narrative were wrong until security-sentinel cross-checked each against the SQL:
- Art. 17 erasure "sets the owner user id to NULL" → actually the anonymise RPC scrubs `requester_ip`/`user_agent`; `user_id` de-links via `ON DELETE SET NULL` (a different mechanism).
- storage.objects writes "are REVOKE'd" → migrations 068/098 CREATE authenticated own-folder/owner write policies (RLS-scoped, not REVOKE'd).
- Conversation entity cited `ADR-076 §3` → ADR-076 is the drift-extraction ADR (renumber artifact); the source is migration 075 / #4521.

**Rule:** for each factual claim in a promoted BR row, open the cited migration and confirm the column name / policy semantics / REVOKE target / ON DELETE behavior / GDPR article. A claim-by-claim drift table is the cheapest gate.

### 3. The `public` token is a whole-schema kill switch; the flagged bare token can come from a DIFFERENT anchor than you expect

The undoc check derives the token from the pre-dot segment of a `schema.table` anchor, so ~48 real `public.*` tables collapse to one `public` token — naming "public" anywhere in the register silences whole-schema detection forever. Leave it flagged (exit 1 is the intended residual); escalate the schema-qualifier-strip fix to #5871. Also: the flagged `conversations` token comes from 017/041 CHECK-constraint anchors (bare `conversations.<constraint>`), NOT the 075 RLS policies (which are `public.conversations.*` and collapse into `public`). Verify the actual anchor via `extract` mode before choosing a `write-row --anchor` — the plan's suggested anchor was wrong and contained a `public.` that would have leaked.

## Session Errors

1. **Write targeted main checkout instead of worktree** (plan phase, forwarded) — Recovery: corrected to worktree path. Prevention: CWD-verify first tool call (already in one-shot Step 0).
2. **Stale-read Edit race during review-fold** (plan phase, forwarded) — Recovery: re-read before dependent edits. Prevention: re-read after any concurrent writer.
3. **Plan's write-row anchor wrong (public-collapse + wrong source)** — Recovery: used `extract` to find the real 017 bare-`conversations` anchor. Prevention: insight #3 — verify anchors against `extract` output, never trust plan-quoted anchors (mirrors `hr-when-a-plan-specifies-relative-paths-e-g`).
4. **8 self-inflicted false stale-citations from backticked filenames** — Recovery: unbacktick filenames; re-ran drift to 0 stale. Prevention: insight #1.
5. **4 accuracy bugs in BR prose caught at review** — Recovery: grep-validated each against the migration and fixed inline. Prevention: insight #2.
6. **Register modified on disk between reads (stale `old_string`)** — Recovery: re-grepped the row verbatim. Prevention: re-read a row before editing after `write-row`/prior edits touched the file.
7. **tasks.md AC8 grep false-flags `see BR-WS-3` cross-refs as dup IDs** — Recovery: anchored the dup-ID grep to row-leading IDs (`^\| BR-...`). Prevention: dup-ID checks over a register must anchor to definition rows, since cross-references legitimately repeat IDs.

## Tags
category: best-practices
module: domain-model-register / scripts/domain-model-drift.sh
related: #5882, #5871, #5754, ADR-076
