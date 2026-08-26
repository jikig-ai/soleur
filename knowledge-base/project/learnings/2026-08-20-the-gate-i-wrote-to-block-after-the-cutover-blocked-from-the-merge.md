---
title: "The gate I wrote to block after the cutover blocked from the merge"
date: 2026-08-20
category: integration-issues
module: cloudflare-pages-migration
issue: 7640
pr: 7649
tags: [preconditions, fixtures, fail-closed-gates, mutation-testing, review-panels, terraform, cloudflare]
---

# The gate I wrote to block AFTER the cutover blocked FROM the merge

PR1 of the ADR-194 Cloudflare Pages migration. Six P1s, four of them written by
this PR, two of them CI-red on arrival. Every one was a check that certified
something other than what it named.

## 1. A precondition whose fixtures modelled a shape production never emits

The disarmament added an apex-topology precondition to `cron-gh-pages-cert-reissue`:

```ts
apexTopologyIsA:
  inputs.apexRecordTypes.length > 0 &&
  inputs.apexRecordTypes.every((t) => t.toUpperCase() === "A"),
```

The live read is **deliberately not `type=`-filtered** — a `type=A` query cannot
see a CNAME apex, which is the state the gate exists to detect. So it returns
every record at the apex name. Measured against the live zone:

```
count=10  types={'A': 4, 'MX': 2, 'TXT': 4}
```

`.every(t => t === "A")` is therefore **false on the current GitHub Pages
topology**. A gate written to block *after* the cutover blocked *from the merge*
— the exact inversion of its purpose, on the only scripted remedy for a wedged
certificate.

Nothing local could see it. Every unit fixture hand-wrote
`apexRecordTypes: ["A","A","A","A"]`, a shape the producer never emits, and the
AC's own non-vacuity assertion passed for the wrong reason: it would have passed
against a predicate hardcoded to `false`.

**Fix:** filter to types that participate in origin selection (`A`/`AAAA`/`CNAME`)
before the `.every()`, preserving fail-closed-on-empty.

**Generalisable:** when a read is deliberately *widened* to catch a state, the
predicate over it must be *narrowed* to the axis that matters. Widening the read
and keeping a whole-array predicate is how a gate inverts. Ask, per fixture:
**which live call site or captured response emits this shape?** If the answer is
"none — I wrote it", the assertion above it is unproven.

## 2. A fail-closed linter reporting a structural error is a blindfold

A Python splice across a code-fence boundary left a plan block unterminated.
`lint-infra-no-human-steps.py` fails closed on malformed markdown, so it
reported:

```
unterminated code fence (opened at line 1334); malformed markdown disables
tail scanning — fail-closed.
```

That reads as a formatting nit. It is not: the linter **was not scanning at
all**, and a real AC-level finding sat underneath it, invisible until the fence
was repaired. Fixing the fence turned one "structural error" into a genuine
finding about a different line.

**Generalisable:** a structural/parse error from a fail-closed gate is not noise
to clear on the way to the real output — it *is* the gate telling you it has
stopped looking. Re-run after every structural fix and read the new output as a
first result, not a confirmation.

## 3. The comment-fix PR wrote a new false comment (recurrence)

Correcting a stale cadence comment that named a now-disarmed cron, I promoted its
sibling: *"the tightest monitored daily cron — `scheduled-community-monitor` @
`0 8 * * *`"*. Also false. `scheduled-daily-triage` fires at `0 4` with
`checkin_margin_minutes = 30`, earlier and tighter than community-monitor's
`0 8` / `60`.

The comment had now been wrong twice for the *same structural reason*: it named a
specific cron, so it rots whenever a margin or schedule moves in a file it does
not mention.

**Fix:** stop naming any cron. Rest the claim on the invariant — every monitored
daily cron fires once per 24h, so a ≤4h detection latency beats the next fire
regardless of which is tightest. The invariant cannot rot.

**Generalisable:** when a claim has been wrong twice, the defect is the claim's
*shape*, not its content. Re-anchor on an invariant rather than correcting the
instance.

