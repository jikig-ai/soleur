#!/usr/bin/env bash
# Unit + mutation battery for lib/docker-run-tuple.py (Guard 1 of the #10065 plan: sandbox masked-/proc
# suite parity). The helper parses the three docker run tuples that start the web-platform app container
# (canary and prod in ci-deploy.sh, first boot in cloud-init.yml) CLOSED-WORLD: every option, environment
# name, volume and port outside the declared set is a red, a declared volume, env name or port missing from its
# tuple is a red too, and the helper censuses every command-position
# docker run / create so a fourth start site cannot hide.
#
# CONTRACT. Every row mutates ONE COPY of the two real files inside $WORK (never the tree), proves the
# mutation LANDED and stayed inside the tuple it names (a first-match edit that hit the canary block would
# otherwise grade a row about the prod tuple), runs the helper with --root pointing at the copy, and
# requires rc 1 plus every named needle on a `FAIL ` line. A row attributed to the wrong token is a MISS,
# not a kill. Must-PASS rows run the same way and require rc 0 plus the exact ok line with the pinned
# posture digest, so a helper that rejects everything fails them.
#
# HARNESS ROWS. H1: the matrix is re-run against COPIES of the helper whose classification, census-count,
# projection, unclassified-census and declared-member arms are stubbed (a redefinition spliced into the copy, never a seam in the shipped
# helper); the rows that arm owns must then be NOT KILLED, so a battery that stays green against a stubbed
# arm is itself vacuous. H2: passes + fails == rows executed, and the row count is an exact literal beside
# its use, reported by printf + exit 1 (never through ok()/bad()).
#
# Run: bash apps/web-platform/infra/docker-run-tuple.test.sh   (unprivileged, no docker, python3 only).

set -uo pipefail

# A direct invocation does not get run-registered-suites.sh's TMPDIR default; /tmp is a shared RAM-backed tmpfs.
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" || exit 2
HELPER="$SCRIPT_DIR/lib/docker-run-tuple.py"
CI_DEPLOY_REL="apps/web-platform/infra/ci-deploy.sh"
CLOUD_INIT_REL="apps/web-platform/infra/cloud-init.yml"

# The posture digest of the three real tuples (sha256 of the posture projection, first 12 hex). A posture
# change is therefore a visible diff in a second AND third file (test/docker-run-tuple-posture.test.ts pins the same
# literal in the required lane); the helper and the tuples can be edited in one diff, these literals are the
# places that have to move.
EXPECTED_POSTURE="e959fc801d99"

PASS=0
FAIL=0
ROWS=0

die() { printf 'HARNESS ABORT: %s\n' "$*" >&2; exit 2; }

ok()  { PASS=$((PASS + 1)); printf '[ok] %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }

# Instrument self-test: one ok() adds exactly one pass and no fail, one bad() exactly one fail and no pass.
# Runs in a SUBSHELL so the real counters are untouched, and reports through printf + exit 2, never through
# bad(), the very function under suspicion.
instrument_selftest() {
  local got
  got="$( PASS=0; FAIL=0; ok selftest-ok >/dev/null; bad selftest-bad >/dev/null; printf '%s/%s' "$PASS" "$FAIL" )"
  if [ "$got" != "1/1" ]; then
    printf 'INSTRUMENT FAIL - docker-run-tuple.test.sh: ok()/bad() self-test got pass/fail=%s, want 1/1; every verdict below would be meaningless\n' "$got" >&2
    exit 2
  fi
}
instrument_selftest

command -v python3 >/dev/null 2>&1 || die "python3 is required"
command -v awk >/dev/null 2>&1 || die "awk is required"
command -v diff >/dev/null 2>&1 || die "diff is required"

# shellcheck source=apps/web-platform/infra/lib/mutation-scorer.sh
source "$SCRIPT_DIR/lib/mutation-scorer.sh" || die "could not source mutation-scorer.sh"

# Canonical fixture-dir guard, copied byte-for-byte from the repo's hook suites (the fixture-relative
# ratchet recognises only this exact text; an inline `case` is not accepted). `exit 2` is deliberate here:
# an empty or relative state path is a harness defect and must end the shell with a FATAL line, never
# fall through to a write that retargets the cwd or the filesystem root.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

WORK="$(mktemp -d -t docker-run-tuple.XXXXXX)" || die "mktemp -d failed"
assert_fixture_dir "$WORK"
trap 'rm -rf "$WORK"' EXIT

PRISTINE="$WORK/pristine"
assert_fixture_dir "$PRISTINE"
mkdir -p "$PRISTINE/apps/web-platform/infra" || die "mkdir pristine failed"
[ -f "$REPO_ROOT/$CI_DEPLOY_REL" ] || die "missing $CI_DEPLOY_REL"
[ -f "$REPO_ROOT/$CLOUD_INIT_REL" ] || die "missing $CLOUD_INIT_REL"
cp "$REPO_ROOT/$CI_DEPLOY_REL" "$PRISTINE/$CI_DEPLOY_REL" || die "could not copy ci-deploy.sh"
cp "$REPO_ROOT/$CLOUD_INIT_REL" "$PRISTINE/$CLOUD_INIT_REL" || die "could not copy cloud-init.yml"

# ---------------------------------------------------------------------------------------
# THE MUTATORS. awk with the operands passed through ENVIRON (an awk -v value would interpret backslash
# escapes, and every continuation line ends in one). Each op snapshots the file, edits it, and proves two
# things before it is kept: the edit LANDED (diff rc 1) and every hunk sits inside the line range of the
# tuple the row names (the placement assertion). A violation aborts the harness: a row whose mutation
# missed its target would grade a different row.
# ---------------------------------------------------------------------------------------
T=""            # the row's tree (set by build_tree)
LOC_FILE=""; LOC_A=0; LOC_B=0

build_tree() { # <id>
  T="$WORK/rows/$1"
  assert_fixture_dir "$T"
  rm -rf "$T"
  mkdir -p "$T/apps/web-platform/infra" || die "mkdir $T failed"
  cp "$PRISTINE/$CI_DEPLOY_REL" "$T/$CI_DEPLOY_REL" || die "copy into $T failed"
  cp "$PRISTINE/$CLOUD_INIT_REL" "$T/$CLOUD_INIT_REL" || die "copy into $T failed"
}

# locate <tuple>: LOC_FILE/LOC_A/LOC_B = the file and the first/last line of that tuple's docker run, in the
# CURRENT state of the row tree. The name line is matched whole (trimmed), so prod does not match canary.
locate() {
  local want rel out
  case "$1" in
    canary)     rel="$CI_DEPLOY_REL";   want='--name soleur-web-platform-canary \' ;;
    prod)       rel="$CI_DEPLOY_REL";   want='--name soleur-web-platform \' ;;
    first-boot) rel="$CLOUD_INIT_REL";  want='--name soleur-web-platform \' ;;
    *) die "unknown tuple $1" ;;
  esac
  out="$(W="$want" awk '
    { l = $0; sub(/^[ \t]+/, "", l); sub(/^--name=/, "--name ", l) }
    !n && l == ENVIRON["W"] { n = NR; next }
    n && !e { if ($0 !~ /\\[ \t]*$/) { e = NR } }
    END { if (n && e) printf "%d %d\n", n - 1, e }
  ' "$T/$rel")" || die "awk locate failed"
  [ -n "$out" ] || die "could not locate the $1 tuple in $rel"
  LOC_FILE="$T/$rel"
  LOC_A="${out% *}"
  LOC_B="${out#* }"
}

# confined <before> <after> <a> <b>: rc 0 iff the files differ AND every diff hunk's left-side lines lie in
# [a-1, b] for an insert (it reports the line it follows) and [a, b] for a change or delete.
confined() {
  local before="$1" after="$2" a="$3" b="$4" d rc
  d="$WORK/diff.txt"
  diff "$before" "$after" > "$d"; rc=$?
  [ "$rc" -eq 1 ] || return 1
  awk -v a="$a" -v b="$b" '
    /^[0-9]/ {
      split($0, p, /[acd]/); split(p[1], l, ",")
      lo = l[1] + 0; hi = (l[2] != "" ? l[2] + 0 : lo)
      kind = $0; gsub(/[^acd]/, "", kind)
      # an add reports the line it FOLLOWS (so a-1 is in range); a change or delete must sit inside [a, b]
      if (kind == "a") { if (lo < a - 1 || hi > b) bad = 1 } else { if (lo < a || hi > b) bad = 1 }
    }
    END { exit bad }
  ' "$d"
}

# mut_awk <tuple> <awk-body>: run the body over the tuple's file with awk vars a, b.
mut_awk() {
  local tuple="$1" prog="$2" before after
  locate "$tuple"
  before="$WORK/before.txt"; after="$WORK/after.txt"
  cp "$LOC_FILE" "$before" || die "snapshot failed"
  awk -v a="$LOC_A" -v b="$LOC_B" "$prog" "$before" > "$after" || die "mutation program failed ($tuple): its anchor was not found"
  confined "$before" "$after" "$LOC_A" "$LOC_B" || die "mutation on $tuple did not land, or escaped its tuple range [$LOC_A,$LOC_B]"
  cp "$after" "$LOC_FILE" || die "install mutated file failed"
}

