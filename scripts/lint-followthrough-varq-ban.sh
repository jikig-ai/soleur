#!/usr/bin/env bash
# lint-followthrough-varq-ban.sh -- the follow-through PROBE lint. Six rules, one exit
# contract. Rule 1 (#6757): no probe may gate its exit on the banned `: "${VAR:?msg}"` /
# colon-less `${VAR?msg}` word-expansion. Rule 2 (#7946): no file under the target dir may
# name the retired credential. Rule 3 (#7490): every repo-relative path a probe assigns must
# exist in the checkout. Rule 4 (#6617): a probe that reads issue comments AND branches on a
# `RESULT:` verdict or an `S<n>-...` soak marker must route that decision through
# scripts/lib/trusted-verdict.sh -- stated as the POSITIVE OBLIGATION, because a ban on the
# wrong mechanism was green over a probe that read `.comments[].body` with no author filter at
# all. Rule 5 (#9818): no probe may mention the comment-author-association field (REST
# `author_association`, GraphQL `authorAssociation`) on an executable line -- the SPELLING ban
# that complements rule 4's obligation. Rule 6 (#11553): every executable-line `/events/` call
# in a probe must carry an ordering bound on the same logical line (backslash-continuations
# folded, so a `curl -G --data-urlencode` block is one checkable unit): `sort=`, or `start=`
# AND `end=`; a `field=<name>()` aggregate select is exempt -- a one-row result has no ordering
# to pin. It walks the same probe set as rules 1/3/4/5, counts `/events/` logical lines
# examined (`scanned_rule6`, exempt included), and carries its own floor. Declared blind
# spots: an endpoint or its params assembled across NON-continuation statements or passed by
# indirection, and a runtime-constructed endpoint. (Rule 4 had a body heading and no index
# entry here, which is the same defect this header already records for rule 1 -- a reader
# looking for it found it only in the failure message.) The name is kept although the file now does more than rule 1: it is
# cited from followthrough-convention.md, ADR-031, the Article 30 register and several
# learnings, and renaming it would churn point-in-time records.
#
# RULE 1 (#6757) -- the BANNED WORD-EXPANSION BAN. Rules 2 and 3 carry headings in both the
# header and the body; rule 1 did not, so a reader looking for it found it only via the summary
# line above.
#
# WHY: under the sweeper's non-interactive shell, `${VAR:?}` / `${VAR?}` ABORTS with
# status 1 the instant the variable is unset/empty. In the sweep-followthroughs.sh exit
# contract `exit 1 = FAIL = "do NOT close"`, so an unprovisioned secret posts a DAILY
# false-FAIL comment forever instead of exiting 2 (TRANSIENT = quiet retry). The
# compliant form is `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`.
# The ban is documented in followthrough-convention.md §Author workflow; this guard is
# its mechanical enforcer. It is the EXECUTABLE FORM of that doc's canonical census.
#
# Detection = the canonical census, byte-faithful:
#   grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?'  (optional colon, then literal `?`)
# then drop FULL-LINE comments (`^[0-9]+:[[:space:]]*#` on the -n output). Any surviving
# line is a violation. The regex is named-var only by design (matches the doc census);
# a positional-param `${1:?}` is uncaught, but every probe secret is a named var.
#
# LINE-NUMBER ORDER IS LOAD-BEARING: run `grep -n` on the RAW file FIRST, then drop
# full-line-comment hits. Piping `grep -v '^#' | grep -n` re-indexes line numbers against
# the comment-stripped stream and mis-cites every offender (ghcr-minter-live's real line 28
# would print as 4). Detection is identical either way; only the diagnostic file:line differs,
# and naming the offender accurately is the whole value of the guard.
#
# RULE 2 (#7946) -- the RETIRED CREDENTIAL NAME BAN. No file under the target dir -- any name,
# any depth, executable line or comment -- may name `SENTRY_AUTH_TOKEN`. That is the
# canonical Sentry env-var name, so a workstation `doppler run -c prd_terraform` binds a
# PERSONAL, human-account-scoped token under it silently (#7797); the followthroughs consume
# `SENTRY_ACTIONS_RO_TOKEN`, an org-level read-only integration (ADR-031), which no Doppler
# config can satisfy by accident. Rule 2 deliberately does NOT apply rule 1's two exemptions:
# it reads `.test.sh` and every other file (an env stub or a fixture is what the next author
# copies) and it does NOT strip comments (a name in a comment is what the next author copies).
# It has its OWN scanned counter (`scanned_rule2`, the file count under the dir) and its own
# floor, so a broken rule-2 walk cannot hide behind rule 1's count -- and vice versa. Same
# exit contract.
#
# RULE 3 (#7490) -- the PROBE REPO-PATH EXISTENCE check. Every assignment-shaped (or
# `source`-shaped) repo-relative path literal in a non-test probe must name an artefact that
# EXISTS in the checkout being tested, resolved from the repo root.
#
# WHY THE REPO ROOT IS THE RESOLUTION BASE: the sweeper runs every probe from there
# (`scheduled-followthrough-sweeper.yml` -> `bash scripts/sweep-followthroughs.sh` -> `env -i
# ... bash <script>`), so that is the directory a repo-relative literal actually resolves
# against at run time. Resolving against TARGET_DIR would be a different, weaker property.
#
# WHY `git ls-files` AND NOT `-e`: a worktree carries untracked files, so `-e` passes locally
# on an untracked artefact and reddens in CI. Tracked-ness removes that whole class. The
# compared value is the tracked file set, which the SAME commit can move -- that is the point:
# a rename that forgets the probe reddens the PR that renamed it. Directories count as
# existing when any tracked file sits under them (a probe may legitimately cite a directory).
#
# THE `# repo-path: runtime` OPT-OUT IS PER LINE, NOT PER FILE. A file-scoped skip would pass
# every row a naive matrix writes while silently exempting a real rot target -- the exact
# failure this rule exists for. It has no live user since #7761 committed that probe's `.after`
# sidecar (2026-09-24); the lint's own suite pins it with a synthetic fixture (R3-M20).
#
# DECLARED BLIND SPOTS (named, not silent): a path built by concatenation across lines or by
# `printf -v`; a path assembled inside `$(cd ... && pwd)`; anything containing `..` (a
# `$HERE/../../apps/...` script-relative literal is NOT normalised and is NOT checked); a
# second path literal on a line that already yielded one; a path whose TOP-LEVEL directory is
# not currently tracked (`plausible()` keys on the tracked top-dir set, so renaming a whole
# top-level directory makes every reference into it silently unplausible rather than missing --
# the one case where this rule degrades toward quiet); and anything in a `*.test.sh`
# (rule 1's exclusion, load-bearing here because `ccla-representative-icla-7922.test.sh`
# assigns a gitignored `node_modules/.bin/tsx` path that exists locally and not in the
# `test-scripts` CI shard). A value that is a regex/glob pattern, a URL, or carries an
# unresolved `$` is ignored by construction.
#
# Rules 1 and 3 share `exit 1` because both mean the same thing to the author: fix the probe.
# Rules 1, 3, 4 and 5 walk the PROBE SET (see "THE PROBE SET" above), not a `*.sh` glob.
# Rule 3 has its OWN counters (`scanned_rule3`, `refs_rule3`, `missing_rule3`) and its OWN two
# floors, so neither rule's floor vouches for another's walk. The two floors are distinct on
# purpose: a broken GLOB and a broken REGEX are different vacuity modes, and the messages say
# which.
#
# Usage:  lint-followthrough-varq-ban.sh [TARGET_DIR]
#   no arg      -> scans <repo-root>/scripts/followthroughs (production run; ≥10-file floor)
#   TARGET_DIR  -> scans that dir verbatim (how the .test.sh points it at a mktemp sandbox)
#
# Exit: 0 = no violations; 1 = one or more violations; 2 = internal error (dir absent, or a
#       production run whose probe count falls below the min-cardinality floor -> broken glob).

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
DEFAULT_DIR="${REPO_ROOT:-.}/scripts/followthroughs"
TARGET_DIR="${1:-$DEFAULT_DIR}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "ERROR: target dir not found: $TARGET_DIR" >&2
  exit 2