## 4. Convergence across agents is not evidence when they share a premise

Three independent review agents (observability, security, user-impact) each
concluded the cert-poll disarm was premature, all reasoning from *"GitHub Pages
is still the live origin and is the thing that must renew."*

It had already failed to renew. Measured:

| Probe | Result |
|---|---|
| `openssl s_client` → GH Pages IP, SNI `soleur.ai` | `notAfter=Aug 16 2026` — expired 4 days earlier |
| `gh api repos/.../pages` | `state: bad_authz`, `is_https_eligible: false` |
| `[cert-poll]` issue | OPEN 33 days, **35 comments**, last written that morning |
| `curl -sSI https://soleur.ai/` | `200` — masked by `ssl = "full"` |

`certEscalation`'s thresholds (warn 21d, critical 7d) were at
`daysUntilExpiry = −4`. There was no future warning to forfeit, and the daily
loop the disarm pre-empts was **already running**.

**Generalisable:** N agents sharing one premise are one agent. Before weighting
convergence, ask *what premise are they all using* and spend one measurement on
it. Prefer one irrefutable artifact over any number of concurring inferences.

## 5. A plan correct under only one of two mutually exclusive hypotheses

PR1 attached `soleur.ai` and `www` — live, HSTS-preloaded — to a Pages project
with **zero deployments**. The plan's own Hypothesis Z states *"the apex begins
serving from Pages at the moment of attachment"*, and the apply runs **on merge**,
so the verifying probe was a post-hoc observation of a production mutation.

Under Z-true that is an outage. Under Z-false the cutover's zero-downtime story
collapses. Nothing discriminated them before the change landed on production.

**Fix:** split into four PRs (substrate → deploy path → attach → record swap) so
each revert removes the resource its own PR introduced. Correct under *both*
branches instead of the preferred one — and it retires an open rollback unknown
by construction rather than by measurement.

**Generalisable:** when a design is correct under exactly one of two hypotheses
and the discriminator runs after the mutation, restructure so the question stops
mattering. A structure that cannot be wrong beats a measurement that must be right.

## 6. A mutation battery's AXES, not its count

A self-run battery reported 16/16. Independent enumeration found the axes it never
touched:

- **dispatch** — one edit to the `verdict()` wrapper (`verdict() { CASES=$((CASES+1)); pass "$2"; }`)
  disarmed the anti-vacuity floor, the accounting identity, and all 24 assertions
  at once, exiting 0 with a real regression riding along
- **member ADDITION** vs edit — a `dynamic "rules"` block adds a bound member while
  the static count stays 2
- **fixture direction** on the list that wins first-match
- HCL `/* … */` block comments, which `strip_comments` did not handle
- a hardcoded workflow path that goes vacuous if a later PR renames the file

**Generalisable:** count the axes a battery edits, not the rows it reports. N
mutations of one shape is one mutation. The highest-yield axis is usually
*dispatch* — nothing in a battery that perturbs inputs can observe its own
assertion helpers going silent.

## 7. The prose documenting a classification satisfied the check guarding it

ADR-136's parity gate exists to stop a new `cloudflare_*` class from entering the
infra unclassified. It fired correctly on `cloudflare_pages_project`. Adjudicating
it OUT meant writing a paragraph explaining *why* — it is the first class with a
natural key to be ruled OUT, so the one-line table cell could not carry it.

That paragraph names the type. The gate's ADR-to-test coupling (P2) asserted the
type appears **anywhere** in the ADR, via `grep -Fq`. So once the explanation
existed, the adjudication row it explains could be deleted and the suite stayed
green at 43/43.

The documentation written to make a decision reviewable is what stopped the test
from checking that the decision was recorded. Bare-token presence was never the
property worth asserting — it merely coincided with it for as long as every
mention of a type lived inside its own table row. The first prose mention broke
the coincidence, and nothing announced it.

Only mutation testing found this. The fix was green, the gate was green, and the
green was meaningless. Anchoring P2 on a table ROW carrying an OUT verdict also
bought a check the old form could not express at all: an ADR that classifies a
type `IN` while the test lists it `OUT` is now a failure — previously the two
could contradict each other in permanent silence.

