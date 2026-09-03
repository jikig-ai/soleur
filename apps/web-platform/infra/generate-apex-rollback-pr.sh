#!/usr/bin/env bash
# generate-apex-rollback-pr.sh — emit the reverse-`moved` rollback for the
# ADR-194 apex cutover (#7640 PR4b, plan 4b.2 / AC70 / AC53).
#
# WHY THIS EXISTS INSTEAD OF `git revert`
#
# `git revert` of the PR4b merge is FORBIDDEN, and the reason is measured rather
# than stylistic. A revert restores the `github_pages` resource and deletes the
# `pages_apex` one WITHOUT any `moved` block, so Terraform sees two unrelated
# addresses: `1 to add, 0 to change, 1 to destroy`, dispatched concurrently.
# Cloudflare rejects an A and a CNAME coexisting at one name (error 81053), so
# that reproduces the collision in the REVERSE direction — on an apex that is
# already failing, which is the only time anyone would run it. The obvious,
# muscle-memory action is the dangerous one.
#
# The safe rollback keeps the transition on ONE resource address in the other
# direction: a `moved` block from `pages_apex` back to the `github_pages` key,
# after which the CNAME->A change is a single-address replace that core
# serialises exactly as the forward cutover did.
#
# WHAT "BYTE-IDENTICAL TO dns.tf AS PR4a LEFT IT" MEANS, PRECISELY
#
# AC70 asks for two things that cannot both hold literally: a generated file
# byte-identical to PR4a's `dns.tf`, AND a reverse `moved` block. PR4a's file has
# no `moved` block at all. The reverse block is not optional — without it this
# script would emit exactly the two-address plan `git revert` produces, i.e. the
# thing it exists to avoid.
#
# So the guarantee is: byte-identical to PR4a's `dns.tf` MODULO the reverse
# `moved` block. `--emit-tf` writes the rollback file; `--emit-tf-stripped`
# writes it with that block removed, and THAT is asserted byte-identical against
# the committed baseline. The assertion stays checkable against a state that
# really existed rather than against a reconstruction of one.
#
# The record declarations are restored FROM the committed baseline rather than
# un-transformed out of the post-flip file. That is deliberate: reconstructing
# the `for_each`, `each.value`, the A type and the original contract comment by
# regex, under incident pressure, is how a rollback acquires its own bugs. The
# baseline is a state that shipped; this script's job is to reach it, not to
# re-derive it.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DNS_TF="${APEX_ROLLBACK_DNS_TF:-$SCRIPT_DIR/dns.tf}"
BASELINE="${APEX_ROLLBACK_BASELINE:-$SCRIPT_DIR/fixtures/dns.tf.pr4a-baseline}"

die() { printf '[FATAL] %s\n' "$1" >&2; exit 2; }

usage() {
  cat >&2 <<'USAGE'
usage: generate-apex-rollback-pr.sh <mode>

  --emit-tf <path>           write the rollback dns.tf (baseline + reverse moved block)
  --emit-tf-stripped <path>  the same, with the reverse moved block removed (AC70's
                             byte-identity target)
  --emit-commit-msg <path>   write the rollback commit message, carrying [ack-destroy]
                             on its own line
  --open-pr                  branch, commit, push and `gh pr create` the rollback

Env seams (tests only): APEX_ROLLBACK_DNS_TF, APEX_ROLLBACK_BASELINE.
USAGE
  exit 2
}

# ---------------------------------------------------------------------------------------
# INPUT VALIDATION — refuse to generate a rollback from a tree that is not the
# one this rollback is for. A generator that emits confidently against the wrong
# input is worse than one that refuses: its output looks exactly like a correct
# rollback and is applied during an incident.
# ---------------------------------------------------------------------------------------
validate_inputs() {
  [[ -r "$DNS_TF" ]]   || die "dns.tf not readable: $DNS_TF"
  [[ -r "$BASELINE" ]] || die "PR4a baseline not readable: $BASELINE"

  grep -qE '^resource "cloudflare_record" "pages_apex" \{' "$DNS_TF" \
    || die "dns.tf does not declare cloudflare_record.pages_apex — this tree is not post-flip, so there is nothing to roll back"
  grep -qE '^resource "cloudflare_record" "github_pages" \{' "$BASELINE" \
    || die "baseline does not declare cloudflare_record.github_pages — it is not the shape PR4a left"
  grep -qE '^resource "cloudflare_record" "pages_apex" \{' "$BASELINE" \
    && die "baseline declares pages_apex — it is post-flip, not the PR4a shape"

  # The forward move's source key IS the rollback's destination. Deriving it from
  # the live file rather than re-pinning it here keeps one literal in play: a
  # rollback that names a different key than the cutover did would `moved` into
  # an address that is not in state, no-op, and reproduce the two-address hazard
  # it exists to avoid.
  FORWARD_FROM="$(grep -oE 'from = cloudflare_record\.github_pages\["[0-9.]+"\]' "$DNS_TF" | head -1 | sed 's/^from = //')"
  [[ -n "$FORWARD_FROM" ]] || die "dns.tf carries no 'moved { from = cloudflare_record.github_pages[...] }' — cannot determine the rollback target"

  SURVIVOR_KEY="$(printf '%s' "$FORWARD_FROM" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
  [[ -n "$SURVIVOR_KEY" ]] || die "could not parse the survivor key out of $FORWARD_FROM"

  grep -qF "\"$SURVIVOR_KEY\"" "$BASELINE" \
    || die "the baseline does not carry the survivor key $SURVIVOR_KEY that dns.tf moves from — baseline and cutover disagree"
}