fi

# The min-cardinality floor keys on the RESOLVED target dir, not on arg-presence: a caller
# passing the real dir explicitly (lint-followthrough-varq-ban.sh scripts/followthroughs)
# must not silently bypass the vacuity floor; a mktemp sandbox dir never resolves to the
# default, so the floor is skipped there (deepen-plan finding).
resolve() { (cd "$1" 2>/dev/null && pwd -P) || echo "$1"; }
is_production_run="no"
if [[ "$(resolve "$TARGET_DIR")" == "$(resolve "$DEFAULT_DIR")" ]]; then
  is_production_run="yes"
fi

# THE PROBE SET (E2). Rules 1, 3, 4 and 5 walk ONE list: every regular file under the target dir, at
# any depth, that the sweeper could EXECUTE. scripts/sweep-followthroughs.sh runs any path under
# scripts/followthroughs/ that passes `-x` (it never looks at the name), so a `*.sh` glob at the top
# level missed a probe with no extension, a probe in a subdirectory, and a probe that is a script by
# shebang but not by name. A file is a probe when ANY of: its name ends `.sh` (the historical
# set, kept so this is a strict superset of the old glob), it is executable, or it starts `#!`.
# A data file (a `.after` sidecar, a fixture, a `.txt`) is none of those and stays out, so a decoy
# there cannot red rule 5. `*.test.sh` is EXCLUDED from the probe set although the sweeper would run
# one too: MEASURED on the live tree, 2 of the test files carry the comment-association field on an executable line as a
# fixture decoy (rule 5 examines executable lines only; 2 more carry it in a comment alone) and 3 read comments and branch on markers because that is what they test
# (rule 4); including them reds the tree over fixtures, so they stay out (rule 2 still reads them) and
# the count is reported in the summary. Residual: a tracker that names a `*.test.sh` as its probe
# is not covered by rules 1/3/4/5 (listed under COVERAGE in the rule-4 section).
is_probe_file() {  # <path>
  case "$1" in *.sh) return 0 ;; esac   # probe-pred-name
  [[ -x "$1" ]] && return 0   # probe-pred-exec
  [[ "$(head -c 2 -- "$1" 2>/dev/null)" == '#!' ]] && return 0   # probe-pred-shebang
  return 1
}
PROBES=()
n_tests_excluded=0
while IFS= read -r -d '' f; do
  is_probe_file "$f" || continue
  case "$f" in *.test.sh) n_tests_excluded=$((n_tests_excluded + 1)); continue ;; esac   # probe-test-exclude
  PROBES+=("$f")
done < <(find "$TARGET_DIR" -type f -print0 | sort -z)   # probe-walk

violations=0
scanned=0
# RULE 1: the banned `${VAR:?}` / `${VAR?}` word-expansion on an executable line.
for f in ${PROBES[@]+"${PROBES[@]}"}; do
  scanned=$((scanned + 1))
  # grep -n on the RAW file FIRST (correct line numbers), THEN drop full-line comments.
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    lineno="${hit%%:*}"
    echo "$f:$lineno: banned \${VAR:?} / \${VAR?} form on an executable line -- use 'if [[ -z \"\${VAR:-}\" ]]; then echo \"TRANSIENT: ...\" >&2; exit 2; fi'" >&2
    violations=$((violations + 1))
  done < <(grep -nE '\$\{[A-Za-z_][A-Za-z0-9_]*:?\?' "$f" | grep -vE '^[0-9]+:[[:space:]]*#')