**Anchor a coupling assertion on the STRUCTURE that encodes the decision (the row,
the verdict cell), never on the presence of a name. A name appears in prose; a
decision does not.** This is `cq-assert-anchor-not-bare-token`, and the way it
recurs is that the person adding the prose and the person relying on the anchor
are the same person, one commit apart.

## Session Errors

1. **Commit signing hang misdiagnosed as memory pressure.** A prior session
   recorded "the box killed three processes" (`git rebase` SIGKILL, `ssh-keygen`
   SIGTERM ×2). Actual cause: `commit.gpgsign=true` + `gpg.format=ssh`, gcr
   keyring answering `agent refused operation`, git falling back to an
   interactive passphrase prompt that never returns in a non-interactive shell.
   Every death was a 2-minute tool timeout; rebase dies identically because it
   re-signs every commit.
   **Prevention:** when a git operation dies at exactly the tool timeout, check
   `git config commit.gpgsign` and `ssh-add -l` before hypothesising resource
   pressure. Exit 143 is SIGTERM from the harness, not the kernel.

2. **`apexTopologyIsA` inverted** (§1). **Prevention:** name the live call site
   each fixture models; a fixture nobody can trace to a producer is a claim.

3. **www redirect broke ACME on www** — a scheme-less subpath-matching list became
   the only redirect actor on a path Rule 10 deliberately passes through, failing
   the cert-reissue routine's own `acmeWwwCarveout`. My "no-op until PR3" claim
   was derived from the apex leg only.
   **Prevention:** when adding a rule to a shared phase, enumerate every path a
   *sibling* ruleset deliberately declines to act on; deliberate inaction is a
   contract another rule can silently override from a later phase.

4. **`cf_api_token_pages` missing from `terraform test` variables** — CI-red.
   `terraform test` resolves every root variable before any run block, so a new
   no-default variable breaks every existing test while `validate` stays green.
   My own work-phase instructions name this trap.
   **Prevention:** adding a root variable ⇒ grep `tests/*.tftest.hcl` for the
   `variables {}` block in the same edit.

5. **AC28 required an encryption-ledger entry that was never made** — the repo
   sweep exited 1. The criterion was tracked and silently went unmet.
   **Prevention:** treat an AC as unmet until its literal command has been run;
   a checked box is a claim.

6. **PR1 attached a production hostname to an empty project** (§5).
   **Prevention:** before any resource that binds a LIVE hostname, ask what it
   points at *at the moment of apply*, not at the end of the migration. If the
   answer is "an artifact a later PR creates", the binding belongs in that later
   PR — an apply that runs on merge cannot be gated by a probe scheduled after it.

7. **New false comment while fixing a stale one** (§3).
   **Prevention:** a correction is a NEW claim and inherits none of the original
   finding's credibility. Run the falsifying command on the replacement text
   before committing it — here, one `awk` over the monitor file would have shown
   `scheduled-daily-triage` at `0 4` / margin 30.

