---
date: 2026-05-25
feature: attachments-rls-bundle-pr2-4318
plan: knowledge-base/project/plans/2026-05-25-feat-attachments-workspace-shared-pr2-plan.md
status: phase-0-complete; awaiting CPO sign-off on R-1/R-3/R-5 + new emergent finding (E-1) before Phase 2
---

# Phase 0 Worklog — PR-2 attachments workspace-shared

Empirical results for plan §Phase 0 PROBE-A..D + 0.3 R-9 spike + 0.4 column-type + 0.5 foldername edge cases. All probes run 2026-05-25.

## Probes summary

| Probe | Source | Result | Verdict |
|---|---|---|---|
| **PROBE-A** | `SELECT COUNT(*) FROM public.messages WHERE workspace_id IS NULL` via Doppler `DATABASE_URL_POOLER` against **prd** | `0` | **PASS** — cascade RPC does NOT need `AND m.workspace_id IS NOT NULL` filter |
| **PROBE-B** | `SELECT COUNT(*) FROM storage.objects WHERE bucket_id='chat-attachments' AND ((storage.foldername(name))[2] IS NULL OR (storage.foldername(name))[2] !~ '^[0-9a-f-]{36}$')` against prd | `0` | **PASS** — no rows become invisible post-mig-068 |
| **PROBE-C** | `ls apps/web-platform/supabase/migrations/068_*.sql` + `git ls-tree origin/main` last prefix | last = `067`; slot 068 free locally + on origin/main | **PASS** |
| **PROBE-D** | `grep -rni "CREATE TRIGGER" apps/web-platform/supabase/migrations/` filtered for `messages` | no `BEFORE/AFTER UPDATE` trigger targets `public.messages` | **PASS** — no WORM carve-out needed in cascade RPC |
| **OQ1 (bonus)** | total prd object count + segment-1 shape audit | 5 total objects, 0 malformed segment-1 (OQ5 also clean) | jikigai-only baseline, as expected |
| **0.4** (column type) | grep `messages` schema across migrations | `messages.user_id` is `uuid REFERENCES auth.users(id) ON DELETE CASCADE` (added in mig 046:93) | **see Emergent Finding E-1 below** |
| **0.5** (foldername edge cases) | run via dev pooler | empty→NULL; `'a'`→`[]`; `'a/'`→`["a"]`; `'a/b/c.png'`→`["a","b"]`; `'a/../b'`→`["a",".."]` (no normalization); `NULL ~ regex` → NULL; `NULL AND true` → NULL (deny) | **PASS** — predicate fails closed |
| **R-9 spike** | DRAFT mig 068 (helper + split policy) applied to dev under `BEGIN; ... ROLLBACK;` via session-mode pooler; tenant JWTs simulated via `SET LOCAL request.jwt.claims` + `SET LOCAL ROLE authenticated` | see §R-9 below | **PASS** — SECURITY DEFINER helper resolves from storage policy context |

## R-9 spike — empirical results

Fixture topology: 2 workspaces (W1, W2), 1 organization, 3 users (Alice ∈ W1 owner, Bob ∈ W2 owner, Carol initially unaffiliated), 1 conversation per workspace owned by the workspace owner, 1 `storage.objects` row per workspace at path `{ownerUuid}/{convId}/r9spike-test-*.png`.

| Test case | Expected | Actual | Verdict |
|---|---|---|---|
| Alice tenant JWT — sees Alice's W1 attachment via own-folder branch | 1 row | 1 row | ✓ |
| Bob tenant JWT — sees Bob's W2 attachment; does NOT see W1 | 1 row, no W1 | 1 row, no W1 | ✓ |
| Carol tenant JWT (no membership) — sees nothing | 0 rows | 0 rows | ✓ |
| Carol added as W1 co-member → tenant JWT now sees W1's attachment via co-member branch | 1 row (W1) | 1 row (W1) | ✓ |
| Helper invocation under postgres: `is_attachment_path_workspace_member(convW1, alice) = true; (convW2, alice) = false; (NULL, alice) = false; (convW1, NULL) = false` | matches plan | matches | ✓ |

Per-test data preserved at `/tmp/pg-runner/r9-spike.js` for reproducibility. All work was wrapped in `BEGIN; ... ROLLBACK;` against the dev pooler (session-mode port 5432); nothing persists in dev.