m_ins() { # <tuple> <option text>: insert "<indent><text> \" before the image line
  export M1="$2"
  mut_awk "$1" 'NR == b { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) ENVIRON["M1"] " \\" } { print }'
}
m_ins_at() { # <tuple> <needle> <raw text>: insert "<indent><raw>" before the first line containing <needle>
  export M1="$2" M2="$3"
  mut_awk "$1" 'NR >= a && NR <= b && !d && index($0, ENVIRON["M1"]) { match($0, /^[ \t]*/); print substr($0, 1, RLENGTH) ENVIRON["M2"]; d = 1 } { print } END { if (!d) exit 3 }'
}
m_repl() { # <tuple> <needle> <replacement>: first fixed-string occurrence inside the tuple
  export M1="$2" M2="$3"
  mut_awk "$1" 'NR >= a && NR <= b && !d { i = index($0, ENVIRON["M1"]); if (i > 0) { $0 = substr($0, 1, i - 1) ENVIRON["M2"] substr($0, i + length(ENVIRON["M1"])); d = 1 } } { print } END { if (!d) exit 3 }'
}
m_del() { # <tuple> <needle>: delete the first line containing <needle>
  export M1="$2"
  mut_awk "$1" 'NR >= a && NR <= b && !d && index($0, ENVIRON["M1"]) { d = 1; next } { print } END { if (!d) exit 3 }'
}
m_dup() { # <tuple>: append a copy of the whole tuple right after itself
  mut_awk "$1" '{ print } NR >= a && NR <= b { buf[NR] = $0 } NR == b { for (i = a; i <= b; i++) print buf[i] }'
}
m_heredoc() { # <tuple>: wrap the tuple's lines in a quoted heredoc (data, not a command)
  mut_awk "$1" 'NR == a { print "cat <<'"'"'DRT_EOF'"'"'" } { print } NR == b { print "DRT_EOF" }'
}
m_tabs() { # <tuple>: tab-indent every continuation line
  mut_awk "$1" 'NR > a && NR <= b { sub(/^[ \t]+/, "\t") } { print }'
}
m_secopts_last() { # <tuple>: move both --security-opt lines to just before the image line (reordered options)
  mut_awk "$1" '
    NR >= a && NR < b && index($0, "--security-opt") { held[++n] = $0; next }
    NR == b { for (i = 1; i <= n; i++) print held[i] }
    { print }'
}
m_frepl() { # <relfile> <needle> <replacement>: first occurrence anywhere in the file (no tuple range)
  local f="$T/$1" before after
  export M1="$2" M2="$3"
  before="$WORK/before.txt"; after="$WORK/after.txt"
  cp "$f" "$before" || die "snapshot failed"
  awk '!d { i = index($0, ENVIRON["M1"]); if (i > 0) { $0 = substr($0, 1, i - 1) ENVIRON["M2"] substr($0, i + length(ENVIRON["M1"])); d = 1 } } { print } END { if (!d) exit 3 }' "$before" > "$after" \
    || die "m_frepl: anchor not found in $1"
  cmp -s "$before" "$after" && die "m_frepl: no change in $1"
  cp "$after" "$f" || die "install failed"
}
m_append() { # <relfile> <text>: append a statement at the end of an existing file
  [ -f "$T/$1" ] || die "m_append: $1 missing"
  printf '%s\n' "$2" >> "$T/$1" || die "append failed"
}
m_append_lines() { # <relfile> <line>...: append each argument as its own line
  local rel="$1" l
  shift
  [ -f "$T/$rel" ] || die "m_append_lines: $rel missing"
  for l in "$@"; do printf '%s\n' "$l" >> "$T/$rel" || die "append failed"; done
}
m_write() { # <relfile> <text>: create a new file in the tree
  mkdir -p "$(dirname "$T/$1")" || die "mkdir failed"
  printf '%s\n' "$2" > "$T/$1" || die "write failed"
}
m_symlink() { # <relfile> <target>: replace an existing file with a symlink (a scanned file must never be followed)
  [ -f "$T/$1" ] || die "m_symlink: $1 missing"
  rm -f "$T/$1" || die "rm failed"
  ln -s "$2" "$T/$1" || die "ln failed"
}
m_rm() { # <relfile>
  [ -f "$T/$1" ] || die "m_rm: $1 missing"
  rm -f "$T/$1" || die "rm failed"
}

# Self-test of the placement assertion: an edit OUTSIDE the tuple range must be refused, an edit inside
# accepted, a no-op refused. Without this a `confined` that always returns 0 would void every placement claim.
placement_selftest() {
  local f="$WORK/pl.before" g="$WORK/pl.after"
  printf 'a\nb\nc\nd\ne\n' > "$f"
  printf 'a\nb\nX\nd\ne\n' > "$g"
  confined "$f" "$g" 3 3 || { printf 'INSTRUMENT FAIL - confined() refused an in-range edit\n' >&2; exit 2; }
  confined "$f" "$g" 4 5 && { printf 'INSTRUMENT FAIL - confined() accepted an out-of-range edit\n' >&2; exit 2; }
  confined "$f" "$f" 1 5 && { printf 'INSTRUMENT FAIL - confined() accepted a no-op\n' >&2; exit 2; }
  return 0
}
placement_selftest

# Scorer self-test: needles must be matched on FAIL lines only.
scorer_selftest() {
  local l="$WORK/sc.log"
  printf 'noise TOKEN_X here\nFAIL TOKEN_A: alpha in f.sh prod\n' > "$l"
  mutation_scorer_failed_on "$l" '^FAIL ' 'TOKEN_A: alpha' || { printf 'INSTRUMENT FAIL - scorer missed a needle on a FAIL line\n' >&2; exit 2; }
  mutation_scorer_failed_on "$l" '^FAIL ' 'TOKEN_X' && { printf 'INSTRUMENT FAIL - scorer matched a needle on a non-FAIL line\n' >&2; exit 2; }
  return 0
}
# The consumer probe (lib/mutation-scorer-consumers.test.sh) stops at the FIRST scorer call; skipping the self-test
# under it makes that first call the matrix's own (eval_kill), so "reaches the scorer" proves the rows are attributed.
[ -n "${MUTATION_SCORER_PROBE:-}" ] || scorer_selftest

# ---------------------------------------------------------------------------------------
# ROW REGISTRY. A kill row names its mutation (a bash command evaluated in the row's tree) and its needles.
# Needle prefixes: none = must appear on some FAIL line; `!` = must NOT appear on any FAIL line;
# `#` = the exact number of FAIL lines.
# ---------------------------------------------------------------------------------------
KILL_ID=(); KILL_MUT=(); KILL_NEEDLES=()
PASS_ID=(); PASS_MUT=()
US=$'\x1f'

kill_row() { # <id> <mutation command> <needle>...
  local id="$1" mut="$2" n joined=""
  shift 2
  for n in "$@"; do joined="${joined}${n}${US}"; done
  KILL_ID+=("$id"); KILL_MUT+=("$mut"); KILL_NEEDLES+=("$joined")
}
pass_row() { # <id> <mutation command>
  PASS_ID+=("$1"); PASS_MUT+=("$2")
}