REVERSE_BLOCK_MARKER='# --- ADR-194 apex rollback (reverse moved) ---'

reverse_block() {
  cat <<BLOCK

$REVERSE_BLOCK_MARKER
# Emitted by generate-apex-rollback-pr.sh. This block, and ONLY this block, is
# what makes the file below differ from dns.tf as PR4a left it.
#
# It returns the apex to its pre-cutover address so the CNAME->A change is a
# single-address replace that Terraform core serialises. Without it the rollback
# is two unrelated addresses dispatched concurrently, which is Cloudflare 81053
# in the reverse direction — the measured reason 'git revert' is forbidden here.
moved {
  from = cloudflare_record.pages_apex
  to   = $FORWARD_FROM
}
BLOCK
}

emit_tf() { # <out> <with-reverse-block: yes|no>
  local out="$1" with="$2"
  cp "$BASELINE" "$out" || die "could not write $out"
  if [[ "$with" == "yes" ]]; then
    reverse_block >> "$out" || die "could not append the reverse moved block"
  fi
}

emit_commit_msg() { # <out>
  cat > "$1" <<MSG || die "could not write $1"
revert(infra): roll the apex back to the GitHub Pages A record (ADR-194)

Generated by apps/web-platform/infra/generate-apex-rollback-pr.sh. This is the
rollback for the #7640 PR4b apex cutover, and it is NOT a \`git revert\` of it.

A revert restores cloudflare_record.github_pages and deletes
cloudflare_record.pages_apex with no \`moved\` block, so Terraform plans two
unrelated addresses and dispatches them concurrently. Cloudflare rejects an A and
a CNAME at one name (81053), so that reproduces the collision in the reverse
direction, on an apex that is already failing. Measured, not assumed.

This carries a reverse \`moved\` block instead, returning the apex to
$FORWARD_FROM so the CNAME->A change is a single-address replace that core
serialises. \`dns.tf\` is otherwise byte-identical to the shape PR4a left.

[ack-destroy]

Ref #7640
MSG
}

MODE="${1:-}"
case "$MODE" in
  --emit-tf)          [[ $# -eq 2 ]] || usage; validate_inputs; emit_tf "$2" yes ;;
  --emit-tf-stripped) [[ $# -eq 2 ]] || usage; validate_inputs; emit_tf "$2" no ;;
  --emit-commit-msg)  [[ $# -eq 2 ]] || usage; validate_inputs; emit_commit_msg "$2" ;;
  --open-pr)
    validate_inputs
    command -v gh >/dev/null || die "gh is not available"
    BRANCH="rollback-apex-cutover-$(date -u +%Y%m%d-%H%M%S)"
    MSG_FILE="$(mktemp)" || die "mktemp failed"
    git -C "$REPO_ROOT" checkout -b "$BRANCH" || die "could not create $BRANCH"
    emit_tf "$DNS_TF" yes
    emit_commit_msg "$MSG_FILE"
    git -C "$REPO_ROOT" add "$DNS_TF" || die "git add failed"
    git -C "$REPO_ROOT" commit -F "$MSG_FILE" || die "git commit failed"
    # AC53: assert the ack landed in the BRANCH COMMIT BODY. `gh pr view --json`
    # cannot see a commit body, and the ack landing in the squash message is the
    # single point of failure for the whole rollback.
    if ! git -C "$REPO_ROOT" log -1 --format=%B | grep -qE '^\[ack-destroy\]$'; then
      die "[ack-destroy] is not on its own line in the commit body — the squash message would not carry it"
    fi
    git -C "$REPO_ROOT" push -u origin "$BRANCH" || die "push failed"
    gh pr create --title "revert(infra): roll the apex back to the GitHub Pages A record (ADR-194)" \
                 --body-file "$MSG_FILE" || die "gh pr create failed"
    rm -f "$MSG_FILE"
    ;;
  *) usage ;;
esac
