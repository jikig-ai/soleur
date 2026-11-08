#!/usr/bin/env bash
# Pattern-only tests for ship-runbook-ssh-gate.sh's two anchored regexes.
# Same pattern as sibling ship-operator-step-gate.test.sh.

set -euo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-runbook-ssh-gate.sh"

PASS=0
FAIL=0
TOTAL=0

SSH_RE='^[[:space:]]*([-*]|[0-9]+\.)?[[:space:]]*`?(ssh\b|docker\s+exec\b|journalctl\s+.*(-f\b|--follow\b)|systemctl\s+(restart|stop|start|kill)\b|kill\b|systemd-run\b)'
# The shared wrapper-boundary fragment (#10248) — same source the gate's own
# incidents.sh chain provides; restated here so CMD_RE stays a faithful copy.
# unset-first per the lib contract: an inherited env value must not masquerade
# as the loaded fragment after a failed source.
# shellcheck source=../../plugins/soleur/scripts/lib/wrapper-boundary.sh
unset SOLEUR_ENV_ASN_RE SOLEUR_LAUNCHER_RE SOLEUR_RTK_RE SOLEUR_BOUNDARY_PFX SOLEUR_BOUNDARY_PFX_LOADED
source "$SCRIPT_DIR/../../plugins/soleur/scripts/lib/wrapper-boundary.sh" 2>/dev/null || true
CMD_RE='(^|&&|\|\||;)\s*('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'

t() {
  TOTAL=$((TOTAL + 1))
  local label="$1" pattern="$2" input="$3" expected="$4"
  local got="no-match"
  if echo "$input" | grep -cE >/dev/null "$pattern"; then got="match"; fi
  if [[ "$got" == "$expected" ]]; then
    PASS=$((PASS + 1)); echo "PASS: $label"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $label  (expected $expected, got $got)"
    echo "  input: $input"
  fi
}

# --- SSH_RE positive matches ---
t "ssh root@... as bullet"           "$SSH_RE" "- ssh root@hetzner journalctl -u inngest" match
t "ssh under numbered list"          "$SSH_RE" "1. ssh deploy@host" match
t "ssh in backticks"                 "$SSH_RE" "  \`ssh deploy@host\`"   match
t "docker exec bullet"               "$SSH_RE" "- docker exec -it web-platform bash" match
t "journalctl follow"                "$SSH_RE" "- journalctl -u inngest-server.service -f" match
t "journalctl --follow long"         "$SSH_RE" "- journalctl --follow -u inngest" match
t "systemctl restart"                "$SSH_RE" "- systemctl restart inngest-server" match
t "systemctl stop"                   "$SSH_RE" "1. systemctl stop nginx" match
t "kill PID"                         "$SSH_RE" "  kill 12345" match
t "systemd-run --user ..."           "$SSH_RE" "- systemd-run --user --scope --slice=foo" match

# --- SSH_RE negatives (must NOT fire) ---
t "Sentry search URL bullet"         "$SSH_RE" "- Search Sentry: https://sentry.io/issues/?query=..." no-match
t "gh run view bullet"               "$SSH_RE" "- gh run view 12345" no-match
t "curl Sentry API"                  "$SSH_RE" "- curl -H 'Authorization: Bearer ...' https://sentry.io/api/0/..." no-match
t "doppler secrets get"              "$SSH_RE" "- doppler secrets get SENTRY_DSN -p soleur -c prd --plain" no-match
t "prose mention of ssh"             "$SSH_RE" "Avoid sshing into the box; use Sentry instead." no-match
t "journalctl no -f (single shot)"   "$SSH_RE" "- journalctl -u inngest --since '-1h'" no-match
t "killer feature (word)"            "$SSH_RE" "Sentry is the killer feature for RCA" no-match

# --- CMD_RE — same shape as sibling operator-step gate ---
t "gh pr ready 4239"                 "$CMD_RE" "gh pr ready 4239" match
t "gh pr merge --auto"               "$CMD_RE" "gh pr merge --squash --auto" match
t "gh pr merge w/o --auto"           "$CMD_RE" "gh pr merge 4239 --squash" no-match
t "chain: ready && merge --auto"     "$CMD_RE" "gh pr ready 1 && gh pr merge --auto" match
t "rtk gh pr merge --auto (wrapper prefix, #10248)" "$CMD_RE" "rtk gh pr merge --auto" match
t "rtk-foo gh pr merge --auto (glued suffix is not rtk)" "$CMD_RE" "rtk-foo gh pr merge --auto" no-match

# --- #5192: commit-body / heredoc strip → CMD_RE no longer fires -----------
# shellcheck source=lib/incidents.sh
source "$SCRIPT_DIR/lib/incidents.sh" 2>/dev/null || true
FP_SCAN=$(strip_command_bodies $'git add . && git commit -m "ship note\ngh pr ready must not be hand-rolled\n"')
t "commit-body gh pr ready stripped → CMD_RE no-match (#5192)" "$CMD_RE" "$FP_SCAN" no-match
REAL_SCAN=$(strip_command_bodies $'git commit -F - <<EOF\nbody\nEOF\n && gh pr merge 7 --squash --auto')
t "real gh pr merge --auto after heredoc still fires (#5192)" "$CMD_RE" "$REAL_SCAN" match

# --- Behavioural rows (#12332): the changed-runbook list is read NUL-delimited and each runbook is re-diffed
#     by its RAW name with --literal-pathspecs. Plain `--name-only` C-quotes a non-ASCII/tab/quote/backslash name;
#     the quoted string then reaches the per-file re-diff as a pathspec that matches nothing, `added` is empty and
#     the gate passes a runbook that adds an ssh step.
FX_ROOTS=()
# Canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh); the relative-path
# ratchet recognises only this executed statement before a write into a fixture root.
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
cleanup_fx_roots() {
  local d
  for d in "${FX_ROOTS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] || continue
    assert_fixture_dir "$d"
    rm -rf "$d"
  done
  return 0
}
trap cleanup_fx_roots EXIT INT TERM

