---
title: Rewrite grep to command grep via PreToolUse updatedInput
issue: 7165
branch: feat-7165-grep-rewrite-updatedinput
pr: 7167
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-08-02-grep-rewrite-command-grep-brainstorm.md
spec: knowledge-base/project/specs/feat-7165-grep-rewrite-updatedinput/spec.md
status: plan
---

# Plan: rewrite `grep` → `command grep` via PreToolUse `updatedInput`

## Overview

A PreToolUse hook on the `Bash` matcher rewrites shim-reaching `grep` tokens to
`command grep` with the shim's GNU-compatible flags replayed. The pattern is never
read, so there is no cost model — the approach #7151 tried three times and had
refuted three times.

Everything load-bearing below was **measured this session**, not derived. The
issue's framing needed five corrections; each is recorded in Research
Reconciliation with the command that produced it.

## Premise Validation

| Cited | Probe | Result |
|---|---|---|
| #7151 (prior attempt) | `gh issue view` | CLOSED, unmerged — premise holds |
| #7163 (learning file) | `gh issue view` | MERGED PR; learning file present on `main` |
| #7166 (memory backstop) | `gh issue view` | OPEN — remains the residual owner |
| `strip_command_bodies` | sourced + called | exists in `.claude/hooks/lib/incidents.sh` |
| `.claude/hooks/*.test.sh` auto-run | `scripts/test-all.sh:577` | confirmed — a new test file is auto-discovered |

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Reality (measured) | Plan response |
|---|---|---|
| D4: "reuse `strip_command_bodies`" | It is **length-destroying** — `echo "grep is data" && grep -E foo bar.txt` goes 42 → 29 chars. Offsets are unusable for a positional rewrite. | Add a **length-preserving** sibling `mask_command_bodies` (same regex family, replaces each quoted/heredoc region with equal-length `\0` filler). Do not reuse the stripper. |
| `updatedInput` is supported | **Verified by execution**, not docs: an isolated `claude -p` subprocess with a throwaway `--settings` hook rewrote a command and the rewritten form ran. | Proceed. Probe re-run is AC1. |
| (unstated) which `permissionDecision` to emit | `allow` **bypasses the permission prompt entirely**. Emitting it on any grep-bearing command would disable permissions for **50.5%** of all Bash calls. Measured: `updatedInput` works with **no** `permissionDecision` at all. | **Never emit `permissionDecision`.** Emit `updatedInput` alone; normal permission flow is preserved. |
| (unstated) interaction with 18 sibling Bash hooks | Measured with a two-hook isolated probe: a sibling `deny` **wins** over our `updatedInput` — the command did not run. | Safe. Our hook cannot un-deny a sibling guardrail. Pinned as AC2. |
| Shim injects `-G --ignore-files --hidden -I --exclude-dir=.git` | Six `--exclude-dir` values (`.git .svn .hg .bzr .jj .sl`). `-G` + `-E` under GNU grep 3.12 → `conflicting matchers specified`, **rc=2**; ugrep tolerates it. `--hidden`/`--ignore-files` rejected outright. | Replay `-I` + all six `--exclude-dir`. **Never** inject `-G`. |
| AC3: "a multi-line payload whose later line carries a regex [is] untouched" | Ambiguous. Under a rewrite, a later line's `grep` **is** a real grep and must be rewritten; the original wording describes the *old classifier's* arming bug. | Restated as FR8 below: arming resets at newlines and `\|&`; each command-position `grep` is rewritten independently. Fixtured both ways. |
| Command position = after `&&`/`\|\|`/`;`/`\|` | **Incomplete — measured false negatives.** Shell keywords are command positions too: `if grep` **27**, `do`/`then`/`else grep` **17**, `{ grep` **9**, `while`/`until grep` **4**, `! grep` **1** across 6,113 Bash calls. All reach the shim; all would be missed. | Anchor set extended to `if then else elif while until do time nice !` and `{`. Verified: `sudo grep` is **not** caught by the `do` substring (lookbehind `(?<![\w-])`). |

