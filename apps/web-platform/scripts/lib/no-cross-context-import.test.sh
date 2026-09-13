#!/usr/bin/env bash
# Guard: no apps/web-platform PRODUCTION source file may reference a module or
# asset that resolves OUTSIDE apps/web-platform/ (the Next.js Docker build
# context copies only apps/web-platform/ + the vendored plugin, NOT repo-root
# scripts/, .claude/, or any sibling app). Such a cross-context reference
# COMPILES under a local `next build` (the full repo is present) but FAILS the
# containerized build with "Module not found: Can't resolve '../../../…'" — a
# silent trap that ships green through PR CI (which builds on the full checkout)
# and only reddens the web-platform-release Docker build, blocking prod deploy.
#
# Two instances of the class this guard sees, and four of the wider "green
# locally, red in the Docker context" family (#5890, #6852, #7666, #8074):
#   * #6852 imported stripFrontmatter from repo-root scripts/lib/frontmatter-strip/
#     strip.ts into cron-compound-promote.ts; local `next build` + tsc were green,
#     release run 29994907565 step 19 failed and the deploy was blocked. #6875
#     inlined the helper; #6877 added this guard (relative import/require only).
#   * #8074 imported three pure functions from the standalone cron containment
#     hook (server/inngest/cron-bash-allowlist-hook.mjs) into a bundled module.
#     The hook resolved its taxonomy with a static `new URL(<literal>,
#     import.meta.url)`; to Turbopack that is a build-time ASSET reference the
#     moment the file is bundled — and a standalone .mjs becomes bundled the day
#     a .ts imports one function from it. The literal pointed above the app into
#     .claude/, which is not in the Docker context: every push to main from
#     0f649dbfb failed the release build until the fix that widened this guard
#     to .mjs files and the `new URL` syntax.
#
# Sibling guard, OTHER axis: apps/web-platform/test/docker-context-import-
# containment.test.ts (vitest) checks that context-root *.config.ts imports are
# not pruned by .dockerignore (#7666, #5890). This guard models "resolves inside
# the app dir"; that one models "not excluded by .dockerignore". They overlap on
# next.config.ts / vitest.config.ts by design — do not consolidate one into the
# other.
#
# Scan design:
#   * ONE `perl -0777` pass over every tracked production file (ONE pathspec
#     array, ONE alternation, ONE resolver loop, ONE fail flag). NOT `git grep`:
#     git grep is line-based and the in-repo scripts/sandbox-canary.mjs already
#     spells `new URL(` with the string on the NEXT line — a line-based scan
#     passed a multi-line copy of the exact defect #8074 shipped. A Prettier
#     reflow of an over-long import(/require( produces the same shape.
#   * The negated class is [^"\x27\n], with \n: under -0777 a JS string literal
#     cannot span a raw newline, and without \n a stray `'../` inside a COMMENT
#     swallows the following real escaping import into one capture, so the
#     escaping import is never reported (measured).
#   * The regex does NOT skip comments — a quoted `'../` specifier in a comment
#     of a scanned file is a hit, and if it escapes, a FAIL. Never write one.
#   * perl's -n uses 2-arg magic open; closed only because every path is
#     `apps/…`-prefixed by the globs (no leading `-`, `<`, `|`).
#   * TWO zero floors are the detection path for a dark scan, not stderr:
#     `checked -eq 0` catches a fully dark scan (perl absent, broken pathspecs,
#     unopenable files); `saw_url -eq 0` catches a PARTIALLY dark scan — drop
#     only the .mjs pathspec or only the `new URL` alternation and ~660 .ts hits
#     keep the first floor quiet while the class this guard was widened for is
#     unscanned. scripts/sandbox-canary.mjs is the known positive on every tree.
#     Do not "clean up" either floor.
#
# Assembly limits (stated, not hidden): tracked files only (an untracked file is
# invisible until `git add`; in CI everything is tracked). The model is
# "resolves inside apps/web-platform/", not "inside the Docker context" —
# .dockerignore prunes scripts/ and infra/ except re-includes; the sibling guard
# covers that for context-root configs. A `.js` glob is deliberately absent:
# zero tracked production .js files exist under the app; add it the day one does.
# Known cost: one `realpath -m` fork per hit (~7 s on ~670 hits); not this PR's.
#
# Auto-discovered by scripts/test-all.sh's `apps/web-platform/scripts/lib/*.test.sh`
# glob (scripts shard). Test files, e2e, public/, and the test/ tree are excluded —
# they are NOT in the Docker build and legitimately reference repo-root scripts/
# under vitest (which has the full repo).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
APP="$ROOT/apps/web-platform"
fail=0
checked=0
saw_url=0

