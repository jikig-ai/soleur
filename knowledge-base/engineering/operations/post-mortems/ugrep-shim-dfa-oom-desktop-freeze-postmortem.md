---
title: "The `grep` shim built a 9.5 GB DFA against a 21 kB file, froze a 31 GB desktop and killed six concurrent sessions"
date: 2026-08-03
incident_pr: 7167
incident_window: "2026-08-01 (observed freeze, six sessions killed) → 2026-08-03 (neutralized in #7167). The shim itself has been present since Claude Code began installing it in the shell snapshot, so every prior session was exposed; only a pattern whose cost depends on literal reachability triggers it."
recovery_at: "2026-08-03 — `.claude/hooks/grep-rewrite.sh` prepends a `grep()` redefinition routing to GNU grep, merged in #7167. Immediate recovery on the day of the freeze was a manual kill of the runaway process."
suspected_change: "None in this repo. Claude Code's shell snapshot installs a bash FUNCTION named `grep` that re-execs the `claude` binary with argv[0]=ugrep. ugrep's DFA construction is superlinear in the repeated-atom width when a bounded repeat's literal is REACHABLE in the subject; the same pattern costs ~7 MB or 1.67 GB depending only on whether its literal occurs. No static property of the command predicts it."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability (the operator's workstation became unresponsive; six concurrent agent sessions were killed)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
# Classification rationale: this is a local AVAILABILITY event on the operator's own
# workstation. No personal data was accessed, altered, lost or disclosed — the runaway
# process was a regex engine allocating memory, and it read only files the operator's own
# grep already had access to. No customer surface, no credential, no third party. Art. 33
# notification is therefore not engaged; Art. 34 likewise. Recorded explicitly rather than
# left blank because a `single-user incident` threshold makes the reader expect the GDPR
# evaluation to have happened.
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

A single `grep` invocation against a 21 kB markdown file consumed **9.5 GB RSS in 171 s at 99% CPU** and was still climbing when it was killed. The operator's 31 GB workstation became unresponsive and **six concurrent Claude Code sessions were lost**.

The cause was not the file and not the repo. Claude Code's shell snapshot installs a bash **function** named `grep` that re-execs the `claude` binary with `argv[0]=ugrep`. So a command that reads as ordinary GNU grep silently runs a different engine with a different cost model.

## Status

resolved — the shim is neutralized for every Bash tool call carrying a `grep` substring, and the mechanism is enforced by a registered PreToolUse hook plus CI gates that fail if the hook is dropped, made non-executable, or joined by a second rewriter.

## Symptom

`ps` attributed the runaway process to `2.1.220` — the **Claude Code version string** — because the re-exec rewrites `argv[0]`. The process therefore read as a Claude Code memory leak rather than as a grep. That misattribution is the single most expensive detail of this incident: it pointed the first diagnosis at the wrong component entirely.

## Incident Timeline

- **Start time (detected):** 2026-08-01, at the moment the desktop stopped responding.
- **Misattribution:** `ps` named `2.1.220`; the working hypothesis became "Claude Code is leaking".
- **Correct attribution:** the re-exec was found in `~/.claude/shell-snapshots/*.sh` — a `function grep` wrapping `exec -a ugrep "$_cc_bin" -G --ignore-files --hidden -I --exclude-dir=…`.
- **Recovery (day of):** manual kill. No data loss beyond the six killed sessions' in-flight context.
- **Root-cause characterization (#7163):** three successive cost models were proposed and **all three were measured wrong in both directions** — see below.
- **Fix (#7167, 2026-08-03):** neutralize the shim by prefixing a `grep()` redefinition.

## Root Cause

Two independent things had to be true.

**1. The engine is not the one the command names.** `grep` resolves to a bash function, not `/usr/bin/grep`. Nothing in the command text says so, and `--version` output is the only cheap tell.

**2. ugrep's cost is not a function of the pattern alone.** This is what defeated every attempt to solve it with a deny gate. Measured, hard-capped:

| Pattern | Literal in corpus? | Peak RSS |
|---|---|---|
| `[0-9]{0,80}x[0-9]{0,120}` | no | 7.3 MB |
| `[0-9]{0,80}5[0-9]{0,120}` | **yes** | **1.67 GB — killed** |

Same pattern shape, same bound product; the only variable is whether the literal is **reachable in the subject**. No static analysis of the command can know that. Three cost models (bounded-repeat-plus-alternation; `∏(upper+1) ≥ 500`; a width-of-repeated-class heuristic) were each refuted — each denied benign regexes costing ~7 MB (UUIDs, ISO timestamps, and the conflict-marker regex inside `guardrails.sh` itself) while allowing genuine blowups.

So the fix could not be a *decision about the command*. It had to be a change to *what the command runs* — which required granting the hook layer an authority it did not have.

## Resolution

`.claude/hooks/grep-rewrite.sh` prepends a `grep()` shell-function redefinition and leaves the command **byte-identical**:

```
grep(){ …command grep… }; <original command, untouched>
```

Bash resolves the name at execution time. Nothing is parsed, so nothing can be mis-parsed. All 12 of the shim's bypass arms are mirrored byte-exact, so a bypass-flag call receives exactly what it receives today.

An earlier design parsed the command and spliced `command grep` over each `grep` token. A 5-agent panel reproduced **seven** corruption failures in it, four of which break commands that work today. The prefix design dissolves all seven and additionally fixes the two forms the parser could not (`G=grep; $G …` and `eval "grep …"`), because those resolve the name through the shell too.

Authority and its bounds: **ADR-162** (single rewriter, never `permissionDecision`, build from the whole `tool_input`, idempotent, fail-open at `exit 0`, permission matching on the original).

## What Went Well

- The misattribution was caught rather than shipped. `ps` naming the Claude Code version was a genuinely convincing wrong answer.
- The three refuted cost models were **measured and recorded** (#7163) rather than argued. That is what made the pivot away from a deny gate defensible instead of a hunch.
- The fix was validated against 12,057 real Bash commands from session transcripts: zero corrupted.

## What Went Poorly

- **Three weeks of exposure, invisible.** The shim has always been present; only a reachable-literal pattern triggers it. There was no signal until a workstation froze.
- **The first fix design was wrong** and only a multi-agent panel caught it — seven reproducible corruption failures in a mechanism that had already been planned and reviewed once.
- **The fix's own performance claim was wrong.** The benchmark compared the new implementation against *itself* in two configurations and never against the shim, so a ~2.25× recursive-grep regression shipped described as a win until review re-measured it. Corrected in the ADR, spec and PR body.
- **Two P1s were introduced by a mitigation added mid-review** (`--include` defeats the `.env` exclude; `-R` reads through it via symlink). Found only because a failed review agent was re-run rather than written off.

## Action Items & Follow-ups

| Issue | Item | Owner |
|---|---|---|
| #7223 | `gh pr/issue` bodies reach a public repo unscanned. Surfaced by this work: dropping ugrep's `--ignore-files` means recursive grep can now surface gitignored file contents into the transcript, and nothing scans the GitHub egress path. Ingress is mitigated at the modal case; egress is the durable fix. | agent |

**The second mitigation already landed.** #7166 (memory backstop via systemd
`StartTransientUnit` + a shared `soleur-agents.slice`) closed COMPLETED on
2026-08-03, in parallel with this work. So the incident now carries BOTH controls,
and they fail independently: this PR is a *lexical* mitigation (it neutralizes the
shim wherever bash resolves the name), while the slice is a *bound* (it holds
regardless of whether the lexical coverage is complete). DHH's plan-review argument
that the cap should land first is satisfied by it landing at all — the guarantee is
now a bound, not a lexical bet. It is deliberately NOT listed as an action item
above: it is done, and a closed issue in a follow-ups table reads as outstanding work.

#7223 is the only residual, and it is OPEN and issue-backed. No further residual work: the hook, its 71-assertion suite, the registration/exec-bit/single-rewriter gates and the aggregator readout are all pinned by tests in #7167, and each was mutation-proved (10/10, then 7/7 post-review, plus 4/4 on the coverage gates).

## Prevention

- **The rewrite itself**, registered on the PreToolUse `Bash` matcher, with `SOLEUR_DISABLE_GREP_REWRITE=1` as the rollback lever.
- **CI gates that fail if the mechanism is dropped:** registration membership (a deleted registration reddens), index-mode `100755` (a hook committed non-executable reddens), and a single-rewriter invariant (a second rewriter reddens, including one hidden in `lib/` or a `.py` hook).
- **Telemetry with a readout:** `grep-rewrite-*` ids are exempt from the aggregator's orphan gate *and* surfaced via `grep_rewrite_fault_count` plus a stderr WARNING — the exemption without the readout would have made a disarmed rewriter invisible, which four review agents independently flagged.
- **The generalizable lesson is recorded separately** in `knowledge-base/project/learnings/2026-08-03-my-ab-had-the-wrong-baseline-arm-so-i-shipped-a-regression-as-a-win.md`, because its highest-value content is about measurement discipline, not about grep.

## Related

- #7163 — the diagnosis and the three refuted cost models (learning: `2026-08-02-ps-named-it-2-1-220-so-a-grep-that-ate-the-box-read-as-a-claude-leak.md`)
- #7151 — an earlier attempt, closed unmerged
- ADR-162 — PreToolUse hooks may rewrite tool input, under a single-rewriter invariant
- `.claude/hooks/UPDATED-INPUT-PAYLOAD-SHAPE.md` — the measured `updatedInput` contract
