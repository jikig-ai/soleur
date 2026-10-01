# Decision challenges — feat-one-shot-9379-git-data-apt-timeout

Persisted for `ship` Phase 6 (rendered into the PR body and filed as an `action-required` issue).
The operator's stated direction is the default in every entry.

## 1. User-Challenge — "route expiry to the existing arm_skip so the suite skips that arm"

- **Stated direction:** a stalled apt cycle should become a declared skip instead of a failure.
- **What the codebase allows today:** `arm_skip` is reachable from four rehearsal arms only (T5 mutation,
  T17 mutation, S1 family). T5 primary, T17 healthy and the R4 driver are deliberately hard (ADR-188; a
  roster guard in the suite fails if T5 primary becomes skip-eligible). T5 primary is the supply-chain
  checksum guard.
- **Default taken in the plan:** keep those three hard. They fail fast with a named cause instead of being
  killed at 600 s. Skip-eligible arms skip; ownership and cutover-access runtime arms become a counted
  declared skip.
- **Consequence:** under a SUSTAINED archive outage the rehearsal leg can still be red, but quickly and
  attributably.
- **Alternative:** amend ADR-188 to make T17 healthy and R4 eligible (and, separately, decide T5 primary).
  Cost: a green run that never exercised the supply-chain guard.
- **Where it is tracked:** deferral issue filed at work time (Deferrals (a)).

## 2. User-Challenge (applied as the plan's default) — ownership stays fail-closed

- **Brief's wording:** "route expiry to the existing arm_skip so the suite skips that arm".
- **What the code and history say:** `git-data-ownership.test.sh` has no `arm_skip`; its apt-exhaustion branch
  fails under `CI=true`, and issue #8744 (same suites, 2026-09-24) says "Keep the fail-closed arm; do not let
  an apt failure turn into a skip".
- **Default taken:** no new skip path; the bound turns the 300 s kill into a fast named failure. Every arm
  that can skip today (rehearsal T5 mutation, T17 mutation, S1 family) now skips on expiry.
- **Alternative:** a counted declared skip for a TIMEOUT cause in ownership (an ADR-188 axis extension).
  Cost: Guard 3 runtime rows R1-R10 go unadjudicated during an outage, and it reverses #8744.

## 3. Taste — add a bounded pre-pull of the pinned image

- **Default:** not added (no evidence the pull is the stall; ownership passed in 98 s on the same runner).
- **Alternative (DHH):** one `timeout 120 docker pull "$UBUNTU_BASE"` per suite. Revisit if the arm line and
  `since_arm` show time spent before apt ran.

## 4. Taste — `gd_docker_run` wrapper and a concrete image-revisit trigger (CTO)

- **Default:** per-site wiring with a derived assembly row; revisit trigger recorded in Deferral (a).
- **Alternative:** a wrapper injecting mount and env at every docker site; deferred because the rehearsal's
  meta-guards read its own `docker run` text.

## 5. Mechanical (applied) — cutover-access removed from scope

Already host-bounded (`timeout -k 10 480 docker run` + `docker rm -f`) and not in the red set; recorded in
Deferral (b). Not operator-requested scope.