# --- Guard 1 matrix rows 1-4: posture-changing options ----------------------------------
kill_row K01-prod-cap-add-space   'm_ins prod "--cap-add NET_ADMIN"'                     'UNKNOWN_OPTION: --cap-add in ci-deploy.sh prod'
kill_row K02-first-boot-cap-add-eq 'm_ins first-boot "--cap-add=SYS_ADMIN"'              'UNKNOWN_OPTION: --cap-add in cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
kill_row K03a-canary-pid-eq       'm_ins canary "--pid=host"'                            'UNKNOWN_OPTION: --pid in ci-deploy.sh canary'
kill_row K03b-canary-pid-space    'm_ins canary "--pid host"'                            'UNKNOWN_OPTION: --pid in ci-deploy.sh canary'
kill_row K04a-prod-systempaths    'm_ins prod "--security-opt systempaths=unconfined"'   'POSTURE_VALUE: --security-opt systempaths=unconfined in ci-deploy.sh prod'
kill_row K04b-prod-systempaths-eq 'm_ins prod "--security-opt=systempaths=unconfined"'   'POSTURE_VALUE: --security-opt systempaths=unconfined in ci-deploy.sh prod'
# --- rows 5, 6, 11: the census (a parser finding fewer or more tuples must not exit 0) -----
kill_row K05-prod-renamed         'm_repl prod "--name soleur-web-platform \\" "--name renamed-web-platform \\"' 'TUPLE_COUNT: want 3 got 2'
kill_row K06-fourth-site-dup      'm_dup canary'                                         'TUPLE_COUNT: want 3 got 4' '#1'
kill_row K06b-fourth-site-shadow  'm_dup canary; m_repl canary "--name soleur-web-platform-canary \\" "--name soleur-web-platform-shadow \\"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K11-heredoc-all          'm_heredoc canary; m_heredoc prod; m_heredoc first-boot' 'TUPLE_COUNT: want 3 got 0'
kill_row K11b-heredoc-one         'm_heredoc prod'                                       'TUPLE_COUNT: want 3 got 2' 'UNCLASSIFIED_DOCKER_RUN'
kill_row K12-comment-mid-tuple    'm_ins_at prod "--security-opt apparmor" "# a comment line ends the bash command here"' 'UNPARSEABLE_OPTION: no image in ci-deploy.sh prod' '!MISSING_DECLARED'
# --- row 7: PATH and loader levers, other environment names ------------------------------
kill_row K07a-canary-env-path     'm_ins canary "-e PATH=/usr/bin:/usr/local/bin"'       'ENV_NAME: PATH in ci-deploy.sh canary'
kill_row K07b-canary-env-ldpre    'm_ins canary "-e LD_PRELOAD=/x"'                      'ENV_NAME: LD_PRELOAD in ci-deploy.sh canary'
kill_row K07c-env-valueless       'm_ins prod "-e FOO"'                                  'ENV_NAME: FOO'
kill_row K07d-env-attached        'm_ins prod "-ePATH=/x"'                               'UNKNOWN_OPTION: -ePATH=/x in ci-deploy.sh prod'
kill_row K07e-env-long-form       'm_ins prod "--env PATH=/x"'                           'ENV_NAME: PATH in ci-deploy.sh prod'
kill_row K07f-node-options-lit    'm_repl canary "-e NODE_OPTIONS=\"\$CANARY_NODE_OPTIONS\"" "-e NODE_OPTIONS=--require=/x"' 'ENV_NAME: NODE_OPTIONS value'
kill_row K07g-first-boot-env-new  'm_ins first-boot "-e SOLEUR_BWRAP_REAL=/x"'           'ENV_NAME: SOLEUR_BWRAP_REAL in cloud-init.yml first-boot'
# --- #10136 Guard 1 (Inngest link chokepoint): the link env, the CA mount, the TLS verification switch ---------------------
# row 1: a literal (https, or the old http) instead of the resolver expansion; first-boot cannot use the expansion
kill_row K07h-canary-literal-https   'm_repl canary "-e INNGEST_BASE_URL=\"\$INNGEST_BASE_URL_RESOLVED\"" "-e INNGEST_BASE_URL=https://10.0.1.40:8443"' 'ENV_NAME: INNGEST_BASE_URL value '"'"'https://10.0.1.40:8443'"'"' in ci-deploy.sh canary' '!prod'
kill_row K07i-prod-literal-old-http  'm_repl prod "-e INNGEST_BASE_URL=\"\$INNGEST_BASE_URL_RESOLVED\"" "-e INNGEST_BASE_URL=http://10.0.1.40:8288"' 'ENV_NAME: INNGEST_BASE_URL value '"'"'http://10.0.1.40:8288'"'"' in ci-deploy.sh prod' '!canary'
kill_row K07j-first-boot-literal-https 'm_repl first-boot "-e INNGEST_BASE_URL=http://10.0.1.40:8288" "-e INNGEST_BASE_URL=https://10.0.1.40:8443"' 'ENV_NAME: INNGEST_BASE_URL value '"'"'https://10.0.1.40:8443'"'"' in cloud-init.yml first-boot'
kill_row K07k-first-boot-resolver-expansion 'm_repl first-boot "-e INNGEST_BASE_URL=http://10.0.1.40:8288" "-e INNGEST_BASE_URL=\$INNGEST_BASE_URL_RESOLVED"' 'UNPARSEABLE_OPTION: -e INNGEST_BASE_URL=$INNGEST_BASE_URL_RESOLVED in cloud-init.yml first-boot'
kill_row K07l-canary-other-expansion 'm_repl canary "-e INNGEST_BASE_URL=\"\$INNGEST_BASE_URL_RESOLVED\"" "-e INNGEST_BASE_URL=\"\$INNGEST_URL\""' 'UNPARSEABLE_OPTION: -e INNGEST_BASE_URL=$INNGEST_URL in ci-deploy.sh canary'
# the unset path: a tuple without the link env or the CA env/volume makes the app fall back to plain http
kill_row K07m-canary-no-link-env     'm_del canary "INNGEST_BASE_URL"'                    'MISSING_REQUIRED: -e INNGEST_BASE_URL is required in every tuple' 'ci-deploy.sh canary' '!prod'
kill_row K07n-first-boot-no-link-env 'm_del first-boot "INNGEST_BASE_URL"'                'MISSING_REQUIRED: -e INNGEST_BASE_URL is required' 'cloud-init.yml first-boot'
kill_row K07o-prod-no-extra-ca-env   'm_del prod "NODE_EXTRA_CA_CERTS"'                   'MISSING_REQUIRED: -e NODE_EXTRA_CA_CERTS is required' 'ci-deploy.sh prod' '!canary'
kill_row K07p-first-boot-no-extra-ca-env 'm_del first-boot "NODE_EXTRA_CA_CERTS"'         'MISSING_REQUIRED: -e NODE_EXTRA_CA_CERTS is required' 'cloud-init.yml first-boot'
kill_row K07q-extra-ca-other-path    'm_repl canary "-e NODE_EXTRA_CA_CERTS=/etc/soleur/inngest-ca.pem" "-e NODE_EXTRA_CA_CERTS=/tmp/evil-ca.pem"' 'ENV_NAME: NODE_EXTRA_CA_CERTS value '"'"'/tmp/evil-ca.pem'"'"' in ci-deploy.sh canary'
# row 6: the CA volume dropped from ONE site, or mounted writable
kill_row K10x-prod-no-ca-volume      'm_del prod "inngest-ca.pem:ro"'                      'MISSING_REQUIRED: -v /mnt/data/inngest-link/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro is required' 'ci-deploy.sh prod' '!canary'
kill_row K10y-canary-no-ca-volume    'm_del canary "inngest-ca.pem:ro"'                    'MISSING_REQUIRED: -v /mnt/data/inngest-link/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro is required' 'ci-deploy.sh canary' '!prod'
kill_row K10z-first-boot-no-ca-volume 'm_del first-boot "inngest-ca.pem:ro"'               'MISSING_REQUIRED: -v /mnt/data/inngest-link/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro is required' 'cloud-init.yml first-boot'
kill_row K10za-ca-volume-writable    'm_repl prod "inngest-ca.pem:ro" "inngest-ca.pem:rw"' 'UNKNOWN_OPTION: -v /mnt/data/inngest-link/inngest-ca.pem:/etc/soleur/inngest-ca.pem:rw in ci-deploy.sh prod' 'MISSING_REQUIRED'
kill_row K10zb-ca-volume-other-source 'm_repl canary "-v /mnt/data/inngest-link/inngest-ca.pem:" "-v /tmp/ca.pem:"' 'UNKNOWN_OPTION: -v /tmp/ca.pem:/etc/soleur/inngest-ca.pem:ro in ci-deploy.sh canary'
kill_row K10zc-ca-volume-old-etc-source 'm_repl prod "-v /mnt/data/inngest-link/inngest-ca.pem:" "-v /etc/soleur/inngest-ca.pem:"' 'UNKNOWN_OPTION: -v /etc/soleur/inngest-ca.pem:/etc/soleur/inngest-ca.pem:ro in ci-deploy.sh prod'
# the TLS verification switch: in a tuple (any spelling of -e) and as non-comment text of either main file
kill_row K07r-canary-reject-unauthorized 'm_ins canary "-e NODE_TLS_REJECT_UNAUTHORIZED=0"' 'ENV_NAME: NODE_TLS_REJECT_UNAUTHORIZED (the TLS verification switch is never allowed) in ci-deploy.sh canary'
kill_row K07s-prod-reject-unauthorized-long 'm_ins prod "--env NODE_TLS_REJECT_UNAUTHORIZED=0"' 'ENV_NAME: NODE_TLS_REJECT_UNAUTHORIZED (the TLS verification switch is never allowed) in ci-deploy.sh prod'
kill_row K07t-first-boot-reject-unauthorized 'm_ins first-boot "-e NODE_TLS_REJECT_UNAUTHORIZED=0"' 'ENV_NAME: NODE_TLS_REJECT_UNAUTHORIZED (the TLS verification switch is never allowed) in cloud-init.yml first-boot'
kill_row K07u-switch-exported-in-script 'm_append "$CI_DEPLOY_REL" "export NODE_TLS_REJECT_UNAUTHORIZED=0"' 'ENV_NAME: NODE_TLS_REJECT_UNAUTHORIZED appears in ci-deploy.sh'
kill_row K07v-switch-in-cloud-init-heredoc 'm_append_lines "$CLOUD_INIT_REL" "cat >> /tmp/x <<'"'"'EOF'"'"'" "NODE_TLS_REJECT_UNAUTHORIZED=0" "EOF"' 'ENV_NAME: NODE_TLS_REJECT_UNAUTHORIZED appears in cloud-init.yml'
# row 3: a fourth site after the compliant three, carrying the old literal (the gate must not stop at the third)
kill_row K06c-fourth-site-old-literal 'm_append "$CI_DEPLOY_REL" "docker run -d --name soleur-web-platform-canary -e INNGEST_BASE_URL=http://10.0.1.40:8288 \"\$VERIFIED_REF\""' 'TUPLE_COUNT: want 3 got 4' 'ENV_NAME: INNGEST_BASE_URL value '"'"'http://10.0.1.40:8288'"'"' in ci-deploy.sh canary'
# row 4: the gate pointed at an empty file finds zero sites and must be RED, never "0 checked, exit 0"
kill_row K06d-empty-ci-deploy       ': > "$T/$CI_DEPLOY_REL"'                              'TUPLE_COUNT: want 3 got 1'
kill_row K06e-empty-both-files      ': > "$T/$CI_DEPLOY_REL"; : > "$T/$CLOUD_INIT_REL"'   'TUPLE_COUNT: want 3 got 0'
# --- row 8: expansions in option position -------------------------------------------------
kill_row K08a-splat               'm_ins prod "\"\${EXTRA_DOCKER_OPTS[@]}\""'            'UNPARSEABLE_OPTION' 'ci-deploy.sh prod'
kill_row K08b-cmdsubst-value      'm_repl prod "--memory \"\$PROD_MEMORY_CAP\"" "--memory \"\$(echo 1g)\""' 'UNPARSEABLE_OPTION'
kill_row K08c-backtick-value      'm_repl canary "--memory \"\$CANARY_MEMORY_CAP\"" "--memory \`echo 1g\`"' 'UNPARSEABLE_OPTION'
kill_row K08d-templatefile-interp 'm_ins first-boot "-e SOLEUR_EGRESS_REAPER=\${reaper}"' 'UNPARSEABLE_OPTION' 'cloud-init.yml first-boot'
kill_row K08e-unbalanced-quote    'm_repl canary "-e SOLEUR_HOST_ID=\"\$HOST_ID\"" "-e SOLEUR_HOST_ID=\"\$HOST_ID"' 'UNPARSEABLE_OPTION' 'ci-deploy.sh canary'
# --- row 9: a tuple missing a posture option -----------------------------------------------
kill_row K09a-first-boot-no-apparmor 'm_del first-boot "--security-opt apparmor"'        'POSTURE_DIVERGENCE' 'cloud-init.yml first-boot'
kill_row K09b-prod-no-seccomp     'm_del prod "--security-opt seccomp"'                  'POSTURE_DIVERGENCE' 'ci-deploy.sh prod'
kill_row K09c-canary-no-tmpfs     'm_del canary "--tmpfs"'                               'POSTURE_DIVERGENCE' 'ci-deploy.sh canary'
# --- row 10: value rewrites and the complement sample ---------------------------------------
kill_row K10a-apparmor-unconfined 'm_repl canary "apparmor=soleur-bwrap" "apparmor=unconfined"' 'POSTURE_VALUE: --security-opt apparmor=unconfined in ci-deploy.sh canary'
kill_row K10b-seccomp-unconfined  'm_repl prod "seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json" "seccomp=unconfined"' 'POSTURE_VALUE: --security-opt seccomp=unconfined in ci-deploy.sh prod'
kill_row K10c-secopt-no-new-privs 'm_ins prod "--security-opt no-new-privileges"'        'POSTURE_VALUE: --security-opt no-new-privileges'
kill_row K10d-tmpfs-proc          'm_ins prod "--tmpfs /proc"'                           'POSTURE_VALUE: --tmpfs /proc'
kill_row K10e-tmpfs-widened       'm_repl prod "size=256m" "size=256m,exec"'             'POSTURE_VALUE: --tmpfs /tmp:rw,nosuid,nodev,size=256m,exec'
kill_row K10f-privileged          'm_ins prod "--privileged"'                            'UNKNOWN_OPTION: --privileged in ci-deploy.sh prod'
kill_row K10g-device              'm_ins prod "--device /dev/mem"'                       'UNKNOWN_OPTION: --device in ci-deploy.sh prod'
kill_row K10h-userns              'm_ins prod "--userns host"'                           'UNKNOWN_OPTION: --userns in ci-deploy.sh prod'
kill_row K10i-ipc                 'm_ins prod "--ipc host"'                              'UNKNOWN_OPTION: --ipc in ci-deploy.sh prod'
kill_row K10j-network             'm_ins first-boot "--network host"'                    'UNKNOWN_OPTION: --network in cloud-init.yml first-boot'
kill_row K10k-read-only           'm_ins canary "--read-only"'                           'UNKNOWN_OPTION: --read-only in ci-deploy.sh canary'
kill_row K10l-sysctl              'm_ins prod "--sysctl net.ipv4.ip_forward=1"'          'UNKNOWN_OPTION: --sysctl in ci-deploy.sh prod'
kill_row K10m-cap-add-all         'm_ins first-boot "--cap-add ALL"'                     'UNKNOWN_OPTION: --cap-add in cloud-init.yml first-boot'
kill_row K10n-user-root           'm_ins prod "-u 0"'                                    'UNKNOWN_OPTION: -u in ci-deploy.sh prod'
kill_row K10o-user-attached       'm_ins prod "-u0"'                                     'UNKNOWN_OPTION: -u0 in ci-deploy.sh prod'
kill_row K10p-combined-short      'm_ins prod "-dit"'                                    'UNKNOWN_OPTION: -dit in ci-deploy.sh prod'
kill_row K10q-volume-attached     'm_ins prod "-v/h:/c"'                                 'UNKNOWN_OPTION: -v/h:/c in ci-deploy.sh prod'
kill_row K10r-volume-root         'm_ins prod "-v /:/host"'                              'UNKNOWN_OPTION: -v /:/host in ci-deploy.sh prod'
kill_row K10s-volume-docker-sock  'm_ins canary "-v /var/run/docker.sock:/var/run/docker.sock"' 'UNKNOWN_OPTION: -v /var/run/docker.sock:/var/run/docker.sock in ci-deploy.sh canary'
kill_row K10t-port-extra          'm_ins prod "-p 0.0.0.0:22:22"'                        'UNKNOWN_OPTION: -p 0.0.0.0:22:22 in ci-deploy.sh prod'
kill_row K10u-env-file-other      'm_repl prod "--env-file \"\$ENV_FILE\"" "--env-file /etc/passwd"' 'POSTURE_VALUE: --env-file /etc/passwd'
kill_row K10v-add-host-other      'm_repl prod "host.docker.internal:host-gateway" "metadata:169.254.169.254"' 'POSTURE_VALUE: --add-host metadata:169.254.169.254'
kill_row K10w-shm-size  'm_ins canary "--shm-size 1g"'                         'UNKNOWN_OPTION: --shm-size in ci-deploy.sh canary'
# --- D3 grammar hardening --------------------------------------------------------------------
kill_row K18a-dup-apparmor        'm_ins prod "--security-opt apparmor=soleur-bwrap"'    'DUPLICATE_OPTION: --security-opt apparmor in ci-deploy.sh prod'
kill_row K18b-dup-seccomp         'm_ins canary "--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json"' 'DUPLICATE_OPTION: --security-opt seccomp in ci-deploy.sh canary'
kill_row K18c-dup-tmpfs           'm_ins first-boot "--tmpfs /tmp:rw,nosuid,nodev,size=256m"' 'DUPLICATE_OPTION: --tmpfs in cloud-init.yml first-boot'
kill_row K19a-trailing-after-image 'm_repl canary "\"\$VERIFIED_REF\"" "\"\$VERIFIED_REF\" --cap-add SYS_ADMIN"' 'TRAILING_ARGS: --cap-add SYS_ADMIN in ci-deploy.sh canary'
kill_row K19b-trailing-command    'm_repl first-boot "\"\$(cat /run/soleur-image-ref)\"" "\"\$(cat /run/soleur-image-ref)\" sh -c id"' 'TRAILING_ARGS: sh -c id in cloud-init.yml first-boot'
kill_row K19d-redirect-after-image 'm_repl canary "\"\$VERIFIED_REF\"" "\"\$VERIFIED_REF\" >/dev/null"' 'TRAILING_ARGS: > /dev/null in ci-deploy.sh canary'
kill_row K19c-image-swapped       'm_repl prod "\"\$VERIFIED_REF\"" "attacker/image:latest"' 'UNPARSEABLE_OPTION: unknown image attacker/image:latest in ci-deploy.sh prod'
# --- the NODE_OPTIONS assignment lines ---------------------------------------------------------
kill_row K17a-node-options-assign 'm_frepl "$CI_DEPLOY_REL" "PROD_NODE_OPTIONS=\"--max-old-space-size=" "PROD_NODE_OPTIONS=\"--require /tmp/x --max-old-space-size="' 'ENV_NAME: NODE_OPTIONS assignment' 'PROD_NODE_OPTIONS'
kill_row K17b-node-options-second 'm_append "$CI_DEPLOY_REL" "CANARY_NODE_OPTIONS=\"\$CANARY_NODE_OPTIONS --inspect\""' 'ENV_NAME: NODE_OPTIONS assignment' 'CANARY_NODE_OPTIONS'
# --- census: verbs, wrappers, spellings, embedded strings ---------------------------------------
kill_row K13a-create-app-name     'm_append "$CI_DEPLOY_REL" "docker create --name soleur-web-platform \"\$VERIFIED_REF\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13b-container-run       'm_append "$CI_DEPLOY_REL" "docker container run -d --name soleur-web-platform \"\$VERIFIED_REF\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13c-global-option       'm_append "$CI_DEPLOY_REL" "docker -H tcp://h:2375 run -d --name soleur-web-platform-x \"\$VERIFIED_REF\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13d-var-docker          'm_append "$CI_DEPLOY_REL" "\"\$DOCKER\" run -d --name soleur-web-platform-x img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13e-sudo-docker         'm_append "$CI_DEPLOY_REL" "sudo docker run --name soleur-web-platform img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13f-unnamed-run         'm_append "$CI_DEPLOY_REL" "docker run -d img"'        'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13g-bash-c-string       'm_append "$CI_DEPLOY_REL" "bash -c '"'"'docker run -d --name soleur-web-platform img'"'"'"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13h-timeout-wrapper     'm_append "$CI_DEPLOY_REL" "timeout 5 docker run -d img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13i-env-assign-prefix   'm_append "$CI_DEPLOY_REL" "DOCKER_HOST=tcp://x:1 docker run -d img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13j-hidden-name         'm_append "$CI_DEPLOY_REL" "docker run -d --name \"\$NAME\" \"\$VERIFIED_REF\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13k-eval-string         'm_append "$CI_DEPLOY_REL" "eval \"docker run -d img\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13l-service-create      'm_append "$CI_DEPLOY_REL" "docker service create --name web img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13m-create-unlisted     'm_append "$CI_DEPLOY_REL" "docker create --name sneaky img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13o-quoted-docker-word  'm_append "$CI_DEPLOY_REL" "\"docker\" run -d img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13p-verb-on-next-line   'm_append_lines "$CI_DEPLOY_REL" "docker \\" "  run -d img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K13n-cloud-init-dup-site 'm_append "$CLOUD_INIT_REL" "    docker run -d --name soleur-web-platform \"\$(cat /run/soleur-image-ref)\""' 'TUPLE_COUNT: want 3 got 4'
# --- census scope beyond the two files ------------------------------------------------------------
kill_row K14a-workflow-start-site 'm_write .github/workflows/x.yml "      - run: docker run -d --name soleur-web-platform \"\$IMG\""' 'UNCLASSIFIED_DOCKER_RUN: .github/workflows/x.yml'
kill_row K14c-workflow-quoted-name 'm_write .github/workflows/y.yml "      - run: docker run -d --name \"soleur-web-platform-canary\" img"' 'UNCLASSIFIED_DOCKER_RUN: .github/workflows/y.yml'
kill_row K14b-infra-script-site   'm_write apps/web-platform/infra/other.sh "docker run -d --name soleur-web-platform \"\$IMG\""' 'UNCLASSIFIED_DOCKER_RUN: apps/web-platform/infra/other.sh'
# --- resource bounds and unreadable inputs ---------------------------------------------------------
kill_row K15-oversize-line        'm_append "$CI_DEPLOY_REL" "docker run -d $(head -c 200000 /dev/zero | tr "\0" "a")"' 'UNPARSEABLE_OPTION: logical line over' 'ci-deploy.sh'
kill_row K16-missing-cloud-init   'm_rm "$CLOUD_INIT_REL"'                               'TUPLE_COUNT: cannot read cloud-init.yml' 'TUPLE_COUNT: want 3 got 2'
kill_row K16b-unterminated-heredoc 'm_append "$CI_DEPLOY_REL" "cat <""<DRT_NEVER_CLOSED"'  'UNPARSEABLE_OPTION: unterminated heredoc DRT_NEVER_CLOSED'
# --- #10065 review: the census must not be hidden by position, by a chained statement, by arithmetic, by a symlink ---
kill_row K20a-chained-after-exempt-create 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$VERIFIED_REF\" >/dev/null; docker run -d --privileged --cap-add SYS_ADMIN --name sneaky img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20b-chained-after-cosign 'm_append "$CI_DEPLOY_REL" "docker run --rm \"\$COSIGN_IMAGE\" x && docker run -d --privileged --name sneaky img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20c-heredoc-arithmetic-shift 'm_append_lines "$CI_DEPLOY_REL" "x=\$(( 1 <""<n ))" "docker run -d --privileged --name sneaky img" "n"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20d-heredoc-quoted-opener 'm_append_lines "$CI_DEPLOY_REL" "echo \"<""<EOF\"" "docker run -d --privileged img" "EOF"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20e-case-label-position 'm_append "$CI_DEPLOY_REL" "case \"\$X\" in start) docker run -d --cap-add ALL img ;; esac"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20f-eval-upper-docker-var 'm_append "$CI_DEPLOY_REL" "eval \"\$DOCKER run -d img\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K20g-exempt-name-privileged 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" --privileged -v /:/h img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'exempt `docker create` of $INNGEST_EXTRACT_CONTAINER carries words beyond'
# --- #10065 review round 2: an exempt site is parsed closed-world, a chained second start needs no privilege flag to be refused,
# --- and a `<<` the lexer cannot decide (single quote, backslash, ${ }, $[ ], $'...') never hides the lines after it
kill_row K21a-chained-bare-after-create 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$VERIFIED_REF\" >/dev/null; docker run -d --name sneaky img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21b-chained-bare-after-cosign 'm_append "$CI_DEPLOY_REL" "docker run --rm \"\$COSIGN_IMAGE\" x && docker run -d img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21c-create-with-volume 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" -v /:/h img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K21d-create-with-user 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" --user root img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K21e-create-with-pid 'm_append "$CI_DEPLOY_REL" "docker create --pid host --name \"\$INNGEST_EXTRACT_CONTAINER\" img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K21f-cosign-cap-add 'm_append "$CI_DEPLOY_REL" "docker run --rm --cap-add SYS_ADMIN \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries the option --cap-add'
kill_row K21g-cosign-host-mount 'm_append "$CI_DEPLOY_REL" "docker run --rm -v /:/h \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'unexpected value for -v'
kill_row K21h-cosign-root-user 'm_append "$CI_DEPLOY_REL" "docker run --rm --user root \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'unexpected value for --user'
kill_row K21i-cosign-other-network 'm_append "$CI_DEPLOY_REL" "docker run --rm --network container:web \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'unexpected value for --network'
kill_row K21j-cosign-image-swapped 'm_append "$CI_DEPLOY_REL" "docker run --rm evil/img \"\$COSIGN_IMAGE\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'starts a different image'
kill_row K21k-heredoc-single-quoted-opener 'm_append_lines "$CI_DEPLOY_REL" "echo '"'"'<""<EOF'"'"'" "docker run -d --privileged img" "EOF"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21l-heredoc-backslash-opener 'm_append_lines "$CI_DEPLOY_REL" "echo \\<""<EOF" "docker run -d --privileged img" "EOF"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21m-heredoc-in-param-expansion 'm_append_lines "$CI_DEPLOY_REL" "x=\${X:-<""<EOF}" "docker run -d --privileged img" "EOF"' 'UNPARSEABLE_OPTION: a heredoc opener inside'
kill_row K21n-heredoc-in-ansi-quote 'm_append_lines "$CI_DEPLOY_REL" "x=\$'"'"'<""<EOF'"'"'" "docker run -d --privileged img" "EOF"' 'UNPARSEABLE_OPTION: a heredoc opener inside'
kill_row K21o-heredoc-in-double-bracket 'm_append_lines "$CI_DEPLOY_REL" "[[ a <""<EOF ]]" "docker run -d --privileged img" "EOF"' 'UNPARSEABLE_OPTION: a heredoc opener inside'
kill_row K21p-wide-scope-symlink 'm_write apps/web-platform/infra/other.sh "echo x"; m_symlink apps/web-platform/infra/other.sh /dev/zero' 'UNPARSEABLE_OPTION: cannot scan apps/web-platform/infra/other.sh' 'not a regular file'
kill_row K21q-setsid-wrapped-docker 'm_append "$CI_DEPLOY_REL" "setsid docker run -d --privileged img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21r-case-paren-label 'm_append "$CI_DEPLOY_REL" "case \"\$X\" in (start) docker run -d --cap-add ALL img ;; esac"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K21s-eval-lower-docker-var 'm_append "$CI_DEPLOY_REL" "eval \"\$docker run -d img\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22a-heredoc-in-multiline-quote 'm_append_lines "$CI_DEPLOY_REL" ": '"'"'" "x <""<ZZ" "'"'"'" "docker run -d --privileged evil/img" ": '"'"'" "ZZ" "'"'"'"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22b-heredoc-in-nested-quote 'm_append_lines "$CI_DEPLOY_REL" ": \"\$(echo \"<""<ZZ\")\"" "docker run -d --privileged evil/img" "ZZ"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22c-wrapper-with-user-arg 'm_append "$CI_DEPLOY_REL" "sudo -u root docker run -d --privileged evil/img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22d-wrapper-flock 'm_append "$CI_DEPLOY_REL" "flock -n /tmp/l docker run -d --privileged evil/img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22e-wrapper-runuser 'm_append "$CI_DEPLOY_REL" "runuser -u root -- docker run -d --privileged evil/img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh'
kill_row K22f-create-other-image 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" evil/img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K22g-create-unlisted-variable-image 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \$EXTRA"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K22h-create-subst-image 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$(printf x)\""' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K23a-exempt-then-indirect 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$VERIFIED_REF\" >/dev/null; xargs docker run -d --privileged img"' 'indirect execution wrapper'
kill_row K23b-exempt-then-app-name 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$VERIFIED_REF\" >/dev/null; x=\"--name soleur-web-platform\""' 'ci-deploy.sh'
kill_row K23c-cosign-privileged 'm_append "$CI_DEPLOY_REL" "docker run --rm --privileged \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries the option --privileged'
kill_row K23d-cosign-env-preload 'm_append "$CI_DEPLOY_REL" "docker run --rm -e LD_PRELOAD=/x \"\$COSIGN_IMAGE\" x"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'unexpected value for -e'
kill_row K23e-create-name-eq-other-image 'm_append "$CI_DEPLOY_REL" "docker create --name=\$INNGEST_EXTRACT_CONTAINER evil/img"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
kill_row K23f-heredoc-in-bracket-arith 'm_append_lines "$CI_DEPLOY_REL" "x=\$[ 1 <""<ZZ ]" "docker run -d --privileged img" "ZZ"' 'UNPARSEABLE_OPTION: a heredoc opener inside'
kill_row K23g-create-dash-image 'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" --privileged"' 'UNCLASSIFIED_DOCKER_RUN: ci-deploy.sh' 'carries words beyond'
# --- a declared member that is MISSING from a tuple: the closed set only refused extras, so the prod start lost the egress-token
# --- mount and nothing noticed. The ! needles prove the line names the right file and tuple, not a sibling.
kill_row K24a-prod-no-workspaces-vol 'm_del prod "-v /mnt/data/workspaces:/workspaces"'   'MISSING_DECLARED: volume /mnt/data/workspaces:/workspaces missing from ci-deploy.sh prod' '!canary' '!cloud-init.yml' '#1'
kill_row K24b-prod-no-plugin-vol     'm_del prod "/app/shared/plugins/soleur:ro"'         'MISSING_DECLARED: volume /mnt/data/plugins/soleur:/app/shared/plugins/soleur:ro missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K24c-prod-no-host-id-env    'm_del prod "-e SOLEUR_HOST_ID"'                     'MISSING_DECLARED: env SOLEUR_HOST_ID missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K24d-prod-no-second-port    'm_del prod "-p 0.0.0.0:3000:3000"'                  'MISSING_DECLARED: port 0.0.0.0:3000:3000 missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K25a-prod-no-token-mount    'm_del prod "-v /var/lib/soleur/egress-tokens"'      'MISSING_DECLARED: volume /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens missing from ci-deploy.sh prod' '!canary' '!cloud-init.yml' '#1'
kill_row K25b-prod-no-reaper-env     'm_del prod "-e SOLEUR_EGRESS_REAPER"'               'MISSING_DECLARED: env SOLEUR_EGRESS_REAPER missing from ci-deploy.sh prod' '!canary' '!cloud-init.yml' '#1'
kill_row K25c-first-boot-no-token-mount 'm_del first-boot "-v /var/lib/soleur/egress-tokens"' 'MISSING_DECLARED: volume /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens missing from cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
# the canary neither mounts the token dir nor reaps (ADR-278 canary isolation): a reaper on the canary would revoke live prod tokens
kill_row K26a-canary-reaper-env      'm_ins canary "-e SOLEUR_EGRESS_REAPER=1"'           'ENV_NAME: SOLEUR_EGRESS_REAPER in ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K26b-canary-token-mount      'm_ins canary "-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens"' 'UNKNOWN_OPTION: -v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens in ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
# --- the arm covers EVERY tuple and EVERY kind, not just the prod rows above: a canary member, a first-boot env/port, two
# --- members gone at once (a version reporting only the first missing member survives a single-deletion row), and a tuple
# --- that already reds UNPARSEABLE_OPTION must not ALSO report every member as missing.
kill_row K27a-canary-no-workspaces-vol 'm_del canary "-v /mnt/data/workspaces:/workspaces"' 'MISSING_DECLARED: volume /mnt/data/workspaces:/workspaces missing from ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K27b-canary-no-port          'm_del canary "-p 0.0.0.0:3001:3000"'                 'MISSING_DECLARED: port 0.0.0.0:3001:3000 missing from ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K27c-canary-no-host-id-env   'm_del canary "-e SOLEUR_HOST_ID"'                   'MISSING_DECLARED: env SOLEUR_HOST_ID missing from ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K27d-first-boot-no-reaper-env 'm_del first-boot "-e SOLEUR_EGRESS_REAPER"'         'MISSING_DECLARED: env SOLEUR_EGRESS_REAPER missing from cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
kill_row K27e-first-boot-no-inngest-env 'm_del first-boot "-e INNGEST_BASE_URL"'            'MISSING_DECLARED: env INNGEST_BASE_URL missing from cloud-init.yml first-boot' 'MISSING_REQUIRED: -e INNGEST_BASE_URL is required in every tuple' '!ci-deploy.sh' '#2'
kill_row K27f-first-boot-no-port      'm_del first-boot "-p 0.0.0.0:3000:3000"'             'MISSING_DECLARED: port 0.0.0.0:3000:3000 missing from cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
kill_row K27g-prod-two-members-gone   'm_del prod "-v /mnt/data/workspaces:/workspaces"; m_del prod "-e SOLEUR_EGRESS_REAPER"' 'MISSING_DECLARED: volume /mnt/data/workspaces:/workspaces missing from ci-deploy.sh prod' 'MISSING_DECLARED: env SOLEUR_EGRESS_REAPER missing from ci-deploy.sh prod' '!canary' '#2'
kill_row K27h-prod-unbalanced-quote   'm_repl prod "-e SOLEUR_HOST_ID=\"\$HOST_ID\"" "-e SOLEUR_HOST_ID=\"\$HOST_ID"' 'UNPARSEABLE_OPTION' 'ci-deploy.sh prod' '!MISSING_DECLARED'
# --- scalar posture flags are REQUIRED too, per tuple (first-boot has no --memory/--memory-swap/--init by design): deleting
# --- --env-file runs prod with zero secrets, --memory leaves it unbounded, --restart leaves it down after a reboot.
kill_row K28a-prod-no-env-file        'm_del prod "--env-file"'                              'MISSING_DECLARED: option --env-file missing from ci-deploy.sh prod' '!canary' '!cloud-init.yml' '#1'
kill_row K28b-prod-no-memory          'm_del prod "--memory \""'                             'MISSING_DECLARED: option --memory missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K28c-canary-no-restart       'm_del canary "--restart"'                             'MISSING_DECLARED: option --restart missing from ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K28d-first-boot-no-env-file  'm_del first-boot "--env-file"'                        'MISSING_DECLARED: option --env-file missing from cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
kill_row K28e-first-boot-no-add-host  'm_del first-boot "--add-host"'                        'MISSING_DECLARED: option --add-host missing from cloud-init.yml first-boot' '!ci-deploy.sh' '#1'
kill_row K28f-prod-no-init            'm_del prod "--init"'                                  'MISSING_DECLARED: option --init missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K28g-prod-not-detached       'm_repl prod "docker run -d" "docker run"'             'MISSING_DECLARED: option -d missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K28h-canary-no-log-driver    'm_del canary "--log-driver"'                          'MISSING_DECLARED: option --log-driver missing from ci-deploy.sh canary' '!prod' '#1'
kill_row K28i-prod-no-memory-swap     'm_del prod "--memory-swap"'                           'MISSING_DECLARED: option --memory-swap missing from ci-deploy.sh prod' '!canary' '#1'
# --- the other half of the scalar matrix: the deploy-start-only options on the CANARY, and prod's own restart/log-driver/add-host
# --- (a spec that quietly dropped --init/--memory/--memory-swap from the canary would otherwise survive every row above).
kill_row K29a-canary-no-init          'm_del canary "--init"'                                'MISSING_DECLARED: option --init missing from ci-deploy.sh canary' '!prod' '!cloud-init.yml' '#1'
kill_row K29b-canary-no-memory        'm_del canary "--memory \""'                           'MISSING_DECLARED: option --memory missing from ci-deploy.sh canary' '!prod' '#1'
kill_row K29c-canary-no-memory-swap   'm_del canary "--memory-swap"'                         'MISSING_DECLARED: option --memory-swap missing from ci-deploy.sh canary' '!prod' '#1'
kill_row K29d-canary-no-env-file      'm_del canary "--env-file"'                            'MISSING_DECLARED: option --env-file missing from ci-deploy.sh canary' '!prod' '#1'
kill_row K29e-prod-no-restart         'm_del prod "--restart"'                               'MISSING_DECLARED: option --restart missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K29f-prod-no-log-driver      'm_del prod "--log-driver"'                            'MISSING_DECLARED: option --log-driver missing from ci-deploy.sh prod' '!canary' '#1'
kill_row K29g-prod-no-add-host        'm_del prod "--add-host"'                              'MISSING_DECLARED: option --add-host missing from ci-deploy.sh prod' '!canary' '#1'
# a rogue option AND a deleted member in one tuple: the MISSING line must not be hidden behind the first violation
kill_row K29h-rogue-option-and-missing 'm_ins prod "--cap-add NET_ADMIN"; m_del prod "--env-file"' 'UNKNOWN_OPTION: --cap-add in ci-deploy.sh prod' 'MISSING_DECLARED: option --env-file missing from ci-deploy.sh prod' '#2'
kill_row K20i-memory-zero-unlimited 'm_repl prod "--memory \"\$PROD_MEMORY_CAP\"" "--memory 0"' 'POSTURE_VALUE: --memory 0 in ci-deploy.sh prod'
kill_row K20h-main-file-symlink   'm_symlink "$CI_DEPLOY_REL" /dev/zero'                 'TUPLE_COUNT: cannot read ci-deploy.sh' 'not a regular file'

