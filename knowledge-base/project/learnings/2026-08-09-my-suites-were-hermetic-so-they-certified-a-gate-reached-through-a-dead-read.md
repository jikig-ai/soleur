---
module: registry-luks-recut / D10 authorization gate
date: 2026-08-09
problem_type: integration_issue
component: ci_workflow
symptoms:
  - "D10 gate aborts at PREPARE with 'APP_DOMAIN_BASE is unreadable from Doppler (soleur/prd)'"
  - "registry-luks-recut unfireable during the incident it exists to recover from"
  - "60-row unit suite and 42-mutation battery green throughout"
root_cause: missing_config
severity: critical
tags: [vacuous-guard, dead-read, provenance, fail-closed, mutation-testing, adr-hygiene]
synced_to: [compound-capture, review]
---

# Every green signal certified the gate's LOGIC; the workflow reached that logic through a read that resolved to nothing

## Problem

`registry-luks-recut` authorizes an **irreversible destroy of production's sole container image
store**. Its D10 gate derived the `/health` URL that defines the restore set by reading
`APP_DOMAIN_BASE` from Doppler `soleur/prd`, with no fallback, failing closed on empty:

```bash
APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE -p soleur -c prd --plain --token "$DOPPLER_TOKEN_PRD") || APP_DOMAIN_BASE=""
if [[ -z "$APP_DOMAIN_BASE" ]]; then
  echo "::error::registry-luks-recut D10 PREPARE ABORT: APP_DOMAIN_BASE is unreadable from Doppler (soleur/prd)…"
  exit 1
fi
```

**That secret exists in no config of the `soleur` project.** Measured live across all 13. So the
gate aborted at PREPARE *before it could reach its own destroy-guard* — unfireable during exactly
the incident it exists to recover from, while the registry crash-looped at ~4 restarts/min with
`/var/lib/zot` at `pcent=100` for three days.

Nothing caught it. `test-registry-pull-path-health.sh` was 60/0. The mutation battery reported
42 caught, 0 survived. Both are hermetic: they sandbox the gate and drive it directly, so they
certify its **logic**. Neither can execute a `run:` body, which is where the dead read lived.

## Solution

Invert the provenance onto the causal source. The name was never invented —
`apps/web-platform/infra/server.tf:1578` sets `APP_DOMAIN_BASE = var.app_domain_base`, publishing
it to the host. It is a **derived copy** of a committed Terraform variable, so reading Doppler
could at best have re-read a copy of the real source; in fact it read nothing.

Added `scripts/derive-app-domain-base.sh` reading `variables.tf`, plus a **static wiring gate**
(`tests/scripts/test-registry-d10-workflow-wiring.sh`) that asserts the workflow *uses* it. The
D10 PREPARE step is now credential-free — `DOPPLER_TOKEN_PRD` deleted.

**The repo already knew.** `.github/actions/cf-tunnel-registry-bridge/action.yml` carried the
comment *"APP_DOMAIN_BASE is not in prd"* while the D10 step body asserted *"APP_DOMAIN_BASE is a
DOPPLER SECRET"*. Two comments in the same dispatch's chain contradicted each other, and the
correct one sat in the leg that actually pushes images.

## Key Insight

**A hermetic suite cannot see a dead live input.** Logic coverage and input validity are
orthogonal, and every signal we generate measures the first. The generalizable gate:

> For any CI step that reads an **external name** (a secret, a config key, a bucket, a queue),
> assert that the name **exists in the source it names**.

Enumerating every `doppler secrets get <NAME> -p <proj> -c <cfg>` in a chain and checking each
`<NAME>` against that config's live `--only-names` converts "reads something that does not exist"
from a class caught by one hard-coded string into one caught **by construction**. It is a
no-SSH, credential-scoped read CI can already do. Filed as #7350: a first sweep found 6 of 29
names read in CI absent from the three configs checked (several legitimately live in other
projects — per-call-site attribution is the actual work).

Corollary, and the reason this is not just "add a test": the defect was invisible to *both*
directions of the usual advice. Adding more logic rows would not have found it, and neither
would a broader mutation battery — the input was not part of anything either could mutate.

### Two sharper corollaries from the same session

**A lint fix can enable a vacuity.** Closing shellcheck SC2015 by adding `return 0` to `fail()`
is exactly what makes a neutered `fail() { return 0; }` a *valid no-op*. Measured: with
`validate_base` deleted from the SUT, the suite reported `22 passed, 0 failed`. The comment I
wrote explaining why `return 0` was load-bearing also, unknowingly, described the weakness. The
fix is an **exact** assertion-count floor (never `>=`, which re-opens the hole on the next added
row), calibrated from a green run.

