# ADR-227: Compaction state is read from a per-session ephemeral ledger, because the transcript answers too late

- **Date:** 2026-09-18
- **Issue:** #8323
- **Supersedes in part:** the plan's provisional title, "the compaction signal
  is read from the transcript, not from a counter file", which the Phase 0
  measurement falsified before implementation began. It is recorded under
  Alternatives as (a) rather than deleted, because the reasoning that made it
  attractive is still correct and the thing that killed it is a timing fact
  nobody could have read off the docs.

## Status

Accepted.

## Context

Soleur told the operator to "run `/clear` and resume" at two fixed points, the
end of `plan` and the end of `work`, regardless of whether context compaction
had ever occurred. On a session with no compaction the nudge is noise; on a
session that auto-compacted twice mid-`/work` it arrives long after the model
lost the branch, PR and plan state it needed. Locally, 8 of 22 recent sessions
compacted, 11 boundaries in total, so both halves of that mismatch are real
rather than hypothetical.

Claude Code 2.1.76+ exposes the compaction lifecycle to hooks (`PreCompact`,
`PostCompact`, and `SessionStart` with matcher `compact`), and it records every
compaction in the session transcript as a `compact_boundary` record carrying
`compactMetadata.{trigger, preTokens, postTokens}`. The obvious design —
and the one this plan carried into implementation — is to read the transcript at
`SessionStart:compact`, count the boundaries, and decide from that.

**That design does not work, and the reason is a flush ordering no document
states.** Measured on 2026-09-18 against CLI 2.1.273, with a marker hook bound
in a throwaway project and driven by headless `claude -p --continue "/compact"`:

| Reading | Result |
|---|---|
| Boundary count at `SessionStart:compact`, compaction #1 | **0** — the file held 1 afterwards |
| Boundary count at `SessionStart:compact`, compaction #2 | **1** — the file held 2 afterwards |
| Same count at `PostCompact`, ~100 ms later | unchanged, still lagging |
| The boundary record's own `timestamp` | `16:10:14.926Z`, *preceding* the hook fire at `16:10:14.957Z` |

So the record exists in memory when the hook runs and is flushed to disk after
it returns. The transcript cannot answer "how many compactions has this session
had" at the only moment the question matters, and the `SessionStart` envelope
carries no `trigger` field either (`PreCompact` has `trigger`; `SessionStart`
has `source`), so the current compaction's trigger is equally unavailable from
that side. Reading the last on-disk boundary yields the *previous* compaction's
trigger.

A second measurement shaped the mechanism that replaced it. **`PreCompact`
firing does not imply a compaction occurred**: three fires produced two
boundaries, because a `/compact` with nothing left to compact fires `PreCompact`
and then no `SessionStart:compact` at all. Any design that counts `PreCompact`
events over-counts, and over-counting here means recommending that the operator
abandon a healthy session one compaction early — with every fixture green,
because a fixture that replays only complete cycles cannot see it.

## Decision

`plugins/soleur/hooks/compaction-state.sh` derives compaction count and trigger
from a **per-session ephemeral ledger under `TMPDIR`**, written by the same hook
across two bound events, using **pending-then-commit**:

- `PreCompact` **overwrites** a single `pending` slot with its own stdin
  `trigger`. It never appends, precisely because it fires on no-op compactions.
- `SessionStart:compact` **commits** that slot as one ledger line, clears it,
  then counts. It fires exactly once per real compaction, so the ledger holds
  one line per compaction and each line carries that compaction's own trigger.
- `SessionStart` with `source` in `startup|resume|clear` **truncates** the
  ledger and clears pending.

That third arm is why the `SessionStart` matcher is `startup|resume|clear|compact`
rather than `compact` alone. It is also what makes the session-window scoping
exact rather than approximated: boundaries accumulate within one transcript
across `--resume`, so an all-time count would pin the recommendation on forever
for a long-lived resumed session.

The recommendation rule is one integer and one string: `trigger == "auto" AND
count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}`.