# --- must-PASS rows (non-canonical shapes of the SAME posture) ------------------------------------
pass_row P1-reordered-equals      'm_secopts_last prod; m_repl prod "--restart unless-stopped" "--restart=unless-stopped"; m_repl prod "--log-driver journald" "--log-driver=journald"'
pass_row P2-other-memory          'm_repl prod "--memory \"\$PROD_MEMORY_CAP\"" "--memory 3g"'
pass_row P3-comment-block         'm_ins_at prod "docker run" "# a benign comment block"; m_ins_at prod "docker run" "# before the tuple"'
pass_row P4-tab-indented          'm_tabs first-boot'
pass_row P5-equals-spellings      'm_repl canary "--name soleur-web-platform-canary \\" "--name=soleur-web-platform-canary \\"; m_repl canary "--security-opt apparmor=soleur-bwrap" "--security-opt=apparmor=soleur-bwrap"; m_repl canary "--env-file \"\$ENV_FILE\"" "--env-file=\"\$ENV_FILE\""'
pass_row P6-benign-other-sites    'm_write .github/workflows/ok.yml "      - run: docker run --rm httpd:2.4-alpine true"; m_write apps/web-platform/infra/egress-gateway-bootstrap.sh "docker run -d --name \"\$GW_NAME\" img"'
pass_row P7-comments-and-strings  'm_append "$CI_DEPLOY_REL" "# docker run -d --name soleur-web-platform img"; m_append "$CI_DEPLOY_REL" "logger -t x \"FAILED: docker run -d\""; m_append "$CI_DEPLOY_REL" "echo docker create --name sneaky"'
pass_row P8-exempt-create-site    'm_append "$CI_DEPLOY_REL" "docker create --name \"\$INNGEST_EXTRACT_CONTAINER\" \"\$VERIFIED_REF\" >/dev/null"'
pass_row P10-if-then-canary       'm_repl canary "docker run -d" "if docker run -d"; m_repl canary "\"\$VERIFIED_REF\"" "\"\$VERIFIED_REF\"; then"'
pass_row P11-arithmetic-shift-no-docker 'm_append_lines "$CI_DEPLOY_REL" "x=\$(( 1 <<3 ))" "echo done"'
pass_row P12-token-mount-first-env-long 'm_del prod "-v /var/lib/soleur/egress-tokens"; m_ins_at prod "-v /mnt/data/workspaces:/workspaces" "-v /var/lib/soleur/egress-tokens:/var/lib/soleur/egress-tokens \\"; m_repl prod "-e SOLEUR_EGRESS_REAPER=1" "--env SOLEUR_EGRESS_REAPER=1"'
pass_row P13-switch-named-in-comment 'm_append "$CI_DEPLOY_REL" "# NODE_TLS_REJECT_UNAUTHORIZED must stay unset everywhere"; m_append "$CLOUD_INIT_REL" "# NODE_TLS_REJECT_UNAUTHORIZED must stay unset"'
pass_row P9-trailing-comment      'm_repl prod "; then" "; then # trailing note"'

