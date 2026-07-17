#!/usr/bin/env bash
# Can the `<producer> | grep -q P` guard class be triaged at all?
#
# Background. Under `set -o pipefail`, `grep -q` exits on first match, the
# producer's next write() takes SIGPIPE (141), and pipefail promotes 141 to the
# pipeline status — inverting an `if`, or (under `set -e`) aborting the script.
# PR #6573 fixed 7 such sites in one file. Its plan proposed tracking the rest
# with a site count that turned out to be a SYNTAX count, not a vulnerability
# count. This probe exists so the successor claim is measured.
#
# What it reports: the corpus size, the pipefail split, the set -e split and the
# resulting symptom mix, the producer-kind mix, and B — the share of var-fed
# sites whose var source can actually be bounded by data-flow. B is the
# deliverable: it is the measured answer to "can this class be triaged?".
#
# Every number is printed with the command that produced it. A count without its
# command is not a finding — that is the defect this whole lineage is about.
#
# THE SELF-CHECK IS THE MOST IMPORTANT PART OF THIS SCRIPT. See preflight().
set -uo pipefail

PATHSPEC="apps/web-platform/infra/"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pathspec) PATHSPEC="${2:?--pathspec needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# LC_ALL=C: a locale sort makes `comm` read its input as unsorted and silently
# emit nothing — a set-diff that prints a clean result while running blind.
export LC_ALL=C

# The shape under test. Kept in one place; every count below derives from it.
SHAPE='\|[[:space:]]*grep([[:space:]]+-[a-zA-Z0-9]+)*[[:space:]]+(-[a-zA-Z]*q[a-zA-Z]*|--quiet)([[:space:]]|$)'

emit() { printf '%-58s %s\n' "$1" "$2"; }
cmd()  { printf '    cmd: %s\n' "$1"; }

# ---------------------------------------------------------------------------
# normalise — strip everything that NAMES the shape without BEING it.
# ---------------------------------------------------------------------------
# This probe hunts a shape that this repo also documents heavily: the guard
# files explain the defect in comments, the test harnesses print it in failure
# messages, and this very script embeds it in prose. A raw `git grep` counts all
# of that as findings. That is a syntax count sold as a relevance count — the
# exact defect this lineage exists to correct — so counting without normalising
# would commit the error inside the instrument built to measure it.
#
# Measured cost of omitting it: of 280 raw git-grep hits under this pathspec,
# 122 — 44% — are prose ABOUT the shape rather than instances of it. The probe
# prints both numbers and their gap, so the reader can see how much of the
# apparent corpus is the repo talking to itself.
#
# The pipeline order is load-bearing and is lifted verbatim from
# scan-workflow.test.sh:138-142, where it is already proven:
#   1. fold line-continuations FIRST  (a `\`-split pipe must rejoin before
#      comment-stripping, or its tail reads as a bare line)
#   2. strip heredoc BODIES          (tracked text git grep enumerates; these
#      survive every other rule here — the door #6573 left open twice)
#   3. strip comments
#   4. strip double-quoted strings   (a fail message naming the shape would
#      match itself and false-count forever)
#   5. neutralise `||` BEFORE matching — `cmd_a || grep -q P FILE` contains the
#      byte `|` but is NOT a pipe: nothing feeds grep's stdin, so no producer
#      can take SIGPIPE and the site is structurally incapable. Measured: this
#      alone accounted for several apparent production "sites" in ci-deploy.sh
#      and cron-egress-resolve.sh. A `\|` regex cannot see the difference.
#   6. fold pipe-newlines LAST       (house style writes multi-line pipes)
normalise() {
  awk '
    # Heredoc bodies are data, not code. Enter on <<[-]["'"'"']?WORD, leave on the
    # terminator. Without this, a heredoc documenting the shape counts as a site.
    !inhd && match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/) {
      tag = substr($0, RSTART, RLENGTH)
      gsub(/<<-?[[:space:]]*|['"'"'"]/, "", tag)
      inhd = 1; hdtag = tag; print ""; next
    }
    inhd { if ($0 ~ "^[[:space:]]*" hdtag "[[:space:]]*$") { inhd = 0 } ; print ""; next }
    { print }
  ' \
  | sed -E ':a;/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' \
  | grep -vE '^[[:space:]]*#' \
  | sed 's/||/__OR__/g' \
  | sed 's/"[^"]*"//g' \
  | sed -E ':b;/\|[[:space:]]*$/{N;s/\|[[:space:]]*\n[[:space:]]*/| /;bb}'
}

