---
date: 2026-07-17
tags: [terraform, roster-drift, derivation-coupling, ci, sweep-scope, merge-time-verification]
issue: 6538
---

# A derivation-coupling sweep must be repo-wide AND re-run at merge — a dir-scoped, measured-once sweep misses consumers that land between measurement and merge

## Context

Retiring the `web-2` Hetzner host (#6538) meant removing the `"web-2"` key from
`var.web_hosts`. The plan's B0.2b step swept for *derivation* consumers (files that
couple to `var.web_hosts` without a literal `web-2` token — the class that a token
grep is structurally blind to) with:

```
git grep -ln 'var\.web_hosts' apps/web-platform/infra   # → 9 files
```

Every one of those 9 was audited and handled in B3. The gate tests were green. The
retirement PR merged.

## What went wrong

CI on the merge went **red** on `test-scripts`/`test`:

```
FAIL: parity: WEB_HOSTS drift — SUT pins [soleur-web-2 soleur-web-platform]
      but IaC derives [soleur-web-platform]
```

A **tenth** consumer existed:
`scripts/followthroughs/hostname-mislabel-web1-6616.sh` hardcodes the web-host
identity set and carries a parity test binding it to `var.web_hosts`. Removing
`web-2` drifted its parity check. Two reasons B0.2b never saw it:

1. **Directory scope.** The sweep was scoped to `apps/web-platform/infra`. This
   consumer lives in `scripts/followthroughs/` — a roster consumer outside the infra
   tree. A `var.web_hosts` coupling is not confined to the infra directory.
2. **Time.** #6616 (which added the probe) merged to `main` *after* the B0.2b
   measurement. The sweep was run once at B0 and treated as settled. A sibling PR
   adding a consumer between measurement and merge is a non-conflicting addition git
   merges silently — so it appears only when the branch rebases onto the newer `main`,
   and fails on `main` post-merge, never on the green pre-rebase branch. (Same class
   as the "all-members drift guard must rebase before ship" learning.)

## The rule

For any change that removes/renames a value other code *derives* from (a roster key,
an enum member, a schema column, a canonical literal):

1. **Sweep repo-wide, not dir-scoped.** `git grep -ln '<the derived symbol>'` over the
   whole tree, then filter — don't pre-scope to the directory you expect consumers in.
   The whole point of a derivation sweep is to find the consumer you did *not* expect;
   scoping it to where you expect them defeats it.
2. **Re-run the sweep at merge/ship time, against fresh `origin/main`**, not just at
   plan/measurement time. Between measurement and merge, sibling PRs add consumers.
   The B0-era "311 hits / 45 files" was already stale by B3 (383/57); the *consumer
   set* drifts the same way the token count does.
3. **A parity test that binds a hardcoded set to the derived source is the correct
   design** — it caught this. Its failure message ("re-sync WEB_HOSTS when the fleet
   changes") is an instruction; follow it, and update the semantic test cases that
   used the removed member (here, "web-2 collision → FAIL" was repurposed to the
   post-retirement inverse "a stale web-2 row is NOT a live collision → PASS").

## Cheapest mechanical gate

Before ship, on the rebased branch:

```
git grep -ln '<derived symbol>' | comm against the B0 hit-set    # any new file = a consumer added since measurement
```

Any file in the current sweep but not the B0 evidence file is a consumer that landed
mid-flight and must be audited before merge.

## See also

- `knowledge-base/project/learnings/best-practices/2026-06-14-all-members-drift-guard-must-rebase-before-ship.md`
  (sibling PR adds a guarded-set member on `main` → post-merge red).
- The B0 evidence for #6538:
  `knowledge-base/project/specs/feat-6538-web2-fsn1-orphan/measurements/b0-findings.md`
  (records the original 9-file derivation set — the baseline this consumer was absent from).
