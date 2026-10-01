---
title: "Counsel review audit — #8918 / PR #9115 (`public.pending_checkout_sessions`, migration 144: server-side checkout idempotency; DPD §5.3(a) exclusion-list entry, GDPR §8.4 retention paragraph, Privacy Policy amended line, compliance-posture ledger row, three Eleventy mirrors, SHA repin, DSAR exclusion)"
type: counsel-review
date: 2026-09-28
issue: 8918
pr: 9115
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-28
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to TWO in-PR corrections (C1–C2, below) that the lead applies before merge. Seven legal surfaces in scope: the three published canonical docs + their Eleventy mirrors, the compliance-posture ledger row, the SHA pin file, and the DSAR exclusion entry. Every implementation claim was checked against the shipped bodies (migration 144 up/down, the post-apply verify sentinel, `app/api/checkout/route.ts`, `app/api/webhooks/stripe/route.ts`, `.service-role-allowlist`), not against the plan alone. The 'no new processing activity' determination is SOUND — the claim row is contract-necessity bookkeeping under existing PA-3 (Subscription & Billing); Stripe and Supabase are already the recorded processors and no new recipient, purpose, or Chapter V transfer arises. Two corrections, neither changes a conclusion: (C1) the GDPR §8.4 paragraph leaves a double blank line before '### 8.5' in BOTH canonical and mirror — MD012 over the tracked corpus; collapse and repin the gdpr-policy SHA. (C2) `article-30-register.md` is silent on the new user-keyed table under PA-3 while the plan's encryption-posture block names the register's billing entry as this store's disclosure surface (`disclosed_as`), and the two closest precedents (denied_jti in PA-1 §(c); statutory_repin_send in PA-27 limbs (c)/(f)/(g)) recorded the sibling table in-cell — append the PA-3 markers, deploy-conditioned."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — MD012: collapse the double blank line between the new pending-checkout paragraph and '### 8.5 Third-Party Retention' to a single blank line in docs/legal/gdpr-policy.md (line ~581) and plugins/soleur/docs/pages/legal/gdpr-policy.md (line ~572); then re-run sha256sum on the canonical file and repin the 'gdpr-policy' entry in apps/web-platform/lib/legal/legal-doc-shas.ts (the canonical SHA changes)."
  - "C2 — Record `pending_checkout_sessions` in-cell in PA-3 (Subscription & Billing) §(c) Categories of personal data and §(f) Retention in knowledge-base/legal/article-30-register.md, conditioned on deployment of migration 144 ('takes effect on deployment of migration 144' — the #6781 statutory_repin_send form). Suggested text under §Conditions."
optional_precision_notes:
  - "O1 — '≤24h stranded bound' (posture row; migration comment's '24h sweep bounds retention'): the cron predicate is created_at < now() - 24h on a daily schedule, so a stranded row's worst-case lifetime is ~48h (24h predicate + one sweep interval). The PUBLISHED phrasings ('daily 24-hour sweep', 'swept daily past 24 hours') are descriptively accurate — only the internal '≤24h bound' shorthand is over-tight. Non-blocking."
  - "O2 — The published enumerations ('a Stripe session id, the tier you selected, and a timestamp') omit the `user_id` PK as a named held datum; 'a per-user dedup marker' conveys the keying, and the ledger's 'no personal data beyond the keying user id' is the precise formulation. Non-blocking."
  - "O3 — The #6781 published entries carried '*effective on deployment of migration 135*'; this PR's published amended lines carry no deployment caveat. The table exists only post-deploy; adding the caveat would match the strongest precedent, but the inbox_item (#6007) entry omitted it and migrations apply on the normal deploy path. Recommended, not conditioned."
  - "O4 — The `.service-role-allowlist` additions are voluntary disclosure: the gate (`apps/web-platform/scripts/service-role-allowlist-gate.sh`) sweeps `server/` + `lib/` only; `app/api/**/route.ts` was scoped to a later PR-C. Adding both billing call sites anyway is the CODEOWNERS-pinned disclosure working as intended. Informational."
