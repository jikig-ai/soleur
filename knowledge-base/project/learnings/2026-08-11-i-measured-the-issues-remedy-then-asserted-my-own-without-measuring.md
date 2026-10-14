---
module: soleur-plugin
date: 2026-08-11
problem_type: security_issue
component: plugin_command
symptoms:
  - "/soleur:sync silently loses 4 of 8 areas on a customer repo"
  - "a same-named customer script executes instead of the plugin's producer"
  - "an ambient CLAUDE_PLUGIN_ROOT executes a hostile payload past the preflight"
root_cause: environmental_property_asserted_as_construction_guarantee
severity: high
tags: [plugin-root, anchoring, fail-closed, mutation-testing, vacuous-assertion, verification]
synced_to: []
---

# I measured the issue's remedy and caught a no-op. Then I asserted my own and did not.

**Issue:** #7442 · **PR:** #7443 · **ADR:** ADR-179 (amends ADR-093) · **Spun out:** #7450 (P0), #7452, #7453

## Problem

`/soleur:sync` was reported unrunnable for 4 of 8 areas on a real customer repo. Its
producers were invoked with paths relative to the caller's working directory — correct in
this monorepo, which self-hosts the plugin, and wrong everywhere else, because on a customer
machine `scripts/` is **their** `scripts/`. On a name collision it executes **their** file,
under an agent that files GitHub issues from parsed sentinels.

The issue proposed the convention already used at ~98 sites: prefix each invocation with
`${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}`.

## The one thing I did right

**I measured the proposed remedy before applying it.** `CLAUDE_PLUGIN_ROOT` is unset in the
bash tool environment (`${VAR+SET}` empty, `env | grep -c` = 0, verified from inside a
plugin-provided skill context, not merely a plain session). So the `:-` default fires and
expands to `./plugins/soleur` — a path the **customer** controls. **The proposed fix expands
to the defect it was meant to repair.**

The repo already requires re-deriving plan-quoted *numbers* and verifying tool-flag *units*.
This is the same discipline applied to a *remedy*: an issue's diagnosis and an issue's
proposed fix are independent claims, and the second is the one nobody re-checks because the
first was right.

## Then I made the identical error, one section later

ADR-179 shipped asserting the replacement form was safe **"under no hypothesis does it
resolve into customer-controlled bytes."** A review agent measured otherwise:

```
export CLAUDE_PLUGIN_ROOT=/var/tmp/hostile-root   # a .envrc, ~/.bashrc, or postinstall
→ preflight `test -d "$X/scripts"`: PASSED against a non-plugin directory
→ HOSTILE PAYLOAD EXECUTED
```

`CLAUDE_PLUGIN_ROOT` is an ordinary environment variable and the Bash tool is initialized
from the user's profile. I had treated an **environmental** property as a **construction**
guarantee — *precisely the reasoning error the ADR diagnoses in the `:-` form*, committed a
few paragraphs after diagnosing it.

**A preflight must verify plugin IDENTITY, never directory shape.** `test -d "$X/scripts"`
is satisfied by any directory with a `scripts/` child. The shipped gate requires the payload
manifest to exist AND to name this plugin, raising the bar from "export one variable" to
"plant a complete fake plugin". The correct claim is **comparative**: bare is strictly better
than `:-` (which needs no attacker precondition at all), but it is not safe by construction,
and the preflight is what carries it.

## Every green signal certified something other than what it claimed

Four independent instances in one PR, none visible to a passing suite:

**1. The "decisive cell" never executed its own mechanism.** `tests/commands/test-sync-producer-reachability.sh`
ran under `set -uo pipefail`, which the T0c subshell inherited — so bash aborted at
**parameter expansion** for all 8 invocations and not one reached path resolution. It was
green because bash died early. Worse: a Claude Code Bash block does **not** run under
`set -u`, so the harness tested a shell mode the SUT never inhabits. Fixed with `set +u`
inside the eval subshell; it then genuinely resolves paths and still passes.

**2. The positive control controlled nothing.** T0d eval'd two hardcoded literals and never
touched the extractor T0c depends on. Measured: narrowing the extractor to a subset left a
live pre-fix producer undetected **with T0d still green**. A control must exercise the path
the assertion depends on, not merely fire. Rebuilt to drive a synthesized pre-fix fixture
through the *same* extraction.