# ---------------------------------------------------------------------------------------
# ROW EVALUATION
# ---------------------------------------------------------------------------------------
ROW_LOG=""
ROW_RC=0
ROW_WHY=""

run_helper() { # <helper> <tree>: sets ROW_LOG and ROW_RC
  ROW_LOG="$WORK/row.log"
  timeout 120 python3 -I "$1" check --root "$2" > "$ROW_LOG" 2>&1; ROW_RC=$?
}

# eval_kill <helper> <idx>: 0 iff the row is KILLED (rc 1 and every needle constraint satisfied)
eval_kill() {
  local helper="$1" i="$2" id mut needles n fails nfail rc=0
  id="${KILL_ID[$i]}"; mut="${KILL_MUT[$i]}"; needles="${KILL_NEEDLES[$i]}"
  build_tree "$id"
  eval "$mut" || die "mutation command failed for row $id"
  run_helper "$helper" "$T"
  ROW_WHY=""
  if [ "$ROW_RC" -ne 1 ]; then ROW_WHY="helper rc=$ROW_RC, want 1"; return 1; fi
  fails="$(grep -a -E '^FAIL ' "$ROW_LOG")" || rc=$?
  if [ "$rc" -gt 1 ]; then die "could not read $ROW_LOG"; fi
  nfail=0
  if [ -n "$fails" ]; then nfail="$(printf '%s\n' "$fails" | wc -l)"; fi
  while [ -n "$needles" ]; do
    n="${needles%%"$US"*}"; needles="${needles#*"$US"}"
    case "$n" in
      '!'*) if [[ "$fails" == *"${n#!}"* ]]; then ROW_WHY="a FAIL line names '${n#!}' (wrong tuple or file)"; return 1; fi ;;
      '#'*) if [ "$nfail" -ne "${n#\#}" ]; then ROW_WHY="want exactly ${n#\#} FAIL line(s), got $nfail"; return 1; fi ;;
      *) mutation_scorer_failed_on "$ROW_LOG" '^FAIL ' "$n" || { ROW_WHY="no FAIL line contains '$n'"; return 1; } ;;
    esac
  done
  return 0
}