tc() { # <label> <expected> <actual>
  TOTAL=$((TOTAL + 1))
  if [[ "$2" == "$3" ]]; then PASS=$((PASS + 1)); echo "PASS: $1"
  else FAIL=$((FAIL + 1)); echo "FAIL: $1  (expected '$2', got '$3')"; fi
}

# make_rb_repo <out-var> <mutating-shell-snippet>: a bare origin with main, a clone on a feature branch with the
# snippet applied and committed (the hook diffs origin/main...HEAD).
make_rb_repo() {
  local root work
  root="$(mktemp -d "${TMPDIR:-/var/tmp}/runbook-gate-fx.XXXXXX")" || return 1
  FX_ROOTS+=("$root")
  assert_fixture_dir "$root"
  work="$root/work"
  git init -q --bare "$root/origin.git"
  git clone -q "$root/origin.git" "$work" 2>/dev/null
  git -C "$work" config user.email "test@example.com"
  git -C "$work" config user.name "Test User"
  git -C "$work" config commit.gpgsign false
  mkdir -p "$work/knowledge-base/engineering/operations/runbooks"
  printf 'seed\n' > "$work/README.md"
  git -C "$work" add -A
  git -C "$work" commit -q -m seed
  git -C "$work" branch -M main
  git -C "$work" push -q -u origin main 2>/dev/null
  git -C "$work" checkout -q -b feat-fixture
  ( cd "$work" && bash -c "$2" )
  git -C "$work" add -A
  git -C "$work" commit -q -m change
  printf -v "$1" '%s' "$work"
}
RB_DIR='knowledge-base/engineering/operations/runbooks'
rb_run() { # <work>: runs the hook for `gh pr ready` in that checkout; sets RB_DEC (decision) and RB_REASON
  local out
  out="$(jq -nc --arg d "$1" '{tool_name:"Bash", tool_input:{command:"gh pr ready 7"}, cwd:$d}' \
    | bash "$HOOK" 2>/dev/null)" || true
  RB_DEC="$(printf '%s' "$out" | jq -r '.decision // empty' 2>/dev/null || true)"
  RB_REASON="$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null || true)"
}
rb_decision() { rb_run "$1"; printf '%s' "$RB_DEC"; }
SSH_STEP="printf '## What to do\n\n- ssh prod-host\n'"

make_rb_repo RB_ASCII "$SSH_STEP > $RB_DIR/plain.md"
tc "row: an ASCII runbook adding an ssh step blocks (the fixture can say deny)" "deny" "$(rb_decision "$RB_ASCII")"

make_rb_repo RB_OK "printf '## What to do\n\n- gh run view 12345\n' > $RB_DIR/ok.md"
tc "control: a runbook whose first step is not ssh passes" "" "$(rb_decision "$RB_OK")"

make_rb_repo RB_OUT "printf 'x\n' > README2.md; mkdir -p docs; $SSH_STEP > docs/not-a-runbook.md"
tc "control: an ssh step OUTSIDE the runbooks directory is not this gate's surface" "" "$(rb_decision "$RB_OUT")"

make_rb_repo RB_UTF8 "$SSH_STEP > $RB_DIR/caf\$'\\xc3\\xa9'.md"
RB_PRE="$(git -C "$RB_UTF8" diff --name-only origin/main...HEAD -- "$RB_DIR/*.md")"
tc "precondition: the plain name-only list C-quotes the non-ASCII runbook name" "1" "$([[ "$RB_PRE" == '"'* ]] && echo 1 || echo 0)"
tc "row: a non-ASCII-named runbook adding an ssh step blocks" "deny" "$(rb_decision "$RB_UTF8")"

make_rb_repo RB_QUOTE "$SSH_STEP > \$'$RB_DIR/q\"uote.md'"
RB_PRE="$(git -C "$RB_QUOTE" diff --name-only origin/main...HEAD -- "$RB_DIR/*.md")"
tc "precondition: the plain list C-quotes a runbook name holding a double quote" "1" "$([[ "$RB_PRE" == '"'* ]] && echo 1 || echo 0)"
tc "row: a quote-named runbook adding an ssh step blocks" "deny" "$(rb_decision "$RB_QUOTE")"

# A bracket name (git matches a pathspec literally first, so this row alone does not separate the flag; the star row below does).
make_rb_repo RB_BRACKET "$SSH_STEP > '$RB_DIR/glob[1].md'"
tc "row: a bracket-named runbook adding an ssh step blocks (--literal-pathspecs)" "deny" "$(rb_decision "$RB_BRACKET")"

# A star name must not over-match a sibling: the CLEAN `a*b.md` would glob onto the ssh-bearing `aXb.md`.
make_rb_repo RB_STAR "printf '## What to do\n\n- gh run view 1\n' > '$RB_DIR/a*b.md'; $SSH_STEP > $RB_DIR/aXb.md"
rb_run "$RB_STAR"
tc "row: the ssh-bearing sibling still blocks" "deny" "$RB_DEC"
tc "row: the clean star-named runbook is not reported (no glob over-match)" "0" "$([[ "$RB_REASON" == *'a*b.md:'* ]] && echo 1 || echo 0)"

# --- Hook syntax ---
if bash -n "$HOOK"; then
  PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: hook syntax OK"
else
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: hook syntax"
fi

echo ""
echo "=== $PASS/$TOTAL pass ($FAIL fail) ==="
[[ $FAIL -eq 0 ]]