**Plan implication**: R-Risk-1's fallback ("inline the helper logic into the storage policy body — lose the abstraction, keep semantics") is **NOT required**. The plan's Phase 2 helper design ships as-drafted.

## Emergent Finding E-1 — Phase 4 pseudonym design is unworkable as drafted

Surfaced by 0.4 (column-type verification). Touches Reconciliation R-7, Sharp Edges §5, AC5(a), Phase 4 SQL body.

### Evidence

1. **`messages.user_id` is `uuid REFERENCES auth.users(id) ON DELETE CASCADE`** (mig 046:93). The column comment at mig 046:101–105 reads: *"Direct founder ownership for tier-routed messages with no conversation thread… NULL for legacy conversation-bound rows whose ownership is reached via `conversations.user_id`."*
2. The plan's drafted cast `('member_' || encode(gen_random_bytes(6), 'hex'))::uuid` is **invalid** — a string like `'member_abcdef012345'` is not a valid uuid (uuids are 32 hex chars in 8-4-4-4-12 form).
3. The plan's Sharp Edges fallback (`uuid_generate_v5` on a deterministic tuple) produces a structurally valid uuid but **violates the FK to `auth.users(id)`**: no synthetic uuid will have a matching `auth.users` row, so the UPDATE will fail with `foreign key violation`.
4. **Codebase convention**: existing anonymise RPCs set `user_id = NULL`. Verified at:
   - `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql:226` (`anonymise_action_sends`)
   - Pattern repeats in mig 048 (`anonymise_scope_grants`), mig 044 (`anonymise_tc_acceptances`), mig 053 (`anonymise_template_authorizations`).

### Proposed redesign

`_anonymise_authored_messages_internal(p_user_id, p_workspace_id)` UPDATEs `SET user_id = NULL` (no pseudonym mint). Consequences:

- **Reconciliation R-7 collapses**: salt-lifecycle decision becomes moot (no pseudonym to salt).
- **Sharp Edges §5 collapses**: pseudonym cast issue dissolves; no `uuid_generate_v5` fallback needed.
- **AC5(a) wording shifts**: assertion changes from *"departing user's user_id no longer appears on shared-conv messages with attachments"* to *"`user_id IS NULL` on shared-conv messages with attachments authored by the departing user"*.
- **UX uploader-attribution follow-up**: identity for "former member" messages must be reconstructed via `workspace_member_removals` (mig 062) joined to the message's conv + timestamp window, NOT via a per-row pseudonym stamp. This is a stronger join (covers ALL removed members consistently) but requires more UI plumbing — the follow-up issue's brief should be amended.
- **Plan §Phase 4 RPC body**: the `UPDATE public.messages SET user_id = ('member_'…)::uuid …` block (and the `Pre-Phase-4 verify column type` comment block) become `UPDATE public.messages SET user_id = NULL …`.
- **PA-2 §(g)(10) prose**: drops the `member_<hex12>` framing; substitutes "uploader identity nulled at cascade time; former-member attribution available via `workspace_member_removals` ledger".

### CPO/CTO sign-off ask

The pseudonym change is materially equivalent for Art. 17 erasure outcome (PII unreachable from the message row). The UX shift (per-row stamp → cross-table join for uploader-attribution) is a design tax on the follow-up issue, not on PR-2.

**Routing**: CPO + CTO need to acknowledge:
1. Original R-1/R-3/R-5 reconciliation table (per `requires_cpo_signoff: true` in plan frontmatter).
2. **NEW**: E-1 redesign (NULL-not-pseudonym for `messages.user_id` cascade; UX uploader-attribution follow-up brief amended).
3. OQ#3 deferral as blocking-pre-flag-flip issue.

Once acked, Phase 2 begins (mig 068 body + down.sql + presign/url route widening + cascade RPCs with NULL-pseudonym shape).

## Run artifacts

- `/tmp/pg-runner/probe-ab.js` — PROBE-A, PROBE-B, OQ1, OQ5, 0.4, 0.5 probe runner (read-only, single-query)
- `/tmp/pg-runner/r9-spike.js` — R-9 spike (transactional; DRAFT helper + split policy + fixtures + 4 tenant-JWT visibility tests + ROLLBACK)
- `/tmp/pg-runner/r9-debug.js` — auth.uid() simulation verification (used to debug initial path-shape bug)

(/tmp paths are operator-local; the DRAFT mig 068 SQL inside r9-spike.js is reproduced verbatim from the plan's Phase 2 section so it can be regenerated.)