done

# RULE 2: the retired credential name in ANY file under the dir, at any depth, comments
# INCLUDED -- one recursive grep, not a `*.sh` glob, so a fixture, a `.md` note or a
# subdirectory cannot carry it past the ban. `-F` because the needle is a literal (a
# superstring such as `MY_SENTRY_AUTH_TOKEN` is caught on purpose: it is the same name with a
# prefix); `-n` on the RAW file so the cited line is the true one. The `# rule2-grep` marker
# is what the suite's M5 row deletes to prove this line is the mechanism.
RETIRED_NAME='SENTRY_AUTH_TOKEN'
scanned_rule2=$(find "$TARGET_DIR" -type f | wc -l)  # rule2-count
rule2_hits=""
rule2_hits=$(grep -rnF -- "$RETIRED_NAME" "$TARGET_DIR" || true)  # rule2-grep
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  # `path:line:text` -- the path is the first field; the line number the second.
  f="${hit%%:*}"; rest="${hit#*:}"; lineno="${rest%%:*}"
  echo "$f:$lineno: rule 2: names the retired credential '$RETIRED_NAME' -- use SENTRY_ACTIONS_RO_TOKEN; the retired name binds a personal token under doppler run -c prd_terraform (see ADR-031, #7946). Comments, fixtures and .test.sh stubs count: they are what gets copied." >&2
  violations=$((violations + 1))
done <<<"$rule2_hits"

# RULE 4: a probe that lets a comment decide its exit code must take that comment's text from
# scripts/lib/trusted-verdict.sh and nowhere else, which is what makes "the lib is the
# chokepoint" a fact rather than an assertion for the routes and markers listed below: a probe
# that reads comments by one of those routes and branches on one of those markers cannot do so
# itself and stay green. (Rule 5 below bans the wrong filter's SPELLING; rule 4 owns the
# obligation.)
#
# WHY THE LIB. `authorAssociation` / `author_association` is computed against the READING
# token's visibility, so under the sweeper's `GITHUB_TOKEN` an org member whose membership is
# PRIVATE renders as CONTRIBUTOR and their verdict or marker is dropped SILENTLY. Measured on
# #6617: the operator posted `RESULT: PASS` on 2026-07-20 and the nightly sweeper reported FAIL
# for two months against an issue whose verdict was already recorded; measured again on #9818
# (the S2 soak tracker), where the same drop turned an activation marker into a daily false
# "elided with no activation on record". Effective repository permission does not depend on
# membership visibility, so the lib resolves that instead.
#
# ANCHORED ON THE OBLIGATION, NOT ON ONE FORBIDDEN SPELLING -- and that distinction was
# MEASURED, not reasoned. The first version of this rule banned the presence of the wrong
# mechanism (`.authorAssociation ==` / `select(... .authorAssociation)`). Two independent
# review lenses observed that the property the lib exists to establish is the ABSENCE of the
# right one, which is not the same claim, and the gap was occupied: at the time this rule was
# written `inngest-zot-client-authz-6500.sh` read `.comments[].body` with NO author filter at
# all -- strictly WORSE than the spelling being banned, and invisible to it. The rule ran
# clean (rc 0) over it while `grep -rn authorAssociation scripts/followthroughs/` found zero
# live filters to ban. A rule green over the exact hole it advertises protection from is worse
# than the documentation alone, because it converts "we wrote this down" into "we gated it".
#
# The obligation: a probe that reads issue COMMENTS and BRANCHES on an anchored verdict or
# marker must route that decision through scripts/lib/trusted-verdict.sh. Both conjuncts are
# load-bearing. Reading comments alone is not a verdict -- `anthropic-admin-key-6297.sh` counts
# bot-authored marker comments (filtered to the bot login, so a user comment cannot move it) and
# `inngest-watchdog-functions-query-6407.sh` greps issue text for a technical failure signature. The
# second one CAN let an unfiltered comment decide a tracker's fate (exit 1 reopens a closed tracker);
# it is not caught here because it branches on no `RESULT:`/`S<n>-` marker, and it is tracked at #10302.
# THE ANCHOR (`VERDICT_BRANCH`) is `RESULT:` OR any `S<n>-<UPPERCASE-WORD>` soak marker. The
# `S<n>-...` spelling is a CONVENTION the anchor encodes (the S2 and S3 soak probes of ADR-276 use it);
# it was a list of four names until round 4, which a new marker family (`S4-GO`) walked past, so it is
# now the whole family. The anchor was widened from `RESULT:` alone in #9818 because a marker probe that read
# `issues/N/comments` directly with NO author filter has no `RESULT:` line and, since it filters on
# nothing, no `author_association` spelling for rule 5 either -- it passed both rules.
# A probe that filters inline on `authorAssociation` also reads comments, branches on a verdict
# and does not call the lib, so it fires here (and, since #9818, on rule 5 as well).
#
# COVERAGE (after the round-4 widening; the single home for this statement, other docs point here).
# COVERED: in every file of the probe set above (any depth, executable or shebang, `*.test.sh`
# excepted), a read of issue comments by any of these spellings: `gh issue view --json` with
# `comments` anywhere in the field list (`--json comments`, `--json body,comments`, `--json=comments`),
# `--comments`, `gh issue view ... -c`, `.comments[]` and `.comments | ...`, the REST routes
# `issues/N/comments` and `issues/N/timeline`, GraphQL `comments(first:`, and `in:comments`
# searches; AND a branch on `RESULT:` or ANY `S<n>-<UPPERCASE-WORD>` marker (`S4-GO`, `S2-ARMED:`,
# not only the four ADR-276 names). NOT COVERED (deferred, tracked at #10302 and #10303):
# comment readers outside scripts/followthroughs/; a `*.test.sh` named as a tracker's probe (outside
# the probe set, see above); other marker families (`watchdog:restart`,
# `Verified:`) and lower-case `S<n>-` spellings (`S2-armed:`); a route or field list built at run
# time (`R=comments; gh api .../issues/$N/$R`); and transitive sources (a probe that sources a helper
# which reads the comments, or reads a file another script wrote). Widening past this flags probes
# that are compliant by other means today, which is why it is deferred.
#
# Three bypasses, all measured against synthetic probes at ship time (#8389 advisor consult),
# all of them shapes a compliant-LOOKING probe reaches for:
#   (a) the REST route was invisible. `gh api "repos/$R/issues/$N/comments" --jq '.[].body'`
#       matched none of the three `gh issue view` spellings, so such a probe was neither a
#       violation NOR counted in scanned_rule4 -- invisible to the rule AND to its own floor.
#       LATENT, not live: measured 2026-09-20, no probe under scripts/followthroughs/ uses
#       the REST comments route today, and the corpus is the same 5 probes before and after
#       this widening. It is the idiom next door rather than an exotic one -- several probes
#       already reach GitHub through `gh api` for other reads -- so the gap is one a future
#       author walks into, which is exactly when a rule that cannot see them is worst.
#   (b) the verdict only had to be EXTRACTED, not matched adjacently. The old regex required
#       PASS/FAIL to sit next to `RESULT:`, so `v=$(grep -oE '^RESULT: [A-Z]+' | awk '{print $2}')`
#       then `[[ $v == PASS ]]` decided a tracker's fate and passed. The obligation is about
#       reading a verdict at all, so the anchor is now `RESULT:` or an `S<n>-` soak marker on an
#       executable line.
#       Over-detection is deliberate and cheap: the remedy is "call the lib", which every
#       legitimate comment-reading probe already does.
# VERDICT_BRANCH quotes the same marker family as the lib's candidate regex (scripts/lib/trusted-verdict.sh,
# `^(RESULT|S[0-9]+-[A-Z][A-Z0-9_-]*):`), kept in step textually. The trailing `:?` is optional and the grep is unanchored, so the
# tail widening (`S3-PR9:`, `S2-EXIT_CENSUS:`) changes no detection here (a prefix of the marker already matched): it is a
# no-op on purpose, pinned by a characterization row and not by a mutant.
# One alternative per spelling; `--json[^|#]*comments` is a SINGLE alternative that also covers
# `--json=comments` (a separate `--json=` alternative would be an equivalent mutant). `[^|#]*` stops
# at a pipe or a comment so a `--json` on one command cannot pair with `comments` in the next.
READS_COMMENTS='--json[^|#]*comments|--comments|gh[[:space:]]+issue[[:space:]]+view[^|#]*[[:space:]]-c([[:space:])]|$)|\.comments(\[\]| *\|)|issues/[^[:space:]"]*/(comments|timeline)|comments\(first:|in:comments'
VERDICT_BRANCH='RESULT:|S[0-9]+-[A-Z][A-Z0-9_-]*:?'
# The CALL, never the `source` line. Sourcing the lib and then reading `.comments[].body`
# anyway satisfies a source-anchored pattern while leaving the decision exactly as
# forgeable -- both endpoints pinned, the wire between them unpinned. Measured: the first
# version of this regex also accepted the filename, and the mutation that reverts the
# verdict read to an unfiltered one while LEAVING the source line in place -- which is what
# a real regression looks like -- passed the rule at rc 0.
LIB_CALL='trusted_verdict_(bodies|comments)'