**An ADR clause can condemn its own ADR.** My ADR-169 amendment said an authorizing input must be
"present in the same artifact CI already checks out" and that "a live credential store satisfies
neither" clause. But ADR-169 *adopted* A0 (live `/health` over HTTP), A1 (live GHCR read under
credential), A2 (live throwaway-registry rehearsal) and A4 (live CF Access grading). A future
reader applying my sentence literally would have been obliged to reject the entire design. The
scoping that survives: an **addressing input** (which host to measure) must be causal and
resolvable from the checkout; the **measurement** must be live, or the gate is a tautology.

## Prevention

- For every external name a CI step reads, assert existence in the named source — not just that
  the read succeeded.
- After changing a test harness's **reporter**, re-ask "can this suite still fail?" Neuter it to
  a no-op and confirm the suite reddens.
- Derive floor constants from a green run. Both of mine were wrong when guessed (38 vs 34; 24
  then 20 vs 22) — and the floor caught its own miscalibration on first run, which is the point.
- After drafting a normative ADR clause, test it against the predicates the **same ADR already
  adopted**. If it rejects any, the clause is unscoped.
- When a plan cuts scope on blast-radius grounds, apply that same test to what you **did** ship.

## Session Errors

**1. Two false-positive `lint-infra-no-human-steps` blocks** on plan prose *describing* an
existing runbook defect. Recovery: one reworded, one wrapped in the sanctioned ignore region.
**Prevention:** the `lint-infra-ignore` region exists for exactly this — reach for it rather
than contorting the prose.

**2. A shell-semantics probe measured the wrong thing.** The `export X=$(cmd)` hazard test ran in
an inline subshell where `set -e` was suppressed, reporting **both** forms unsafe. Recovery:
retested in real script files, which gave the correct, decisive result. **Prevention:** shell
semantics probes must run in real script files under the production interpreter — an inline
`bash -c` does not inherit the errexit context being measured.

**3. Read a stale `rc=0` as completion.** The mutation battery's rc file was left by a prior run;
the battery was still executing. Recovery: deleted the rc file and re-observed growth.
**Prevention:** delete the rc file before launching, and require BOTH the rc file AND the
runner's terminal marker. See [[2026-07-30-a-known-gap-of-seven-was-a-predicate-and-my-battery-mutated-one-axis]].

**4. Nearly reported a catastrophic fail-open from a comment.** I reasoned from cloud-init
comments that `-target` would not pull the LUKS resources into the plan, which would have meant
the destroy-guard failed open. Recovery: ran the actual plan — both resources appeared as
`create`, the guard fired `luks_key_touched=2`, ABORT. **Prevention:** for any claim about what a
plan *contains*, run the plan. Comments describe intent, not graph edges.

**5 + 6. Guessed floor constants.** `EXPECTED_PASSES=38` (measured 34); `EXPECTED_ASSERTIONS=24`,
then over-corrected to 20 (measured 22). **Prevention:** derive from a green run and paste the
measured integer; never write the number you expect.

**7. Three mutations silently failed to land** (heredoc `\$` escaping) and reported VOID.
Recovery: moved the mutator into a standalone Python file with an explicit anchor-count assert.
**Prevention:** assert the mutation landed by diffing against a **pristine backup**, never
against HEAD (legitimately dirty during a review pass); treat baseline-identical as UN-RUN.

**8. Wrong diff direction for collision detection.** `git diff HEAD..origin/main` listed my own
files as sibling collisions. **Prevention:** collisions are `comm -12` of
`(merge-base..origin/main)` against `(merge-base..HEAD)`.

**9. `comm` failed on sort order.** **Prevention:** `LC_ALL=C sort` before any `comm`.

**10. Wrote to a scratchpad directory that no longer existed.** **Prevention:** `mkdir -p` in the
same command that writes.

**11. My SC2015 fix enabled a new vacuity** — see Key Insight. **Prevention:** exact
assertion-count floor after any reporter change.

**12. My ADR-169 amendment condemned ADR-169's own adopted design** — see Key Insight.
**Prevention:** test a new normative clause against the predicates the same ADR adopted.

**13. Misattributed the runbook's error to ADR-096.** Cold-vehicle item 3 names the `/health`
parse and never mentioned Doppler; the "confirm it in Doppler" instruction was in the runbook row
this PR removed. **Prevention:** quote the artifact you are correcting **in full** before
asserting what it said. Same class as
[[2026-08-06-my-correction-overshot-into-a-new-wrong-claim-in-a-compliance-artifact]].

