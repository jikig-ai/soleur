# Review findings — PR #7879 (11-agent panel, report-only)

Panel returned so far: semgrep-sast, git-history-analyzer, architecture-strategist,
observability-coverage-reviewer. Outstanding: security-sentinel, test-design-reviewer,
structural-enumeration, data-integrity-guardian, pattern-recognition-specialist,
code-quality-analyst, performance-oracle.

Disposition rule: cost-of-filing auto-flip — <=100 lines AND <=4 files means fix inline, no CONCUR.
Everything below is inline unless marked otherwise.

## P1

- [ ] **A1 (architecture)** `tests/scripts/_git_fixture_env.py:37` `ensure_incident_sandbox()` is NOT in
      `incident-sandbox-coverage.test.sh` CHOKEPOINTS. ADR-205 names it THE chokepoint for
      `python3 -m unittest`. Delete it and section D stays green (D checks conftest.py, which still
      DEFINES it); section C3 then keeps crediting coverage that no longer exists.
- [ ] **A1b (architecture)** Three enumerations of "the five chokepoints" disagree: ADR-205, the C4
      clause, and the guard's array. Reconcile to one.
- [ ] **O1 (observability)** The namespace rule drops non-prefixed ids from the orphan gate AND they
      reach NO field of the committed `rule-metrics.json`. Measured: `monitor-supersede`,
      `cost-of-filing-*`, `net-issue-flow*` appear 0 times. Before this PR, a new hook id forced an
      aggregator edit via exit 5; that forcing function is gone. The plan's failure-mode table says
      "structurally prevented" — now false. Fix: emit `summary.non_corpus_counts`.
- [ ] **O2 (observability)** `_valid_rule()` widening + O1 = unbounded unattributed write channel with
      zero counting surface. `emit_incident` rotates at 5 MB, so a flood displaces real telemetry
      into a .gz with nothing reporting.

## P2

- [ ] **A2 (architecture)** shell/TS builder parity is asserted in prose, enforced nowhere. The parity
      test pins only `GIT_LOCATION_VARS`, not the builders' exported-key sets.
- [ ] **A3 (architecture)** The three inline bash sandbox copies gate on `[ -z "$VAR" ]`, so a
      NON-ABSOLUTE inherited `INCIDENTS_REPO_ROOT` passes through; TS and Python both require
      `startsWith("/")`. `_incidents_repo_root()` returns any non-empty value verbatim.
- [ ] **A4 (architecture)** Two false claims I wrote: `incident-sandbox.ts:8` "the ONLY containment
      mechanism" and `model.c4:74` "never at the call site". Both contradicted by
      `test-incident-sandbox.sh`, a per-suite mechanism this PR hardened and the coverage guard
      MANDATES for 46 hook suites.
- [ ] **A5 (architecture)** ADR-205 absent from `knowledge-base/INDEX.md`. Re-run generate-kb-index.
- [ ] **A6 (architecture)** AP-025 deviation (state-predicate vs enumerated-entry-point) unrecorded in
      ADR-205 and in the principles register. The rejection is well argued; record it.
- [ ] **A7 (architecture)** ADR-205 omits the marker-capture ingress widening — the namespace
      decision's largest downstream effect, and rule-metrics.json is committed.
- [ ] **O3 (observability)** `compound/SKILL.md:290,309` runs the aggregator `>/dev/null 2>&1`, so a
      genuine orphan's ERROR line is DISCARDED and the artifact is reverted. Pre-existing, but this
      PR narrows what the gate catches, so the thin channel is now load-bearing.
- [ ] **O4 (observability)** `incident-sandbox-coverage.test.sh:195-200,218` — the root `bunfig.toml`
      yields `$REPO` as a COVERED_ROOT and the C4 branch covers `*.py`, so any python suite is
      credited `why="preload"` from a BUN preload that can never load into a Python process.
- [ ] **O5 (observability)** Three belts do `mkdir -p ... 2>/dev/null || true` then export regardless,
      while `test-incident-sandbox.sh` was changed in THIS PR to exit 1 on that condition.
      `emit_incident` drops the row without a sentinel, so on a full tmpfs every test emit is
      silently discarded.
- [ ] **O6 (observability)** The plan's `discoverability_test` expects `"orphan_rule_ids": []`, which
      is now the outcome BY CONSTRUCTION for the class the change touches — it can no longer fail on
      its paired failure mode.

## P3

- [ ] **S1 (semgrep/shellcheck)** SC2206 `fixture-env-adoption.test.sh:141` — unquoted array expansion
      on the override path globs to 698 entries. Default path safe (verified). Fix: `read -ra` + `set -f`.
- [ ] **A8** namespace-predicate blind spot: `cq_rule-ids` / `hr.foo` match neither the prefix regex nor
      the corpus, so they classify as hook telemetry. The nine stanzas would have flagged them.
- [ ] **A9** `rule-metrics-aggregate.sh:314-316` cites "0 of 105 AGENTS ids" but the script parses
      `AGENTS.md`; 105 is `AGENTS.rules.md`'s count. True either way, wrong file cited.
- [ ] **A10** 5 of 6 sandbox implementations install no EXIT trap. One dir per runner invocation.
- [ ] **A11** `conftest.py:78-82` docstring promises RuntimeError; `mkdtemp` raises OSError un-wrapped.
- [ ] **A12** `test-incident-sandbox.sh:56` is NOT idempotent — it clobbers an outer root, contradicting
      the layering contract stated at `incident-sandbox.ts:31-33`.
