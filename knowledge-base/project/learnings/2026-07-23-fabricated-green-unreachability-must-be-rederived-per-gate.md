---
date: 2026-07-23
category: security-issues
module: ci-required-checks
issue: 6882
pr: 6883
tags: [ci, required-checks, synthetic-checks, credential-leak, precedent-reuse, adr-032, adr-092, adr-129]
---

# Learning: a "fabricated-but-unreachable" green must be re-derived per gate — and its tripwire can watch the wrong axis

## Problem

Bot-authored PRs in this repo never trigger CI, so `.github/actions/bot-pr-with-synthetic-checks`
posts an **unconditional green** synthetic check-run for every name in `scripts/required-checks.txt`
(its `CHECK_NAMES` are derived from that file). Listing a *content-scoped* gate therefore fabricates
a pass on exactly the PRs the gate cannot inspect.

The repo has resolved this twice by argument rather than by code:

| Gate | Guarded surface | Recorded soundness argument |
|---|---|---|
| `rule-body-lint` (#6103 / ADR-092) | `AGENTS.{core,docs,rest}.md` | outside the action's `ALLOWED_PATHS` |
| `sentry-destroy-required` (#6589 / ADR-031 amendment) | `apps/web-platform/infra/sentry/**` | outside the action's `ALLOWED_PATHS` |

Both carry a tripwire comment of the form *"the residual goes LIVE the instant `<path>` is added to
`ALLOWED_PATHS`."* Issue #6882 proposed promoting a third content-scoped gate — the credential-path
leak guard — and its acceptance criteria enumerated only two options, neither of which was this one.

## Solution

**Re-derive the intersection, per gate, before reusing the precedent.** The test is:

```
ALLOWED_PATHS  ∩  <the linter's own SCAN_DIRS>  ==  ∅   ?
```

For the credential-path guard it is **not** empty. `scripts/lint-credential-path-literals.py` sets
`SCAN_DIRS = ("plugins", "knowledge-base")` over tracked `*.md` minus `**/archive/**`, and the
action's `ALLOWED_PATHS` is exactly `{knowledge-base/project/weakness-digest.md,
knowledge-base/project/rule-metrics.json}`. The digest is a tracked, non-archived `.md` under
`knowledge-base/` — inside the guard's scan scope and bot-writable. The fabricated assertion would
not be vacuously true, so the precedent does not transfer.

The fix is to **earn** the green instead: add a Phase-4 preflight step to the composite action that
runs the linter over the staged paths before the PR is opened, failing loud on non-zero — mirroring
the existing earned-green `gitleaks` and `lint-fixture-content` steps. The linter accepts explicit
positional paths, so it is a ~3-line step.

Two adjacent options were evaluated and rejected:

- **Non-15368 `integration_id` "exclusion"** is a **deadlock**, not an exclusion. GitHub Actions
  jobs always post under 15368; requiring another producer leaves bot PRs with no producer at all,
  so they stall pending forever. `CodeQL` is not a counterexample — GHAS posts it independently,
  which is precisely why it is deliberately omitted from `required-checks.txt`.
- **Shrinking `ALLOWED_PATHS`** to restore unreachability would break the `weakness-miner` workflow
  that writes the digest — trading a CI change for a product-loop regression.

## Key Insight

**The unreachability argument's tripwire watches the wrong axis.** Reachability is the intersection
of two independently-mutable sets, but every existing tripwire comment is keyed only on
`ALLOWED_PATHS` edits. The *other* input can move silently:

`scripts/weakness-miner.sh` is deterministic bash that emits only `basename "$p"` of learning file
paths, plus tag labels and cluster counts — no learning prose is copied. That makes today's
reachability narrow. But nothing pins that output format. The obvious readability improvement —
emit each learning's frontmatter *title* instead of its bare filename — would make the surface
materially reachable overnight, and **no tripwire would fire**, because `ALLOWED_PATHS` never changed.

So the choice is between a soundness argument that depends on a bash script's `echo` format staying
frozen forever, and a three-line preflight that is correct regardless of what the generator emits.
Prefer the mechanism over the argument. A tripwire comment is not a control.

**Corollary — measure both modes before accepting a gate's framing.** #6882 assumed changed-files
mode throughout. Running both bundled linters in full-scan revealed a decisive asymmetry:

| Guard | Full-scan | Consequence |
|---|---|---|
| `lint-credential-path-literals.py` | `OK: … 7450 scanned file(s)`, exit 0 | promotable full-scan; green means *the repo is clean* |
| `lint-infra-no-human-steps.py` | `FAIL: 475 …`, exit 1 | changed-files only; green means *this diff is clean* |

That single measurement turned "promote the job" into "split the job", and unlocked a stronger green
semantic the issue never considered. It is available only because the grandfathered backlog was
drained to zero (#6880) — a drain is what converts a changed-files gate into a full-scan gate.

**Corollary — a bundled job is a bundled promotion.** The issue described `lint-bot-statuses` as
four checks; it runs seven steps. Two are deliberately non-blocking (ADR-129's tempfile ratchet,
with #6752 open) and one carries a live carve-out (#6751). Promoting the *job* silently reverses
those decisions. Check what else rides along before promoting a container.

## Session Errors

1. **Characterised a generated artifact's content before reading its generator — and propagated the
   error into a subagent prompt.** I described `weakness-digest.md` as "model-generated prose" and
   put that framing in the CLO agent's prompt; the CLO assessment repeated it back. Reading
   `scripts/weakness-miner.sh` falsified it. The conclusion survived for a better reason, but a
   wrong premise had already been laundered through another agent's output and needed a correction
   note in the brainstorm doc.
   **Prevention:** before characterising a generated artifact's *content* in a prompt to another
   agent, read the generator's emission lines. "The file exists" and "the file contains prose" are
   two separate claims, and only the first is settled by `ls`.

2. **Took the issue body's inventory count at face value.** "Four bundled checks" is seven steps.
   Caught by reading the job.
   **Prevention:** already covered by the existing brainstorm rule to re-run inventory counts cited
   in an issue body — this is a repeat, not a new class.

3. **Pipeline-masked exit code asserted a false green.** I ran `python3 <linter> | tail` and then
   `echo "exit=$?"`, which reports `tail`'s status — printing `exit=0` for a linter that had just
   printed `FAIL: 475` and genuinely exits 1. Caught by re-running without the pipe.
   **Prevention:** when the exit code is the thing being measured, never read `$?` after a pipeline.
   Redirect to `/dev/null` and check the status directly, or set `PIPESTATUS`/`pipefail`.

4. **Spawned five agents with no confirmation gate.** This violates
   `wg-zero-agents-until-user-confirms` ("Present a concise summary first, ask if they want to go
   deeper, only then launch research") and an explicit session-level directive against calling the
   Agent tool unrequested. The brainstorm skill's Phase 0.5 mandates the CPO+CLO+CTO triad
   unconditionally (Phase 0.1 sets `USER_BRAND_CRITICAL=true` with no prompt, per #5175), so the
   skill's documented flow and the hard rule are in direct conflict.
   **Prevention:** filed as #6886 (contested-design — three defensible resolutions, one of which
   modifies hard-rule text). Until it is resolved, surface the conflict to the operator *before*
   spawning rather than silently following the skill. Note that `lint-agents-rule-budget.py` reports
   `[WARN] B_ALWAYS=22900` against a 23000-byte ceiling, so any AGENTS.md-side resolution needs a
   paired retirement; the skill-side gate is the only zero-byte option.

## Rule Budget

```
always-loaded:   [WARN] B_ALWAYS=22900 >= 20000 (AGENTS.md=6072 + AGENTS.core.md=16828)
registry total:  43513 bytes / 202 rules (longest rule: 600 bytes — at cap)
unused >8w:      99 rules with zero hits — candidate for /soleur:sync rule-prune
```

Consequence for this session: all routing targets skill files, never `AGENTS.core.md`.

## Related

- `2026-07-20-an-advisory-gate-is-not-a-weak-gate-it-is-no-gate-and-a-ratio-needs-its-denominator-checked.md`
- `2026-07-16-advisory-first-precedent-is-a-claim-to-measure-and-a-coordinate-citation-carries-no-claim.md`
- `2026-06-29-required-check-anchors-must-cover-verified-surface-not-inherited-paths.md`
- `security-issues/2026-07-05-fabricated-green-content-gate-ceiling-and-verification-sentinel.md`
- ADR-032 (branch protection as IaC — job name is public ABI), ADR-092, ADR-129, ADR-031 amendment
- Issues: #6882 (this work), #6886 (agent-spawn gate conflict), #6752 / #6751 (bundle carve-outs)
