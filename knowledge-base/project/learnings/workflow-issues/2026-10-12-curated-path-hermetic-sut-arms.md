---
title: "A 'no installer available' arm is only hermetic under a curated PATH — /usr/bin/python3 was silently running a real pip install"
date: 2026-10-12
category: workflow-issues
module: plugins/soleur/skills/review/test/ensure-semgrep.test.sh (#9964, PR #10174)
issues: [9964]
tags: [test-isolation, hermetic-stubs, curated-path, env-i, stub-argv-fidelity]
---

# PATH-shimmed stubs are not hermetic while `/usr/bin` is on the line

## Problem

A suite shimmed a dead `semgrep` in a mktemp dir and ran the SUT under
`PATH="$D:/usr/bin:/bin"` — standard shim practice. The arm titled "no
installer available" stubbed only `semgrep`. The SUT's third installer arm is
`python3 -m pip install --user semgrep` — and real `python3` lives in
`/usr/bin` on every host. The arm was silently exercising a **real PyPI
install into `$HOME/.local`** (host mutation + network egress), and on the
very host the issue was filed from it could overwrite the dead shim the PR
documents. The arm only passed when the install happened to fail.

A second leak: the SUT prepends `$HOME/.local/bin` after pipx/pip installs —
the host's real `~/.local/bin/semgrep` (dead, live, or absent) joined the
re-probe and changed the verdict depending on host state.

## What worked

`env -i` with a curated PATH, not a prepended one:

```sh
run_sut() { env -i PATH="$dir:$dir/tools" HOME="$dir/home" /bin/bash "$SUT"; }
```

- `tools/` holds **only** symlinks to the coreutils the stubs need
  (`chmod`, `cp`, `mkdir`, `env`, `ls`). Real brew/pipx/python3/timeout cannot
  be resolved — `command -v` can only hit the arm's own stubs.
- `HOME` is a per-arm sandbox dir, so `$HOME/.local/bin` prepends land in the
  sandbox and can be *measured* (a stub installing only into the fake HOME
  proves the prepend is load-bearing — rc 0 fails without it).
- Side benefit: the `timeout`-absent probe branch gets exercised for free
  (curated PATH has no timeout binary → unbounded fallback arm runs).
- Bonus property: `env -i` drops ambient CI/inherited env vars that the SUT
  or a stub could accidentally read.

## Adjacent fixes that shared the review round

- **`attempted` vs `installed`:** the rc vocabulary promised "install
  attempted" → 1 vs "no install path" → 2. Tracking only installer *success*
  sent attempted-but-failed down the rc-2 tail with a false "no path
  available" message. Track attempted separately — the diagnostic code is a
  caller contract, not a bookkeeping detail.
- **Probe-ran pins on every rc-0 path:** asserting rc 0 + `called` proves the
  installer ran; it does NOT prove the post-install re-probe ran. The
  installer stub installs a probe-logging semgrep (`echo $1 >>probe-log`) and
  each rc-0 arm asserts `--version` appears — deleting the re-probe goes red.
- **Argv-faithful stubs:** a stub that succeeds on any argv accepts
  `pipx semgrep install` and `brew frobnicate` equally — record `$*` into
  `called` AND require the exact argv (`$1=-m $2=pip $3=install ...`) before
  the success branch.
- **Stub generation by composition, not nested printf:** three levels of
  `\\\\\\"` escaping produced a structurally-broken installed stub — the fix
  was writing the installed binary once per arm (`write_installed`) and
  having installer stubs `cp` it into place. Compose; don't nest escapes.

## Session Errors

**Nested-printf stub generation broke at three escape levels**

- The brew/pipx/python3 stubs generated their *installed* semgrep via a
  `printf` inside a `printf` — four arms failed on structure, not semantics.
- **Prevention:** when a stub must produce a second stub, pre-write the inner
  artifact directly (`write_installed`) and have the outer stub `cp` it —
  the composition is readable and has exactly one escape level.

## Cross-references

- `plugins/soleur/skills/community/test/community-argv.test.sh` — the
  MINPATH/`env -i` pattern this follows (found by the test-design seat)
- 2026-10-12-a-text-grep-over-a-grammar-is-never-closed.md — escape-level
  arithmetic class (same-day sibling)