- [ ] **A13** `git-tripwire.ts:105` registers the telemetry sandbox as an import side effect of a module
      named git-tripwire. bunfig preload is an ordered array; a second entry preserves ordering.
- [ ] **O7** mktemp stderr discarded in three belts — the only statement of WHY the sandbox failed.
- [ ] **O8** `conftest.py` unreachable RuntimeError branch (mkdtemp always returns absolute).
- [ ] **O9** env-i forfeit predicate covers `*.ts|*.tsx|*.py` but not `*.sh`. No current true positive.
- [ ] **O10** `lefthook.yml:262` plugin-component-test sandboxed SOLELY by the root bunfig preload, with
      no belt and no comment naming the dependency.
- [ ] **O11** `test-helpers.sh` sourced in an INTERACTIVE shell permanently redirects that shell.

## Judged correct and NOT actionable

- Cross-package import is not an inversion (no package.json in plugins/soleur, no workspaces,
  dependency-cruiser governs only the client->server secret boundary, edge pre-existed on main).
- The ABORT/EXPORT asymmetry argument is sound on its stated grounds.
- semgrep SC1087 at `fixture-env-adoption.test.sh:203` is a false positive (`[` is not an identifier
  character, so the bracket class stays literal) — verified by running the concatenated regex.

---

## security-sentinel (returned; no provable P1)

Three brief-flagged P1 candidates were empirically REFUTED, and the refutations are worth keeping:
- `${!GIT_@}` is IFS-safe (unlike `${!prefix*}`, which joins on `IFS[0]`) — verified under
  `IFS=$'\n'` and `IFS=`.
- The `GIT_LOCATION_VARS` skip is not abusable: an inherited `GIT_LOCATION_VARS=pwned` becomes
  `declare -arx`, and arrays cannot be placed in a child environment.
- The lexical-ceiling fallback does not escape — git resolves symlinks in ceiling entries itself
  (verified with a symlinked fixture under an enclosing repo).

### P2 — fail-open holes in guards THIS PR ships

- [ ] **SEC2** `fixture-env-adoption.test.sh:482-505` — the return-check assertion is blind to the
      violation it names, TWO ways. `_strip_shell_data` removes quoted spans FIRST, so
      `git_fixture_env "$root2"` becomes `git_fixture_env ` with nothing after it and
      `SHELL_HELPER_CALL_RE` misses — the canonical UNCHECKED call is dropped from `call_sites`
      entirely. And comments are never stripped on this path, so any `||` or `&&` in a trailing
      comment certifies the call as return-checked. `CALL_SITE_FLOOR=10` cannot catch it: the real
      sites survive stripping precisely BECAUSE they end in `|| { ... }`.
- [ ] **SEC3** `fixture-env-adoption.test.sh:196,203` — derivation A POOLS verbs per line.
      `git -C /d add -A && git -C /d log --oneline` classifies read-only; so does `git init; git status`.
      The header claims pooling was removed; it was moved from FILE to LINE granularity, not removed.
      A shell suite whose only mutating spawn shares a line with a read verb drops out of derivation A
      and the guard goes green over an unconverted fixture. Same shape for `_code_line_tokens` on .ts.
- [ ] **SEC4** `incident-sandbox-coverage.test.sh:268` — section F's hook-suite blanket is a BARE-TOKEN
      grep. A file containing only `# we deliberately do not source test-incident-sandbox.sh here`
      passes. Section E's C1 in the SAME file does it correctly with an anchored source-line regex.
      This is what stands between 45 hook suites and the real ledger.
- [ ] **SEC5** `incident-sandbox-coverage.test.sh:178,184` — section D asserts the chokepoint file
      CONTAINS the mechanism, not that its entry point INVOKES it. Deleting
      `ensure_incident_sandbox()` from `pytest_configure` (leaving the function defined and
      unreferenced) still passes 5/5 green.
- [ ] **SEC1** confirms A3 with a concrete repro: `INCIDENTS_REPO_ROOT=.` survives all three bash
      chokepoints, and `emit_incident` then builds `./.claude/.rule-incidents.jsonl` against the
      HOOK's cwd — the operator's real ledger for any hook spawned at the checkout root.

### P3

- [ ] **SEC6** `git-fixture-env.sh:109-118` — "exports nothing" is true only on the FIRST call. On a
      refusal after a successful call, the PREVIOUS fixture's `GIT_CEILING_DIRECTORIES` and
      `XDG_CONFIG_HOME` remain exported. My suite probes a virgin subshell, so its failure direction
      is SILENT. Add a probe that succeeds then refuses.
- [ ] **SEC7** `_valid_rule` greps `AGENTS.rules.md` while the aggregator parses `AGENTS.md`. In sync
      today (105 each, symmetric difference empty); nothing pins index<->body parity.
- [ ] **SEC8** `rule-incident-marker-capture.test.sh:135-137` shared-regex assertion is
      comment-satisfiable in principle; the sibling `git-env-list-parity.test.sh:73-77` strips
      comments first and says why.
- [ ] **SEC9** `rule-metrics-aggregate.sh:93-101` — `/^[^#]/` parses an INDENTED comment line as data,
      yielding junk ids. Also nothing checks a retired id was ever in AGENTS.md.
- [ ] **SEC10** `fixture-env-adoption.test.sh:269` — `case "$line" in *//*|*'*'*) ;; esac` is a DEAD
      no-op left over from derivation C. Reads as load-bearing; is not. Remove.
- [ ] **SEC11** confirms A12 — `test-incident-sandbox.sh:78` clobbers an inherited root while its
      three siblings all document "a root already chosen wins".

