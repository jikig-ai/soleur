#!/usr/bin/env bash
# ship-incident-pir-gate.sh — the /ship Phase 5.5 Incident-PIR signal scan (#6813).
#
# Reads a PR/plan haystack on stdin. Exit 0 + prints "INCIDENT-SIGNAL: yes" when
# the text looks like a PRODUCTION-INCIDENT fix (a past-tense outage signal AND a
# production signal); exit 1 (no output) otherwise. The script OWNS the regexes,
# so ship/SKILL.md and the test invoke it directly and drift is impossible —
# replacing the old pattern of scraping the regex literals out of Markdown prose
# (which also carried an `A && B && echo` `set -e` foot-gun the script now avoids
# by owning its own exit semantics).
#
# Why the old regex fired on every `single-user incident` plan (#6813):
#   1. bare `incident` matched the `brand_survival_threshold: single-user incident`
#      frontmatter label present in EVERY such plan;
#   2. no word boundary, so `incident` matched inside `incidental`;
#   3. no hypothetical exclusion, so a `## User-Brand Impact` section describing
#      what breaks *if this lands broken* read as an outage report.
# This gate strips the threshold label + hypothetical framing first, then matches
# only PAST-TENSE / report vocabulary.
set -uo pipefail

# ---------------------------------------------------------------------------
# CORPUS CONSTRUCTION (#7987). Default is stdin, unchanged; `--pr <N>` makes the
# script build its own haystack.
#
# WHY THIS MOVED IN HERE. The corpus was assembled by PROSE in ship/SKILL.md:
# read the PR body, grep a `knowledge-base/project/{plans,specs}/...` path out of
# it, `cat` that file, concatenate. When the body cites no plan the second half is
# the EMPTY STRING, and the gate then reports "no incident signal" having examined
# zero bytes of plan -- a mandatory gate silently PLAN-BLIND -- it still fired on
# outage vocabulary in the PR body itself, but reported a verdict on the body
# alone in output byte-identical to a full scan.
#
# Measured on PR #7987: 19 KB of body containing no `knowledge-base/` path at all,
# verdict "no incident signal". Adding the plan link and re-running the SAME gate
# on the SAME commit returned INCIDENT-SIGNAL: yes. Opposite answers, and nothing
# in the first run said half its input was missing.
#
# The regexes were split out of this same SKILL.md prose for the same reason in
# #6813 ("the script OWNS the regexes, so drift is impossible"). The input was
# left behind. A gate whose INPUT is assembled by prose is exactly as unpinned as
# one whose PATTERNS were: `parse-form-a.awk` and `probe-verb-gate.sh` are split
# out on precisely this argument -- a harness must execute the production runtime,
# not scrape it out of a document.
#
# NOT fail-toward-PIR on a missing plan: most PRs legitimately have no plan, so
# firing there would make the gate noise and get it dismissed -- the #6813 failure
# this gate was rebuilt to escape. The fix is to make the state VISIBLE, not to
# make it loud. Same posture preflight uses for SKIP-NOSANDBOX: its own terminal,
# always emitted, never folded into the silent set.
PIR_PR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      # NOT `${2:?...}`. That is bash's own parameter error: it exits **1** with no
      # stdout, and ship/SKILL.md consumes this gate as `if bash … --pr "$(gh pr
      # view --json number --jq .number)"; then … else "no incident signal"`. So an
      # EMPTY inner `gh` result made a usage error report as a clean ALL-CLEAR --
      # the same vacuity class this gate is being fixed for, one level up, and
      # introduced by this PR's own wiring. rc=2 is the "could not evaluate"
      # terminal the non-numeric branch below already uses.
      PIR_PR="${2-}"
      if [[ -z "$PIR_PR" ]]; then
        echo "ship-incident-pir-gate: --pr needs a PR number (got an empty value)" >&2
        exit 2
      fi
      # Validate HERE, at top level. Inside emit_corpus this `exit 2` would run in
      # the command substitution that captures the corpus, killing only the
      # SUBSHELL: the assignment then fails, the fail-toward-PIR guard fires, and
      # a plain usage error is reported as INCIDENT-SIGNAL + exit 0. Measured --
      # the argument-rejection test caught it.
      if [[ ! "$PIR_PR" =~ ^[0-9]+$ ]]; then
        echo "ship-incident-pir-gate: --pr must be a positive integer, got '$PIR_PR'" >&2
        exit 2
      fi
      shift 2 ;;
    *) echo "ship-incident-pir-gate: unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Strip C0 controls, DEL and U+2028/9 from anything PR-body-derived before it is
