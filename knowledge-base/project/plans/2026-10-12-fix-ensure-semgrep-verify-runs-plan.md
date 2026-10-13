# Plan: ensure-semgrep.sh verifies semgrep RUNS, not just resolves on PATH (#9964)

## Overview

`plugins/soleur/skills/review/scripts/ensure-semgrep.sh` bootstraps the semgrep
CLI for the review skill's `semgrep-sast` seat. Its presence test is
`command -v semgrep` — a PATH resolution check. On this host every installed
semgrep shim has a shebang pointing at mise `python/latest` (3.15) while the
package lives under python3.14 site-packages, so `semgrep` resolves and then
dies with `ModuleNotFoundError` on every invocation. The script exits 0 and the
SAST seat silently runs nothing — the exact vacuity class the seat exists to
refuse.

## Problem Statement / Motivation

- **Symptom (reproduced live):** `command -v semgrep` → `~/.local/bin/semgrep`;
  `semgrep --version` → `ModuleNotFoundError: No module named 'semgrep'`;
  `ensure-semgrep.sh` → prints the shim path, exit 0.
- **Blast radius:** every `soleur:review` run on a host in this state green-lights
  a SAST seat that never executed — deterministic CWE/secret rules produce zero
  findings and the review reads that as "clean".
- **The class:** resolution ≠ execution. Any shim layer (mise, pyenv, asdf,
  dead venv shebangs, broken nix store links) can produce a resolvable-but-dead
  binary.

## Proposed Solution

Add an execution probe `semgrep_works()`:

```sh
semgrep_works() {
  command -v semgrep >/dev/null 2>&1 && semgrep --version >/dev/null 2>&1
}
```

and rewire every success arm:

1. **Presence arm** (current `command -v` short-circuit): becomes
   `if semgrep_works; then command -v semgrep; exit 0; fi` — a resolvable-but-dead
   semgrep falls through to the install path as if absent.
2. **Each install arm** (brew → pipx → `pip --user`): after a successful install
   command, verify with `semgrep_works`, not `command -v`. If the install
   "succeeded" but the probe still fails (PATH shadowing — e.g. brew's binary at
   `/opt/homebrew/bin` or `/usr/local/bin` stays behind the dead
   `~/.local/bin` shim), fall through to the NEXT installer.
3. **Terminal failure:** when all installer attempts are done and the probe
   still fails, exit non-zero with a diagnostic naming the resolved-but-dead
   binary (`command -v semgrep` output) — exit 1 (install attempted, still
   not working) rather than 2 (no installer available), so the review skill's
   abort message distinguishes "couldn't install" from "installed but a
   shadowing broken shim still wins PATH".

**Deliberate non-goals:** no installer reordering (brew → pipx → pip is the
documented order), no PATH surgery on the dead shim (the script must not
delete or reorder user binaries — it falls through to installs that land
ahead of or at the same path), no `timeout` wrapper on the probe (matches the
issue's suggested form; semgrep startup is bounded in practice and `timeout`
is not portable to bare macOS).

## Files to Edit

- `plugins/soleur/skills/review/scripts/ensure-semgrep.sh` — add
  `semgrep_works()`, rewire presence + install arms, diagnostic on terminal
  failure.
- `plugins/soleur/skills/review/SKILL.md` — one-line update if the exit-code
  vocabulary changes (exit 1 gains "installed but still dead" semantics).

## Files to Create

- `plugins/soleur/skills/review/scripts/ensure-semgrep.test.sh` — hermetic
  suite. PATH-shimmed stubs: (a) working `semgrep` → rc 0, no installer
  invoked; (b) resolvable-but-dead `semgrep` + working installer stubs →
  installer invoked, rc 0 after install; (c) dead `semgrep` + no installers →
  rc non-zero, NOT reported present; (d) dead `semgrep` + installer that
  installs a still-dead binary → falls through / rc 1; (e) absent `semgrep` +
  working installer → rc 0 (regression: absent-path unchanged); (f) vacuity
  pin — the suite's own shim actually executed the stub semgrep (--version
  invoked at least once on every rc-0 path: a probe that never ran cannot
  prove runs-ability).

## Acceptance Criteria

- [ ] **AC1** A resolvable-but-dead `semgrep` no longer causes exit 0: the
  script proceeds to the install path or exits non-zero.
- [ ] **AC2** Every exit-0 path passes through a successful
  `semgrep --version` execution (the probe is the single success gate).
- [ ] **AC3** A successful installer whose binary is still shadowed by the dead
  shim falls through to the next installer; the terminal exit is non-zero
  with a diagnostic naming the dead binary.
- [ ] **AC4** The absent-semgrep path is unchanged modulo the probe
  (install order brew → pipx → pip --user; exit codes 0/1/2 vocabulary
  preserved).
- [ ] **AC5** `ensure-semgrep.test.sh` drives each arm hermetically and at
  least one arm fails when the execution probe is reverted (mutation: swap
  `semgrep_works` for `command -v` in the presence arm → the suite goes red).

## Test plan

- `bash plugins/soleur/skills/review/scripts/ensure-semgrep.test.sh`
- Live repro check on this host: run `ensure-semgrep.sh` — expected behavior
  is to attempt install (pipx exists) and either verify the fresh binary or
  exit non-zero naming the dead shim. Note the observed outcome in tasks.md.
- `bash -n` on both files; `lint-shell-capture-exit` baseline run;
  `grep-q-pipe-guard` sweep clean on the new file (no `| grep -q`/`| grep -m`
  pipe-into-early-exit forms).