**3. My mutation battery reported 8/8 while nine mutants survived.** Every mutation I
imagined edited the operand **content** of an already-recognized line. The survivors changed
a different axis:

| Axis | Surviving mutant |
| --- | --- |
| syntactic shape | `./scripts/x.sh` (direct-exec, no runner token) |
| command position | `cd . && bash scripts/x.sh` (second position) |
| path normalization | `${CLAUDE_PLUGIN_ROOT}/../../x` passed the *residency* check — `resolve()` normalizes `..` straight through the payload boundary |
| parser | a nested ```` fence inverts backtick parity and blinds the guard for the rest of the file |
| dispatch | no assertion-count floor: deleting a case summarized green and exited 0 |

**Audit a battery's AXES, not its count.** N mutations of one shape is one mutation.

**4. My fix for "nothing guards the preflight" pinned spelling, not function.** The first
assertion grepped for the manifest path — which a **gutted gate still satisfies**. Verified:
downgrading the check to directory-shape AND neutering the whole block both stayed green.
The fix was to **execute** the extracted block against a hostile root and require refusal.

## Three assertions naming mechanisms that do not exist

- A comment claiming a `scripts/*.test.sh` glob keeps a suite gated. `test-all.sh` states in
  its own comments that it has no such glob; registration is by hand.
- The plan's `alert_route: "degraded row via write-kb-coverage.ts --producer-unreachable"` —
  a flag that was designed and never built (`--degraded` is the only one parsed).
- A Check 10 `expected_output` that could not match the suite's output, and would have
  **failed preflight at ship**.

Same class as the repo's existing *"an observability plan can name a sink the code cannot
reach."* The gate: for every mechanism your prose names, run the command that would falsify it.

## Reusable technical insight: what makes a script relocatable

**Relocatability is a property of where a script gets its DATA root, not of its directory.**

| Script | Data root | Relocatable? |
| --- | --- | --- |
| `domain-model-drift.sh` | caller-supplied (`--repo <path>`), lib via `$SCRIPT_DIR/lib/` | **Yes** — moved into the payload |
| `rule-prune.sh:52` | `${RULE_METRICS_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}` | **No** — a move silently repoints it |
| `rule-metrics-aggregate.sh:34` | `${INCIDENTS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}` | **No** — same |

This is **necessary, not sufficient**: the code root must move atomically with it, and every
consumer must be repointed in the same commit. Note also that both non-relocatable scripts
*are* parameterized — with a **location-derived default**, which is the same fail-open `:-`
construct the ADR rejects one level up in markdown.

## Delegation insight

My CTO brief omitted the `$SCRIPT_DIR/..` fact, so its first binding ruling instructed
relocating **both** rule-metrics scripts — which would have broken both. One correction
round-trip and it retracted in full, and independently found the aggregator carried the same
defect I had only claimed for the pruner.

**A binding ruling is only as good as the disqualifying facts in the brief.** Enumerate the
facts that would CHANGE the ruling, not just the ones that support your framing.

## Session Errors

**Forwarded from `session-state.md` (planning phase):**

1. **A research subagent asserted relocating `rule-prune.sh` was "safe — critically portable".** — Recovery: falsified by direct read of `rule-prune.sh:52`. — **Prevention:** verify a delegated portability claim by reading the script's root derivation; `$SCRIPT_DIR`-derivation is not portability, it inverts the requirement.
2. **The same agent cited a `scheduled-rule-prune.yml` workflow that does not exist.** — Recovery: `ls` refuted it. — **Prevention:** `test -f` every workflow path a subagent cites before planning against it.
3. **The plan's recurrence chain miscited #4826 as a class member.** — Recovery: live `gh issue view` showed it is the class's *victim*. — **Prevention:** resolve every `#N` in a recurrence chain before asserting membership.

**Implementation:**