8. **Broke a fence; fail-closed lint masked a finding** (§2).
   **Prevention:** after any programmatic splice into markdown, assert fence
   parity (`grep -c '^\s*```'` is even) in the same command that writes the file.
   A splice computed from `str.find` offsets can consume a delimiter silently.

9. **AC5 prescribed a bare grep that fails on a correct file** —
   `-target=cloudflare_record.github_pages` also matches
   `…github_pages_challenge`, so the AC expected 1 and a correct file returns 2.
   The natural "fix" is to loosen the assertion.
   **Prevention:** anchor target/address greps on the line, not the substring
   (`cq-assert-anchor-not-bare-token`).

10. **Invalid mutation sandbox** — copied only `apps/web-platform/infra/`, so the
    guard's read of `plugins/soleur/docs/CNAME` failed and the CONTROL was red.
    Every row measured against it was void.
    **Prevention:** run the unmutated control first and require it GREEN; a red
    baseline voids the battery. Compare per-case verdicts, never totals.

11. **Partial mutation gave a misleading RED** — a regex deleted 7 of 12 list
    items; the guard reddened and I briefly read that as refuting a correct
    finding. Re-run with brace matching showed control and mutant failing on the
    *same* case, i.e. zero added failures.
    **Prevention:** assert the mutation landed at the intended cardinality
    (`items remaining: 0`), not merely that the file changed.

12. **`git stash list` inside a compound Bash command** — the guardrail denies it
    outright and rejected the entire call, losing the unrelated commands with it.
    **Prevention:** never put a hook-denied verb in a multi-command call.

13. **`doppler secrets set --help` blocked twice** — the guardrail requires
    `> /dev/null` because the CLI prints every remaining secret on success.
    **Prevention:** read Doppler help via `doppler help secrets set`.

14. **`.playwright-mcp` output resolves from the repo root**, not the worktree
    (`hr-mcp-tools-playwright-etc-resolve-paths`). Looked in the worktree, found
    nothing, briefly concluded no snapshots were being written.
    **Prevention:** MCP artifact paths are repo-root-relative; check there first.

15. **Two agents stalled at the 600s watchdog** — both on the wide-read shape
    ("read the 25-file diff / 1400-line plan, then act").
    **Prevention:** bound a delegate's reads explicitly (`sed -n` a section, not
    the file) and split multi-task briefs. Prefer *resume* over respawn — a
    resume keeps the transcript and neither agent lost work.

16. **The planning subagent wrote no `session-state.md`** despite the pipeline
    prescribing it, so nothing forwarded plan-phase errors into compound.
    **Prevention:** the orchestrator should write `session-state.md` from the
    returned Session Summary rather than assuming the subagent did.

17. **A new `cloudflare_*` class shipped un-adjudicated, and only the deferred
    shard caught it.** `cloudflare_pages_project` was added without a row in
    ADR-136's adjudication table. It went unseen because `tests/scripts` was the
    shard this branch had skipped while `lease-protects-active.test.sh` was unsafe
    to run against a low-`/tmp` box; the omission surfaced only once that fix
    reached main and the shard ran again.
    **Prevention:** a deferred shard is unrun coverage, not absent coverage. When
    a diff adds a resource TYPE (not just a resource), name the shard that
    adjudicates types and run that suite directly rather than waiting for the
    battery — `test-preapply-entrypoint-gate.sh` takes ~2s.

18. **I defeated a gate with the prose written to satisfy it**, then nearly
    shipped the vacuity — see §7. The fix was green and the green meant nothing.
    **Prevention:** after editing any file a coupling test reads, mutate the
    thing the test claims to protect and confirm RED. A passing test on a file
    you just changed is a hypothesis, not evidence.

19. **`git stash list` inside a compound Bash call — a recurrence.** Already
    recorded earlier in this same session, and repeated while checking a linter
    baseline. The guardrail denies the whole call, so the unrelated commands in
    it were lost too.
    **Prevention:** hook-denied verbs are denied at the CALL level, not the
    command level. Never place one in a compound line — and treat "I already
    made this mistake this session" as a reason to re-read the call before
    sending, since the recurrence cost more than the original.

## Verified artifacts

Guard 23/23 · mutation battery 16/16 · `terraform fmt`/`validate`/`test` (3 passed)
· encryption-posture ledger (17 stores, 0 failing) · vacuity meta-guard 19/19 ·
T15 no-human-steps · preapply-entrypoint gate 43/43 (P2 mutation-verified
across 4 arms) · AC26 literal · AC8 per-path (all five deferred artifacts
intact) · `ssl = "full"` retained.

## The thing worth remembering

Every defect here was a check that certified something other than what it named:
a precondition asserting a shape production never emits; a linter reporting it had
stopped looking; a comment naming an instance instead of an invariant; a panel
agreeing on an unmeasured premise; a plan measuring after the mutation; a battery
counting rows instead of axes.

The cheap gate for all six is the same question, asked of the artifact rather than
the intent: **what input makes this green while the thing it protects is broken?**