---

## STRUCTURAL-CAUSE ROLL-UP (mandatory, done before disposition)

Two causes account for most of the panel's guard findings:

**CAUSE 1 — "the guard greps for the MECHANISM, not for its INVOCATION."**
Instances: A1 (`_git_fixture_env.py` missing from CHOKEPOINTS), SEC5 (section D passes with the
conftest call deleted), SEC4 (section F satisfied by a comment mentioning the helper).
The seat that should have enumerated this is the structural-enumeration seat — still outstanding.
Fix once, at the predicate level: every chokepoint assertion must anchor on the CALL, comment-
stripped, and be unique within its search scope.

**CAUSE 2 — "the derivation strips or pools before it classifies, and the loss is fail-open."**
Instances: SEC2 (quoted-span stripping deletes the unchecked call), SEC3 (per-line verb pooling),
SEC2b (comments never stripped on the return-check path -> a comment certifies the check).
All three are in `fixture-env-adoption.test.sh` — the guard I added derivation C to. The pattern is
that each transform was written for one axis and its interaction with the classifier was not traced.

Neither cause was reported by more than one agent as the same gap, which is the signal the
structural seat is doing work the adversarial seats cannot.

---

## data-integrity-guardian (returned) — THREE P1s, TWO OF THEM AGAINST MY OWN WORK

### DI-1 (P1) — THE QUARANTINE WAS INVERTED

I removed the 109 rows that reach **no field** of the artifact and LEFT the ~30 archived rows that
corrupt real rules' `prevented_errors`. Proven by rebuilding the pre-quarantine ledger and diffing
two aggregator runs: **byte-identical modulo `generated_at`** (A=1566 lines, B=1675).

The archives ARE merged by the aggregator (`rule-metrics-aggregate.sh:98-101`), and the rows in them
are attributed to REAL AGENTS ids:

| id | fabricated denials in archives | committed `prevented_errors` | contamination |
|---|---|---|---|
| `hr-when-a-command-exits-non-zero-or-prints` | 20 | 99 | **20%** |
| `rf-never-skip-qa-review-before-merging` | 10 | 80 | **12.5%** |

`measurements.md:281` justifies leaving them with "Archives untouched as the task requires."
**The task requirement is the defect** — the archive rows are the only ones that ever mattered.

Also: **"143" is over-counted by 4.** Three `wg-ship-push-before-merge` and one
`hr-never-write-to-claude-code-memory-claude` are REAL denials on real commands that merely QUOTE
the fixture literal in a heredoc or `--body`. A substring predicate over-selects; it happened not to
on the active file, but that was luck. Pin any cleanup on `rule_id` AND exact snippet equality.

### DI-2 (P1) — the 109 rows never came from a test runner, and the tap is still open

The plan attributes all 143 to `test/pre-merge-rebase.test.ts`. True of the archived 30. **False of
the active 109**: those are `warn` / `post-dispatch-watch-gate` / snippet exactly `gh pr merge 123`,
timestamped today 07:24-09:03. No suite emits that (its own suite uses `gh pr merge 7599`).

Mechanism: `.claude/hooks/post-dispatch-watch-gate.sh:77-80` greps `$CMD` **RAW**. Any agent Bash
call whose text merely CONTAINS the dispatch literal — a heredoc, a quoted reproduction while
working on this very PR — writes a stale head entry to `soleur-pending-dispatch`, and then EVERY
subsequent Bash call in that session emits a `warn` row. One poisoned state file, 109 rows in 100
minutes. That matches the burst exactly, and it is almost certainly MY OWN session quoting the
literal while working on #7853.

This is the false-positive class `strip_command_bodies()` (`incidents.sh:359-364`) exists for.
TEN Bash-matcher hooks call it; `post-dispatch-watch-gate.sh` calls it ZERO times.

**Consequence: the chokepoint redirect cannot reach this emitter** — it is a live PostToolUse hook in
the agent's session, not a test runner. The quarantine is a one-time mop under an open tap.
Different subsystem => its own issue per compound triage, but the plan's attribution must be fixed.

### DI-3 (P1) — `_valid_rule()` widening forges named summary fields of the COMMITTED artifact

Net-new acceptances vs the old allowlist include `hook-input-*` and `grep-rewrite-*` — precisely the
ids the aggregator reads into named summary fields. Demonstrated end-to-end in a sandbox: a
`SOLEUR_RULE_APPLIED rule=grep-rewrite-<anything>` marker in contributor-writable payload markdown,
executed on the `gh pr checkout` review path, forges an attacker-chosen key into
`grep_rewrite_fault_reasons` in the committed `rule-metrics.json` AND fires a false security alarm
claiming a shim was not neutralized and a hook ran with guards disarmed (ADR-156/157/162 signals).

The hook's new security note claims the bound is a row "which no rule-metrics consumer reads".
**That is false**, and `rule-metrics-aggregate.sh:328-335` says so 200 lines away. Test case 2b
currently ASSERTS the widening as intended, so this needs a decision, not just a patch.

### DI-4 (P2) — the quarantine file is one `gzip` away from re-injecting all 109 rows

`.claude/.rule-incidents-synthetic-quarantine.jsonl` sits in the same dir as the aggregator's glob
`.claude/.rule-incidents-*.jsonl.gz`. Verified the gzipped name matches EXACTLY. Any housekeeping
that compresses old `.jsonl` under `.claude/` silently re-ingests 109 fabricated rows.

### DI-5 (P2) — clause 2 deletes the only surface a retired-id-with-live-emitter had