**No counter file is introduced in the user's repository, and nothing is
written to the knowledge base.** The ledger lives under `TMPDIR`, is keyed on
the session id, is age-reaped after seven days, and is disposable by
construction: losing it costs one directive, never correctness.

The transcript is still read, once, for a single field — `prior_boundaries`, a
corroboration marker inside `additionalContext`. It does not feed the rule. The
consequence is stated plainly because it narrows a claim the plan made: an
upstream format rename degrades that marker and nothing else, so the FR7 canary
is a **staleness** signal for the measurements recorded in this ADR and in the
hook's header, not a **liveness** signal for the feature.

**No `PostCompact` binding ships in this slice.** See alternative (g).

### First customer-shipped consumer of the transcript format

This is the first Soleur component shipped to customers that dereferences
`transcript_path` and reads conversation history. `.claude/hooks/monitor-supersede-guard.sh`
already parses transcript internals, but it is repo-side: when it breaks, the
operator sees it break, on their own machine, immediately. A plugin hook breaks
silently on other people's machines. The rot economics differ, and FR7 exists
because of that difference rather than as general diligence.

The earlier answer to the rot question — "the suite's fixtures pin the parsed
shape" — is **retracted**. The fixtures are synthesized (`cq-test-fixtures-synthesized-only`),
so they pin the shape Soleur wrote, not the shape the CLI emits; every one of
them stays green through a rename. Every marker also carries the
`claude --version` string, so drift is attributable to a specific CLI bump.

## Alternatives Considered

**(a) Read the count from the transcript at `SessionStart:compact`** — the
plan's primary design. Rejected on the measurement in §Context: the boundary is
not yet flushed, so the count is short by exactly one and the trigger belongs to
the previous compaction. Nothing about the record's *shape* is wrong; the
timing is. Recorded first because it is the design a future reader will reach
for again.

**(b) Piggyback `.claude/.session-manifests/<sid>.json`** — the obvious existing
host. Rejected twice over: it is repo-side, and `session-rules-loader.sh`
overwrites it on every SessionStart **including `compact`**, so the hook's own
state would be destroyed by the event that needs it.

**(c) A counter store committed in the user's repository.** Rejected: it needs a
`.gitignore` entry the plugin cannot add to a user's repo, so it would either
dirty every customer's working tree or be committed by accident.

**(d) The per-session `TMPDIR` ledger.** **Accepted** (see §Decision). It is not
alternative (c): (c) lived in the user's repository and needed an un-addable
ignore rule; this is machine-local, disposable, and reaped. The plan authorized
it as a conditional fallback and the measurement made it the primary. Its one
correction relative to the plan's wording is pending-then-commit instead of
append-per-`PreCompact`, forced by the 3-fires-2-boundaries measurement.

**(e) Skill prose only — tell the model to notice its own compactions.**
Rejected: a model cannot observe its own compaction count. This is the status
quo the feature replaces, and its defect is that it fires identically on a
session with zero compactions and one that has lost state twice.

**(f) `PostCompact` plus a `UserPromptSubmit` rebinding.** Rejected: `PostCompact`
stdout is never model-visible, so the directive would have to be smuggled into a
later event. It also inherits the same lagging count — measured, `PostCompact`
read the stale value 100 ms after `SessionStart:compact`.

**(g) A `PostCompact` checkpoint writer into `session-state.md`**, with a
gitleaks guard. **Deleted by a six-agent plan review**, unanimously, and tracked
for re-proposal at **#8328**. It is recorded here with its two P0s so the
re-proposal inherits them rather than re-deriving them:

1. **Nothing reads it.** `work/SKILL.md` Phase 0 loads `constitution.md`,
   `tasks.md` and `spec.md` — never `session-state.md`. The block would be
   write-only.
2. **`one-shot/SKILL.md` step 3 writes that file from a whole-file template**
   containing no marker, so every plan-phase run destroys any hook-owned block.
   The hook can respect the skill; the skill cannot respect the hook.

