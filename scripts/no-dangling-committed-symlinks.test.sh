#!/usr/bin/env bash
# No tracked symlink in this repository may dangle.
#
# WHY THIS EXISTS. The GitHub Actions runner extracts this repository's archive whenever a
# workflow references one of its own actions by the self-repository form (`uses: $/…`) or by
# `owner/repo/path@ref`. That extraction FAILS on a dangling symlink, and it fails in `Set up
# job` — before any step runs, naming a path that usually has nothing to do with the change:
#
#     ##[error]Could not find file '/home/runner/work/_actions/_temp_<uuid>/_staging/
#     soleur-<sha>/test/fixtures/orphan-proc-dangling/4242/cwd'.
#
# Measured on run 35360150848: `test/fixtures/orphan-proc-dangling/4242/cwd` was committed as a
# link to `/nonexistent-orphan-fixture/work (deleted)` — a deliberate procfs fixture — and it
# aborted the marketplace-drift watcher's whole job. A single re-committed dangling link
# anywhere in the tree disables every workflow that uses a self-reference.
#
# The fixtures that need a dangling link synthesize one under `mktemp -d` at run time
# (`scripts/orphan-process-reaper.test.sh` AC30b does exactly this), so a committed one is never
# required. The rule is therefore unconditional: no tracked symlink may dangle.
#
# The README at test/fixtures/orphan-proc-dangling/ records the same rule in prose. This suite
# is the control — that PR shipped a comment where it needed a check, which is the defect class
# the whole change exists to close.
#
# Exit: 0 clean, 1 on any dangling tracked symlink (each named, with its target).

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

missing=0
scanned=0

# `git ls-files -s` prints `<mode> <sha> <stage>\t<path>`; mode 120000 is a symlink. Strip
# through the TAB so a path containing spaces survives intact.
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  scanned=$((scanned + 1))
  if [[ ! -e "$path" ]]; then
    printf 'dangling committed symlink: %s -> %s\n' "$path" "$(readlink "$path" 2>/dev/null)" >&2
    missing=$((missing + 1))
  fi
done < <(git ls-files -s | awk '$1 == "120000" { sub(/^[^\t]*\t/, ""); print }')

if [[ "$missing" -gt 0 ]]; then
  printf '%s dangling committed symlink(s) of %s scanned. These break GitHub Actions archive\n' \
    "$missing" "$scanned" >&2
  printf 'extraction for EVERY `$/` and `owner/repo@ref` self-reference — see\n' >&2
  printf 'test/fixtures/orphan-proc-dangling/README.md. Synthesize such links at run time instead.\n' >&2
  exit 1
fi

# A zero-symlink tree would pass vacuously. The repo has carried tracked symlinks continuously
# since before this suite existed, so report the count rather than asserting a floor: a drop to
# zero is legible in the output without false-failing a legitimate future removal.
printf 'no-dangling-committed-symlinks: OK — %s tracked symlink(s), all resolve\n' "$scanned"
