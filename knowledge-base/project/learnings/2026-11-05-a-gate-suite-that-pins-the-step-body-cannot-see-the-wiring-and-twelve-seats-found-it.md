# Learning: a gate suite that executes the step body pins what the step decides, not whether anything obeys it

## Problem

PR #12133 (epic #9927 item 8) rewrote the host-replace inherited-done preflight to fail closed and added a suite
that extracted the step by name and EXECUTED it under a stubbed `doppler` (16 decisions, 17 mutants, all caught).
A 12-seat review found the suite certified the step's body and nothing about whether the gate is in force:

1. A step-level `if: ${{ false }}`, a `shell:` key, job-level `defaults.run.shell`, moving the step after the plan,
   a second job replacing `hcloud_server.inngest` without the step, or a new workflow reading the secret all left
   the suite green (the harness runs the extracted body under `env -i` and fixed bash flags, so step context is
   unmodelled).
2. The "exactly one reader of the arm secret" count in Guard 2 matched only `secrets.DOPPLER_TOKEN_INNGEST_ARM`:
   `secrets['…']`, a lower-case name and `toJSON(secrets)` all read as 1.
3. A "value withheld" row fed `Bad Value!`, but the step strips whitespace first, so the grep for `Bad Value`
   could never match; echoing the flag value passed 39/39.
4. A stub that answered by `*"-c prd"*` globs accepted `-c prd_terraform`; the absent-key row passed through the
   empty-value arm because the stub's `get` succeeded for an absent key (real doppler exits 1).
5. `timeout 30` on both doppler calls was pinned by nothing (deleting it stayed green).

## Solution

- Extract the step with `yaml.safe_load` and pin its wiring: exact key set (`env,name,run`), index before the first
  terraform plan/apply (detected by run text, not step name), `defaults`/`shell`/`BASH_ENV` absent, and every job
  whose run text replaces the host contains exactly one such step.
- Scan `.github/workflows` + `.github/actions` repo-wide, case-insensitively and bracket-aware, for the readers of
  both secrets, and ban `toJSON(secrets)`, `join(secrets`, `secrets[format(`.
- Make the stub exact-argv (refusals logged and asserted empty), give it the real absent-key behaviour, add an
  exit-124 mode, and add hygiene rows (token not in the log, argv, `$GITHUB_ENV`).
- State the scope in the suite header: it names the spellings this repo can produce; it is not a proof that no
  other consumer exists. Stop widening regexes once the remaining holes (script-hidden replace, composite action
  fed through an input) are by-design outside it.

## Key Insight

For a gate expressed as a workflow step, "executes the real bytes" is necessary and not sufficient: the property
is "this runs, before the destructive step, under this shell, and nothing else can do the destructive thing",
and every clause of that is outside the step body. Write the wiring checks in the FIRST version of the suite —
they are mechanical once the step is parsed as YAML. Separately, when a review fix round keeps finding new
spellings, record the guard's scope in its header rather than chasing the last regex; the honest claim is the
durable one.

## Session Errors

1. **Suite helper called in `$(...)` lost its globals** (`run_step` counters/`LAST_*`; `mutate` aborts and counters).
   Recovery: set `RUN_RC`/`MUT` globals, call directly, count executions via a file. **Prevention:** already in the
   work skill ("`mutate` in `$(...)` cannot abort"); name helpers that mutate state `*_into VAR` or document
   "never in `$( )`" at definition, as done here.
2. **Stub shebang `#!/usr/bin/env bash` unusable under a symlink-farm PATH** (exit 127 read as a doppler failure).
   **Prevention:** write the stub's shebang from `command -v bash` (absolute) whenever the PATH is restricted.
3. **Ranged `sed` mutations landed on 25 other files' lines** (`set -uo pipefail` appears in every step).
   **Prevention:** scope every mutation to the step's range and assert the diff-line count (the `mutate` helper does).
4. **New fixture site tripped the `fixture-relative-assert` ratchet** (`cp -r A B "$d/"`). **Prevention:** one source
   per `cp`, guard with `assert_fixture_dir` as a statement first (documented in work 6.6).
5. **`gh issue create` denied by the filing gate** (no user-visible consequence / `Mandated-By`). **Prevention:** a
   plan-mandated tracker needs `Mandated-By: wg-when-deferring-a-capability-create-a` on its own body line.
6. **`$TMPDIR` is unset in this harness**: `cat > "$TMPDIR/x"` resolved to `/x` and failed (twice, harmless).
   **Prevention:** use `mktemp -d -t soleur-run.$$.XXXXXXXX` or the scratchpad, never `$TMPDIR/...` unguarded.
7. **`pgrep -f` blocked by the self-match hook** while looking for the affected gate. **Prevention:** resolve
   ownership through `/proc/<pid>/cwd`.
8. **Affected gate left running while the tree changed underneath it** (a 27-minute lock queue meant it started after
   the agents' edits); stopped by killing its process group. **Prevention:** launch the gate only after the last
   edit of the phase, and read the queue heartbeat before assuming a hang.
9. **Plan departed from the brief** (keep rollback/resume): recorded as a CTO ruling plus an `operator (scope)` row,
   not asked in-session. **Prevention:** none needed; the routing worked.