# Counted over the files the rule's own predicate SELECTS, not over `find`. The previous
# counter was `find "$TARGET_DIR" -type f | wc -l` -- byte-identical to rule 2's, so rule 4's
# floor was true exactly when rule 2's was, rule 2's `exit 2` ran first, and rule 4's floor was
# unreachable for every input. It existed only to be mutated by the test that existed to prove
# it. This counts comment-reading probes, so a broken READS_COMMENTS regex drives it to zero
# and trips the floor -- which is the failure this rule's walk can actually have.
scanned_rule4=0
rule4_hits=""
for f in ${PROBES[@]+"${PROBES[@]}"}; do
  # Comment-stripped: a probe's header explains WHY the lib is mandatory, and every one of
  # those sentences quotes the constructs below (cq-assert-anchor-not-bare-token).
  code="$(sed -E 's/^[[:space:]]*#.*$//' "$f")" || { echo "ERROR: rule 4 could not read $f; a probe the rule cannot read must not report clean" >&2; exit 2; }
  # The DENOMINATOR is "consumes issue comments by ANY route" -- a direct read OR the lib --
  # so migrating a probe onto the lib moves it within the corpus instead of out of it. Counting
  # only direct readers would make the floor fall every time the rule succeeds at its job, which
  # is a floor that punishes compliance. (Measured while writing this: the first version counted
  # direct readers, I derived its floor from the PRE-migration tree, and it fired at 2-of-3 on
  # the very run that proved the migration had worked.)
  direct=0; via_lib=0
  grep -qE -- "$READS_COMMENTS" <<<"$code" && direct=1   # rule4-grep
  grep -qE -- "$LIB_CALL" <<<"$code" && via_lib=1
  (( direct == 1 || via_lib == 1 )) || continue
  scanned_rule4=$((scanned_rule4 + 1))                              # rule4-count
  (( direct == 1 )) || continue
  grep -qE -- "$VERDICT_BRANCH" <<<"$code" || continue
  # (c) NO via_lib exemption for a DIRECT reader. The old line was `(( via_lib == 0 )) || continue`,
  # so a single occurrence of the call anywhere in the file exempted it -- a probe could call the
  # lib once and then decide on an unfiltered `.comments[].body`, which is the "both endpoints
  # pinned, the wire between them unpinned" shape this rule's own header says it closed, one level
  # up. R4-M2d pinned only the `source`-line variant of it. A COMPLIANT probe has no raw comment
  # read at all: it takes its bodies from the lib, so `direct == 1` is itself the defect and
  # via_lib cannot excuse it. via_lib keeps its OTHER job untouched -- holding a lib-routed probe
  # inside scanned_rule4 so the floor is not lowered by the rule succeeding.
  rule4_hits="${rule4_hits}${f}"$'\n'