# echoed. The plan-path class excludes whitespace but not ESC (0x1b): a body could
# emit ESC[2K / ESC[1A and ERASE the very "I did not read your plan" warning these
# diagnostics exist to add. Same helper and same reasoning as preflight Check 5.
_pir_sanitize() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | LC_ALL=C sed $'s/\xe2\x80\xa8/ /g; s/\xe2\x80\xa9/ /g'; }

emit_corpus() {
  if [[ -z "$PIR_PR" ]]; then cat; return; fi

  local body plan resolved root
  body="$(gh pr view "$PIR_PR" --json title,body --jq '.title + "
" + .body' 2>/dev/null || true)"
  if [[ -z "$body" ]]; then
    # Cannot read the PR at all. FAIL TOWARD THE PIR: unlike a missing plan (a
    # normal state), an unreadable PR means the gate has no input whatsoever, and
    # a gate with no input must not report an all-clear.
    echo "ship-incident-pir-gate: PIR-CORPUS-UNREADABLE — could not read PR #$PIR_PR; failing toward PIR" >&2
    printf 'unreadable pr: production outage
'
    return
  fi
  printf '%s
' "$body"

  # Select the plan from a FENCE-STRIPPED body. The raw body was grepped here,
  # so a plan path quoted inside a fenced usage example SHADOWED the real link
  # (`head -n1` takes the first match) and the gate then scanned the wrong plan
  # while reporting PIR-CORPUS, i.e. fully-scanned. That is the same "a quoted
  # example must not read as a live declaration" reasoning this PR applies to the
  # plan's CONTENTS, never applied to the plan SELECTOR.
  #
  # Indent-tolerant and unbalanced-fence-tolerant: on a stripper failure fall back
  # to the raw body rather than losing the link entirely (fail toward reading the
  # plan, since a missing plan half is the defect this whole change removes).
  local _sel
  _sel="$(printf '%s' "$body" | awk '/^[[:space:]]*```/ { f = !f; next } !f { print }' 2>/dev/null)" || _sel="$body"
  [[ -n "$_sel" ]] || _sel="$body"
  plan="$(printf '%s' "$_sel" | grep -oE 'knowledge-base/project/(plans|specs)/[^[:space:])"`]+\.md' | head -n1 || true)"
  if [[ -z "$plan" ]]; then
    echo "ship-incident-pir-gate: PIR-CORPUS-BODY-ONLY — no knowledge-base/project/{plans,specs}/*.md path in PR #$PIR_PR; scanned the body alone, NOT the plan" >&2 || true
    return 0
  fi

  # Path-traversal guard, same shape preflight Check 10 uses: a PR body is
  # attacker-authored text and this turns any readable `.md` into gate input.
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
  # Resolve against $root FIRST. `$root` is repo-relative and `realpath -e "$plan"`
  # is CWD-relative, so they agreed only when cwd happened to BE the repo root:
  # the same PR, same plan, same commit returned INCIDENT-SIGNAL from the root and
  # a silent no-signal from a subdirectory -- and the operator-facing note blamed
  # the security guard, so a cwd bug read as an attack refusal. `/ship` does not
  # guarantee cwd and SKILL.md invokes this through a deliberately
  # location-independent path. This is the PR own defect statement ("opposite
  # answers, and nothing said half the input was missing") through another door.
  resolved="$(realpath -e "$root/$plan" 2>/dev/null || realpath -e "$plan" 2>/dev/null || true)"
  case "$resolved" in
    "$root"/knowledge-base/project/plans/*|"$root"/knowledge-base/project/specs/*) ;;
    *)
      echo "ship-incident-pir-gate: PIR-CORPUS-BODY-ONLY — cited plan '$(_pir_sanitize "$plan")' does not resolve under $root/knowledge-base/project/{plans,specs}/; refusing to read it" >&2 || true
      return 0 ;;
  esac

  # `|| true` on every diagnostic in this function: each `return` yields the status
  # of its LAST command, so a bare `echo … >&2` makes the corpus builder's exit
  # status depend on whether fd 2 happens to be writable -- and that status is
  # promoted by `pipefail` into the fail-toward-PIR guard below. Measured before
  # the fix: the same PR gave a clean no-signal with fd 2 open and
  # `INCIDENT-SIGNAL: yes` under `2>&-` and `2>/dev/full`. This file's own header
  # documents identifying and fixing exactly that shape for the awk sentinel.
  echo "ship-incident-pir-gate: PIR-CORPUS — PR #$PIR_PR body + plan '$(_pir_sanitize "$plan")'" >&2 || true
  cat "$resolved"
}

# Past-tense / report outage vocabulary. NO bare `incident` (it matches the
# threshold literal and `incidental`); word-boundaried; requires a signal that
# something HAPPENED, since a PIR is owed for an event, not a hypothetical.
# The vocabulary is deliberately in TWO groups. The first is a USER-FACING outage
# ("users could not", "went down"). The second is a DELIVERY outage: nothing the
# user can see is down, but shipping is stopped — releases blocked, production
# pinned N versions behind. That is still a production incident and still owes a
# PIR, and none of the user-facing verbs describe it. **Why:** #7242 — every
# `Web Platform Release` failed for four hours and production sat three releases
# behind, and this gate returned "no incident signal" on the PR that fixed it,
# because the report says "failed at the zot-mirror bridge" and "pinned three
# releases behind" rather than "failed in production". The gate that exists to
# stop an incident shipping without its learning missed a textbook one.
OUTAGE_RE='(incident report|post-?incident|post-?mortem|outage|went down|was down|took down|brought down|stopped working|silently (broke|broken|failing)|regression in prod|users? (could not|were unable to)|shipped broken|ran broken|failed in prod(uction)?|broke prod(uction)?|releases? behind|(releases?|deploys?|deployments?) (was|were) blocked|blocked (every|all) (release|deploy))'
# `prod` is boundary-guarded — this is the SAME substring class the header above
# documents fixing for `incident`/`incidental`, left unfixed one line below it.
# Measured on the PR that found it: bare `prod` matched 14 times in the haystack
# and NOT ONCE as the word `prod` or `production` — every hit was `producer`,
# `produced`, `product`, `reproduced`. Plans are dense with all four ("the session
# that produced these six items", "a producer/consumer pair"), so the production
# conjunct was satisfied by essentially every plan, and the whole gate reduced to
# its outage half. A `post-mortem` reference to a LOCAL test-runner retrospective
# then demanded a PIR for an event that never happened.
#
# NO `\b` — the host grep is ugrep, where `\b` is not a word boundary in ERE and
# silently matches nothing, which would delete the alternative rather than bound
# it. `[^a-zA-Z]` is spelled with both cases explicitly because these greps run
# under `-i`, where a bare `[^a-z]` is implementation-defined.
#
# `prod(uction)?` keeps `production` matching (every positive fixture relies on
# that exact word); the trailing guard is what rejects `produc*`.
#
# `live` is guarded on BOTH sides, and fixing only `prod` would have been the
# same soundness-for-completeness swap this gate keeps re-learning: unguarded,
# `live` matches `lives` on the right ("the parser lives in a real file" is
# ordinary prose here) and `delivery`/`delivered`/`deliverables` on the left.
# Standalone `live` stays a production token — only the substrings are rejected.
PROD_RE='(prod(uction)?([^a-zA-Z]|$)|deployed|([^a-zA-Z]|^)live([^a-zA-Z]|$)|app\.soleur\.ai|tenant-zero|customer)'

# The ONLY discriminator between "a plan citing a closed incident as precedent" and "a plan
# reporting an unreported outage" inside a hypothetical paragraph — the two are otherwise
# textually identical, so this is a whitelist, not a decision procedure. F2 and F10 are the same
# document minus `This already happened —`, with opposite verdicts; that is how thin it is.
#
# HONEST WEIGHT (#7801 review). The EFFECT, not a survey: deleting this rule moves exactly ONE
# plan of the 1878 under knowledge-base/project/plans/ (recursive, incl. archive/) —
# 2026-08-01-release-outcome-email-step-env-refs-plan.md, a genuine incident whose
# paragraph reads "This already happened — the outage began ~2026-07-30". n=1, in the fail-open
# direction, and no cheaper discriminator exists (date, issue-ref and past-tense form all appear
# in the precedent fixture too). `occurred` is the measured winner's own inflection, kept for the
# fail-safe direction and pinned by a fixture. `not hypothetical` was cut: it had a corpus hit but
# no fixture and no verdict effect.
# THE BAR, stated so the two survive it honestly: a measured winner needs a corpus hit AND a
# fixture; an INFLECTION of one needs only a fixture. `already occurred` has zero corpus hits and
# zero verdict movers — it is kept solely because losing an inflection of the measured winner fails
# OPEN on a safety gate, and it is pinned by actuality-occurred-inflection.md rather than asserted.
# Anything that is not an inflection needs the full bar. **Why:** #7801 R3.
ACTUALITY_RE='already (happened|occurred)'

# The line-scoped drop set. `network-outage deep-dive` was REMOVED: the sed two stages up deletes
# that token globally, so DROP_RE could never see it — provably dead code, carried forward from the
# grep this replaced.
# Folded into the SAME awk as the paragraph rules (#7801 review): as two
# stages it was incoherent, because the line filter ran AFTER the paragraph strip and so deleted
# lines the ACTUALITY_RE re-admit had deliberately restored. Measured: "The outage already happened
# … and it would break production again." read as NO SIGNAL — one conditional clause silenced a
# stated actuality, contradicting the re-admit's own contract. Lowercased; every match runs against
# tolower($0).
# The sentinel the strip emits on stdout when it suppressed an outage line; the shell converts
# it to the stderr note and removes it from the haystack before either matcher runs.
SENTINEL='__PIR_STRIP_SUPPRESSED__'
DROP_RE='^brand_survival_threshold:|brand-survival threshold:|if this lands broken|if this leaks|if this lands|would break|could break'

# Strip, in order:
#   1. fenced code blocks (``` … ```) — regexes/config/SQL quoted in a plan are
#      DATA, not an incident report (a plan that documents this very gate quotes
#      `OUTAGE_RE='(outage|incident|…)'`). An UNBALANCED fence is NOT treated as a
#      block: the parity toggle would otherwise leave the rest of the document
#      inside a fence that never closes and drop it, at exit 1, with no note —
#      byte-identical to a clean no-signal, and reachable from an odd ``` count
#      in a pasted PR body, which deletes the whole linked plan. Buffered lines
#      are re-emitted at END when the toggle is still open (#7801 review).
#   2. inline `code` spans — same reason, for backticked tokens;
#   3. the threshold declaration (frontmatter key + the bold User-Brand-Impact
#      label) and the hypothetical/conditional framing lines, so trigger 3 does
#      not read a plan's own metadata or its "if this lands broken" section as
#      an incident. The strip is PARAGRAPH-scoped, not line-scoped (#7801): the
#      label line opens a window that runs to the next block boundary, because
#      #6813 removed the framing LINE and left the sentences after it in the
#      same paragraph, so a plan CITING a past closed incident as design
#      precedent still read as an outage report. Three boundaries close the
#      window — a blank line, a heading, a new list item; tables and
#      blockquotes deliberately do NOT (an accepted residual, named so the
#      omission stays a decision). An actuality idiom (ACTUALITY_RE) re-opens
#      it: once a paragraph says the event HAPPENED, the rest of it is a
#      report. The strip is LEXICAL and cannot decide precedent-citation from
#      self-report — a real outage phrased without an actuality idiom inside
#      the paragraph is swallowed, pinned as a characterization fixture rather
#      than left undocumented;
#   4. the `Network-Outage Deep-Dive determination` HEADING (deepen-plan Phase
#      4.5, recorded per `hr-ssh-diagnosis-verify-firewall` so an N/A skip is
#      auditable). This is a plan-TEMPLATE section name, not an outage claim —
#      and since nearly every plan carries some prod word, matching the word
#      `Outage` inside it made the gate fire on any plan that recorded the
#      determination, including ones whose body says the checklist is "not
#      applicable rather than unverified". CLARIFIED #7801 review: this is a
#      GLOBAL token deletion, not a heading-line strip — which is what #6665
#      INTENDED ("gate NAMES are stripped so the token cannot reach OUTAGE_RE at
#      all"), not a defect. Its accepted cost, stated plainly because it was not:
#      a genuine report phrased with the hyphenated gate name ("The
#      network-outage on 2026-08-16 took the production site offline") loses its
#      outage token and does not signal, while the same sentence without the
#      hyphen does. **Why:** #7003, #6665.
# Residual (accepted): a plan whose SUBJECT is incident detection still discusses
# outages in prose and may signal — that is fail-toward-PIR over-production the
# operator hand-adjudicates, not the #6813 false-positive class (which was every
# ordinary `single-user incident` plan tripping on the threshold label alone).
# shellcheck disable=SC2016  # the sed backticks are literal (inline-code strip), no expansion wanted
#      Same class, second instance (#6665): "network-outage" is the NAME of the
#      plan-skill Phase 1.4 gate, and every plan that documents it firing writes
#      the phrase — so the bare `outage` alternative matched a gate name, not an
#      event, on a CI-perf PR with no production incident. Gate NAMES are stripped
#      below (not added to a negative lookahead) so the token cannot reach
#      OUTAGE_RE at all; this is the same shape as the threshold-label strip.
# shellcheck disable=SC2016  # the sed backticks are literal (inline-code strip), no expansion wanted
# The assignment is GUARDED (#7801). A broken strip stage would otherwise empty the haystack, exit
# 1, and read as a clean no-signal — byte-identical to "this PR is fine" on a surface where nothing
# is watching: this gate ships to a customer's own CLI (observability layer 7), where there is no CI
# run to notice an awk that does not accept the program. So a pipeline FAILURE fires.
#
# The guard is the plan's original bare form, and it is correct ONLY because the pipeline now
# terminates in awk. It did not, in the first draft: `grep -v` exits 1 when it selects no lines —
# the ordinary outcome for an empty PR body — so the bare guard reported an incident for a PR with
# no text at all. Merging the line filter into the awk removed the terminal grep and with it that
# whole failure mode, rather than papering over it with an exit-code arm.
if ! haystack="$(emit_corpus \
  | awk 'BEGIN{f=0; n=0} /^[[:space:]]*```/{f=!f; print ""; next}
         !f{print; next}
         {buf[++n]=$0}
         END{ if (f) for (i=1; i<=n; i++) print buf[i] }' \
  | sed 's/`[^`]*`/ /g' \
  | sed -E 's/[Nn]etwork-[Oo]utage/ /g' \
  | awk -v ACTUALITY_RE="$ACTUALITY_RE" -v DROP_RE="$DROP_RE" -v OUTAGE_RE="$OUTAGE_RE" -v SENTINEL="$SENTINEL" 'BEGIN{skip=0; noted=0}
       # --- ORDER (#7801). Exactly ONE of these five orderings is load-bearing, and saying so
       # precisely is the point: the first draft of this comment claimed "ORDER IS THE DESIGN" and
       # named two constraints, one of which measurement then falsified. An overstated contract
       # deters the next person from simplifying, which is a real cost paid for nothing.
       # MEASURED across the 28 fixtures, by permuting each rule and counting verdict movers:
       #   re-admit BELOW skip{next} .... 3 movers  -> LOAD-BEARING (cannot fire inside a window) [M7]
       #   DROP_RE ABOVE the re-admit ... 1 mover   -> LOAD-BEARING (actuality-outranks-...)  [M11]
       #   blank/heading BELOW trigger .. 0 movers  -> free
       #   list ABOVE the trigger ....... 0 movers  -> free (boundaries only SET state and fall
       #                                   through, so the trigger still matches a bulleted label;
       #                                   this ordering DID constrain before the two stages were
       #                                   merged, which is why the claim survived into the draft)
       # Both real constraints are about where the re-admit sits, and both are mutation-pinned
       # rather than asserted here. Tables and blockquotes are NOT boundaries: an accepted
       # residual, named so the omission stays a decision rather than an oversight.
       /^[[:space:]]*$/                                 {skip=0}
       /^[[:space:]]*#+([[:space:]]|$)/                 {skip=0}
       tolower($0) ~ /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)?[*_]*if this (lands|leaks)/ {skip=1; if (!noted && tolower($0) ~ OUTAGE_RE) { noted=1; print SENTINEL } next}
       /^[[:space:]]*([-*+][[:space:]]+|[0-9]+[.)][[:space:]]+)/ {skip=0}
       # An actuality claim OUTRANKS the drop rules below: once a paragraph says the event
       # HAPPENED, the rest of it is a report, and a trailing conditional clause in the same
       # sentence must not silence it.
       tolower($0) ~ ACTUALITY_RE                       {skip=0; print; next}
       # The residual, made OBSERVABLE. The note is emitted as a SENTINEL LINE on stdout, not
       # written to /dev/stderr from inside awk: mawk exits 2 when that write fails (closed fd,
       # /dev/full, no /proc), the guard below reads any non-zero as a broken pipeline, and the
       # verdict then depended on whether fd 2 happened to be writable — on the very surface, a
       # customer CLI, that the guard exists for. Measured before the fix: identical input gave
       # exit 1 with a terminal and INCIDENT-SIGNAL with `2>&-`. The shell re-emits it below.
       # It covers all THREE drop paths, not just the paragraph sink, so a silenced report is
       # never silent about being silenced.
       skip                     { if (!noted && tolower($0) ~ OUTAGE_RE) { noted=1; print SENTINEL } next }
       tolower($0) ~ DROP_RE    { if (!noted && tolower($0) ~ OUTAGE_RE) { noted=1; print SENTINEL } next }
                                                        {print}')"; then
  echo "INCIDENT-SIGNAL: yes"
  echo "ship-incident-pir-gate: strip pipeline failed — failing toward PIR (#7801)" >&2
  exit 0
fi

# Convert the strip sentinel into the operator-facing note and drop it from the haystack. Both
# steps are AFTER the guarded assignment, so neither can influence the verdict: a failed write to
# a closed stderr leaves the verdict untouched, which is the whole reason the note is not emitted
# from inside awk.
if [[ "$haystack" == *"$SENTINEL"* ]]; then
  echo "ship-incident-pir-gate: PIR-STRIP-SUPPRESSED — outage vocabulary inside a hypothetical paragraph was stripped; if this PR fixes a real incident, say so outside that paragraph (#7801)" >&2 || true
  haystack="${haystack//$SENTINEL/}"
fi

# Herestrings (no pipe) — a piped `grep -q` under pipefail can SIGPIPE on an
# early match and invert the result; a herestring cannot.
if grep -qiE "$OUTAGE_RE" <<<"$haystack" && grep -qiE "$PROD_RE" <<<"$haystack"; then
  echo "INCIDENT-SIGNAL: yes"
  exit 0
fi
exit 1
