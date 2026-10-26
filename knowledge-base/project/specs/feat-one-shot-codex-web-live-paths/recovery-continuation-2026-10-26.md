# Recovery continuation — 2026-10-26

## Source reconciliation and local evidence

Recovered uncommitted work is preserved in checkpoint `2371552479`. Merge
`39cdb743116635277ea23c3e1356b5b5c3f4eecc` incorporates freshly fetched main
`63eabdb0610ae0e809d381ff6807c65042423648`, including the originally requested
`852b0ef01aec1b2648de9a65360d7b3d6e5e1409`. The merge had no conflicts.
The main measurement found 182 forward migrations, maximum ordinal 163;
the independently owned 164 reservation remains outside this branch's mapping.
The branch has 193 forward migrations, maximum ordinal 175. No shared catalog
or ledger was read to obtain these source counts.

All 21 renamed SQL files were independently compared with their pre-move
committed bytes, Git blob IDs and SHA-256 values. Every comparison passed.
The surviving local manifest `.soleur/renumber-20261026/sql-after.json` has
SHA-256 `690bff9db0ad86715633d60e75f1d381128e0e94e7eacbe1a3ba53a7d19d565d`.
The earlier raw capture and collector are absent; their historical summaries
and digests cannot establish current live state or writer clearance.

## Verification

On the reconciled source, pinned Node 22 TypeScript passes. The Python
migration-ledger suite passes 8/8; dev-ledger parity passes 295/295; TOM4 passes
28/25 source assertions and all 36 mutation cases. These are source/synthetic
checks, not shared-ledger parity or live application evidence.

The six-file focused Vitest set initially reported 36 pass / 4 fail. The
acknowledgment protocol fixtures omitted the required nonce; issue #11221 tracks
that pre-existing test gap. Updating only synthesized fixtures and adding
missing/malformed nonce cases produces 42/42 passing tests in those six files.
Runtime schema validation remains strict. The separate rights/retention DSAR
gap remains tracked by issue #11170 and is not fixed by fixture changes.

The rehearsal-admission suite reports 6 pass / 2 fail because the byte-preserving
renumber changed the complete runner identity to
`f71ba896687dafb34b760a754c47045a4eab1e5271d4662b1dd6e10a7f88ae3e`.
Its previous source-review pin is unchanged. Fresh complete-runner review is
required before updating it; no local green result substitutes for that review.
Synthetic authentication in `prepare.py` expired at 2026-10-26 00:00 UTC.
Renewal requires the established whole-contract review process, not an expiry
literal edit. Offline source tests and metadata-only capture preparation do
not renew authenticated qualification authority.

## Pre-push finding and exact exception

The main-derived scanner reported one historical finding: commit
`7e473494e634`, `workspace-default-engine.pen`, rule `generic-api-key`, line 946.
Safe structural inspection identified the root `fileToken` field: a 36-character
UUID with four hyphens. No value was printed. The branch's existing
`.gitleaksignore` records this exact document location as a Pencil document ID;
main's ignore list does not include it. The scan reported FINDINGS, not CLEAN.

The operator was asked to approve only that false-positive exception for the
draft push, without altering scan rules or readiness. The response was:
“Approve this single false-positive exception”. This authorizes this one
historical Pencil document-ID finding only. No scanner configuration, history,
inline waiver, draft state or auto-merge setting was changed by the exception.

## Independent holds

CLO purpose/basis, retention, Article 15/20 and post-consumption decisions are
being prepared as a separate internal assessment. The operator's reserved
legal-risk acceptance remains distinct from an internal CLO proposal.

Fresh shared evidence requires a new source-bound collector, verified CA,
independent review and an exact-action proposal/approval before execution.
Writer observation is not exclusion: the workflow/run census, enforced writer
coordination, actual mutex acquisition and transactional CAS remain separate.
The ten legacy filename mappings are 143–152 → 165–174, retaining exact body
blobs and original timestamps. Migration 175 remains genuinely unapplied.
No replay, down migration, hash/timestamp rewrite, reconciliation or provider
request is authorized here. Preserve PR #9051 draft and auto-merge off.
