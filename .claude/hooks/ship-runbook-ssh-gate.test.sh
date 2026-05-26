#!/usr/bin/env bash
# Pattern-only tests for ship-runbook-ssh-gate.sh's two anchored regexes.
# Same pattern as sibling ship-operator-step-gate.test.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/ship-runbook-ssh-gate.sh"

PASS=0
FAIL=0
TOTAL=0

SSH_RE='^[[:space:]]*([-*]|[0-9]+\.)?[[:space:]]*`?(ssh\b|docker\s+exec\b|journalctl\s+.*(-f\b|--follow\b)|systemctl\s+(restart|stop|start|kill)\b|kill\b|systemd-run\b)'
CMD_RE='(^|&&|\|\||;)\s*gh\s+pr\s+(ready|merge\s+.*--auto)(\s|$|&&|\|\||;)'

t() {
  TOTAL=$((TOTAL + 1))
  local label="$1" pattern="$2" input="$3" expected="$4"
  local got="no-match"
  if echo "$input" | grep -qE "$pattern"; then got="match"; fi
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

# --- Hook syntax ---
if bash -n "$HOOK"; then
  PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); echo "PASS: hook syntax OK"
else
  FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); echo "FAIL: hook syntax"
fi

echo ""
echo "=== $PASS/$TOTAL pass ($FAIL fail) ==="
[[ $FAIL -eq 0 ]]