attests:
  - "docs/legal/data-protection-disclosure.md — the 2026-09-28 Amended block and the `pending_checkout_sessions` item appended to the §5.3(a) 'Excluded from the export, with reason' list"
  - "docs/legal/gdpr-policy.md — the 2026-09-28 Amended block and the §8.4 pending-checkout retention paragraph, as corrected by C1"
  - "docs/legal/privacy-policy.md — the 2026-09-28 Amended block"
  - "plugins/soleur/docs/pages/legal/{data-protection-disclosure,gdpr-policy,privacy-policy}.md — the same three additions on the published mirrors (gdpr-policy as corrected by C1)"
  - "knowledge-base/legal/compliance-posture.md — the 2026-09-28 (#8918) ledger entry"
  - "apps/web-platform/lib/legal/legal-doc-shas.ts — the three repinned SHAs (verified byte-exact against sha256sum of the canonical files)"
  - "apps/web-platform/server/dsar-export-allowlist.ts — the `pending_checkout_sessions` entry in DSAR_TABLE_EXCLUSIONS (the lockstep trigger)"
does_not_attest:
  - "supabase/migrations/144_pending_checkout_sessions.{sql,down.sql}, supabase/verify/144_pending_checkout_sessions.sql, app/api/checkout/route.ts, app/api/webhooks/stripe/route.ts, the new tests, and the concurrency-modal copy change (technical controls; counsel attests the records' statements about them, not their correctness)"
  - "knowledge-base/project/plans/2026-09-28-fix-billing-checkout-server-idempotency-plan.md, the spec session-state/tasks files, and the row-identity learning (engineering records; the plan's disclosed_as pointer is relied upon only as evidence of intended disclosure surface for C2)"
  - "apps/web-platform/.service-role-allowlist diff (operational record; consistent with the table's service-role-only posture)"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "(1) C1/C2 land before merge: this attestation is written against the corrected text; re-read after the corrections commit. (2) Schema drift: any column added to `pending_checkout_sessions` that carries user-supplied content (or `client_secret`/another bearer capability) re-opens the 'operational bookkeeping' characterization and the Art. 5(1)(c) minimization finding. (3) Retention control failure: `pending_checkout_sessions_retention` unscheduled, disabled, or erroring post-deploy makes the published 24h-sweep statements false — the verify sentinel asserts scheduling post-apply; an operational miss re-opens the §8.4/§5.3(a) retention claims. (4) A `user_id`-keyed row surviving >24h+one-sweep at scale would contradict 'transient'; the dsar completeness sentinel (`test/dsar-allowlist-completeness.test.ts`) keeps the exclusion classification mandatory for any future table change. (5) Standing external-counsel triggers: first arm's-length user, an affected data subject outside the EEA, a regulated-industry tenant."
---

# Counsel review audit — #8918 / PR #9115 (pending_checkout_sessions, migration 144)