Live in the operator's ledger now: `cq-never-skip-hooks` **79 rows, event_type `bypass`** (the
highest-signal class this system tracks, and the input to `rules_bypassed_over_baseline`),
`cq-when-lefthook-hangs-in-a-worktree-60s` 17, `cq-docs-cli-verification` 1 — all with live emitters
in `incidents.sh:283/312`. Now: not in `rules[]`, exempt from `orphan_rule_ids`, no counter.
This is verbatim the ADR-156 consequence the same PR diagnoses and FIXES for three other namespaces.

### DI-6 (P2) — rule-metrics.json was regenerated BEFORE the quarantine, against my own instruction

`measurements.md:283` says regenerate AFTER. `generated_at` 10:38:10Z, quarantine mtime 11:06Z.
Materially harmless (A==B proven) but the record says the step is outstanding.

### DI P3
- Clause 1 loses the mis-prefixed-emitter orphan class; the docstring at `:299-301` is now untrue.
- Retired-list `/^[^#]/` indented-comment bug is byte-identical to `rule-prune.sh:119-125` — a shared
  latent bug, NOT a regression I introduced.
- Quarantine file has no provenance/batch delimiter and is gitignored, so reversibility lives on one
  untracked local file.
- Marker flooding uncapped: measured **500 rows from a single Bash tool call**.
- 77 malformed lines in the merged corpus (pre-existing torn writes).

### Confirmed correct (recorded because the reasoning is subtler than I stated)
The `cat >` / no-`mv` choice is load-bearing, not stylistic: `incidents.sh:214` runs
`[[ -f "$file" ]] || : > "$file"` OUTSIDE the lock, so a `mv` would let a racing emitter create a NEW
inode and flock that — two inodes, two locks, torn writes. `log-rotation.sh:12-21` documents this
exact hazard. `emit_incident` opens fd 9 `O_APPEND` before locking, so a writer parked on the lock
across the truncate lands correctly after it.

---

## structural-enumeration (returned) — BOTH assemblies are narrower than their properties

Verdict, sink 1: the property is "no test can append a row to a resolved ledger root"; the assembly
is "no suite whose source SPELLS a hop-1 basename in a quoted literal on a non-comment line, and
whose filename matches four extensions, lacks one of six protection spellings". Narrower on FOUR
independent axes.

Verdict, sink 2: the property is "every test file that spawns git with a mutating invocation obtains
its environment from the shared helper"; the assembly scopes shell to three roots that EXCLUDE
`apps/web-platform/test/**`, `test/**`, `scripts/**` and `.claude/hooks/**`.

### SINK 1 escapes (each with a one-line edit)
- [ ] **ST1** hop 1's command-position anchor `(^|[;&|}]|&&|\|\|)` omits **`then`**. Live present-tense
      miss: `.claude/hooks/monitor-supersede-guard.sh:79` `if command -v emit_incident …; then
      emit_incident "$@" || true; fi` is invisible to hop 1, hence hop 2, hence the outside set.
- [ ] **ST2** hop 1's predicate is "calls `emit_incident`", but the sink is reached TRANSITIVELY via
      `lib/hook-input.sh` (`hook_input_report()` fires on any unparseable stdin — the commonest shape
      in hook suites). `agent-token-tee.sh`, `doppler-secrets-delete-redirect.sh`,
      `ship-runbook-ssh-gate.sh` all source it and none is a hop-1 member.
- [ ] **ST3 (sharpest)** `scripts/rule-metrics-aggregate.sh:594` **TRUNCATES** the ledger
      (`: > "$INCIDENTS"` under `AGGREGATOR_ROTATE=1`). It contains no `emit_incident`, so it is
      structurally outside hop 1 and every suite that only spawns it is outside hop 2.
      `tests/scripts/test-rule-metrics-aggregate.sh:301,307` runs exactly this with PER-INVOCATION
      inline `INCIDENTS_REPO_ROOT` — the "partial isolation" spelling the guard's own header
      condemns. **Drop the prefix on ONE of 16 call sites and the row set is DESTROYED, with no
      assertion firing.** Truncation is a strictly worse breach of the same sink than an append.
- [ ] **ST4** direct `>> "$root/.claude/.rule-incidents.jsonl"` appends exist in
      `scripts/rule-metrics-aggregate.test.sh` (5 sites) and `tests/scripts/…` (10). A redirection is
      not an `emit_incident` call; neither hop reaches it.
- [ ] **ST5** confirms O4 with sharper detail: `COVERED_ROOTS` includes the REPO ROOT, and
      `case "$p" in "$r"/*)` therefore matches EVERY file, so any `.py` is credited `preload` from
      the root `bunfig.toml` that python never reads.
- [ ] **ST6** section F globs `$HERE/*.test.sh` only, so `.claude/hooks/lib/freeze-lock.test.sh` —
      registered by test-all.sh precisely because "shell globs do not cross `/`" — is exempt from the
      blanket. Same directory-blindness the guard's header records as its first revision's defect.
- [x] Outside set of 3 is CORRECT for its population; all three independently verified over-counts
      (incl. all five `.openhands/hooks/*.sh` confirmed zero `emit_incident`).