# `:(glob)` magic so TOP-LEVEL app files (next.config.ts, middleware.ts,
# instrumentation.ts, sentry.*.config.ts) are in scope: a plain
# `apps/web-platform/**/*.ts` pathspec requires a `/` after the app dir and
# silently skipped them (a pre-existing gap of the git-grep form).
PATHSPECS=(
  ':(glob)apps/web-platform/**/*.ts'
  ':(glob)apps/web-platform/**/*.tsx'
  ':(glob)apps/web-platform/**/*.mjs'
  ':!apps/web-platform/**/*.test.ts'
  ':!apps/web-platform/**/*.test.tsx'
  ':!apps/web-platform/**/*.test.mjs'
  ':!apps/web-platform/**/*.spec.ts'
  ':!apps/web-platform/**/*.spec.tsx'
  ':!apps/web-platform/test/**'
  ':!apps/web-platform/e2e/**'
  ':!apps/web-platform/public/**'
)

# One multiline scan: `from '../x'`, `import('../x')`, `require('../x')`,
# `new URL('../x', …)` — on one line or across lines. Captures the keyword so
# the loop can tell which arm produced each hit. The captures are copied into
# lexicals BEFORE the keyword test: `$1 =~ /^new/` is itself a match and, when
# it succeeds, resets $1/$2 — so a `url` hit printed an EMPTY specifier (and
# the empty middle field collapsed under IFS=tab, so `kind` never read `url`).
# Measured on the first run; the saw_url floor is what caught it.
# Process substitution (not
# `| while`) so fail/checked/saw_url mutate in THIS shell; `cd "$ROOT"` so
# $ARGV is repo-relative; `xargs -0r` so an empty list never runs perl -ne on
# STDIN; `2>/dev/null` mirrors the old arm for a tracked-but-deleted file.
while IFS=$'\t' read -r file spec kind; do
  [[ -z "$file" ]] && continue
  checked=$((checked+1))
  [[ "$kind" == url ]] && saw_url=1
  resolved="$(realpath -m "$(dirname "$ROOT/$file")/$spec")"
  case "$resolved" in
    "$APP"/*) : ;;  # resolves within web-platform — in the Docker build context
    *)
      echo "FAIL: $file references '$spec'"
      echo "        → resolves to $resolved (OUTSIDE apps/web-platform/ — absent from the Docker build context)"
      fail=1
      ;;
  esac
done < <(cd "$ROOT" && git ls-files -z -- "${PATHSPECS[@]}" \
         | xargs -0r perl -0777 -ne 'while (/\b(from|import|require|new\s+URL)\s*\(?\s*["\x27](\.\.?\/[^"\x27\n]*)["\x27]/g) { my ($kw, $sp) = ($1, $2); my $k = ($kw =~ /^new/) ? "url" : "import"; print "$ARGV\t$sp\t$k\n" }' 2>/dev/null)

if [[ "$checked" -eq 0 ]]; then
  echo "FAIL: no relative references scanned — the scan produced zero candidates, which is not credible for apps/web-platform; perl is missing, the pathspecs broke, or the files were unopenable."
  exit 1
fi

if [[ "$saw_url" -eq 0 ]]; then
  echo "FAIL: the new URL(…) arm produced zero hits — scripts/sandbox-canary.mjs is a known positive on every tree; the .mjs pathspec or the alternation went dark."
  exit 1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "OK: $checked relative reference(s) scanned; none escape apps/web-platform/ (Docker build context intact)."
fi
exit "$fail"
