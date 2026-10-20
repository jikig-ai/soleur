#!/usr/bin/env bash
# lint-feature-map-coverage.sh -- fail when the tracked
# apps/web-platform/app/** page.tsx set and apps/web-platform/test/feature-map.md
# drift apart in either direction (#10399).
#
# WHY (#10399, epic #10397): the repo carries no maintained, user-POV
# inventory of the app's routes, so navigation-driven skills (test-browser,
# qa, ux-audit, reproduce-bug) re-derive file->route mappings at runtime.
# feature-map.md is that inventory -- and an inventory that silently rots is
# worse than none, because it steers verification at the wrong route with the
# confidence of a registry. This file is the durability half of the map: it
# proves bidirectional consistency on every run instead of trusting the PR
# that last touched it.
#
# FOUR ARMS, because the defect exists at four levels.
#
#   Coverage:     every route derived from a tracked page.tsx is either
#                 mapped (a `## \`/route\`` heading) or reasoned-exempt (a
#                 `- \`/route\` — <reason>` bullet under `## Deliberately
#                 unmapped`). A new page.tsx without either reds.
#   Staleness:    every mapped/exempted route still derives from a real
#                 page.tsx -- a tombstone entry for a deleted route reds
#                 (deleting a page AND its entry in one PR is the DESIRED
#                 consistency, not drift).
#   Completeness: every mapped entry body carries `selectors:` and
#                 `expects:` lines -- the issue's AC demands them, so a
#                 presence-only heading would certify a non-conformant map.
#   Contradiction: a route present in BOTH the mapped and exempted sets
#                 reds -- a classification must pick one side.
#
# Exemption bullets carry a REASON: `- \`/route\` — <reason>` requires
# non-empty text after the em-dash. A bullet without it is
# MALFORMED-EXEMPTION, not an exemption -- skipping is a recorded decision,
# not silent absorption. The registry lives inside the map itself (the
# `## Deliberately unmapped` section) so the allowlist is maintained where
# contributors already look, per the CTO ruling in the plan's
# decision-challenges.md.
#
# THE PRODUCER IS `git ls-files` OVER THE WHOLE TRACKED app/ TREE filtered to
# `/page.tsx$` -- not a directory walk, and NOT the glob
# 'apps/web-platform/app/**/page.tsx': measured on git 2.56 the `**/`
# pathspec does not match zero directories, so it silently drops
# apps/web-platform/app/page.tsx -- the `/` route itself. `apps/web-platform/app`
# as a bare pathspec enumerates the tree recursively and the grep keeps the
# one suffix that defines a navigable page (`route.ts` API handlers are
# deliberately outside it).
#
# Route derivation: strip `apps/web-platform/app/`, drop the trailing
# `/page.tsx`, remove `(...)` route-group segments, keep everything else
# literal -- `internal/` is a real path segment, `[param]`/`[...catchall]`
# stay literal in the map key. An empty remainder is `/`.
#
# THIS FILE HAS A COMPANION SUITE (scripts/lint-feature-map-coverage.test.sh):
# a guard whose failure mode is "silently stops detecting" cannot be proved by
# reading it, so the battery mutates the tree underneath it.
#
# FIXTURE SEAM: SOLEUR_FEATURE_MAP_ROOT redirects the repo root (producer and
# consumer) so the companion battery can drive a scratch fixture repo. The
# root must be a real `git` work tree -- the producer is `git ls-files`, and
# a plain directory would enumerate ZERO routes and trip the anti-vacuity arm.
# (Distinct from SOLEUR_LINT_GATES_ROOT so a session mid-debug on the
# env-gates sentinel cannot cross-drive this one.)
#
# ENFORCEMENT LEVEL IS ADVISORY. The CI step lives in the `lint-bot-statuses`
# job, which is absent from BOTH scripts/required-checks.txt and the ruleset,
# so a PR can merge with it red -- promotion is a deliberate follow-up on the
# #6883/ADR-139 path, not a side effect.

set -euo pipefail
export LC_ALL=C