done

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  lineno="$(grep -nE -- "$READS_COMMENTS" "$f" | head -1 | cut -d: -f1)"
  echo "$f:${lineno:-1}: rule 4: reads issue comments AND branches on a RESULT: verdict or an S<n>- soak marker WITHOUT routing the decision through scripts/lib/trusted-verdict.sh. This repo is PUBLIC with issues open, so an unfiltered '.comments[].body' accepts a verdict from ANY authenticated GitHub user -- one HTTP POST of 'RESULT: PASS' closes the tracker (#7448). Source the lib and call trusted_verdict_bodies (verdict text) or trusted_verdict_comments ({t,b} per comment, for markers). Do NOT re-inline an author-association select instead (rule 5): it is computed against the READING token's visibility, so a member with PRIVATE org membership renders as CONTRIBUTOR under GITHUB_TOKEN and their verdict is dropped silently (#6617: two months of nightly FAIL on an already-recorded verdict)." >&2
  violations=$((violations + 1))
done <<<"$rule4_hits"

# RULE 5 (#9818): no probe may mention the comment-author-association field on an EXECUTABLE
# line, in either spelling: REST `author_association` or GraphQL `authorAssociation` (case-
# insensitive, with or without the underscore). It is a SPELLING ban and deliberately says
# nothing about WHY the word is there, because the only legitimate trust decision is the lib's
# (rule 4 owns that obligation): a comment's association is computed against the READING token's
# visibility, so under the sweeper's `GITHUB_TOKEN` a private org member reads as CONTRIBUTOR
# and their marker is dropped (#6617, #8389; measured again on the S2 soak tracker #9818: an
# activation comment dropped, a daily false FAIL). Rule 4 alone stayed green over S2 and S3
# because it keyed on `RESULT:`, which a marker probe never writes.
#   - WHOLE-LINE comments are stripped exactly as rule 4 strips them (`sed -E 's/^[[:space:]]*#.*$//'`),
#     because every probe header explains why the lib is mandatory and quotes the word.
#   - A TRAILING `# why` mention on an executable line therefore DOES fire. That is a documented
#     limitation, not an oversight: a quote-aware strip is more mechanism than a spelling ban earns.
#   - `.test.sh` files are exempt (a fixture legitimately carries the field as a decoy); see THE PROBE SET above.
#   - There is NO per-line opt-out: an escape hatch is what the next author reaches for.
#   - KNOWN RESIDUAL: a runtime-built field name (`K=author_association; .[$K]`) or the hyphen
#     spelling is out of this rule's reach; rule 4 is only a PARTIAL backstop (a literal comments
#     route and a literal `S<n>-` / `RESULT:` marker only).
# Its counter is NOT a bare `find | wc -l` (that is byte-identical to rules 1 and 3, whose
# MIN_PROBES `exit 2` fires first, so its own floor would be unreachable -- the failure rule 4's
# header records). `scanned_rule5` counts the probes whose comment-stripped code the predicate
# actually EXAMINED, and a regex canary runs before the walk so a neutered pattern trips
# something a file count cannot.
RULE5_RE='author_?association'  # rule5-re
{ grep -qiE -- "$RULE5_RE" <<<'.author_association' && grep -qiE -- "$RULE5_RE" <<<'.authorAssociation'; } || { echo "ERROR: rule 5 (author-association ban) regex canary failed -- the pattern no longer matches both '.author_association' and '.authorAssociation'; the rule would report clean over a corpus it cannot see" >&2; exit 2; }  # rule5-canary
scanned_rule5=0
for f in ${PROBES[@]+"${PROBES[@]}"}; do
  code5="$(sed -E 's/^[[:space:]]*#.*$//' "$f")" || { echo "ERROR: rule 5 could not read $f; a probe the rule cannot read must not report clean" >&2; exit 2; }  # rule5-strip
  hits5="$(grep -niE -- "$RULE5_RE" <<<"$code5" || true)"  # rule5-grep
  scanned_rule5=$((scanned_rule5 + 1))  # rule5-count
  while IFS= read -r hit; do
    [[ -z "$hit" ]] && continue
    echo "$f:${hit%%:*}: rule 5: names the comment-author-association field on an executable line. A comment's association is computed against the READING token's visibility, so under the sweeper's GITHUB_TOKEN a member with PRIVATE org membership renders as CONTRIBUTOR and their comment is dropped silently (#6617, #8389, #9818). Decide trust from scripts/lib/trusted-verdict.sh (trusted_verdict_bodies / trusted_verdict_comments), which resolves effective repository permission. There is no per-line opt-out." >&2
    violations=$((violations + 1))  # rule5-loop
  done <<<"$hits5"
done