## User-Brand Impact

Carried forward from the brainstorm (`hr-weigh-every-decision-against-target-user-impact`).

**If this lands broken, the user experiences:** a corrupted shell command — a
mangled `git grep` (179 measured calls), a rewritten quoted payload (228 measured
calls), or a broken `xargs grep` — so the agent acts on a *wrong* answer rather
than an absent one.

**If this fails open, the user's workflow is exposed via:** a one-line search
reaching 9.5 GB RSS at 99% CPU, freezing the desktop and killing every concurrent
session — the 2026-08-01 incident, unmitigated as of today.

**Brand-survival threshold:** `single-user incident`.

## Implementation Phases

### Phase 0 — Preconditions (no code)

1. Re-run the `updatedInput` probe in an isolated `claude -p` subprocess with a
   throwaway `--settings` (never modify the live session's settings). Confirm:
   rewrite applies, and applies with **no** `permissionDecision`.
2. Re-run the sibling-`deny` precedence probe. Confirm `deny` still wins.
3. Confirm all 6 `--exclude-dir` values and `-I` are accepted by the installed
   GNU grep; confirm `-G` + `-E` still errors (guards against a grep upgrade).

### Phase 1 — `mask_command_bodies` (RED → GREEN)

Add a length-preserving masker beside `strip_command_bodies` in
`.claude/hooks/lib/incidents.sh`. Failing test first: assert
`${#masked} == ${#original}` for a payload with a double-quoted region, a
single-quoted region, and a heredoc body; assert masked regions contain no `grep`.

### Phase 2 — the rewrite hook (RED → GREEN)

Create `.claude/hooks/grep-rewrite-guard.sh`. Verified mechanic (prototyped and
tested against 26 fixtures this session):

1. Read payload; extract `.tool_input.command` **forcing a scalar** —
   `| if type=="string" then . else tojson end` (TR5: the confirmed `eval` + `jq @sh`
   RCE is pre-existing on `main` in 10 files; do not reproduce it here).
2. If the command matches the **shim's own bypass predicate** (`-[Zz]*`, `--null`,
   `--null-data`, `---*`, `-@*`, `-*-filter*`, `-*-pager*`, `-*-view*`,
   `-*-config*`), **return without rewriting** — see OQ1 resolution.
3. Mask quoted/heredoc regions (Phase 1 helper).
4. Find `grep` tokens at command position **in the mask**; apply substitutions to
   the **original** at those offsets, right-to-left.
5. Emit `{"hookSpecificOutput":{"hookEventName":"PreToolUse","updatedInput":{"command":"<rewritten>"}}}`
   — **no `permissionDecision`**. If nothing was rewritten, emit nothing and `exit 0`.

Anchor (verified — do not hand-edit without re-running the fixture matrix):