REPO_ROOT="${SOLEUR_FEATURE_MAP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MAP_FILE="apps/web-platform/test/feature-map.md"   # single constant -- cited by symbol everywhere below
APP_PREFIX="apps/web-platform/app/"
MAP_PATH="$REPO_ROOT/$MAP_FILE"

fails=0
# Arm counters are bound here, before the map-existence branch, so a missing
# map cannot leave `${var}` references unbound under `set -u`.
uncovered=0
tombstone=0
contra=0
incomplete=0
malformed_n=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/mapped"
: > "$WORK/exempted"

# --- Producer ---------------------------------------------------------------
# `|| true`: grep exits 1 on zero matches and `set -euo pipefail` would kill
# the script before the anti-vacuity arm can report the empty census -- the
# zero check below is the verdict, not the pipeline rc.
git -C "$REPO_ROOT" ls-files "$APP_PREFIX" | grep -E '/page\.tsx$' | LC_ALL=C sort -u > "$WORK/pages" || true
pages_n=$(wc -l < "$WORK/pages" | tr -d ' ')

# ANTI-VACUITY. A producer that derives nothing certifies nothing: a narrowed
# glob, a moved app/ tree, or a non-repo root must all read as failures, never
# as "0 checked, all clean". The battery's R6 row mutates the suffix regex to
# prove this arm fires.
#
# Finding lines go to STDOUT, not stderr: they are the operator-protection
# signal (the routes a contributor must map), and several agent runtimes
# swallow stderr -- the same reason the summary line is a stdout print.
if (( pages_n == 0 )); then
  echo "feature-map-coverage: producer derived ZERO page.tsx routes under ${APP_PREFIX} -- a vacuous producer is not a clean tree."
  fails=$((fails + 1))
fi

# derive each route: strip the app prefix and the /page.tsx suffix, drop
# `(...)` route-group segments, keep literal segments (incl. [param] and
# `internal/`), empty remainder -> `/`.
: > "$WORK/routes"
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  rel="/${f#"$APP_PREFIX"}"        # leading slash makes the suffix strip uniform (page.tsx at root included)
  rel="${rel%/page.tsx}"
  out=""
  IFS='/' read -ra segs <<< "$rel" || true
  for seg in ${segs[@]+"${segs[@]}"}; do
    [[ -z "$seg" ]] && continue
    [[ "$seg" == \(*\) ]] && continue
    out+="/$seg"
  done
  printf '%s\n' "${out:-/}" >> "$WORK/routes"
done < "$WORK/pages"
LC_ALL=C sort -u -o "$WORK/routes" "$WORK/routes"

# --- Consumer ---------------------------------------------------------------
if [[ ! -f "$MAP_PATH" ]]; then
  echo "feature-map-coverage: map file missing at ${MAP_FILE} -- the coverage registry does not exist, so no route can be certified."
  fails=$((fails + 1))