# eval_pass <helper> <idx>: 0 iff the helper accepts the mutated tree with the exact ok line
eval_pass() {
  local helper="$1" i="$2" id mut first want
  id="${PASS_ID[$i]}"; mut="${PASS_MUT[$i]}"
  build_tree "$id"
  eval "$mut" || die "mutation command failed for row $id"
  run_helper "$helper" "$T"
  ROW_WHY=""
  want="docker-run-tuple:ok tuples=3 posture=$EXPECTED_POSTURE"
  first="$(head -n 1 "$ROW_LOG")"
  if [ "$ROW_RC" -ne 0 ]; then ROW_WHY="helper rc=$ROW_RC, want 0"; return 1; fi
  if [ "$first" != "$want" ]; then ROW_WHY="first line '$first', want '$want'"; return 1; fi
  return 0
}

show_log() { sed -n '1,8p' "$ROW_LOG" | sed 's/^/    | /'; }

# ---------------------------------------------------------------------------------------
# THE REAL TREE (canonical rows)
# ---------------------------------------------------------------------------------------
real_rc=0
real_out="$(timeout 120 python3 -I "$HELPER" check 2>&1)" || real_rc=$?
ROWS=$((ROWS + 1))
if [ "$real_rc" -eq 0 ] && [ "$real_out" = "docker-run-tuple:ok tuples=3 posture=$EXPECTED_POSTURE" ]; then
  ok "C1 the real tree passes: $real_out"
