---
module: System
date: 2026-11-06
problem_type: integration_issue
component: tooling
symptoms:
  - "A file-census guard skipped `islink()`d LEAF entries but `os.path.isdir`/`os.listdir` on `.github`, `.github/workflows`, `.github/actions` followed ANCESTOR links — outside content scanned under in-root relpaths with no advisory"
  - "The fix commit closing a stale-line-cite finding reintroduced the same class — 7 of 15 cites wrong at commit time"
  - "A resumed-session fix round found the main panel ran but its Reviewed-By-Soleur trailer was never emitted AND the dedup ledger never persisted to session-state.md, forcing seat reconstruction"
root_cause: incomplete_guard
resolution_type: code_fix
severity: medium
tags: [symlink, census-boundary, review-fix-round, anchor-cites, trailer-attestation, dedup-ledger]
synced_to: [work, review]
---

# A leaf `islink` guard cannot see the ancestor symlink — `isdir` follows links at every level

PR #12235 fix-round, ADR-267. Three seats converged on the same residual: the
lint's `collect()` guarded `os.path.islink` on leaf files and one directory
level (`actions/<sub>`), but `os.path.isdir`/`os.listdir`/`os.path.isfile`
follow ancestor links silently — a committed symlink at `.github`,
`.github/workflows`, or `.github/actions` let the census read outside the
scan root and report rows under in-root relative paths. The children inside
are not themselves links, so no leaf check can see the escape.

**The invariant:** a directory-walking boundary guard needs `islink` on EVERY
level it descends through — root/.github, the census dirs, each enumerated
sub_dir, and the leaf. Missing one level is the same defect; three fix-round
seats independently drove the two unguarded levels.

**Fixture coverage is the harder half.** Deleting the guard regressed green:
no fixture planted any symlink. Pinning needs one fixture per level —
linked sub_dir (skip+advisory), linked census dir (refuse rc=2), linked
`.github` (refuse), linked FILE leaf — and each must be mutation-driven, not
asserted. The final miss was a fixture that linked a dir but never a file:
`_add`'s leaf guard deleted green until a file-leaf fixture landed.

**Sibling lesson — a fix to a cite-rot finding was reviewed like code and
still shipped rot.** The comment rewrite that closed "7 stale `:NNN` cites"
re-cited 7 of 15 sites wrong at commit time. A citation is not safe because
it exists; re-resolve EVERY anchor against the current tree before
committing — `file › ident` content anchors (per
`cq-cite-content-anchor-not-line-number`) beat line numbers, which rot in
the very PR that edits the cited files.

**Resume-time attestation gap:** the prior session's 8-seat panel reported
and fixed everything, then the session ended before `emit-review-trailer.sh`
ran and before the dedup ledger was appended to session-state.md — the two
artifacts a LATER session's fix round consumes (`--finding-seats`, the
main-panel `Reviewed-Coverage` precondition). A resume prompt should name
the checks (`git log --format=%B | grep Reviewed-By-Soleur`, ledger section
in session-state.md) so the gap is visible at resume, not discovered at
attestation time. Rules already exist (risk-tier-and-fix-rounds.md §Persist
the ledger); this was execution drift across a session boundary.