**14. Shipped an unguarded hard-fail into a four-caller composite action.**
`cf-tunnel-registry-bridge` is invoked by `reusable-release.yml` and both inngest image builds,
not just the recut chain. The old line could not fail (`|| echo "soleur.ai"`); mine ran under
`set -euo pipefail` — adding an abort arm to the **release pipeline** during an active registry
incident, which is the same blast-radius objection that cut the web-host conversion from this
very plan. The same file already guarded `${GITHUB_WORKSPACE}/scripts/*` with `-r` checks two
functions down. **Prevention:** apply a plan's own scope-cut rationale to what you did ship, and
grep the file you are editing for how it already treats the same dependency.

**15. Guarded the wrong variable.** `app_domain` and `app_domain_base` are independent Terraform
variables, and `APP_DOMAIN` is live in `prd_terraform` — so `TF_VAR_app_domain` is injected on
every apply while `APP_DOMAIN_BASE` exists nowhere. A domain move via the only working lever
shifts production while the gate keeps measuring the old host. **Prevention:** before guarding a
variable against override, check which variable actually **has** an override lever wired.

**16. Announced `/compound` instead of invoking it**; the operator had to say "try again".
**Prevention:** already covered by `hr-pipeline-skills-never-inline-after-go-route` and the work
skill's forward-looking-sentence rule. Recorded as a recurrence, not a new rule.

## What the review panel found

Six agents; **3 P1 + 7 P2, all fixed inline, zero issues filed.** More defects in my guards than
in the fix. The three that mattered most:

- **An injection class.** `validate_base` accepted `x@evil.example.com`, making
  `https://app.x@evil.example.com/health` resolve to **evil.example.com** with `app.x` as userinfo. Not merely a
  wrong URL: the gate reads that host to *define the restore set*, and the bridge interpolates the
  same value into `--hostname`, where cloudflared presents the **production CF Access service
  token**. One character-class arm (`*[!a-zA-Z0-9.-]*`) closes `@`, `:`, `?`, `#`, `%`, quote,
  backslash and IDN homoglyphs together.
- **Two live false-aborts** that re-armed the original defect via routine Terraform edits: a
  `validation {}` block placed above `default` (and `variables.tf` already carries eight), and a
  trailing `#` comment on the default line.
- **Three vacuous rows in the wiring gate.** Pointing an arm at a different script while a comment
  named the audited one passed 21/0; so did replacing the fail-closed abort with a hardcoded
  fallback; so did reverting the bridge to a literal. All now anchored on call forms and extracted
  blocks — see [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]].

## Also recorded

**AC1 and AC10 each contradicted a decision made later in the same plan**, and neither is visible
from the ACs alone. AC1 demanded residual-zero across the whole workflow while Phase 4 kept two
sites deliberately cut; AC10 required widening the ADR the same plan calls a category error. Both
recorded in `knowledge-base/project/specs/archive/20260809-184702-feat-one-shot-d10-health-url-derivation/decision-challenges.md`.

## A gap found while archiving this learning

`archive-kb.sh` discovers artifacts by globbing the **branch slug**
(`one-shot-d10-health-url-derivation`). A plan's filename derives from the plan's own *title*,
not the branch — here `2026-08-06-fix-registry-luks-recut-d10-health-url-derivation-plan.md`.
The two share only a suffix, so the glob archived the spec directory and silently left the plan
behind, reporting `Archived 1 artifact(s)` — which reads as complete.

Half-archived is worse than either state: the spec is in `archive/` while the plan it derives
from is still live, and nothing flags the asymmetry. Archived the plan by hand under the same
timestamp. The durable fix is for discovery to also glob the plan's `feature:`/`branch:`
frontmatter (both name the branch) rather than relying on filename overlap.

## See also

- [[2026-07-29-my-guard-tested-the-one-case-that-cannot-happen-in-production]] — the sibling
  shape: a guard whose discriminating case is unreachable in its shipping environment.
- [[2026-07-27-my-ab-could-not-resolve-the-effect-i-concluded-from-it]] — measuring the wrong
  thing confidently.
- [[2026-08-06-the-gate-i-built-to-catch-a-blind-spot-had-the-same-blind-spot]] — a guard-building
  PR reproducing its own defect class.
- [[2026-07-20-my-anti-echo-guard-was-defeated-one-layer-below-the-layer-i-reasoned-about]] —
  reasoning at the wrong layer.