else
  bad "C1 the real tree does not pass (rc=$real_rc): $real_out"
fi

real_rc=0
real_out="$(timeout 120 python3 -I "$HELPER" check --root "$REPO_ROOT" 2>&1)" || real_rc=$?
ROWS=$((ROWS + 1))
if [ "$real_rc" -eq 0 ] && [ "$real_out" = "docker-run-tuple:ok tuples=3 posture=$EXPECTED_POSTURE" ]; then
  ok "C2 --root pointing at the real repo root gives the same verdict"
else
  bad "C2 --root <repo root> verdict differs (rc=$real_rc): $real_out"
fi

# posture subcommand: the options the suite should start its container with, one per line.
posture_want_prod=$'--init\n--security-opt apparmor=soleur-bwrap\n--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json\n--tmpfs /tmp:rw,nosuid,nodev,size=256m'
posture_want_first=$'--security-opt apparmor=soleur-bwrap\n--security-opt seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json\n--tmpfs /tmp:rw,nosuid,nodev,size=256m'
for t in prod canary first-boot; do
  real_rc=0
  real_out="$(timeout 120 python3 -I "$HELPER" posture --tuple "$t" 2>&1)" || real_rc=$?
  want="$posture_want_prod"
  if [ "$t" = "first-boot" ]; then want="$posture_want_first"; fi
  ROWS=$((ROWS + 1))
  if [ "$real_rc" -eq 0 ] && [ "$real_out" = "$want" ]; then
    ok "C3 posture --tuple $t prints the declared options"
  else
    bad "C3 posture --tuple $t (rc=$real_rc) printed: $real_out"
  fi