### SINK 2 escapes
- [ ] **ST7** **47 suites** spawn git with a mutating verb and are named in NO guard-5 list. 17 are
      `.claude/hooks/*.test.sh` (incl. `pre-merge-rebase.test.sh`, `guardrails.test.sh`,
      `git-commit-secret-scan.test.sh`) — 0 of 17 source `test-helpers.sh`, no tripwire, no fixture
      env. Their only protection is the entry-point scrub; a direct `bash .claude/hooks/<x>.test.sh`
      from a shell holding `GIT_DIR` — the #7833 shape — is unguarded at every layer.
      Also `apps/web-platform/test/ci/service-role-allowlist-gate.test.sh` DELIBERATELY mutates the
      live index (`git add -f`, `git rm --cached -f` against the real repo) — legitimate, but it is
      exactly the class that should carry a waiver and guard 5 cannot see it.
- [ ] **ST8** **The out-of-scope block's stated mitigation is FALSE for 7 of its 20 members.** The
      guard prints "They source test-helpers.sh, so the #7833 tripwire IS armed for them". Seven do
      not source it and six of those have ZERO arming references. Named, with their mutating spawns:
      `fixture-cd-containment` (a cwd-relative `git commit` with no `-C` — the exact shape `GIT_DIR`
      overrides), `fixture-dir-operand-assert`, `fixture-relative-assert`, `gitleaks-merge-commit`,
      `harvest-debt`, `proc`, `roadmap-reconcile`.
- [ ] **ST9** Waivers: **1 of 7 unreservedly justified**. The six `workspace*`/`mu1-integration`
      entries scrub **3 of the 9** `GIT_LOCATION_VARS`; the waiver text claims "the git-location
      family", which is nine names — the identical defect `hook-git-env-coverage.test.sh`'s header
      records. And assertion 2's rot-check is satisfied by ANY ONE of its patterns, so it cannot
      distinguish a 3-name scrub from a 9-name one — the exact rot it claims to prevent.
      Separately **5 of 7 waivers are DECORATIVE** (not in derivation A at all — they mock the spawn),
      and the `>= 2` floor permits that indefinitely.
- [ ] **ST10** SIX copies of the var list exist, FOUR are enforced. `tests/conftest.py::_GIT_LOCATION_VARS`
      says in its own docstring "enforced by git-env-list-parity.test.sh" — and that test contains NO
      reference to conftest. Plus five inline copies in `plugins/soleur/skills/git-worktree/test/*`.