```
(?:\A|[\n;&|(`{]|\|\&|\$\(|(?<![\w-])(?:if|then|else|elif|while|until|do|time|nice|!)(?=[ \t]))[ \t]*(\\?)grep(?![\w-])
```

Injected replacement:

```
command grep -I --exclude-dir=.git --exclude-dir=.svn --exclude-dir=.hg --exclude-dir=.bzr --exclude-dir=.jj --exclude-dir=.sl
```

Prefix-exclusion (defense-in-depth; the anchor already excludes these
incidentally because none places `grep` adjacent to a delimiter — keep both):
`git`, `xargs`, `-exec`, `command`, `sudo`.

### Phase 3 — fixtures

Create `.claude/hooks/grep-rewrite-guard.test.sh` (auto-discovered by
`scripts/test-all.sh:577`). Mirror `guardrails.test.sh`'s harness shape: synthetic
stdin payloads, `INCIDENTS_REPO_ROOT` redirect, non-git CWD isolation.

### Phase 4 — exec-bit gate

Create `.claude/hooks/hook-exec-bit.test.sh` asserting every hook path referenced
in `.claude/settings.json` is committed **100755 in the git index**
(`git ls-files -s`, not `test -x`).

**Derive the path list from `settings.json`, not a glob.** Measured: 68 of 74
tracked `.claude/hooks/**/*.sh` are 100755, but 6 are legitimately 100644 —
`lib/incidents.sh`, `lib/freeze-lock.sh`, `lib/log-rotation.sh` (sourced) and
`incidents.test.sh`, `lib/freeze-lock.test.sh`, `skill-context-queries.test.sh`
(run via `bash`). A naive `.claude/hooks/*.sh` glob would go **RED immediately**
on two of those. Deriving from `settings.json` asserts the invariant (*what
production execs*) rather than a proxy.

### Phase 5 — ADR + C4

### Phase 6 — mutation battery

Both directions (TR6): deleting the rewrite → RED; mutating the anchor to also
match `git grep` → RED.

## Files to Create

| Path | Mode | Note |
|---|---|---|
| `.claude/hooks/grep-rewrite-guard.sh` | **100755** | the hook |
| `.claude/hooks/grep-rewrite-guard.test.sh` | 100644 | auto-run via `test-all.sh:577` |
| `.claude/hooks/hook-exec-bit.test.sh` | 100644 | settings.json-derived exec-bit gate |
| `knowledge-base/engineering/architecture/decisions/ADR-155-rewrite-not-classify-for-shim-reaching-grep.md` | 100644 | ordinal **provisional** |

## Files to Edit

| Path | Change |
|---|---|
| `.claude/hooks/lib/incidents.sh` | add `mask_command_bodies` (length-preserving) |
| `.claude/settings.json` | register the hook on the `Bash` matcher |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | `hooks` container + `hooks -> claude` label now falsified (see C4 below) |

## Acceptance Criteria

### Pre-merge (PR)

1. **AC1** — the measured reproducer, submitted as a Bash payload, is **rewritten
   (not denied)** and completes cheaply. Probe under `ulimit -v 2000000` + `timeout`;
   expect single-digit MB / sub-second (GNU grep measured 7.7 MB / 0.10 s).
2. **AC2** — isolated two-hook probe confirms a sibling `deny` still wins over our
   `updatedInput`.
3. **AC3** — the hook emits **no** `permissionDecision` key:
   `... | jq -e '.hookSpecificOutput | has("permissionDecision") | not'`.
4. **AC4** — all seven bypass forms fixtured with the FR6 dispositions.
5. **AC5** — all must-not-touch forms fixtured **byte-identical**: `git grep`,
   `pgrep`/`zgrep`/`ugrep`, `egrep`/`fgrep`, quoted-`grep`-as-data, already-`command grep`,
   `xargs grep`, `find -exec grep`, `/usr/bin/grep`, `sudo grep`, heredoc body.
6. **AC6** — `\grep` **is** rewritten.
7. **AC7** — the six shell-keyword positions are rewritten (`if`, `while`, `until`,
   `do`/`then`/`else`, `{`, `!`).
8. **AC8** — shim-bypass commands (`grep -z`, `--null-data`) are **not** rewritten.
9. **AC9** — `git ls-files -s -- .claude/hooks/grep-rewrite-guard.sh` reports `100755`.
10. **AC10** — mutation battery kills **both** directions (TR6).
11. **AC11** — `bash scripts/test-all.sh` green; the new suites appear in the run
    (assert by suite name in the log, not by total count).
12. **AC12** — `ADR-155-*.md` exists and the ordinal is re-verified against
    `origin/main` at ship time (collision gate).

### Post-merge (operator)

None. Every step above is automatable in-session.

## Observability

```yaml
liveness_signal:
  what: hook emits updatedInput on shim-reaching grep
  cadence: per Bash tool call (~50.5% carry a grep token)
  alert_target: none (too high-volume to alert on)
  configured_in: .claude/settings.json PreToolUse[Bash]
error_reporting:
  destination: emit_incident -> .claude/.rule-incidents.jsonl
  fail_loud: true (TR4 — the disarm must not be silent)
failure_modes:
  - mode: malformed payload / jq failure -> fail-open, no rewrite
    detection: emit_incident "grep-rewrite-disarm"
    alert_route: weekly rule-metrics aggregator
  - mode: residual form reached (G=grep / eval "grep ...")
    detection: emit_incident "grep-rewrite-residual"
    alert_route: weekly aggregator — measured 0/6,116 today, so any hit is signal
  - mode: over-rewrite (a must-not-touch form mutated)
    detection: fixture suite AC5 + mutation battery AC10
    alert_route: CI red
logs:
  where: .claude/.rule-incidents.jsonl (rotated by lib/log-rotation.sh)
  retention: per existing rotation policy
discoverability_test:
  command: 'printf %s "$PAYLOAD" | bash .claude/hooks/grep-rewrite-guard.sh | jq .'
  expected_output: hookSpecificOutput.updatedInput.command containing "command grep -I"
```

**OQ2 resolved:** do **not** emit per rewrite (~3,000 per 6,000 calls). Emit only on
disarm and on residual-form detection — both rare, both actionable.

## Architecture Decision (ADR/C4)

### ADR

**ADR-155 (provisional ordinal)** — *Rewrite, don't classify, for shim-reaching `grep`.*
Records: cost is `class size × bound magnitude × literal reachability`, the third
factor is unobservable to a PreToolUse hook, so classification is structurally
wrong; `updatedInput` sidesteps it. Supersedes the approach of #7151 (closed
unmerged). `## Alternatives Considered` must carry the three refuted cost models
and the recursive carve-out (rejected: measured to fail identically at 1.67 GB).

Ordinal is **provisional** — highest on `origin/main` is ADR-154. Re-verify at
ship time and sweep this plan, `tasks.md`, and AC12 if it moves.

### C4 views

**Enumeration performed** (C4 completeness mandate — all three `.c4` files read):

- **External human actors:** none new. No new human interacts with the system.
- **External systems / vendors:** none new. GNU grep is a local binary, not an
  external system; no vendor edge is added.
- **Containers / data stores:** `platform.engine.hooks` (existing, `model.c4:68`) —
  **description falsified**. It reads `technology "PreToolUse Guards + PostToolUse hints"`;
  the engine now also *rewrites* tool input.
- **Access relationships:** `hooks -> claude "Guards tool calls"` (`model.c4:389`) —
  **label falsified** for the same reason.

So this is **not** a "no C4 impact" case. In-scope edit: update the `hooks`
container technology/description and the `hooks -> claude` relationship label to
cover input rewriting. No new element, so no `views.c4` `include` line is needed
(`platform.engine.hooks` is already included at `views.c4:30,58`). Run
`c4-code-syntax.test.ts` + `c4-render.test.ts` after the edit.

## Domain Review

**Domains relevant:** Engineering (only).

Product/UX Gate: **NONE**. The mechanical UI-surface override does not fire — no
path in Files to Create/Edit matches a UI-surface term or glob. No wireframes.

**Not run — operator-declined.** The operator selected a no-agent scoping pass, so
no domain leaders were spawned at brainstorm Phase 0.5 or here. `requires_cpo_signoff:
true` is set by the `single-user incident` threshold and is **outstanding** — it must
be satisfied before `/work`, or explicitly waived. `user-impact-reviewer` remains the
load-bearing review-time gate either way.

**GDPR gate:** trigger (b) fired (threshold = `single-user incident`), but the change
processes no personal data. The only new persistence is `emit_incident`, which writes
to the pre-existing local `.rule-incidents.jsonl` with a 1024-char snippet cap. No
new processing activity; no Article 30 row.

**IaC gate:** skipped — no infrastructure.
**Encryption posture:** skipped — no persistent store, no new cross-component connection.

## Open Code-Review Overlap

Queried 62 open `code-review` issues against every planned path — **no direct match**.

Adjacent, **acknowledged** (not folded in):

- **#7005** *"sweep the remaining pipefail + `grep -q` fail-open sites"* — same
  keyword, different concern (fail-open exit-code handling in repo scripts, not the
  shim). Those 54 hook scripts are structurally out of scope here (the shim is not
  `export -f`'d). Stays open.
- **#7076** *"run-registered-suites.sh derivation misses 8 registered infra suites"* —
  suite-registration coverage. Our new suites land via the `test-all.sh:577` glob,
  which is a different mechanism. Stays open.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **False positive on 50.5% of Bash calls** | 26-fixture matrix, both directions, prototyped and passing before a line ships. AC5 pins byte-identity. |
| Multi-hook `updatedInput` combination is **undocumented** | Only our hook rewrites. `deny` precedence measured (AC2). If a second rewriting hook is ever added, behavior is unspecified — recorded in the ADR. |
| GNU grep upgrade changes `-G`/`-E` conflict semantics | Phase 0 precondition re-checks it; AC8 fixtures the bypass set. |
| Losing `.gitignore` filtering on recursive greps | Accepted (D3). Cost is result noise on 3.8% of calls; no latency/memory cost (7.6 MB / 0.10 s measured). |
| Residual forms (`$G`, `eval "grep"`) | Measured **0/6,116** — theoretical today. Owned by #7166; instrumented so any real occurrence surfaces. |
| Rewriting corrupts a command in a way tests miss | The hook emits nothing on the no-match path, so a bug can only mangle a command it *matched*; the anchor is pinned by fixtures and by the over-rewrite mutation (AC10). |

## Test Scenarios

Rewrite: bare, `-E`, `-f patternfile`, `$(…)`, backtick, `(subshell)`, piped,
`P='…'; grep "$P"`, `\grep`, `if`/`while`/`until`/`do`/`then`/`{`/`!`, `\|&`,
later-line-of-multiline.

Untouched: `git grep`, `pgrep`, `zgrep`, `ugrep`, `egrep`, `fgrep`, `xargs grep`,
`find -exec grep`, `command grep`, `/usr/bin/grep`, `sudo grep`, double-quoted data,
single-quoted data, heredoc body, `grep -z`, `--null-data`, `eval "grep …"`,
`G=grep; $G …`.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| A fourth regex cost model | **Forbidden** by the prior art — the missing variable is unobservable. |
| Carve out recursive invocations | **Rejected on measurement** — recursive blows up identically (1.67 GB). Would protect 96% and mislabel the rest as safe. |
| Replay the full shim flag set incl. `-G` | **Rejected** — `-G` + `-E` is fatal under GNU grep (rc=2). |
| Hand-maintained `--exclude-dir` denylist for `node_modules`/`dist` | **Rejected as YAGNI** (D3) — drifts from `.gitignore`, buys only noise reduction. |
| Fold into `guardrails.sh` | **Rejected** — that hook is deny-only with many early `exit 0` paths that would skip the rewrite. Repo convention is one concern per hook (18 on the `Bash` matcher). |
| Emit `permissionDecision: "allow"` alongside `updatedInput` | **Rejected on measurement** — `allow` bypasses the permission prompt; with grep in 50.5% of commands it would disable permissions repo-wide. Not needed: `updatedInput` works alone. |

## Sharp Edges

- **Never emit `permissionDecision`.** `allow` bypasses the permission system for
  every command containing a grep token — half of all Bash calls.
- **`strip_command_bodies` cannot drive the rewrite.** It is length-destroying
  (42 → 29 measured); use the length-preserving `mask_command_bodies`.
- **Never inject `-G`.** GNU grep exits 2 on `-G` + `-E`; ugrep tolerates it, so
  this only fails after the rewrite lands.
- **The exec-bit gate must derive from `settings.json`, not a glob.** Six tracked
  `.claude/hooks/**/*.sh` are legitimately 100644 (libs + tests); a glob goes RED
  on two of them immediately.
- **Never re-run the reproducer uncapped** — `ulimit -v 2000000` + `timeout`, always.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`,
  or omits the threshold will fail `deepen-plan` Phase 4.6.