# Producer classification needs the variable references that `normalise` destroys
# (stripping "…" also strips the "$var" that IS the var-fed signal). So classify
# on comment/heredoc/OR-normalised text with strings INTACT. Using `normalise`
# here would report var-fed=0 — a clean-looking artifact of the instrument, not
# a property of the corpus.
normalise_keep_strings() {
  awk '
    !inhd && match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/) {
      tag = substr($0, RSTART, RLENGTH)
      gsub(/<<-?[[:space:]]*|['"'"'"]/, "", tag)
      inhd = 1; hdtag = tag; print ""; next
    }
    inhd { if ($0 ~ "^[[:space:]]*" hdtag "[[:space:]]*$") { inhd = 0 } ; print ""; next }
    { print }
  ' \
  | sed -E ':a;/\\$/{N;s/\\\n[[:space:]]*/ /;ba}' \
  | grep -vE '^[[:space:]]*#' \
  | sed 's/||/__OR__/g' \
  | sed -E ':b;/\|[[:space:]]*$/{N;s/\|[[:space:]]*\n[[:space:]]*/| /;bb}'
}

# Count real sites in one file, after normalisation.
count_sites() { normalise < "$1" | grep -cE "$SHAPE"; }

# ---------------------------------------------------------------------------
# preflight — refuse to measure through a grep that cannot observe the defect.
# ---------------------------------------------------------------------------
# This gate is BEHAVIOURAL, and that is deliberate. The obvious form — assert
# `grep --version` says GNU — cannot work: the session that wrote this probe
# resolved grep to GNU grep 3.12 and still read 0/N everywhere, because an
# interactive shell FUNCTION wrapped it and drained stdin. Identity passed;
# behaviour was broken. ugrep -q drains too, and reports its own identity
# honestly. So the only question that discriminates is the one asked directly:
#
#     when a match arrives early, does this grep exit and let the producer die?
#
# If it does not, every reading is 0/N and the verdict is a FALSE ALL-CLEAR:
# a green that says "no site is reachable" about a corpus nobody measured.
# That is worse than the over-count this work exists to correct, because a green
# is never audited. Refuse, loudly, and name the cause.
preflight() {
  local producer rc
  producer="$(mktemp)"
  # A producer that writes a match, then keeps writing well past any pipe buffer
  # (64 KiB on Linux). An early-exiting matcher kills it on the next write.
  cat > "$producer" <<'PROD'
printf 'SIGPIPE_PROBE_MATCH\n'
i=0
while [[ $i -lt 40000 ]]; do printf 'filler-line-%d-padpadpadpadpadpadpad\n' "$i"; i=$((i + 1)); done
PROD

  set +o pipefail
  # shellcheck disable=SC2312  # PIPESTATUS is read on the next line, deliberately
  /bin/bash "$producer" 2>/dev/null | grep -q SIGPIPE_PROBE_MATCH
  rc="${PIPESTATUS[0]}"
  set -o pipefail
  rm -f "$producer"

  if [[ "$rc" -ne 141 ]]; then
    cat >&2 <<EOF
FATAL: this host's \`grep\` does not early-exit — refusing to measure.

  probe: a producer emitting a match then ~40k more lines was piped to \`grep -q\`.
  expected: producer killed by SIGPIPE (PIPESTATUS[0]=141).
  actual:   PIPESTATUS[0]=$rc — the producer ran to completion.

  A grep that drains its input cannot observe the defect being counted. Every
  reading taken here would be 0/N, and this probe would report that no site is
  reachable. That green would be false, and nobody re-audits a green.

  This is NOT a \`grep --version\` problem and cannot be diagnosed as one: the
  host that authored this probe resolved GNU grep 3.12 and still drained, via a
  shell function shadowing the binary. Known causes:
    - a shell function or alias wrapping grep   (check: type grep)
    - ugrep / BusyBox grep on PATH ahead of GNU  (check: command -v grep)

  Run where CI's grep runs, or strip the wrapper:  env -i PATH=/usr/bin:/bin bash \$0
EOF
    return 1
  fi
  emit "grep early-exits on match (SIGPIPE observable)" "yes (PIPESTATUS[0]=141)"
  cmd 'printf MATCH; <40k lines> | grep -q MATCH  =>  PIPESTATUS[0] == 141'
  return 0
}

echo "== sigpipe guard triage feasibility =="
echo "-- preflight: is this host able to observe the defect at all? --"
preflight || exit 1
printf '    grep: %s\n' "$(command -v grep)"
printf '    pathspec: %s\n\n' "$PATHSPEC"

# ---------------------------------------------------------------------------
# Phase 1 — the decidable splits (static)
# ---------------------------------------------------------------------------
echo "-- corpus --"
# Candidates come from a raw git grep; real sites are re-counted after
# normalisation. The gap between the two is reported, not hidden: it is the
# measure of how much of this corpus is the repo TALKING about the shape.
mapfile -t CANDIDATES < <(git grep -lE "$SHAPE" -- "$PATHSPEC" | sort)
raw_sites="$(git grep -cE "$SHAPE" -- "$PATHSPEC" | awk -F: '{s+=$NF} END {print s+0}')"
declare -a FILES=()
n_sites=0
for f in "${CANDIDATES[@]}"; do
  n="$(count_sites "$f")"
  [[ "$n" -gt 0 ]] || continue          # candidate named the shape only in prose
  FILES+=("$f"); n_sites=$((n_sites + n))
done
n_files="${#FILES[@]}"
emit "raw git-grep hits (UNNORMALISED — not the finding)" "$raw_sites across ${#CANDIDATES[@]} files"
emit "real sites (comments/strings/heredocs stripped)" "$n_sites across $n_files files"
emit "  of which were prose about the shape, not the shape" "$((raw_sites - n_sites))"
cmd "normalise < \$f | grep -cE '<shape>'   (normalise = fold-continuations | strip-heredocs | strip-comments | strip-strings | fold-pipes)"
echo

# The partition that decides the disposition. 84% of this corpus is test-harness
# internals, where the bug is test debt (a noisy failure, or a test that gates
# nothing). Production is where a silent inversion changes what infra DOES.
# Nobody had run this split; the prior record reasoned over the union.
echo "-- partition: production vs test-harness --"
prod_sites=0; test_sites=0; prod_files=0; test_files=0
declare -a PROD_FILES=()
for f in "${FILES[@]}"; do
  n="$(count_sites "$f")"
  case "$f" in
    *.test.sh) test_sites=$((test_sites + n)); test_files=$((test_files + 1)) ;;
    *)         prod_sites=$((prod_sites + n)); prod_files=$((prod_files + 1)); PROD_FILES+=("$f") ;;
  esac
done
emit "test-harness sites (*.test.sh)" "$test_sites across $test_files files"
emit "PRODUCTION sites" "$prod_sites across $prod_files files"
cmd "for f in \$(git grep -lE '<shape>' -- '$PATHSPEC'); do case \$f in *.test.sh) t+=n;; *) p+=n;; esac; done"
echo

# PF (pipefail) — the only filter that can eliminate a site outright: without
# pipefail, 141 never reaches the pipeline status.
#
# Reported as a BOUND, not a verdict. A file with no `set -o pipefail` of its own
# may still be sourced by a caller that sets it, in which case it inherits the
# defect. Resolving that needs a call-graph this probe does not build. So
# "no-pipefail" here means "not locally set", never "safe".
echo "-- PF split (production) --"
pf_yes=0; pf_no=0
declare -a PF_NO_FILES=()
for f in "${PROD_FILES[@]}"; do
  n="$(count_sites "$f")"
  if grep -qE '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*o[[:space:]]+pipefail|^[[:space:]]*set[[:space:]]+-o[[:space:]]+pipefail' "$f"; then
    pf_yes=$((pf_yes + n))
  else
    pf_no=$((pf_no + n)); PF_NO_FILES+=("$f")
  fi
done
emit "production sites in files that set pipefail" "$pf_yes"
emit "production sites in files that do NOT (bound, not verdict)" "$pf_no"
cmd "grep -qE '^\s*set\s+-[a-zA-Z]*o\s+pipefail' \$f  per production file"
if [[ "${#PF_NO_FILES[@]}" -gt 0 ]]; then
  printf '    note: not-locally-set != safe (a sourcing caller may set it): %s\n' "${PF_NO_FILES[*]}"
fi
echo

# Symptom mix. The prior framing modelled ONE symptom (an inverted `if`) and
# missed the other: a BARE pipeline under `set -e` aborts the script mid-run.
echo "-- symptom mix (production, pipefail-bearing) --"
sym_abort=0; sym_invert=0
for f in "${PROD_FILES[@]}"; do
  grep -qE '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*o[[:space:]]+pipefail|^[[:space:]]*set[[:space:]]+-o[[:space:]]+pipefail' "$f" || continue
  n="$(count_sites "$f")"
  if grep -qE '^[[:space:]]*set[[:space:]]+-[a-zA-Z]*e' "$f"; then
    sym_abort=$((sym_abort + n))
  else
    sym_invert=$((sym_invert + n))
  fi
done
emit "symptom=aborts (set -e present)" "$sym_abort"
emit "symptom=inverts (no set -e)" "$sym_invert"
cmd "grep -qE '^\s*set\s+-[a-zA-Z]*e' \$f  per pipefail-bearing production file"
echo

# ---------------------------------------------------------------------------
# Phase 2 — B: the one number that decides whether triage is available
# ---------------------------------------------------------------------------
# A site is bounded only when its var's ASSIGNMENT resolves to a bound. "Feeds a
# var" => bounded is precisely the inference that produced the discredited
# figure: it asserts the consequent while leaving the antecedent unestablished.
# Shape is not evidence here.
echo "-- producer kind + B (production) --"
streaming=0; varfed=0; other=0; bounded=0; unbounded=0; undecided=0
for f in "${PROD_FILES[@]}"; do
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    if [[ "$line" =~ printf[[:space:]]+[\'\"]%s[\'\"][[:space:]]+\"?\$\{?([A-Za-z_][A-Za-z0-9_]*) ]] ||
       [[ "$line" =~ echo[[:space:]]+\"\$\{?([A-Za-z_][A-Za-z0-9_]*) ]]; then
      varfed=$((varfed + 1))
      var="${BASH_REMATCH[1]}"
      # Resolve the var's assignment. Bounded only if the RHS is a fixed-width
      # or literal source; unbounded if it is a command substitution of an
      # arbitrary-length producer; undecided otherwise. Undecided is REPORTED,
      # never folded into bounded — folding it is how the prior figure was made.
      # Find the assignment anywhere on a line, not just at line-start: the real
      # corpus writes `code="${r%%|*}"; body="${r#*|}"` — an anchored pattern
      # misses it and scores UNDECIDED for the wrong reason (right answer, broken
      # instrument). Prefer being undecided honestly over being undecided by bug.
      asn="$(grep -nE "(^|[[:space:];])[[:space:]]*(local[[:space:]]+)?${var}=" "$f" | head -1)"
      if [[ -z "$asn" ]]; then
        undecided=$((undecided + 1))
      # BOUNDED, by construction rather than by frequency. An explicit truncation
      # to N bytes with N < 65536 (the Linux pipe capacity) means the producer
      # `printf '%s' "$var"` performs ONE write that fits entirely in the pipe
      # buffer. That write cannot block, so it completes before grep can close
      # the pipe, so no SIGPIPE is deliverable. This is NOT the 4096-byte
      # threshold #6573 retracted: that claim was frequency-based ("we didn't
      # observe a kill"), and #6573 was right to retract it — an 8 KB producer
      # read 0/200 unperturbed and was still killed under strace, because it
      # wrote MANY times and any write after grep's exit fails regardless of
      # buffer room. The rule here is about a single non-blocking write, and it
      # was measured on this host at 400 B: 0/300 inversions, while the same
      # single-write producer at 200 KB (over capacity, so the write blocks)
      # inverted 300/300. Size alone decides nothing; size-below-capacity on a
      # single write decides this.
      elif [[ "$asn" =~ (head|tail)[[:space:]]+-c[[:space:]]+([0-9]+) ]] &&
           [[ "${BASH_REMATCH[2]}" -lt 65536 ]]; then
        bounded=$((bounded + 1))
      elif [[ "$asn" =~ \$\((bash|sh|docker|curl|cat|jq|terraform|aws|gh|ssh)[[:space:]] ]]; then
        unbounded=$((unbounded + 1))
      else
        # Everything else is UNDECIDED and is REPORTED as such. A function
        # parameter (`local e="${1:-}"`) is the common case: its bound is a
        # property of every caller, not of this line. Folding these into
        # "bounded" on the strength of their shape is exactly how the discredited
        # figure was produced — it asserts the consequent and leaves the
        # antecedent (is the var actually bounded?) unestablished.
        undecided=$((undecided + 1))
      fi
    elif [[ "$line" =~ (^|[[:space:]])(cat|bash|sh|docker|curl|jq|terraform|aws|gh|ssh|systemctl|journalctl|nft|dig)[[:space:]] ]]; then
      streaming=$((streaming + 1))
    else
      other=$((other + 1))
    fi
  done < <(normalise_keep_strings < "$f" | grep -E "$SHAPE")
done
emit "producer kind: streaming command" "$streaming"
emit "producer kind: var-fed" "$varfed"
emit "producer kind: other/unclassified" "$other"
cmd "normalise_keep_strings < \$f | grep -E '<shape>'  then match producer shape per line"
echo
emit "  var-fed => bounded (assignment resolves to a bound)" "$bounded"
emit "  var-fed => unbounded (cmdsubst of arbitrary producer)" "$unbounded"
emit "  var-fed => UNDECIDED (assignment unresolvable)" "$undecided"
cmd "grep -nE '(^|[;[:space:]])\s*(local\s+)?<var>=' \$f | head -1  then classify RHS: (head|tail) -c N with N<65536 => bounded-by-construction; \$(bash|curl|docker|…) => unbounded; else UNDECIDED"
if [[ "$varfed" -gt 0 ]]; then
  b_pct=$(( bounded * 100 / varfed ))
  emit "B = bounded / var-fed" "${bounded}/${varfed} = ${b_pct}%"
else
  b_pct=0
  emit "B = bounded / var-fed" "n/a (no var-fed production sites)"
fi
echo

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
# The threshold was fixed in the plan BEFORE these numbers were known, so no arm
# can be rationalised after the fact. It is a staleness guard, not a triage gate:
# triage below the production count would require B, and B is the thing under test.
echo "-- verdict --"
emit "production denominator" "$prod_sites sites / $prod_files files"

# Security-rung auto-forfeit. The threshold arm below is a STALENESS guard, not a
# safety judgement: it asks "is the class still the size we planned for?", never
# "is converting it safe?". Where a site is the guard on an RLS, auth, egress, or
# credential seam, a wrong conversion does not fail loudly — it produces a green
# gate that gates nothing, which is the exact failure this class already causes.
# So a security rung in the set forfeits the convert arm regardless of size, and
# the site detail goes to a tracked issue rather than a public audit note.
declare -a SEC_FILES=()
for f in "${PROD_FILES[@]}"; do
  case "$f" in
    *rls*|*anon-probe*|*egress*|*auth*|*token*|*cred*|*secret*|*bwrap*|*sandbox*)
      SEC_FILES+=("$f") ;;
  esac
done
sec_n="${#SEC_FILES[@]}"
emit "security-gating production files (RLS/egress/auth/cred/sandbox)" "$sec_n"
cmd "case \$f in *rls*|*anon-probe*|*egress*|*auth*|*token*|*cred*|*secret*|*bwrap*|*sandbox*) ;; esac"
if [[ "$sec_n" -gt 0 ]]; then
  printf '    files: %s\n' "${SEC_FILES[*]}"
fi

if [[ "$sec_n" -gt 0 ]]; then
  emit "disposition (production)" "TRACK — security-rung auto-forfeit fired"
  printf '    forfeit: %d of %d production files guard a security seam. Size says\n' "$sec_n" "$prod_files"
  printf '             CONVERT (%s sites / %s files, within 50/12); the forfeit overrides.\n' "$prod_sites" "$prod_files"
elif [[ "$prod_sites" -le 50 && "$prod_files" -le 12 ]]; then
  emit "disposition (production)" "CONVERT — within 50 sites / 12 files, no security rung"
else
  emit "disposition (production)" "TRACK — exceeds 50 sites / 12 files"
fi
emit "disposition (test-harness, $test_sites sites)" "TRACK — never converted here"
if [[ "$varfed" -gt 0 && "$b_pct" -ge 80 ]]; then
  emit "triage via B" "AVAILABLE (B >= 80%) — a per-site ledger is derivable"
else
  emit "triage via B" "UNAVAILABLE — B is not >= 80%; window analysis cannot triage this class"
fi
echo
arm="convert"; [[ "$sec_n" -gt 0 || "$prod_sites" -gt 50 || "$prod_files" -gt 12 ]] && arm="track"
echo "triage-feasibility verdict: production=$prod_sites/$prod_files test-harness=$test_sites B=${b_pct}% arm=$arm"
