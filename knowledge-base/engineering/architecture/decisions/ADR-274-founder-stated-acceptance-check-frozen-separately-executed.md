---
title: Founder-stated acceptance check, frozen and separately executed
status: accepted
date: 2026-10-06
supersedes: none
issue: 9578
related: [9578, 9577, 9620, 9588, 7412]
related_adrs: [ADR-175, ADR-229]
tags: [preflight, plan, acceptance, founder, sandbox, freeze, self-hosted, check-13]
brand_survival_threshold: single-user incident
---

# ADR-274: Founder-stated acceptance check, frozen and separately executed

## Status

**Accepted - 2026-10-06 (#9578).** Self-hosted CLI only, Linux first. Hosted Command Center capture is out of scope and waits
on #9620; no marketing, changelog or demo copy may claim this feature before it ships.

## Context

The founder never defines engineering "done" today: acceptance criteria are written by the agent that then does the work. #9578
asks for the founder to state, in their own words and before work starts, what proves a piece of work is done, and for a step other
than `work` to run it. The issue is explicit that this extends the plan's acceptance field and does not build a new engine.

The cost of getting it wrong is a single founder who trusts a "passed" label on broken work, or whose command output leaks a token
into a public repository (`brand_survival_threshold: single-user incident`). So the design is organised around six properties:
the founder states it in their own words; approves the exact runnable text, not a paraphrase; the text cannot change unnoticed;
the check fails before the work (it is not vacuous); a step other than `work` runs it and the result claims only what is true; a
failure stops and asks, and an override is recorded as an override.

## Decision

**A `founder_check:` block under `## Acceptance Criteria` in the plan, frozen by a commit, run by a new preflight Check 13 through
the existing Step 10.5 sandbox.** Everything else follows from not adding a mechanism the six properties do not need.

1. **Capture** (`soleur:plan`, interactive only). The founder's words are stored verbatim as `text`; the agent proposes a literal
   `command` and one literal `expected` substring; the founder approves that exact text. Headless runs ask nothing and write no block.
2. **Must fail first.** `soleur:preflight --founder-check-baseline` runs the check against the pre-work tree. A check that already
   passes is `VACUOUS` and refused; a tooling failure (timeout, command not found, an unhealthy sandbox) is `INVALID`, never a
   baseline fail. `creates:` lists data paths the work will produce, so "the new file exists" can be baselined for the right reason.
3. **Freeze = the earliest reviewed copy.** The freeze is the plan's copy at the merge base when it was already reviewed on main,
   else the earliest branch commit carrying the block. The freeze commit precedes the first commit outside `knowledge-base/`; an
   ordering violation is a stop-and-ask, not a hard FAIL. Check 13 compares the canonical fields (`kind`, `text`, `command`,
   `expected`, `creates`, `pins`) of HEAD to the freeze, so a reformat passes and any edit stops. `hash:` is an identity shown in the
   log, **not** the integrity control: a hash is self-consistent by construction, and editing the block and recomputing the hash in one
   commit passes a hash check while the freeze comparison still reds it.
4. **A script the work writes is the agent certifying itself.** An interpreter verb (`bash python3 node bun`) is accepted only when
   every repo-relative script it names already exists at the freeze and is recorded in `pins:` by git blob sha; `creates:` is
   accepted only with non-interpreter verbs. A pinned script edited after the freeze is a change like any other.
5. **Run it only through Step 10.5.** Check 13 sets `CMD` and runs the Step 10.5 fence inside a command substitution; it carries no
   sandbox of its own and `founder-check.py` executes nothing. The Step 10.5 sandbox is **unchanged**; ADR-175's Layers 1 and 2
   apply as written and `credentials_required` gets no waiver (a check needing credentials is a `needs-your-eyes` check).
6. **Authorship anchor.** A block executes without a prompt only when the freeze commit's author email equals the local operator's
   and, when a PR exists, the PR author's login equals the authenticated login. Otherwise it is `UNTRUSTED`: interactively the exact
   command is shown and nothing runs before the answer; headless it FAILs and never executes. Check 13 is not path-gated like Check
   10, so without this a contributor's PR head carrying a self-consistent plan would run on the operator's machine with no prompt.
7. **Outcome vocabulary.** `PASSED` (ran, returned success), `FAILED`, `FAILED-AS-EXPECTED` and `VACUOUS` (baseline), `INVALID`,
   `SKIP-NOSANDBOX`, `NEEDS-YOUR-EYES` / `FOUNDER-CONFIRMED` (a judgement check: the founder, not a command, decided), `OVERRIDDEN`,
   `UNTRUSTED`, `CHANGED-SINCE-APPROVAL` and `STOPPED-AWAITING-FOUNDER`. A pass is labelled "ran, returned success against
   `<sha>`", never a bare PASS, and the wording constants are pinned by tests and reviewed by the CLO. Headless mode refuses
   `OVERRIDDEN` and `FOUNDER-CONFIRMED`; a failing check there is `STOPPED-AWAITING-FOUNDER`. An agent never decides for the founder.
8. **No output text is ever committed.** `founder-check-log.md` records kind, command, rc, outcome, `attempt_n`, `tested_sha`, the
   block hash, time, `output_sha256` and `expected_matched`. Output is shown in the terminal only: a regex scrubber for secret
   shapes has false negatives and a false negative is the single-user leak. The founder is told at every capture that `text` and
   `command` are committed to the repository and that one check does not cover everything.

### ADR-229 verification (no change)

ADR-229 models skill-level lifecycle transitions; `preflight` and `qa` are non-node skills the offline classifier drops. "Check
failed, go back to work" is the existing `ship → work` / `review → work` edge (its doc comment already names "preflight/QA
failed"); "change the check mid-ship" is the declared `work → plan` edge. "Stopped awaiting operator" and "override" are not FSM
concepts. Nothing is added to `ONE_SHOT_CHILD_SKILLS`, `IMPLEMENTATION_TAIL` or `DECLARED_TRANSITIONS`, so `workflow-fidelity.ts`
and `skill-body-budget.json` are untouched. This was verified by a full read of both ADRs; the next reader need not redo it.

## Alternatives Considered

Cited from the plan's Cut List, not restated: a new agent, a new ADR-229 edge, hosted capture in slice 1, running from `qa`
(8 bytes of body headroom, a different authority), a new standalone skill (a `description:` budget at its cap) and generalising
Check 10 in place (its gates and its OR-token matching are wrong for a founder check) were each cut for buying nothing the six
properties need. Extracting the sandbox into a script was rejected here: it conflicts with the pinned inline `BWRAP_ARGS` and
`lint-window-closure-assertion.py`; it is the operator's call if the wrapper proves brittle.

## Consequences

- **Tamper-evident, not tamper-proof.** The authorship anchor compares identity strings that the operator's own agent can also write
  (the same circularity as ADR-175's PR-head case); an agent that rewrites branch history is not stopped by comparisons it also
  controls. Overrides are legible, attributable and visible in the PR diff; they do not authenticate the founder.
- **Host-loopback pivot (#7412) is unchanged and not claimed closed.** `--share-net` keeps the operator's real loopback and egress
  reachable from a check.
- **Stale-pass window.** Preflight runs at ship Phase 5.4; Phase 5.5 gates can mutate code and the Phase 7 behind-sync merges main
  afterwards, and neither is a back-edge. The pass wording, the aggregate row and the log row therefore name the commit tested.
- **Headless reach gap.** One-shot runs give no founder to ask, so a plan with no block skips Check 13 and prints the banner. Reach is
  a tracked follow-up (a pre-supplied block for headless runs needs `ship/SKILL.md` ceiling surgery), not hidden.
- **Linux-first.** bubblewrap is Linux-only (ADR-175), so on macOS a command check cannot run and only a `needs-your-eyes` check can
  be captured. An un-sandboxed run there would contradict ADR-175's fail-closed posture and is not offered.
- **Most real checks may be judgement checks.** The verb list has ten entries, no pipes, a read-only repo and a 15-second cap; test
  runners and builds hit those limits, and `node` / `bun` are not found inside the sandbox on mise or asdf installs. Capture warns the
  founder before approval.
- **The log is evidence, not an authority.** On the abort path `ship` stops before it commits artifacts, so a failure row may never be
  committed.
- **Observability (layer 7).** A self-hosted CLI surface has no Soleur-side sink by design. The signal is the metadata-only
  `SOLEUR_FOUNDER_CHECK_RESULT` marker plus the committed log, read back by `founder-check.py summary`.

## C4 impact

The `contributor` actor's description and its adjacent comment in `model.c4` said the discoverability probe is the one PR-head artifact
preflight executes; they now say plan-declared probes and checks, with no count. No element or relationship is added.