4. **My rule-prune sentinel was line-separable.** — Recovery: T0 caught the decoys executing when the invocation was read without its gate. — **Prevention:** a control on a separate line does not survive a line-wise reader; make the operand itself fail-closed in isolation.
5. **`domain-model-drift.test.sh` resolved its SUT as a sibling**, so the relocation broke it invisibly to path-literal greps. — Recovery: repointed with a fail-loud existence guard. — **Prevention:** after any `git mv`, grep for `$SCRIPT_DIR`-relative sibling resolution, not just for the literal path.
6. **Cited `ADR-174` in a shipped message before checking the ordinal** (correct: 177). — Recovery: `check-adr-ordinals.sh`. — **Prevention:** derive the ordinal before writing it into any artifact.
7. **Wrote a comment claiming a `scripts/*.test.sh` glob that does not exist.** — Recovery: read `test-all.sh`'s own comments. — **Prevention:** see "mechanisms that do not exist" above.

**Review — my own work falsified:**

8. **ADR-179's "under no hypothesis" claim was false, measured.** — Recovery: preflight rewritten to verify plugin identity; ADR corrected. — **Prevention:** ask of every safety claim whether it is a property of the CODE or of the ENVIRONMENT.
9. **T0c never executed the mechanism it documents** (`set -u`, 8/8). — Recovery: `set +u` in the eval subshell. — **Prevention:** ask which shell options the harness imposes that the real surface does not.
10. **T0d was not a control over the extractor.** — Recovery: rebuilt over a synthesized fixture through the same extraction. — **Prevention:** a control must fail for the reason the assertion would.
11. **My mutation battery reported 8/8 while nine mutants survived.** — Recovery: review's test-design pass found them. — **Prevention:** enumerate the AXES a battery edits before crediting its count.
12. **First preflight assertion pinned string presence, not gate function.** — Recovery: T0i executes the extracted block against a hostile root. — **Prevention:** name a mutation that satisfies the assertion while violating the property.
13. **The plan's `alert_route` named a flag never built.** — **Prevention:** as #7.
14. **The plan's Check 10 `expected_output` could not match.** — Recovery: bound to the suite's real output. — **Prevention:** run the AC's literal command.

**Process:**

15. **`git checkout -- sync.md` during mutation-verify wiped my own uncommitted fixes.** The review skill documents this exact trap and I hit it anyway. — Recovery: restored from a `mktemp` backup taken before mutating. — **Prevention:** mutate a SANDBOX COPY; if mutating in place, back up first and never restore with `git checkout --` on a dirty file.
16. **An anchored-grep fix shipped with doubled backslashes and an escaped quote inside a single-quoted string.** — Recovery: caught by running the pattern directly against the real file. — **Prevention:** run a regex you just wrote before committing it; do not trust it by reading.
17. **My CTO brief omitted the disqualifying fact**, so the first ruling was wrong. — Recovery: one correction round-trip. — **Prevention:** see "Delegation insight".
18. **Two mutation setup-fails from shell escaping in my own mutator.** — Recovery: switched to a heredoc-based Python mutator. — **Prevention:** pass mutation strings via a quoted heredoc, never through nested shell quoting.
19. **Left the tree dirty after a mutation run before catching it.** — Recovery: restored and re-verified. — **Prevention:** assert `git diff --quiet` after every battery, and treat a dirty tree as a failed run.

### Recurring-vs-one-off triage

| Item | Recurring? | Disposition |
| --- | --- | --- |
| 8, 9, 10, 11, 12 | recurring | this learning + routed to `review` SKILL.md |
| 4, 7, 13, 14 | recurring | this learning ("mechanisms that do not exist") |
| 15, 18, 19 | recurring | routed to `review` SKILL.md (mutation-verify hygiene) |
| 1, 2, 17 | recurring | routed to `plan` SKILL.md (delegated-claim briefing) |
| 3, 5, 6, 16 | one-off | noted here only; no recurrence vector |

## Prevention — the one-line version

Both halves of this session reduce to a single question, asked of a *remedy* rather than a
*diagnosis*: **what would falsify this, and did I run it?** I asked it of the issue's fix and
caught a no-op. I did not ask it of my own, and shipped a false security claim, a vacuous
decisive test, a control that controlled nothing, and three assertions naming mechanisms
that were never built.