Two supporting findings: `.gitleaks.toml` exists at this repo root and nowhere
under `plugins/soleur/`, so on a customer install the guard fail-opens on
essentially every install; and `gitleaks git --pre-commit --staged` reads the
git index, not a string, so the prescribed command could not have done the job.
The gdpr-gate finding about an absolute worktree path carrying the OS username
into a tracked, pushed file is inherited by #8328 with the writer.

**(h) Statusline `context_window`.** Rejected: measured unreachable from hooks.

**(i) A token-ratio clause** (`postTokens/preTokens > 0.15` as a second trigger).
Rejected at review on three independent grounds: the threshold was picked from
n=1 and sits *above* the only real measurement (1006181 → 105006 = 0.104), so it
would never have fired on observed data; it is not independent of the count
clause; and the prescribed `awk 'print (a/b) > 0.15'` is file redirection in
awk, which creates a file named `0.15` and always succeeds.

**(j) Deriving the current phase from the transcript's last `Skill` record.**
Rejected at review: the last record is not the current phase (measured:
`soleur:preflight`), and inside `/soleur:one-shot` it is the child skill, so the
one-shot exception rested on a signal the read path cannot produce. The
directive names the branch and the plan path instead; the phase is legible in
the artifacts it orders re-read.

**(k) Registering the FR7 canary as a `soleur:schedule` GitHub Actions cron** —
the plan's task 4.2. Rejected on measurement after the canary was written: it
reads `~/.claude/projects/**/*.jsonl`, a GitHub runner has none, and the canary
correctly reports TRANSIENT when it cannot measure. The registration would
produce a probe that can never PASS and never FAIL. It is bound instead to the
repo-side `SessionStart` surface, stamp-gated to once per seven days.

## Consequences

- The feature is **Claude Code only**. Codex, Devin and Grok Build degrade to
  silence and say so in their `INSTRUCTIONS.md`; the skill-prose fallback keeps
  the end-of-work resume prompt firing everywhere, with no `/clear` nudge.
- A **plugin hook is global**, so the scope guard is load-bearing rather than
  hygienic. It is `welcome-hook.sh`'s sentinel — a `plugins/soleur` directory —
  **plus** a Soleur plan/spec artifact, never `git rev-parse --is-inside-work-tree`,
  which is true in every customer repo. Without it, a customer compacting work
  on their own application would have their summary shaped around PR numbers and
  operator holds they do not have. This was the worst finding in the plan review
  and both conjuncts are mutation-proven.
- **AP-020 widens.** The principle was scoped to the model-controlled hook-stdin
  envelope; this hook dereferences `transcript_path` and reads full conversation
  history, which is content merely *pointed at* by that envelope. See
  `principles-register.md`.
- Fail-open is the contract: every path exits 0, and `trap 'exit 0' ERR EXIT`
  carries it. The `EXIT` arm is load-bearing and measured, not assumed — on bash
  5.3.15 a `set -u` unbound-variable fault with an ERR-only trap exits **127**;
  with the EXIT arm it returns 0. Any non-zero exit other than 2 makes Claude
  Code silently drop the whole JSON output.

## Verification

- `plugins/soleur/test/compaction-state-hook.test.sh` — 103 cases over 104
  subject invocations, with an instrument self-test that drives both assertion
  arms and refuses to continue unless both counters and the failure ledger move,
  plus case and subject-invocation floors reported with `printf` + `exit` rather
  than through the helpers they backstop.
- A 22-row mutation battery kills 22, with a green control and a byte-identical
  restore check. Three rows survived the first pass: a whole-scenario deletion
  survived a floor with 19 cases of slack (both floors are now pinned to the
  measured count); dropping the `trigger == auto` operand survived because the
  manual-only fixture has `count_auto = 0` and cannot discriminate (scenario 19
  adds two autos followed by a manual, which can); and the third was an
  instrument defect rather than a result — the md5 landed-check proved *a* byte
  changed while the `replace` had hit the header comment quoting the trap line,
  so the row was scored against an unmutated subject.
- `scripts/followthroughs/compaction-format-drift-8323.sh` — all four arms
  driven, including a renamed `subtype` going RED and a positive control still
  going GREEN.