This file is the evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on PR #9115
(issue #8918). The gate fired on the `docs/legal/**` amendments, the `knowledge-base/legal/` ledger
entry, and the DSAR exclusion they disclose. The brand-survival threshold is `single-user incident`.
The CLO agent is the v1 attestation authority; the operator holds an optional veto.

## Scope and limit check

- **Append-only discipline holds on the ledger.** `git diff --word-diff=porcelain
  origin/main...HEAD` over `knowledge-base/legal/compliance-posture.md` and the six legal-doc
  surfaces shows exactly three deleted tokens: `2026-09-18` (the posture `last_updated` bump) and
  `schedule).` ×2 (the §5.3(a) exclusion list's running enumeration, edited in place to append the
  new item — canonical + mirror; a running list, not a register cell, so in-place append is the
  established pattern). The posture entry is prepended as a dated `<!-- -->` ledger comment.
- **The public surface is engaged.** `docs/legal/{data-protection-disclosure,gdpr-policy,
  privacy-policy}.md` + all three mirrors are edited. The #7387 gates were run locally:
  `lint-legal-scope-block-placement.sh --base origin/main` → 0 scope blocks, 0 violations;
  `lint-legal-mirror-drift-baseline.sh --base origin/main` → 9 pairs, drift within baseline;
  `check-tc-document-sha.sh` (repo root) → exit 0, all pins match (verified independently with
  `sha256sum`). `EXPECTED_COUNT=9` = 9 canonical docs. Heading-sequence parity unaffected (no
  headings added or removed).
- **markdownlint over the changed files FAILS on two lines** — MD012 double blank line before
  `### 8.5` in canonical and mirror gdpr-policy → C1.
- **No `[DRAFT — pending CLO` markers** in the legal diff (the one match is session-state prose
  saying no markers were added).
- **Merge-conditioning.** The posture ledger describes the PR's content in changelog form
  (consistent with every prior row). The published amendments carry no deployment caveat — see O3.
- **Citations by name, not by line** throughout the reviewed records (`pending_checkout_sessions`,
  `pending_checkout_sessions_retention`, `STALE_NULL_MARKER_MS`, migration 144).
- **Production untouched.** No supabase/stripe/terraform/gh write was run. Reads + local lints only.

## Drift table

| # | Claim | Checked against | Verdict |
|---|---|---|---|
| D1 | Columns: `user_id` (PK, FK `public.users(id)` ON DELETE CASCADE), `session_id`, `target_tier` NOT NULL CHECK-pinned to four PlanTiers + 'legacy', `created_at` | migration 144 `CREATE TABLE`; `VALID_TARGET_TIERS` = ["solo","startup","scale","enterprise"]; `LEGACY_TIER_SENTINEL` | **Holds** |
| D2 | RLS enabled, zero policies (service-role-only) | migration `ENABLE ROW LEVEL SECURITY`, no `CREATE POLICY`; verify sentinel `zero_rls_policies` | **Holds** |
| D3 | Art. 17 erasure = ON DELETE CASCADE from `public.users` | FK `confdeltype='c'`; verify sentinel `users_fk_cascade` | **Holds** |
| D4 | Deleted on checkout completion and expiry | webhook `checkout.session.completed` and `checkout.session.expired` arms each run `.from("pending_checkout_sessions").delete().eq("session_id", …)` | **Holds** |
| D5 | Route reclaim deletes: terminal-session reclaim, different-tier expire-then-reclaim, stale null marker past `STALE_NULL_MARKER_MS` (90s), `releaseClaim` on create/record failure | `app/api/checkout/route.ts` marker-hit path and helpers | **Holds** |
| D6 | Daily 24h retention sweep exists and ships WITH the table | `cron.schedule('pending_checkout_sessions_retention','0 4 * * *', DELETE WHERE created_at < now() - interval '24 hours')`; verify sentinel `retention_cron_scheduled`; 094 cron-block precedent confirmed | **Holds** |
| D7 | "Operational bookkeeping only" / "no personal data beyond the keying user id" | Column set is session_id (opaque Stripe id) + enumerated `target_tier` + `created_at` on a `user_id` PK; `client_secret` deliberately NOT persisted (migration LAWFUL_BASIS comment — Art. 5(1)(c)) | **Holds** (O2) |
| D8 | Art. 6(1)(b) contract necessity | Row exists solely to provision the subscription the user initiated (dedup of `stripe.checkout.sessions.create`); sits inside PA-3's recorded basis | **Holds** |
| D9 | "No new processing activity, lawful basis, recipient, sub-processor, or third-country transfer — Stripe was already the recorded payments processor" | PA-3 §(d) Stripe Inc processor; §(e) US transfer w/ EU-US DPF + SCC; Supabase recorded processor | **Holds** — but the register records nothing about the table under PA-3 → C2 |
| D10 | Excluded from the Art. 15 export, with reason published | `DSAR_TABLE_EXCLUSIONS.pending_checkout_sessions`; DPD §5.3(a) list item in canonical + mirror; `dsar-allowlist-completeness.test.ts` requires every user-keyed table classified | **Holds** |
| D11 | Repinned SHAs match canonical bytes | `sha256sum docs/legal/*.md` vs `LEGAL_DOC_SHAS`: DPD `30eba235…`, GDPR `d69b1e61…`, privacy `5b690fff…` — all three exact | **Holds** (re-verify after C1) |
| D12 | Mirrors carry the identical additions | mirror diffs: same Amended blocks, same §5.3(a) item, same §8.4 paragraph | **Holds** |
| D13 | TC_VERSION unchanged appropriate; Tier-1 classification | No T&C edit; `check-tc-document-sha.sh` green; matches the house footer phrasing | **Holds** |
| D14 | Amended-block placement + house phrasing | All six surfaces insert `**Amended:** September 28, 2026` after the Sep-23 Corrected block, before the doc body; each carries Tier-1 classification + draft-review footer | **Holds** |
| D15 | "Stripe embedded sessions self-expire by then" (§8.4) | Stripe Checkout sessions self-expire ~24h; the route relies on this plus the reclaim paths | **Holds** |
| D16 | Posture ledger facts: cron shipped with the table (094 precedent, not deferred); verify sentinel asserts RLS+CASCADE+cron post-apply; `.service-role-allowlist` gained the two billing call sites (CODEOWNERS-pinned) | migration 094 cron-block precedent confirmed; verify file's four checks; allowlist +2 paths; `.github/CODEOWNERS` pins the file to @deruelle | **Holds** (O4) |
| D17 | No lint regression on edited legal files | `npx markdownlint-cli` over the seven edited files → MD012 ×2 (canonical :581, mirror :572) | **FAILS → C1** |
| D18 | Register disclosure surface exists for this store | plan `disclosed_as`: "article-30-register.md billing processing entry"; `grep pending_checkout article-30-register.md` → 0 | **Empty pointer → C2** |
| D19 | "≤24h stranded bound" | Cron predicate >24h on a daily schedule → worst case ~48h | **Over-tight shorthand → O1** |
| D20 | No past-tense claim that the table exists pre-deploy | posture entry describes PR content; published entries are present-tense disclosures without deployment caveat | **Holds** (O3) |

## Findings

- **F1 (C1): MD012 in both GDPR surfaces.** The new §8.4 paragraph is followed by two consecutive
  blank lines before `### 8.5` in `docs/legal/gdpr-policy.md:581` and its mirror at `:572`.
  `pr-quality-guards.yml` runs markdownlint over the whole tracked corpus — this reds CI. Fix is a
  one-line deletion in each file plus a re-pin of the `gdpr-policy` SHA (the canonical bytes
  change). Mechanical; does not touch prose.
- **F2 (C2): the Art. 30 register is silent on a new user-keyed table under PA-3.** The "no new PA"
  determination itself is sound (D9). But Art. 30(1)(c)/(f) ask for categories and retention per
  activity, and `pending_checkout_sessions` introduces a `user_id`-keyed Stripe `session_id` —
  a datum class PA-3 §(c) does not enumerate — with a lifecycle §(f) does not describe. The two
  closest precedents recorded the sibling table in-cell under the existing PA: `denied_jti` sits in
  PA-1 §(c); `statutory_repin_send` (#6781) amended PA-27 (c)/(f)/(g) in lockstep — and that table
  carried NO `user_id` at all, so a fortiori a user-keyed table warrants the same. Counter-
  precedents exist (`worktree_write_lease` — no personal data; the mint tables — an earlier gap,
  plausibly #7349-class), but the decisive fact is internal: **the plan's own encryption-posture
  block declares "article-30-register.md billing processing entry" as this store's
  `disclosed_as`** — the register is the record the plan points to, and it currently points at
  nothing. An in-cell, deploy-conditioned marker resolves it. Append-only, cheap, consistent.
- **F3: the Art. 15 exclusion ground is honest — and deliberately not the "impersonal" ground.**
  The row IS personal data under Art. 4(1) (keyed to an identified user; the tier is that user's
  own selection). The exclusion is nonetheless defensible: the row is transient (deleted on
  completion/expiry/reclaim; stranded bound via the daily sweep), its only novel datum is an opaque
  Stripe identifier, and the durable record it gates is already exported (`users` subscription
  state + Stripe IDs) and held by the processor of record. The §5.3(a) item was correctly written
  as a STANDALONE exclusion with its own reason rather than folded into the "operational
  concurrency tables (transient runtime state, not personal data)" parenthetical — which would
  have asserted impersonality the table does not have. The stated ground (transient bookkeeping;
  durable record exported) is the right one.
- **F4: no lawful-basis, purpose, recipient, or transfer change.** Art. 6(1)(b) applies — the
  marker exists to perform the purchase contract the user initiated. Stripe and Supabase are
  already PA-3's recorded processors; the US transfer safeguard stack (DPF + SCC Module 2) is
  already recorded at PA-3 §(e). Data minimization is respected: `client_secret` (a bearer
  capability) is deliberately never persisted — reuse re-reads it from Stripe.
- **F5: every deletion-path claim in the legal text is true of the code.** (a) webhook delete on
  `checkout.session.completed`; (b) webhook delete on `checkout.session.expired`; (c) route reclaim
  delete on a terminal (complete/expired) retrieved session; (d) route expire-then-reclaim on an
  open different-tier session; (e) route reclaim of a null-`session_id` marker past
  `STALE_NULL_MARKER_MS` (90s, deliberately above stripe-node's 80s default timeout); (f)
  `releaseClaim` on create/record failure; (g) daily `0 4 * * *` cron deleting rows older than 24h.
  All writes are generation-fenced on row identity (`created_at`/`session_id`), never bare
  `user_id` — the ABA protection the posture row claims.
- **F6: no Art. 33/34 trigger.** A new table with no live data and a money-path correctness fix;
  nothing destroyed, lost, altered, or disclosed (Art. 4(12)). No breach-register row required.
- **F7: the non-truth gates are green.** Scope-block gate 0/0; mirror-drift ratchet within baseline
  (the additions are paired on both surfaces); SHA guard passes; `EXPECTED_COUNT=9` unchanged. Per
  #7349, gates measure agreement not truth — the D-rows above are the truth check.

## Conditions

Two corrections. Both are in-PR text; each anchor was verified unique with `grep -cF`.

**C1 — `docs/legal/gdpr-policy.md` and `plugins/soleur/docs/pages/legal/gdpr-policy.md`:**
delete one of the two blank lines between the paragraph ending `…(Data Protection Disclosure,
Section 5.3(a)).` and the heading `### 8.5 Third-Party Retention`, leaving exactly one blank line.
Then `sha256sum docs/legal/gdpr-policy.md` and repin the `"gdpr-policy"` entry in
`apps/web-platform/lib/legal/legal-doc-shas.ts` to the new digest.

**C2 — `knowledge-base/legal/article-30-register.md`, PA-3 (Subscription & Billing):**
append inside the **§(c) Categories of personal data** cell:

```
**Pending-checkout claim rows (`public.pending_checkout_sessions`, migration 144, #8918) — this
entry takes effect on deployment of migration 144; until then the table does not exist:** a per-user
idempotency marker written while POST /api/checkout creates a Stripe embedded-checkout session.
Columns: `user_id` (PK, FK `public.users(id)` ON DELETE CASCADE — the Art. 17 path), Stripe
`session_id`, `target_tier` (CHECK-pinned to the four plan tiers plus the 'legacy' sentinel),
`created_at`. RLS enabled with zero policies (service-role-only). The `client_secret` bearer
capability is deliberately not persisted (Art. 5(1)(c)). No new processing activity — contract-
necessity bookkeeping inside this PA.
```

and inside the **§(f) Retention** cell:

```
Pending-checkout claim rows (`pending_checkout_sessions`, #8918): transient — deleted on
`checkout.session.completed` and `checkout.session.expired` webhook receipt, on route reclaim paths
(terminal session, different-tier expire, stale null marker past STALE_NULL_MARKER_MS), and by the
daily `pending_checkout_sessions_retention` pg_cron sweep of rows older than 24 hours; erasure
cascades from `public.users`.
```

O1–O4 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `git diff --word-diff=porcelain origin/main...HEAD -- knowledge-base/legal/compliance-posture.md docs/legal plugins/soleur/docs/pages/legal | grep -c '^-[^-]'` → 3 (frontmatter date + the two `schedule).` in-place list appends).
- `sha256sum docs/legal/data-protection-disclosure.md docs/legal/gdpr-policy.md docs/legal/privacy-policy.md` → compare against `LEGAL_DOC_SHAS` (all three match pre-C1; gdpr-policy repins post-C1).
- `bash scripts/lint-legal-scope-block-placement.sh --base origin/main` → 0 violations; `bash scripts/lint-legal-mirror-drift-baseline.sh --base origin/main` → within baseline; `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0.
- `npx markdownlint-cli docs/legal/gdpr-policy.md plugins/soleur/docs/pages/legal/gdpr-policy.md` → MD012 ×2 pre-C1, clean post-C1.
- `grep -n "ENABLE ROW LEVEL SECURITY\|CREATE POLICY\|ON DELETE CASCADE\|cron.schedule" apps/web-platform/supabase/migrations/144_pending_checkout_sessions.sql` → D2/D3/D6.
- `grep -n 'check_name' apps/web-platform/supabase/verify/144_pending_checkout_sessions.sql` → rls_enabled, zero_rls_policies, users_fk_cascade, retention_cron_scheduled.
- `grep -n 'pending_checkout_sessions' apps/web-platform/app/api/webhooks/stripe/route.ts` → deletes in the completed and expired arms (D4).
- `grep -n 'STALE_NULL_MARKER_MS\|\.delete()' apps/web-platform/app/api/checkout/route.ts` → reclaim + release paths (D5).
- `grep -n 'pending_checkout_sessions' knowledge-base/legal/article-30-register.md` → 0 pre-C2 (D18).
- `grep -n 'disclosed_as.*article-30' knowledge-base/project/plans/2026-09-28-fix-billing-checkout-server-idempotency-plan.md` → the register-as-disclosure-surface pointer (D18).