done

# posture on a violating tree: rc 1, nothing on stdout (the suite must stop, not start a container from half a parse).
build_tree posture-red
m_ins prod "--cap-add NET_ADMIN"
real_rc=0
real_out="$(timeout 120 python3 -I "$HELPER" posture --tuple prod --root "$T" 2>"$WORK/posture.err")" || real_rc=$?
ROWS=$((ROWS + 1))
if [ "$real_rc" -eq 1 ] && [ -z "$real_out" ] && [[ "$(cat "$WORK/posture.err")" == *"UNKNOWN_OPTION: --cap-add"* ]]; then
  ok "C4 posture on a violating tree exits 1 with an empty stdout and the FAIL line on stderr"
else
  bad "C4 posture on a violating tree: rc=$real_rc stdout='$real_out'"
fi

real_rc=0
real_out="$(timeout 120 python3 -I "$HELPER" posture --tuple bogus 2>&1)" || real_rc=$?
ROWS=$((ROWS + 1))
if [ "$real_rc" -eq 2 ] && [[ "$real_out" == *"invalid choice"* ]]; then
  ok "C5 an unknown --tuple name exits 2 with an argparse invalid-choice message"
else
  bad "C5 an unknown --tuple name exited $real_rc: $real_out"
fi

# ---------------------------------------------------------------------------------------
# THE MATRIX against the real helper
# ---------------------------------------------------------------------------------------
for i in "${!KILL_ID[@]}"; do
  ROWS=$((ROWS + 1))
  if eval_kill "$HELPER" "$i"; then
    ok "${KILL_ID[$i]} killed"
  else
    bad "${KILL_ID[$i]} NOT KILLED: $ROW_WHY"
    show_log
  fi
done
for i in "${!PASS_ID[@]}"; do
  ROWS=$((ROWS + 1))
  if eval_pass "$HELPER" "$i"; then
    ok "${PASS_ID[$i]} accepted"
  else
    bad "${PASS_ID[$i]} REJECTED (a guard that rejects everything fails here): $ROW_WHY"
    show_log
  fi
done

# ---------------------------------------------------------------------------------------
# H1: the same rows against STUBBED copies of the helper. Each stub redefines ONE arm (spliced in before
# the entry point of a copy under $WORK). The rows that arm owns must come back NOT KILLED; a row that is
# still killed means the stub did not take effect or the row is attributed to the wrong arm.
# ---------------------------------------------------------------------------------------
kill_index() { # <row id> -> prints the index
  local j
  for j in "${!KILL_ID[@]}"; do
    if [ "${KILL_ID[$j]}" = "$1" ]; then printf '%s\n' "$j"; return 0; fi
  done
  die "H1 names an unknown row $1"
}

make_stub() { # <stub name> <function name> <python return expr> -> prints the path of the stubbed helper copy
  local name="$1" fn="$2" ret="$3" out="$WORK/stub-$1.py" entry
  cp "$HELPER" "$out" || die "could not copy the helper for stub $name"
  entry="$(grep -c -E '^if __name__ == "__main__":' "$out")" || true
  [ "$entry" = "1" ] || die "helper must carry exactly one 'if __name__ == \"__main__\":' entry line (found $entry)"
  awk -v fn="$fn" -v ret="$ret" '/^if __name__ == "__main__":/ { printf "def %s(*a, **k):\n    return %s\n\n", fn, ret } { print }' "$out" > "$out.new" || die "stub splice failed"
  mv "$out.new" "$out" || die "stub install failed"
  printf '%s\n' "$out"
}

h1_stub() { # <stub name> <function> <return expr> <row id>...
  local name="$1" fn="$2" ret="$3" stub id j
  shift 3
  stub="$(make_stub "$name" "$fn" "$ret")" || die "stub $name failed"
  for id in "$@"; do
    j="$(kill_index "$id")"
    ROWS=$((ROWS + 1))
    if eval_kill "$stub" "$j"; then
      bad "H1[$name] row $id is still KILLED with its arm stubbed out (the stub did not land, or the row is attributed to a different arm)"
      show_log
    else
      ok "H1[$name] row $id NOT KILLED with the $fn arm stubbed (the battery is not vacuous for it)"
    fi
  done
}

h1_stub classify check_options '[]' \
  K01-prod-cap-add-space K02-first-boot-cap-add-eq K03a-canary-pid-eq K03b-canary-pid-space \
  K04a-prod-systempaths K04b-prod-systempaths-eq K07a-canary-env-path K07b-canary-env-ldpre \
  K08a-splat K10a-apparmor-unconfined K10b-seccomp-unconfined K10f-privileged K10r-volume-root K20i-memory-zero-unlimited \
  K26a-canary-reaper-env K26b-canary-token-mount \
  K07h-canary-literal-https K07m-canary-no-link-env K07o-prod-no-extra-ca-env K10x-prod-no-ca-volume K07r-canary-reject-unauthorized
h1_stub declared check_declared '[]' \
  K24a-prod-no-workspaces-vol K24b-prod-no-plugin-vol K24c-prod-no-host-id-env K24d-prod-no-second-port \
  K25a-prod-no-token-mount K25b-prod-no-reaper-env K25c-first-boot-no-token-mount \
  K27a-canary-no-workspaces-vol K27b-canary-no-port K27c-canary-no-host-id-env K27d-first-boot-no-reaper-env \
  K27e-first-boot-no-inngest-env K27f-first-boot-no-port K27g-prod-two-members-gone \
  K28a-prod-no-env-file K28b-prod-no-memory K28c-canary-no-restart K28d-first-boot-no-env-file K28e-first-boot-no-add-host \
  K28f-prod-no-init K28g-prod-not-detached K28h-canary-no-log-driver K28i-prod-no-memory-swap \
  K29a-canary-no-init K29b-canary-no-memory K29c-canary-no-memory-swap K29d-canary-no-env-file \
  K29e-prod-no-restart K29f-prod-no-log-driver K29g-prod-no-add-host
h1_stub census check_count '[]' \
  K05-prod-renamed K06-fourth-site-dup K11-heredoc-all K16-missing-cloud-init K20h-main-file-symlink
h1_stub projection check_projection '[]' \
  K09a-first-boot-no-apparmor K09b-prod-no-seccomp K09c-canary-no-tmpfs
h1_stub unclassified check_census_extra '[]' \
  K13a-create-app-name K13c-global-option K13f-unnamed-run K13g-bash-c-string K14a-workflow-start-site \
  K20a-chained-after-exempt-create K20b-chained-after-cosign K20c-heredoc-arithmetic-shift K20d-heredoc-quoted-opener \
  K20e-case-label-position K20f-eval-upper-docker-var K20g-exempt-name-privileged \
  K21a-chained-bare-after-create K21b-chained-bare-after-cosign K21c-create-with-volume K21d-create-with-user \
  K21e-create-with-pid K21f-cosign-cap-add K21g-cosign-host-mount K21h-cosign-root-user K21i-cosign-other-network \
  K21j-cosign-image-swapped K21k-heredoc-single-quoted-opener K21l-heredoc-backslash-opener K21q-setsid-wrapped-docker \
  K22a-heredoc-in-multiline-quote K22b-heredoc-in-nested-quote K22c-wrapper-with-user-arg K22d-wrapper-flock \
  K22e-wrapper-runuser K22f-create-other-image K22g-create-unlisted-variable-image K22h-create-subst-image K21r-case-paren-label K21s-eval-lower-docker-var

# ---------------------------------------------------------------------------------------
# H2: the ledger. passes + fails must equal the rows executed (a verdict silently discarded would break it),
# and the row count is an exact literal beside its use. Reported by printf + exit 1, never through ok()/bad().
# ---------------------------------------------------------------------------------------
printf '\n=== docker-run-tuple: %d passed, %d failed (%d rows) ===\n' "$PASS" "$FAIL" "$ROWS"
if [ "$((PASS + FAIL))" -ne "$ROWS" ]; then
  printf '[FATAL] accounting identity: passes(%s) + fails(%s) != rows(%s) - a verdict was discarded\n' "$PASS" "$FAIL" "$ROWS" >&2
  exit 1
fi
MIN_ROWS=296
if [ "$ROWS" -lt "$MIN_ROWS" ]; then
  printf '[FATAL] anti-vacuity floor: only %s rows ran, floor is %s\n' "$ROWS" "$MIN_ROWS" >&2
  exit 1
fi
# The floor is pinned EXACTLY to the measured row count: lowering MIN_ROWS (which would let rows be deleted
# unnoticed) is as visible as deleting a row. Bump it deliberately when you add one.
if [ "$ROWS" -gt "$MIN_ROWS" ]; then
  printf '[FATAL] floor drift: %s rows ran but MIN_ROWS is %s - set MIN_ROWS=%s\n' "$ROWS" "$MIN_ROWS" "$ROWS" >&2
  exit 1
fi
if [ "$FAIL" -gt 0 ]; then
  printf 'FAIL: %d row(s) failed - the helper does not pin what it claims.\n' "$FAIL"
  exit 1
fi
printf 'OK\n'
