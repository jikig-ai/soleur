# `set -o pipefail` + `grep -q` on an EARLY match SIGPIPEs the upstream and flips a real match to a false negative

## Problem

While authoring `apps/web-platform/infra/workspaces-luks-header.test.sh` (#6649), a `holds`
predicate intermittently reported "property does not hold on the real file" — it passed on one run
and failed on the next with no code change. The predicate was the standard repo shape:

```bash
p_script_distinct() {
  strip_comments "$1" | grep -Eq 'PATTERN' && echo 1 || echo 0
}
```

The pattern genuinely matched the file (a manual `strip_comments "$1" | grep -Eq 'PATTERN'` returned
`MATCH`), yet inside the harness — which runs `set -uo pipefail` — the predicate returned `0`.

## Root cause

`grep -q` exits **as soon as it finds the first match** and closes its end of the pipe. When the
match is **early** in the input and the upstream producer is still writing (a *streaming* `sed` from
`strip_comments`, or a `printf` of a body larger than the OS pipe buffer), the producer receives
**SIGPIPE** and exits non-zero (141). Under `set -o pipefail` the pipeline's exit status becomes that
non-zero producer status **even though `grep` succeeded** — so `&& echo 1` is skipped and `|| echo 0`
runs. The result is a **false negative that only appears when the pattern actually matches early**,
and it is timing/buffer-dependent, hence the flake.

The asymmetry is the tell:
- **No match:** `grep -q` reads ALL input (never early-closes) → producer finishes → pipe exit 0/1
  cleanly → predicate is correct and stable. (This is why `p_no_doppler_run`-style "must be ABSENT"
  guards never flaked.)
- **Early match:** `grep -q` early-closes → producer SIGPIPE → `pipefail` → false negative → flake.

`assert_mutation_append` guards also hide the bug: their injected match lands at the **end** of the
file, so `grep -q` reads everything before matching → no early close → no SIGPIPE. The flake only
bites a `holds` assertion whose real match is near the top.

## Solution

Never pipe a streaming/large producer into `grep -q` under `pipefail`. Two safe forms:

```bash
# (a) herestring — no pipe at all, so no SIGPIPE (preferred for a captured var):
grep -Eq 'PATTERN' <<<"$body"

# (b) grep -c — reads ALL input (never early-closes), then compare the count:
[ "$(strip_comments "$1" | grep -Ec 'PATTERN' || true)" -gt 0 ]
```

In the PR every `printf '%s' "$var" | grep -q` became `grep <<<"$var"`, and the one
`strip_comments "$f" | grep -q` on an early match became the `grep -Ec … -gt 0` form. The suite went
from 18 assertions (flaky) to 29 assertions **stable across repeated runs**.

## Key insight

`pipefail` + `grep -q` is a foot-gun whenever the match can be early and the upstream streams. It is
invisible on a first green run and on append-mutation tests, so it ships as a latent flake. The repo
has **many** accumulate-then-exit `.test.sh` drift guards built on `strip_comments | grep -q`; any
whose `holds` pattern matches early in a large file is a candidate for this flake. Prefer a herestring
(`grep <<<"$var"`) or `grep -c` (count) over `grep -q` on a pipe in any `set -o pipefail` gate.

## Session Errors

- **`grep -q` + pipefail SIGPIPE flake (this learning).** Recovery: herestrings + `grep -c`.
  Prevention: this learning; when authoring a `set -o pipefail` `.test.sh` guard, use
  `grep <<<"$var"` or `grep -Ec … -gt 0`, never `producer | grep -q` for a possibly-early match.
- **`gh issue create` `--milestone` hook rejected the whole Bash call, killing the inline
  `cat <<EOF` body write.** Recovery: wrote the body with the Write tool first, then
  `gh issue create --body-file`. Prevention: already covered by
  `best-practices/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md`
  (never heredoc an issue body in the same Bash command as a hook-gated `gh issue create`).
- **`vitest run` at repo root → EXIT 127.** Recovery: plugin tests run via `bun test`; app tests via
  `apps/web-platform/node_modules/.bin/vitest`. Prevention: known env fact; no rule change.
- **shellcheck SC2034 on `eval`'d vars.** Recovery: `# shellcheck disable=SC2034` + dropped a
  redundant assignment the eval'd loader overwrites. One-off.

## Tags
category: test-failures
module: apps/web-platform/infra