else
  # Mapped set: `## \`/route\`` headings ONLY. The anchor is `^## ` + a
  # backtick-slash -- `## Deliberately unmapped` carries no backtick and stays
  # out, `### ` subsections inside entries cannot match the two-# anchor, and
  # a bare path token elsewhere in the document certifies nothing (battery
  # R10/R12 pin both directions). Optional trailing prose after the closing
  # backtick is allowed.
  grep -oE '^## `(/[^`]*)`' "$MAP_PATH" | sed -E 's/^## `([^`]+)`.*/\1/' | LC_ALL=C sort -u > "$WORK/mapped" || true

  # Exempted set: bullets under `## Deliberately unmapped` of the exact shape
  # `- \`/route\` — <reason>`. The em-dash and a non-empty reason are part of
  # the shape; anything bullet-like that fails the shape is a
  # MALFORMED-EXEMPTION, reported by name below.
  : > "$WORK/malformed"
  awk '
    /^## Deliberately unmapped/ { in_unm=1; next }
    /^## / { in_unm=0 }
    in_unm && /^- (`?\/)/ {
      if ($0 ~ /^- `\/[^`]*` — [^[:space:]]/) {
        r=$0; sub(/^- `/, "", r); sub(/`.*/, "", r)
        print "OK\t" r
      } else {
        print "BAD\t" $0
      }
    }
  ' "$MAP_PATH" > "$WORK/exempted_raw" || true
  while IFS=$'\t' read -r tag val; do
    [[ -n "$tag" ]] || continue
    if [[ "$tag" == "OK" ]]; then
      printf '%s\n' "$val" >> "$WORK/exempted"
    else
      printf '%s\n' "$val" >> "$WORK/malformed"
    fi
  done < "$WORK/exempted_raw"
  LC_ALL=C sort -u -o "$WORK/exempted" "$WORK/exempted"

  # Entry completeness: each mapped heading's body (until the next `^## ` or
  # EOF) must contain `selectors:` and `expects:` lines. `### ` subsections do
  # not close a body (the anchor is two # then space).
  awk '
    function emit() {
      if (route != "") printf "%s\t%d\t%d\n", route, sel, hasexp
    }
    /^## `\/[^`]*`/ {
      emit()
      route=$0; sub(/^## `/, "", route); sub(/`.*/, "", route)
      sel=0; hasexp=0; next
    }
    /^## / { emit(); route="" }
    route != "" {
      if ($0 ~ /selectors:/) sel=1
      if ($0 ~ /expects:/) hasexp=1
    }
    END { emit() }
  ' "$MAP_PATH" > "$WORK/completeness" || true

  # --- Arm reports ----------------------------------------------------------
  # Findings go to stdout: they are the operator-protection signal (the routes
  # a contributor must map), not diagnostic noise -- stderr is swallowed by
  # several agent runtimes.
  : > "$WORK/union"
  cat "$WORK/mapped" "$WORK/exempted" | LC_ALL=C sort -u > "$WORK/union"

  # Coverage arm: derived minus union = unmapped, unexempted routes.
  uncovered=0
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    uncovered=$((uncovered + 1))
    echo "UNCOVERED-ROUTE: ${r} -- derived from a tracked page.tsx but neither mapped nor exempted in ${MAP_FILE}"
  done < <(comm -23 "$WORK/routes" "$WORK/union")

  # Staleness arm: union minus derived = tombstone entries (map or exemption
  # outlived its page).
  tombstone=0
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    tombstone=$((tombstone + 1))
    echo "TOMBSTONE-ENTRY: ${r} -- present in ${MAP_FILE} but no page.tsx derives it; delete the entry or restore the route"
  done < <(comm -13 "$WORK/routes" "$WORK/union")

  # Contradiction arm: intersection of mapped and exempted.
  contra=0
  while IFS= read -r r; do
    [[ -n "$r" ]] || continue
    contra=$((contra + 1))
    echo "CONTRADICTORY-ROUTE: ${r} -- carries both a '## \`${r}\`' entry and a Deliberately-unmapped bullet; pick one classification"
  done < <(comm -12 "$WORK/mapped" "$WORK/exempted")

  # Completeness arm.
  incomplete=0
  while IFS=$'\t' read -r r sel hasexp; do
    [[ -n "$r" ]] || continue
    missing=""
    if (( sel == 0 )); then missing="selectors:"; fi
    if (( hasexp == 0 )); then missing="${missing:+${missing}, }expects:"; fi
    if [[ -n "$missing" ]]; then
      incomplete=$((incomplete + 1))
      echo "INCOMPLETE-ENTRY: ${r} -- mapped entry body lacks ${missing} (presence is not conformance)"
    fi
  done < "$WORK/completeness"

  # Malformed exemption bullets.
  malformed_n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    malformed_n=$((malformed_n + 1))
    echo "MALFORMED-EXEMPTION: ${line} -- Deliberately-unmapped bullets must be '- \`/route\` — <reason>'; an exemption is a recorded decision"
  done < "$WORK/malformed"
fi

if (( fails > 0 )); then
  exit 1
fi

mapped_n=$(wc -l < "$WORK/mapped" | tr -d ' ')
exempted_n=$(wc -l < "$WORK/exempted" | tr -d ' ')

if (( pages_n > 0 && uncovered == 0 && tombstone == 0 && contra == 0 && incomplete == 0 && malformed_n == 0 )); then
  echo "feature-map-coverage: ok (routes=${pages_n} mapped=${mapped_n} exempted=${exempted_n})"
  exit 0
fi
exit 1
