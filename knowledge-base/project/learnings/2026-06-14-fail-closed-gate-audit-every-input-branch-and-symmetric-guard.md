# Learning: a fail-closed gate's NON-primary input branches are where the fail-open holes hide

## Problem

The sweep-completeness CI gate (#5269) is designed to FAIL CLOSED — its whole
purpose is to catch cross-file drift, so any path where it silently exits 0 on an
unprovable state defeats it. The primary changeset branch (`gh pr diff`) was
carefully fail-closed (empty/failed diff → exit 1). But a `silent-failure-hunter`
review of the diff found two fail-OPEN holes the author missed, both in
*non-primary* code paths:

1. **Secondary input branch swallowed a missing file to empty.** The `$2`
   changeset-file branch used `changed=$(cat "$CHANGESET_SRC" 2>/dev/null || echo "")`
   — a missing/unreadable file became an empty changeset → no trigger matched →
   `exit 0`. The `gh` branch guarded this; the file branch did not. The fixture
   drives the gate exclusively through `$2`, so this was the *documented* calling
   convention silently failing open.
2. **Asymmetric integrity guard.** The registry self-consistency pass rejected an
   empty `dependents: []` but NOT an empty `trigger: []` — a set with no trigger
   passed integrity, then never fired (fail-open rot, exactly what the anti-rot
   pass exists to prevent).

## Solution

- Missing/unreadable changeset file → `[[ -f ]]` guard → `exit 1` (fail-closed);
  an empty-but-PRESENT file stays a legit `exit 0` ("0 files changed"). The `-f`
  guard is what distinguishes "unprovable" from "provably zero" — `|| echo ""`
  cannot.
- Mirror the empty-dependents integrity check with an empty-triggers one.
- Lock both with regression cases (missing-file → 1, empty-present → 0,
  empty-trigger → 1).

## Key Insight

When building a fail-closed gate, the careful fail-closed reasoning almost always
lands on the **primary** path; the holes hide in (a) **every other input branch**
(stdin vs file vs API — audit each for the `2>/dev/null || echo ""`
swallow-to-empty antipattern) and (b) **asymmetric integrity checks** (if you
guard field X being empty, guard its siblings Y/Z too — a registry/config
validator that checks one required field but not its peer fails open on the
unchecked one). A reviewer lens specifically tasked with "where can this exit 0
when it should exit 1?" catches what RED/GREEN fixture-passing does not — the
18-case fixture was green while both holes were live, because no fixture exercised
the missing-file or empty-trigger inputs until the review named them.

## Tags
category: ci-cd
module: .github/scripts/check-sweep-completeness.sh
