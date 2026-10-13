# Decision Challenges — feat-one-shot-6992-iac-guard-sigpipe-fail-open

Persisted for the operator because this pipeline ran headless. `ship` renders these into the PR
body and files them as `action-required`.

## DC-1 — Reviewers recommend splitting this into two PRs (User-Challenge)

**Your stated direction:** ship #6992 and #6991 as ONE PR closing both.

**What the reviewer says:** `code-simplicity-reviewer` recommends splitting. The two issues share
no file, no mechanism, no test, and no failure mode. The "unifying theme" (a guard that reports
success while doing nothing) is a narrative, not a coupling. The proposed split is serialised,
not parallel, because both parts touch `plugins/soleur/skills/work/SKILL.md` and
`scripts/test-all.sh`:

- PR 1 — `Closes #6992`: Phases 0–5.
- PR 2 — `Closes #6991`: Phases 6–9.

**Why it might be right:** 10 phases and ~20 acceptance criteria for what reduces to two one-file
bug fixes is a large review surface, and each half is independently revertible in fact. A
reviewer of Part A gains nothing from carrying Part B's tmpfs context, and vice versa.

**Why your direction might still be right:** both issues came from one incident and one
investigation; splitting doubles the ship/review/merge overhead for work that is already scoped
and measured; and the plan's phase boundaries already give per-part revertibility without
per-part PRs.

**What was done:** your direction was kept — the plan ships as one PR. Nothing is blocked. If you
prefer the split, say so before `/work` begins; the phase boundaries map onto the two PRs
cleanly with no re-planning.

## DC-2 — Two of this issue pair's own suggested directions were blocked by measured facts

Not a challenge to you — a heads-up that the plan deliberately diverges from the issue text, with
evidence:

- #6991 suggests routing the alarm to a `SOLEUR_*` marker → Better Stack and/or Sentry.
  **Measured:** Vector is not installed on this workstation, `tmpfs-guard` is not in the Vector
  tag allowlist, no local Sentry DSN exists, `doppler` is off cron's `PATH`, and `gh` authenticates
  via the OS keyring which cron cannot reach. There is no local-cron → remote-observability path
  in this repo. The plan routes to the next agent session instead, and declines to create a new
  egress path from your laptop.
- #6991 points at `scripts/lib/scratch-root.sh` as machinery to build on. **Measured:** it has
  zero production callers and its test is registered in no runner. Deferred to its own issue.