# RULE 3: repo-relative path literals must name something that exists in the checkout.
# The tracked set is files PLUS every ancestor directory of a tracked file, so a probe that
# legitimately cites a DIRECTORY is not reported as a miss.
#
# The census program is held in a quoted heredoc rather than inlined in `awk '...'`: the
# program's own body carries both `"` and `$`, and nesting it inside a single-quoted shell
# word needs `'"'"'` seams that are a parse hazard in exactly the way this repo's own rules
# warn about. A variable keeps the program readable and the quoting trivially correct.
read -r -d '' RULE3_AWK <<'RULE3_AWK_EOF' || true
function cut_at(rest,   i, c, out) {
  out = ""
  for (i = 1; i <= length(rest); i++) {
    c = substr(rest, i, 1)
    if (c == "\"" || c == "}" || c == " " || c == "\t") break
    out = out c
  }
  return out
}
function plausible(p,   top) {
  if (p == "") return 0
  if (index(p, "/") == 0) return 0
  if (p ~ /\$/) return 0
  if (p ~ /\.\./) return 0
  if (p ~ /[][*?\\()|^]/) return 0
  if (p ~ /:\/\//) return 0
  top = p; sub(/\/.*/, "", top)
  if (index(TOPDIRS, "|" top "|") == 0) return 0
  return 1
}
{
  line = $0
  if (line ~ /^[ \t]*#/) next
  if (line ~ /#[ \t]*repo-path:[ \t]*runtime/) next
  if (line !~ /^[ \t]*(local[ \t]+|export[ \t]+|readonly[ \t]+|declare[ \t]+-[a-zA-Z]+[ \t]+)?[A-Za-z_][A-Za-z0-9_]*=/ && line !~ /^[ \t]*(source|\.)[ \t]/) next
  cand = ""; arm = ""
  if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-\$\{[A-Za-z_][A-Za-z0-9_]*\}\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "braced-default"
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-\$[A-Za-z_][A-Za-z0-9_]*\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "bare-default"
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*:-/)) {
    # Capture the default DIRECTLY. The first version walked backwards to the nearest `-`,
    # which is the `-` of `:-` only when the first path segment is hyphen-free -- so
    # `${OV:-knowledge-base/...}` yielded `base/legal/...`, whose top segment is not a tracked
    # directory, and `plausible()` dropped the whole reference with no diagnostic. That is a
    # silent MISS in the arm's own most likely shape: `knowledge-base/` is this repo's
    # commonest repo-relative prefix. Measured: a seeded probe with one `knowledge-base/` and
    # one `scripts/` absent default reported ONE miss, not two.
    rest = substr(line, RSTART + RLENGTH)
    if (rest ~ /^[A-Za-z0-9_.-]+\//) { cand = cut_at(rest); arm = "literal-default" }
  } else if (match(line, /"\$\{[A-Za-z_][A-Za-z0-9_]*\}\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "braced"
  } else if (match(line, /"\$[A-Za-z_][A-Za-z0-9_]*\//)) {
    cand = cut_at(substr(line, RSTART + RLENGTH)); arm = "bare"
  } else if (match(line, /"[A-Za-z0-9_.-]+\//)) {
    cand = cut_at(substr(line, RSTART + 1)); arm = "literal"
  }
  if (cand != "" && plausible(cand)) printf "%d\t%s\t%s\n", FNR, cand, arm
}
RULE3_AWK_EOF

tracked_list="$( (cd "${REPO_ROOT:-.}" 2>/dev/null && git ls-files 2>/dev/null) || true )"
# The membership set is written to a FILE and grepped as a file operand -- never
# `printf ... | grep -qxF`. Under this script's `set -o pipefail`, `grep -q` closes the pipe on
# its FIRST match, the producer takes SIGPIPE (141), and the pipeline exits non-zero although
# grep matched -- so every tracked path would report as MISSING and the guard would be
# false-RED on a clean tree. The failure is invisible for a small producer and certain for this
# one (~18k lines, and the matches are early). Measured on this very file before the fix: 22
# tracked paths reported missing. Same trap as the `grep -q`-on-a-pipe ban the repo's own work
# rules carry. A file operand also makes it one open per reference instead of an 18k-line
# re-serialisation.
tracked_set_file="$(mktemp -t ft-tracked-set.XXXXXXXX)"
trap 'rm -f "$tracked_set_file"' EXIT
# Files plus every ancestor directory, so a probe citing a DIRECTORY is not a miss.
printf '%s\n' "$tracked_list" \
  | awk -F/ '{print; p=""; for (i=1;i<NF;i++) { p=(p==""?$i:p"/"$i); print p }}' \
  | sort -u > "$tracked_set_file"
TOPDIRS="|$(printf '%s\n' "$tracked_list" | grep / | cut -d/ -f1 | grep -xE '[A-Za-z0-9._-]+' | sort -u | paste -sd'|' -)|"

scanned_rule3=0
refs_rule3=0
missing_rule3=0
for f in ${PROBES[@]+"${PROBES[@]}"}; do
  scanned_rule3=$((scanned_rule3 + 1))
  while IFS=$'\t' read -r lineno cand arm; do
    [[ -z "${cand:-}" ]] && continue
    refs_rule3=$((refs_rule3 + 1))
    if ! grep -qxF -- "$cand" "$tracked_set_file"; then
      echo "$f:$lineno: rule 3: MISSING $f -> $cand [$arm] -- not tracked in this checkout; the sweeper runs probes from the repo root, so this literal resolves to nothing. Repoint it, or annotate THAT LINE with '# repo-path: runtime' if the artefact is written at run time." >&2
      missing_rule3=$((missing_rule3 + 1))   # rule3-missing
      violations=$((violations + 1))
    fi
  done < <(awk -v TOPDIRS="$TOPDIRS" "$RULE3_AWK" "$f")   # rule3-census
done

# RULE 6 (#11553) -- the ORDERING BOUND on `/events/` calls. Every executable-line
# `/events/` call in a probe must carry an explicit ordering contract on the same LOGICAL
# line (backslash-continuations folded): `sort=`, or both `start=` AND `end=`. A
# `field=<name>()` function-field select is exempt -- a one-row aggregate has no ordering
# to pin, and `sort` on a field the select does not name risks a 400. `sort` is OPTIONAL
# on this endpoint: absent it, `get_orderby` is None and there is no ORDER BY guarantee --
# "newest-first" is observed behavior, not contract, so a coverage argument leaning on row
# order rests on an undocumented default (CTO ruling on #11543; convention:
# followthrough-convention.md; learning
# 2026-10-29-sentry-events-sort-optional-pin-it-for-coverage-arguments.md).
#
# Detection: per probe, full-line comments are dropped BEFORE folding (a comment cannot
# join a command's tail, and a documented `/events/` call does not fire); physical lines
# ending `\` fold into one logical line so BOTH spellings are one checkable unit -- the
# full-URL literal AND `curl -G --data-urlencode` blocks, where the bound param may sit on
# a different physical line from the endpoint. The violation cites the PHYSICAL line where
# `/events/` matched, not the fold's first line -- the same line-number fidelity rule 1's
# header calls the whole value of the guard. The bound predicate keys on `sort=`,
# `start=`, `end=` and `field=<name>()` with a non-identifier left edge, so `resort=`,
# `append=` or `backend=` cannot satisfy or false-fire it.
#
# DECLARED BLIND SPOTS (named, not silent): an endpoint or its params assembled across
# NON-continuation statements (string concat, `printf -v`, a helper that appends `&sort=`
# later); a runtime-constructed endpoint; a bound passed by variable indirection. Same
# accepted class rule 3 declares. One asymmetry is structural: this lint drops `#` lines
# BEFORE folding, but bash ends a backslash-continuation AT a `#` line -- a comment
# interposed inside a continued command splits it in two while the lint still reads one
# logical line (shellcheck SC2215 catches it; the lint cannot see it).
scanned_rule6=0
rule6_hits=""
for f in ${PROBES[@]+"${PROBES[@]}"}; do
  while IFS=$'\t' read -r lineno logical; do
    [[ -z "$logical" ]] && continue
    case "$logical" in */events/*) ;; *) continue ;; esac   # rule6-scan
    scanned_rule6=$((scanned_rule6 + 1))                   # rule6-count
    grep -qE '(^|[^A-Za-z_])sort=' <<<"$logical" && continue
    grep -qE '(^|[^A-Za-z_])field=[A-Za-z_][A-Za-z0-9_]*\(\)' <<<"$logical" && continue
    { grep -qE '(^|[^A-Za-z_])start=' <<<"$logical" \
      && grep -qE '(^|[^A-Za-z_])end=' <<<"$logical"; } && continue
    rule6_hits="${rule6_hits}${f}:${lineno}"$'\n'
  done < <(awk '
    /^[[:space:]]*#/ { next }
    {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (buf == "") { buf = line } else { buf = buf " " line }
      if (line ~ /\/events\//) { evline = FNR }
      if (line ~ /\\$/) { sub(/\\$/, "", buf); next }
      printf "%d\t%s\n", (evline ? evline : FNR), buf
      buf = ""; evline = 0
    }
    END { if (buf != "") printf "%d\t%s\n", (evline ? evline : NR), buf }
  ' "$f")
done
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  echo "$hit: rule 6: /events/ call carries no ordering bound -- pin sort= or bound the window with start= AND end= on the same logical line. A field=<name>() aggregate select is exempt (ordering is meaningless on a one-row aggregate; pinning sort there risks a 400). sort is OPTIONAL on this endpoint, so no ORDER BY is guaranteed -- a statsPeriod-only read arguing newest-N covers the window rests on an undocumented default (#11553; followthrough-convention.md)." >&2
  violations=$((violations + 1))
done <<<"$rule6_hits"

# Rule 3's TWO floors. MIN_REF_FILES guards the GLOB (files walked); MIN_REFS guards the
# REGEX (references extracted). A neutered regex walks every file and finds nothing, which the
# file floor cannot see -- which is why there are two, with two messages naming which broke.
# REPO_PATHS_MIN_REFS / REPO_PATHS_MIN_REF_FILES are TEST-ONLY overrides (mirroring
# VARQ_BAN_MIN_PROBES); production CI never sets them. Both defaults were DERIVED from one run
# of the committed census above, measured 2026-09-18 on the repointed tree: rule 3 WALKED 74
# non-test probes and EXTRACTED 44 references from 29 of them. The two numbers count different
# things and the floors must too -- `scanned_rule3` is every probe walked (74), not the 29 that
# happen to carry a reference -- so the file floor sits just under the walk and the ref floor
# just under the extraction. Slack is deliberate but small: refs are not one-per-file, and a
# probe that legitimately loses its last path literal should not red the tree.
MIN_REF_FILES="${REPO_PATHS_MIN_REF_FILES:-70}"
MIN_REFS="${REPO_PATHS_MIN_REFS:-40}"
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule3 < MIN_REF_FILES )); then
  echo "ERROR: rule 3 walked only $scanned_rule3 probe file(s) in $TARGET_DIR -- expected at least $MIN_REF_FILES; the GLOB or path is broken" >&2
  exit 2
fi
if [[ "$is_production_run" == "yes" ]] && (( refs_rule3 < MIN_REFS )); then
  echo "ERROR: rule 3 extracted only $refs_rule3 repo-path reference(s) from $scanned_rule3 file(s) -- expected at least $MIN_REFS; the census REGEX is broken (the walk is not: it saw $scanned_rule3 files)" >&2
  exit 2
fi

# Minimum-cardinality floor (production run only): a broken glob yielding 0 files must not
# pass vacuously. Skipped for an explicit sandbox dir (the .test.sh fixtures are few).
# VARQ_BAN_MIN_PROBES is a TEST-ONLY override so the .test.sh can force a floor breach on the
# real tree (set it above the probe count) and prove exit 2 fires; production CI never sets it
# and gets the default 10.
MIN_PROBES="${VARQ_BAN_MIN_PROBES:-10}"
# Rule 4's own floor, on its OWN measure: probes that consume issue comments by any route.
# MEASURED 2026-10-14 with this rule's own READS_COMMENTS and LIB_CALL regexes over the comment-
# stripped probe set: NINE. Four are DIRECT readers (anthropic-admin-key-6297,
# inngest-watchdog-functions-query-6407, run-report-exit-first-contact-8076 and watchdog-arm-soak-9237:
# none branches on a `RESULT:` or `S<n>-` marker, which is why none fires; run-report-exit-first-contact-8076
# joined the count when `in:comments` searches became a covered route) and five route through
# the lib (concierge-strand-754ee124-5733, cpx22-invoice-reconcile-7431, inngest-zot-client-authz-6500
# and the S2 and S3 soak probes). The floor is for VACUITY, not for pinning the corpus: a broken
# READS_COMMENTS regex or walk drives the count to zero and the rule would report clean over a corpus it
# cannot see, so it trips at 3 (well under the measured 9, so retiring a tracker does not red the tree).
# WHICH NUMBERS ARE EXACT. The floors in this file (MIN_PROBES, MIN_REF_FILES, MIN_REFS, this one and
# MIN_RULE5_FILES) are FLOORS by design: the corpus they walk legitimately grows and shrinks, and a
# new probe must not have to edit them. The exact counts by design (ADR-193) are the suites'
# accounting-conservation checks (`passes + fails == cases`) and their row-by-row ratchets, not these.
MIN_COMMENT_READERS="${VARQ_BAN_MIN_COMMENT_READERS:-3}"
if [[ "$is_production_run" == "yes" ]] && (( scanned < MIN_PROBES )); then
  echo "ERROR: only $scanned non-test probe(s) scanned in $TARGET_DIR -- expected the full set; the glob or path is broken" >&2
  exit 2
fi
# Rule 2's own floor, keyed on ITS counter: a rule-2 walk that resolves nothing must not
# report clean over nothing, and rule 1's count must not be what vouches for it.
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule2 < MIN_PROBES )); then
  echo "ERROR: rule 2 (retired-name ban) checked only $scanned_rule2 file(s) in $TARGET_DIR -- its walk resolved nothing; the glob or path is broken" >&2
  exit 2
fi
# Rule 4's own floor, keyed on ITS counter for the same reason: no rule's floor may vouch for
# another's walk.
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule4 < MIN_COMMENT_READERS )); then
  echo "ERROR: rule 4 (trusted-verdict obligation) found only $scanned_rule4 comment-reading probe(s) in $TARGET_DIR -- expected at least $MIN_COMMENT_READERS; the READS_COMMENTS regex or the walk is broken, and the rule is reporting clean over a corpus it cannot see" >&2
  exit 2
fi

# Rule 5's own floor, on ITS counter (probes whose comment-stripped code the predicate examined):
# no rule's floor vouches for another's walk, and the regex canary above guards the pattern itself.
# VARQ_BAN_MIN_RULE5_FILES is a TEST-ONLY override (mirroring VARQ_BAN_MIN_COMMENT_READERS).
# MEASURED 119 probes in the probe set (2026-10-14; unchanged by the any-depth, executable-or-shebang walk, which found no file the old glob missed); floored just
# under it so retiring a tracker does not red the tree (a floor, see "WHICH NUMBERS ARE EXACT" above).
MIN_RULE5_FILES="${VARQ_BAN_MIN_RULE5_FILES:-100}"
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule5 < MIN_RULE5_FILES )); then
  echo "ERROR: rule 5 (author-association ban) examined only $scanned_rule5 probe(s) in $TARGET_DIR -- expected at least $MIN_RULE5_FILES; the walk is broken, and the rule is reporting clean over a corpus it cannot see" >&2
  exit 2
fi

# Rule 6's own floor, on ITS counter (/events/ logical lines examined, exempt included):
# no rule's floor vouches for another's walk. VARQ_BAN_MIN_EVENTS_LINES is a TEST-ONLY
# override (mirroring VARQ_BAN_MIN_RULE5_FILES). MEASURED 14 /events/ logical lines on the
# probe set (2026-10-31); floored well under it so retiring a tracker does not red the
# tree (a floor, see "WHICH NUMBERS ARE EXACT" above).
MIN_EVENTS_LINES="${VARQ_BAN_MIN_EVENTS_LINES:-5}"
if [[ "$is_production_run" == "yes" ]] && (( scanned_rule6 < MIN_EVENTS_LINES )); then
  echo "ERROR: rule 6 (ordering bound) examined only $scanned_rule6 /events/ call(s) in $TARGET_DIR -- expected at least $MIN_EVENTS_LINES; the /events/ needle or the walk is broken, and the rule is reporting clean over a corpus it cannot see" >&2
  exit 2
fi

if (( violations > 0 )); then
  echo "FAILED: $violations violation(s) -- banned \${VAR:?}/\${VAR?} on an executable line (rule 1), the retired credential name (rule 2), a repo-relative path absent from this checkout (rule 3), a comment-verdict or soak-marker read that bypasses scripts/lib/trusted-verdict.sh (rule 4), the comment-author-association field named on an executable line (rule 5), and/or an /events/ call with no ordering bound (rule 6). See followthrough-convention.md §Author workflow." >&2
  exit 1
fi

echo "followthrough-varq-ban: clean ($scanned probe(s) scanned; retired-name rule checked $scanned_rule2 file(s) in $TARGET_DIR; rule 3 walked $scanned_rule3 file(s), extracted $refs_rule3 repo-path ref(s), $missing_rule3 missing; rule 4 (trusted-verdict obligation) checked $scanned_rule4 comment-reading probe(s); rule 5 (author-association ban) examined $scanned_rule5 probe(s); rule 6 (ordering bound) examined $scanned_rule6 /events/ call(s); $n_tests_excluded *.test.sh file(s) outside the probe set)"
exit 0
