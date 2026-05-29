# Learning: editing `docs/legal/*.md` is a 3-way lockstep; and the rpc-grants lint conflates a SECURITY INVOKER fn that precedes a SECURITY DEFINER fn

Captured 2026-05-29 during `feat-byok-delegation-consent` (#4625, PR #4627).

## Problem

Two failure modes hit during `/work`, both surfaced only by the **full-suite
exit gate** (`scripts/test-all.sh`), not by the per-task touched-file tests:

1. **`migration-rpc-grants.test.ts` flagged a SECURITY INVOKER function.**
   Migration 083 defines `current_byok_side_letter_version()` (`SECURITY
   INVOKER`, returns a literal) immediately followed by `CREATE OR REPLACE
   resolve_byok_key_owner` (`SECURITY DEFINER`). The lint's extraction regex
   is `CREATE … FUNCTION (name)(params) … SECURITY DEFINER … AS $$(body)$$`
   with a **lazy** `[\s\S]*?` between the name and `SECURITY DEFINER`. Because
   the INVOKER fn has no `SECURITY DEFINER`, the lazy scan ran *past it* to the
   resolver's `SECURITY DEFINER`, producing one synthetic "fn" named
   `current_byok_side_letter_version` carrying the resolver's body. The lint
   then demanded a `REVOKE … FROM PUBLIC, anon, authenticated` for that name —
   which the INVOKER fn had as `FROM PUBLIC, anon` only.

2. **`LEGAL_DOC_SHAS` + Eleventy mirror date drift.** Editing the header/body
   of `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
   tripped two independent gates: `legal-doc-shas-guard` (canonical
   `sha256sum` no longer matched `apps/web-platform/lib/legal/legal-doc-shas.ts`)
   and `legal-doc-consistency` (the `**Last Updated:**` date in the Eleventy
   mirror `plugins/soleur/docs/pages/legal/<name>.md` — both hero `<p>` and
   body line — no longer matched the canonical date).

## Solution

1. Give the `SECURITY INVOKER` function the **full** `REVOKE … FROM PUBLIC,
   anon, authenticated` form (then `GRANT EXECUTE TO …`) even though it does
   not strictly need `authenticated` revoked. Harmless (a DEFINER caller runs
   it with definer privileges regardless) and it satisfies the conflated match.

2. Editing any `docs/legal/*.md` is a **3-way lockstep**, all in the same PR:
   - **(a) Cross-document gate** (`legal-doc-cross-document-gate.yml`): if the
     diff touches `dsar-export.ts` / `dsar-export-allowlist.ts` (or other
     enumerated surfaces), ALL FOUR of `docs/legal/privacy-policy.md`,
     `docs/legal/gdpr-policy.md`, `docs/legal/data-protection-disclosure.md`,
     `knowledge-base/legal/compliance-posture.md` must be touched.
   - **(b) SHA pin** (`check-tc-document-sha.sh`): `sha256sum docs/legal/<doc>.md`
     → paste into `LEGAL_DOC_SHAS["<doc>"]`. (Body-equivalence vs mirror is
     opt-in / T&C-only, so the 8 non-T&C docs only need the canonical-sha pin.)
   - **(c) Mirror date lockstep** (`legal-doc-consistency.test.ts`): update the
     Eleventy mirror's hero `<p>…Last Updated <DATE></p>` AND body
     `**Last Updated:** <DATE>` to match the canonical's new date.

## Key Insight

- The **full-suite exit gate is load-bearing** precisely because touched-file
  tests miss orphan/sibling guards. The legal-doc SHA pin lives in a TS const
  (`lib/legal/legal-doc-shas.ts`) and the mirror lives in `plugins/soleur/`;
  neither is a "touched file" when you edit `docs/legal/*.md`, so only
  `test-all.sh` catches the drift. Run it before Phase 3, not at ship.
- A **`SECURITY INVOKER` function placed before a `SECURITY DEFINER` function**
  in the same migration is the trap for the rpc-grants lint. Cheapest defense:
  give every function the canonical 3-role REVOKE, or place INVOKER helpers
  *after* the last DEFINER fn in the file.
- Editing an **already-applied migration's header** (074) only changes its
  `content_sha`, which the `dev-migration-drift-probe` surfaces as a
  `::warning::` (not a merge gate, runner is filename-keyed) — reconcile
  `_schema_migrations.content_sha` on dev+prd post-merge; document it in the
  feature's `migration-checklist.md`.

## Session Errors

- **Bare-repo git command** — `git branch --show-current` at the bare root
  exited 128. Recovery: `cd` into the worktree first. Prevention: in pipeline
  mode with a stated worktree path, `cd` there before any git invocation.
- **Edit-before-Read (×6)** — used `cat`/`sed` to inspect, then Edit failed
  "File has not been read yet". Recovery: Read tool then Edit. Prevention: the
  harness tracks only Read-tool reads; `cat` does not satisfy
  `hr-always-read-a-file-before-editing-it`.
- **rpc-grants lint conflation** — see Problem #1. Recovery: full 3-role REVOKE
  on the INVOKER fn. Prevention: above.
- **Full-suite caught legal-doc drift** — see Problem #2. Recovery: repin SHAs
  + bump mirror dates. Prevention: the 3-way lockstep above.
- **Non-fast-forward push** — Phase-0.5 rebase rewrote the pushed branch.
  Recovery: `git push --force-with-lease`. Prevention: expected after a
  mandated rebase of an already-pushed feature branch; use lease-protected
  force-push, not a fresh push.

## Tags
category: build-errors
module: legal-docs, supabase-migrations