- [ ] **ST11** Derivation C limitation, self-stated: `env: process.env` satisfies it ("only that the
      caller passed SOMETHING"). One-line escape in an already-adopted file.
- [x] The 4-entry deferred list is complete and each reason checks out.

### Roll-up update
CAUSE 1 gains ST1, ST2, ST5, ST6. CAUSE 2 gains ST9 (the rot-check that cannot see the rot).
NEW **CAUSE 3 — "the guard's SCOPE excludes populations the property covers"**: ST3, ST4, ST7, ST8.
This is the cause no adversarial seat reported at all, and it is the one the structural seat exists
to find.

---

## pattern-recognition (returned) — NEW findings not already captured

### P1
- [ ] **PR1** `tests/scripts/_git_fixture_env.py:107-123` — the Python builder **LACKS the
      GIT_CONFIG_COUNT signing override** its TS and SH siblings carry. Not cosmetic: the python
      fixtures DO commit (~15 commits under `env=git_fixture_env(repo)` in
      `tests/scripts/test_lint_rule_bodies.py`). A developer with repo-local `commit.gpgsign=true`
      fails those tests. Both siblings' suites treat the override as load-bearing. The parity test
      pins the CONSTANT LIST; nothing pins the BUILT ENVIRONMENT. Same shape unpinned for
      `XDG_CONFIG_HOME`, `GIT_ATTR_NOSYSTEM`, `GIT_TERMINAL_PROMPT`.
- [ ] **PR2** Input validation diverges three ways: PY (`Path(...).resolve()`) and TS (`resolve()`)
      both SILENTLY resolve a relative fixture dir against cwd; only SH refuses. Measured:
      `PY ACCEPTED a relative fixture dir; ceiling = /tmp/tmpvm3dg9bc`. My shell suite's comment
      "Only the input guard can refuse this" is true of the shell arm and misleading as a contract.

### P2 — TWO DEFECTS IN MY OWN EARLIER FIXES
- [ ] **PR3** `plugins/soleur/test/git-fixture-env.test.ts:229` — the injected list contains
      `GIT_CONFIG_KEY0` (**no underscore**). `GIT_CONFIG_KEY_0` and `GIT_CONFIG_VALUE_0` are
      therefore NEVER set to `/tmp/hostile-injected`, so **2 of the 3 hostile-value assertions I
      added in commit 8f60490e5 are vacuous** — trivially true — and the skip-list entries never
      match anything in `injected`. Only `GIT_CONFIG_COUNT` is genuinely exercised. The comment
      above them says this check is the whole point of the block.
- [ ] **PR4** `plugins/soleur/test/gdpr-gate.test.ts:7,11,13,14` — my sandbox edit added duplicate
      imports of `mkdtempSync` and `tmpdir`. **4x TS2300 under the repo's own tsc.** Bun tolerates it
      and `plugins/soleur/test/` is in no tsc project, so nothing reds. `joinPath` is a redundant
      alias for `join`. Root cause: I hand-rolled an 8th sandbox spelling instead of importing
      `ensureIncidentSandbox()` from the module this PR adds.
- [ ] **PR5** `fixture-env-adoption.test.sh:523` — an OUT_SET needle is satisfied by PROSE ADDED IN
      THIS SAME PR: `test-helpers.sh:10` contains `` `git_fixture_env <dir>` `` in a comment, and the
      backtick is one of the regex's command-position anchors. Both sides new on this branch. Impact
      nil today (no mutating git line there) but it is a live hole in the OUT_CEILING=20 ratchet.
      `derive_B:313,319` has the same missing comment filter, where the direction is WORSE.
- [ ] **PR6** `derive_C` has NO liveness floor — it consumes the CODE subset of B, while the only
      floor (`B_FLOOR=10`) pools code and shell. Convert three more shell suites and B's shell half
      alone clears the floor; losing every code file then leaves `PARTIAL_N == 0` passing over a scan
      of nothing. The file's own header states the rule this violates.
- [ ] **PR7** `.github/scripts/test/run-all.sh` — newly promoted to a first-class entry point by this
      PR and given the `unset`, but it has **no rc-97 classifier**, so a tripwire abort reached
      through it reports as a generic failure with no attribution. `scripts/test-all.sh:664` has one.
- [ ] **PR8** The list is written down ~15 times, not six: 5 more inline copies with their own
      `exit 97` in `plugins/soleur/skills/git-worktree/test/*.test.sh` and
      `plugins/soleur/scripts/grok-fidelity-gate.sh`. The parity header still claims "six places" and
      still names `test-helpers.sh` as the SHELL row (stale — this PR moved it), and its SCRUB row
      omits `.github/scripts/test/run-all.sh`, which this PR added.

### P3
- [ ] **PR9** `net-issue-flow.test.sh:437` — my comment claims the predicate is "extracted rather than
      restated", but the grep needle RESTATES the whole alternation. On a widened aggregator
      predicate it emits 1 fail plus 2 spurious passes.
- [ ] **PR10** Stale prose in the drift guards: `_git_fixture_env.py:47-50` still names
      `test-helpers.sh` as the shell list; `hook-git-env-coverage.test.sh:75-76` names two of five.
- [ ] **PR11** `rule-incident-marker-capture.test.sh:146` — `grep -c 'startswith(' == 3` over an
      un-comment-stripped file.
- [ ] **PR12** The two idioms are NOT the same idea and nothing records it: the TS/PY builders are
      PURE (return a per-fixture value); the bash builder MUTATES the calling shell globally, so a
      multi-fixture suite is order-dependent.

---

## code-quality-analyst (returned) — NEW findings

It independently RE-RAN and confirmed four prose claims with falsifying commands (the "0 of 105"
figure — and found it is structurally enforced by `lint-rule-ids.py:37` `RID_RE`, which is stronger
than I claimed; the GIT_CONFIG_COUNT override outranking repo-local config; the seven RUNNER_RE
workflows; the retired-list parse being byte-identical to `rule-prune.sh`).

### P1
- [ ] **CQ1 — SHIPS THE CONTAMINATION #7853 WAS FILED ABOUT.** `rule-metrics.json` was generated at
      10:38:10Z; the quarantine landed at 13:06:51, **28 minutes later**, and there is no later
      regeneration. The committed artifact reports
      `rf-never-skip-qa-review-before-merging` = **80** and
      `hr-when-a-command-exits-non-zero-or-prints` = **99**, while the live active ledger now holds
      **5** and **0**. `tasks.md` 5.6 is checked `[x]` but its own stated ordering constraint was
      violated. Confirms DI-6 with the impact made concrete.

### P2
- [ ] **CQ2** Guard 3's `CHOKEPOINTS` omits BOTH bunfig preloads AND `_git_fixture_env.py`, so §C's
      claim "removing the export from any one of them reds twice" is **false for 3 of the 5**
      documented chokepoints. Sharpest statement of the A1/SEC5/ST1 cluster.
- [ ] **CQ3 (NEW, mine)** `lib/git-fixture-env.sh` carries the tripwire but **NOT** the telemetry
      sandbox, while its TS sibling `git-tripwire.ts:105` DOES call `ensureIncidentSandbox()`.
      Sourcing the shell helper gives git containment ONLY. Ten shell files source it with no sandbox
      source; **six are this PR's own conversions**. `tasks.md` 3.3.1 states the false premise
      ("Sourcing the helper brings a suite inside a chokepoint"). The tell is that
      `test_hook_emissions.sh` and `scan-workflow.test.sh` had to source the sandbox SEPARATELY.
- [ ] **CQ4** The A-1 correction is INCOMPLETE — **A-2 is an uncorrected sibling in the same
      document** (still says "three, not five" and "retires task 5.5 entirely"), and the superseded
      consequence survives in `tasks.md` 5.5 (checked `[x]` under a justification T1.8 disproved) and
      in `session-state.md`. This is the corrected-document-with-uncorrected-field class verbatim.
- [ ] **CQ5** ADR-205's normative Decision blockquote is falsified by the predicate the same ADR
      ships: under it as written `cq-pencil-collapse-auto-recover` IS an orphan, but the gate exempts
      it. The next reader deletes the exemption for consistency and returns the gate to rc=5.
- [ ] **CQ6** `gdpr-gate.test.ts` duplicate imports are a **hard SyntaxError under `node --check` and
      `bun build`**, not merely TS2300. Worse than pattern-recognition reported.
- [ ] **CQ7** Derivation C admits `env: process.env` — the fully-inherited environment, i.e. the
      pre-#7849 state. Combined with B's file-level membership, a file can make ONE real helper call
      and pass `process.env` to every other spawn and stay green on A\B AND on C.
- [ ] **CQ8** `INDEX.md`: 206 ADR files exist, 205 indexed; the single missing entry is ADR-205.
      Count should be 6403. The lefthook `generate-kb-index` step did not run on the ADR commit.

### P3
- [ ] **CQ9** Guard 5's return-check admits `|| true` — "checks the return" and discards it.
- [ ] **CQ10** `A_N != B_N` **reds when the tree improves**: converting the two #7889 deferrals could
      legitimately make the cardinalities equal, failing with "check the two extractors have not
      collapsed into one query". Trains the next reader to bump the number.
- [ ] **CQ11** marker-capture case 5 is a comment-blind `grep -qF` over both files.
- [ ] **CQ12** `tasks.md` 3.7 still `[ ]` though the suite shipped in 7b1cc4ecb (after the checkoff
      commit). §8 also unchecked.
- [ ] **CQ13** Deferral count stated THREE ways: plan AC23 "five", tasks.md 7.4 "six", reality one
      tracker (#7889) with seven items. **AC23 cannot be verified by the command it names.**
- [ ] **CQ14** `fixture-relative-assert.baseline.txt` header prose stale by 15 (says 1236, totals 1251).
- [ ] **CQ15** memory-backstop added 8 new P1b relative-operand sites (14 -> 22) with no justification
      note, on a branch whose subject is fixture-path containment.
- [ ] **CQ17** ADR-205's "every layer aborts" is FALSE of the three belts (`|| true` on mkdir).
- [ ] **CQ19** T5c's anti-restore guard is token-shaped (`for +_hop +in`); a rename defeats it.

### Disagreement to record
CQ says SC2206 is "not a bug" (per-element quoting inside `:-` protects the DEFAULT path) — which
agrees with semgrep and with my own measurement. My measurement of **698 entries** was on the
OVERRIDE path, which CQ did not test. Both readings stand; the override path is still worth fixing.

---

## test-design-reviewer (returned, isolated worktree) — the vacuity my batteries missed

Method was correct and worth recording: baseline green in ITS sandbox before every row, each
mutation asserted landed via `cmp` against a pristine copy, and — the part I did not do — every
"loosen a threshold / delete the verdict" row re-run **composited with a known-caught subject
mutation**, because such a row is INCONCLUSIVE alone (an unmutated tree has no failure to hide).
Score: **8.0 / B**.

### TD1 (P1) — the verdict line is unbackstopped in EVERY suite, and it is repo-wide
| composite (subject mutation known-CAUGHT alone) | rc | verdict |
|---|---|---|
| `exit 97`->`1` + delete `if (( FAIL > 0 )); then exit 1; fi` | **0** | SURVIVED (3 `[FAIL]` lines still printed) |
| reverted conversion + delete `(( FAIL == 0 )) \|\| exit 1` | **0** | SURVIVED (2 `[FAIL]` lines printed) |
| injected fail + delete verdict in `incident-sandbox-coverage.test.sh` | **0** | SURVIVED (prints `OK: 18/19`) |

Mechanism confirmed repo-wide: `run_suite` captures rc only and never scans suite output
(`"$@" || rc=$?`); `.github/scripts/test/run-all.sh` identical. ADR-193's
`guard-vacuity-floor.test.sh` mutation-tests the FLOOR mechanism, but its population is "suites that
already carry a shape-recognizable floor" — **nothing in the repo requires a verdict line to exist.**
A one-line deletion makes any of these suites permanently green.

### TD2 (P1) — derivation C has no non-vacuity floor; two one-line edits flip a RED tree green
Instrument-verified against the header's own scenario, with a known-positive control:
| row | rc | |
|---|---|---|
| partial conversion only (**known-positive**) | 1 | CAUGHT |
| + `CODE_DIRECT_SPAWN_RE` -> never-matches | **0** | **SURVIVED** |
| + `CODE_ENV_BINDING_RE` -> `'.'` | **0** | **SURVIVED** |
Assertion count stays 20, so `MIN_ASSERTIONS` never notices. A, B and the return-check derivation
each carry a floor; C — the newest, and the ONLY assertion covering the partial-conversion class —
does not. The file's own header declares that floor mandatory.

### TD3 (P1) — marker-capture case 5: the orphan gate can be made SEMANTICALLY DEAD, green
Rewrote the aggregator's real selector to `test("^(ZZZNEVER)-")` leaving the literal in a comment two
lines above: **rc=0, 12 pass, 0 fail.** Case 5 reports the two sides still agree. The hook half is
saved only by behavioural case 2, so case 5 is vacuous precisely for the half it uniquely covers.

### TD4 (P2) — SIX hermeticity exports in MY shell builder have ZERO assertions
Deleting `GIT_CONFIG_GLOBAL`, `GIT_CONFIG_NOSYSTEM`, `XDG_CONFIG_HOME`, `GIT_ATTR_NOSYSTEM`,
`GIT_TERMINAL_PROMPT` — all SURVIVED. Proven behavioural, not cosmetic: under a synthesized hostile
`HOME` the mutant leaks `core.hooksPath=/var/tmp/hhome/hooks` into the fixture (unmutated: NONE), so
**the operator's global hooks would EXECUTE inside the fixture**. My suite only asserts a commit
SUCCEEDS, and a commit succeeds fine with all six gone.

### TD5 (P2) — fixture DIRECTION gap: the tripwire can only be caught getting LOOSER
`[[ -n "${!_v:-}" ]]` -> `[[ -v "$_v" ]]` SURVIVED: a harmless set-but-EMPTY `GIT_TEMPLATE_DIR=` now
aborts the runner with exit 97. Every tripwire fixture asserts must-trip; none asserts
must-stay-silent.

### TD6 (P2) — the frame walk's whole point is unpinned
Replacing `_soleur_git_reporting_frame` with a constant SURVIVED — the suite asserts only
`*"DISARMED"*`, so "names WHICH entry point lacked the scrub" is pinned by nothing.

### TD7 (P2) — idempotency unpinned, and double-source is the NORMAL path
Deleting `_SOLEUR_GIT_FIXTURE_ENV_SOURCED=1` SURVIVED; double-sourcing emits
`GIT_LOCATION_VARS: readonly variable` on stderr — which the lib's own comment calls a real defect
("converted suites capture stderr"). `test-helpers.sh` sourcing this file makes double-source normal.

### TD8 (P2) — `memory-backstop.test.sh` has NO floor at all
1156 lines, 66 assertions, zero vacuity floor / instrument self-test / conservation check. Neutering
`pass()` yields `RESULT: PASSED 0`, rc=0 — and the runner records a pass. This PR adds 290 lines to
it plus a companion battery without adding a floor.

### TD9 — a FALSE CLAIM in my own comment (equivalent mutant, measured)
`physical="$(cd -P …)"` -> `physical="$abs"` is **EQUIVALENT**. Built a symlinked fixture with an
enclosing repo above the ceiling: BOTH arms blocked discovery, because git resolves symlinks in
`GIT_CEILING_DIRECTORIES` entries itself. My comment's claim that "discovery escapes" is **not
reproducible on this git**. (Security-sentinel measured the same thing independently.)

### Recorded as STRONG (do not regress)
`incident-sandbox-coverage.test.sh` is the strongest file in the set — `MIN_CASES=18`, a
`PASS+FAIL==CASES` conservation check, cardinality-aware emitter floors (`>=1 .sh` AND `>=1 .py`),
and it CAUGHT the growth probe (a new leaking test spawning two emitter-reaching hooks). Its only gap
is the shared TD1 verdict-line issue.
Guard 5 is genuinely strong on growth and operand degeneration — all of those rows were CAUGHT.

### Environment note
The machine's 4 GiB `/tmp` tmpfs hit **100%** mid-session.

---

## performance-oracle (returned) — 11/11 PANEL COMPLETE

### PF1 (P1) — A REGISTERED GATE SUITE IS RED ON THIS BRANCH, AND I INTRODUCED ALL THREE FINDINGS
`scripts/lint-trap-tempfile-ownership` (registered `test-all.sh:1253`) fails, rule (c)
"mktemp with no owning trap" (ADR-129). Verified independently, linter rc=1:
- `.github/scripts/test/run-all.sh:69` — my incident-sandbox belt
- `plugins/soleur/test/git-fixture-env-shell.test.sh:46` — my new suite's `mkfixture()`
- `plugins/soleur/test/test-helpers.sh:28` — my incident-sandbox block
**This is merge-blocking and it is exactly what the `scripts` shard would have caught.** That shard
never ran: it sat queued on the advisory lock for 21 min behind an 89-minute sibling and I stopped
it. The cheap deterministic gate beats the panel on this class — run it FIRST next time.

### PF2 (P1) — the adoption guard is 20.66 s, 23% of it recomputing a value already in scope
`derive_C:264` calls `derive_B` from scratch while `B_SET` is already computed at `:369` and in
scope at the `:543` call site. `derive_B` standalone: **4.83 / 4.85 s**. One-line fix
(`printf '%s\n' "$B_SET" | grep …`) takes 20.66 -> ~15.8 s with no semantic change.
Context: it is now the most expensive member of the `plugins/soleur/test/*.test.sh` auto-glob —
2x the previous slowest of its family — and it is NOT relevance-gated. 11,364 execve/run.

### PF3 (P2) — 7 dirs / ~420 KB leaked per full gate, and the runner's leak detector CANNOT SEE IT
`mkfixture()` (7 call sites, no trap, no `rm` anywhere in the file) leaks 6; the runner's own
sandbox leaks 1. `tc_epilogue` -> `tc_tmp_entry_count` reads `TC_TMPDIR` pinned to `/tmp`
(`test-all.sh:179`) while every sandbox lands in `TMPDIR` pinned to `/var/tmp` (`:165`). **The leak
detector built to catch exactly this is structurally blind to it** — same "partial isolation greps
identically to full isolation" shape this PR argues against.

### PF4 (P2) — the developer inner loop goes 0 -> 1 leaked dir, into the 4 GiB tmpfs
A/B main vs HEAD: a direct `bash <suite>`, `bun test <file>`, and the python import each now leak 1.
A bare shell carries ambient `TMPDIR=/tmp`, not the runner's `/var/tmp` pin.

### Measured NON-findings (recorded so they are not re-litigated)
- **Do NOT memoize the builders.** shell `git_fixture_env` = 4.92 ms/call, TS = 41.9 us/call, 19
  runtime invocations across 5 converted suites, ~0.1 s whole-gate. A cache keyed on `fixtureDir`
  would fight the per-fixture ceiling contract for no win.
- The inheritance short-circuit WORKS: with the root pre-set, a `test-helpers.sh` suite creates
  **0** sandboxes. The "118 files source test-helpers.sh" concern does not materialise under the gate.
- `memory-backstop.test.sh`: +290 diff lines and +12 assertions for **+0.07 s**, because the
  expensive battery is deliberately not `*.test.sh` and not auto-globbed. Right call; keep.
- Pre-existing and NOT this PR: 20 of 56 suites clobber `test-incident-sandbox.sh`'s EXIT trap
  (~20 leaked dirs/gate), and that helper has no `-z` short-circuit (~0.41 s/gate of pointless
  mkdtemps). Both from #7804. This PR is the natural place for the `-z` guard.
