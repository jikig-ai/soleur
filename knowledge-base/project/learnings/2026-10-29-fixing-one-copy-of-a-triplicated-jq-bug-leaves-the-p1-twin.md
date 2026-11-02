---
date: 2026-10-29
pr: "#11442"
issue: "#11424"
severity: P1-caught-in-fix-round
title: Fixing one copy of a triplicated jq bug leaves the P1 twin
tags: [jq, bash, review, fix-round, triplication, enumerator, oci]
---

## Context

`mirror-ghcr-to-zot.sh` enumerates OCI manifest children/blobs in **four
deliberately triplicated sites** (`fetch_artifact`, `verify_blobs_of`,
`count_artifact`, `verify_pushed`'s TSV variant — the script is distributed
self-contained to a bare incident host, so no shared helper).

The main panel found `count_artifact`'s `[ (.layers // []) | .size ]` —
indexing the `.layers` **array** with `.size`, which jq answers with
`Cannot index array with string ("size")` (exit 5). The fix-commit corrected
that one site. The ADR-267 fix-round seat then found the SAME class alive at
`verify_blobs_of:578` — `[ ... + [(.layers // []) | (.digest // "-")] ]` —
and rated it **P1**: the new `verify_pushed` signature-manifest dispatch
routes every plain-manifest signature root through the broken arm, so live
verification could never reach `result=ok`. The dry-run-only fixture had
stayed green because it only exercised the fixed enumerator.

## The lesson, in two parts

**jq mechanics:** `[(.layers // []) | .size]` reads `.size` on the array
object — a hard jq error that `2>/dev/null || printf '0 0'` / `//` fallbacks
do NOT rescue (the error is an operator error, not a missing key). Element
access needs the iterator: `[(.layers // [])[] | .size]`.

**Fix mechanics:** when a bug lives in code that is *deliberately
triplicated*, the fix commit must grep the expression's **distinctive core**
across the file — `.layers // []) | .` here — not just the reported line.
Three correct copies and one broken copy is the most dangerous shape of
duplication: it looks "already handled" in the diff while keeping a
production arm dead.

## What actually caught it

The targeted fix round (ADR-267) — seats re-reading `git diff PANEL..HEAD`
against their own prior findings — is what saw the missed copy AND the new
dispatch that made it live. The header's "deliberate triplication — keep all
four in lockstep" NOTE was also added in the same batch, so the contract is
now written where future edits land.

## Prevention

- When fixing a shape/operator bug in deliberately-triplicated code, grep the
  distinctive core of the bad expression file-wide before committing — count
  every occurrence, not just the reported site.
- Fixture coverage must exercise EVERY arm of the triplicated contract, not
  the one arm that was fixed — the stub-harness live-path row (crane stub
  serving bydigest manifests) is what pins `verify_blobs_of` here.

## Session Errors

- Fixed `count_artifact`'s jq array-index bug but missed the identical
  pattern in `verify_blobs_of` — **Prevention:** the grep-the-core sweep
  above; now enforced by the lockstep NOTE + the live-path fixture row.
- ZOT_TARGET guard placed before `die()`'s definition → ShellCheck SC2218 —
  **Prevention:** env guards belong after the flag-parse loop, which the
  fix-round also corrected for `--help` reachability.
- Comment deletion merged into the next line (20-space TAG indent) —
  **Prevention:** deletion edits should remove the whole line including its
  indent, then re-read the site.
- `--dry-run` fixture exercised only the fixed enumerator —
  **Prevention:** see last Prevention bullet.
