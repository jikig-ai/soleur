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

  # The www rollback target is DERIVED from the baseline, not re-typed here —
  # one literal, one place.
  WWW_ROLLBACK_CONTENT="$(awk '/resource "cloudflare_record" "www"/,/^}/' "$BASELINE" \
    | awk -F'"' '/^[[:space:]]*content[[:space:]]*=/ { print $2; exit }')"
  [[ -n "$WWW_ROLLBACK_CONTENT" ]] \
    || die "could not derive the www rollback target from the baseline"

  grep -qF "\"$SURVIVOR_KEY\"" "$BASELINE" \
    || die "the baseline does not carry the survivor key $SURVIVOR_KEY that dns.tf moves from — baseline and cutover disagree"
}

REVERSE_BLOCK_MARKER='# --- ADR-194 apex rollback (reverse moved) ---'

# ---------------------------------------------------------------------------------------
# THE ROLLBACK IS A SCOPED TRANSFORM, NOT A FILE REPLACEMENT.
#
# An earlier revision emitted the rollback as `cp "$BASELINE" dns.tf`. That is
# correct on the day it is written and becomes destructive the moment anyone adds
# a DNS record: the baseline is FROZEN at PR4a, so a rollback three weeks later
# reverts the whole file to that snapshot and DELETES every record merged since —
# and it ships with `[ack-destroy]` already in the commit body, which walks those
# deletes straight past the destroy guard.
#
# `dns.tf` currently declares 30 records including `cloudflare_record.app`
# (app.soleur.ai, the authenticated product host), the Protonmail MX/DKIM set,
# `dmarc`, `supabase_custom_domain` and `cloudflare_zone_dnssec.soleur_ai`. A
# rollback of the APEX must not be able to touch any of them.
#
# So this rewrites only the apex region of the LIVE file:
#   - drop the forward `moved` block and the `pages_apex` resource
#   - restore `github_pages` and add the reverse `moved`
# Everything else is carried through byte-for-byte, and `assert_scoped()` below
# proves it rather than asserting it.
#
# The restored resource deliberately has NO `for_each`. That meta-argument was an
# artifact of the pre-PR4a four-address config; the rollback target is one record,
# so a plain resource is both simpler and sufficient, and it keeps the reverse
# `moved` a single-address move exactly as the forward one was.

restored_github_pages_block() {
  cat <<BLOCK
resource "cloudflare_record" "github_pages" {
  # Restored by generate-apex-rollback-pr.sh. NO \`for_each\`: the rollback target
  # is a single address, so the reverse \`moved\` below is a single-address move
  # and the A<-CNAME change is one replace that Terraform core serialises —
  # the same property the forward cutover relied on.
  zone_id = var.cf_zone_id
  name    = "soleur.ai"
  content = "$SURVIVOR_KEY"
  type    = "A"
  proxied = true
  ttl     = 1
}
BLOCK
}

reverse_block() {
  cat <<BLOCK

$REVERSE_BLOCK_MARKER
# Emitted by generate-apex-rollback-pr.sh.
#
# It returns the apex to its pre-cutover address so the CNAME->A change is a
# single-address replace that Terraform core serialises. Without it the rollback
# is two unrelated addresses dispatched concurrently, which is Cloudflare 81053
# in the reverse direction — the measured reason 'git revert' is forbidden here.
moved {
  from = cloudflare_record.pages_apex
  to   = cloudflare_record.github_pages
}
BLOCK
}

# Every `resource "<type>" "<label>"` in a file, one per line.
block_labels() { grep -oE '^resource "[a-z_]+" "[a-z_0-9]+"' "$1" | sed 's/^resource //' || true; }

# THE SAFETY PROPERTY, ASSERTED RATHER THAN TRUSTED: the rollback may drop
# `pages_apex` and add `github_pages`, and must leave every other declaration in
# the live file exactly where it was. This is what makes the transform safe in a
# way the file copy never was.
assert_scoped() { # <generated>
  local out="$1" live_labels gen_labels missing
  live_labels="$(block_labels "$DNS_TF" | grep -v '"pages_apex"' || true)"
  gen_labels="$(block_labels "$out")"
  missing="$(comm -23 <(printf '%s\n' "$live_labels" | sort -u) <(printf '%s\n' "$gen_labels" | sort -u))"
  [[ -z "$missing" ]] || die "the generated rollback would DROP declarations that are live in dns.tf: ${missing//$'\n'/ } — refusing to emit a rollback that deletes unrelated DNS records"
  grep -qE '^resource "cloudflare_record" "pages_apex"' "$out" \
    && die "the generated rollback still declares pages_apex — it is the address being moved away from"
  grep -qE '^resource "cloudflare_record" "github_pages"' "$out" \
    || die "the generated rollback does not restore cloudflare_record.github_pages"
  grep -qF "content = \"$WWW_ROLLBACK_CONTENT\"" "$out" \
    || die "the generated rollback leaves www pointing away from $WWW_ROLLBACK_CONTENT"
  grep -qF 'cloudflare_pages_project.docs' "$out" \
    && die "a reference to the Pages project survives the rollback"
  return 0
}

emit_tf() { # <out> <with-reverse-block: yes|no>
  local out="$1" with="$2"
  # Drop the forward `moved` block and the `pages_apex` resource from the LIVE
  # file, brace-depth scoped so a nested block cannot terminate the range early.
  awk '
    # forward moved block -> to = cloudflare_record.pages_apex
    /^moved[[:space:]]*\{/ { buf = $0 "\n"; depth = 1; inm = 1; next }
    inm {
      buf = buf $0 "\n"
      depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}")
      if (depth <= 0) { inm = 0; if (buf !~ /to[[:space:]]*=[[:space:]]*cloudflare_record\.pages_apex/) printf "%s", buf; buf = "" }
      next
    }
    /^resource "cloudflare_record" "pages_apex"[[:space:]]*\{/ { depth = 1; inr = 1; next }
    inr { depth += gsub(/\{/, "{"); depth -= gsub(/\}/, "}"); if (depth <= 0) inr = 0; next }
    { print }
  ' "$DNS_TF" > "$out" || die "could not write $out"

  # RETURN www TO THE GITHUB PAGES ORIGIN. The forward cutover re-pointed
  # `cloudflare_record.www`'s content at the Pages project; the rollback must
  # undo that too, or www keeps resolving to a project the apex no longer uses.
  # The wholesale file copy did this implicitly and the scoped transform must do
  # it explicitly — my own suite caught the omission.
  #
  # `name`/`type` are untouched: `type` is ForceNew, so rewriting it would make
  # www a SECOND replacement racing the apex's, which is the hazard this whole
  # design exists to avoid (Camp B, AC44).
  python3 - "$out" "$WWW_ROLLBACK_CONTENT" <<'PYEDIT' || die "could not revert the www record"
import io, re, sys
p, want = sys.argv[1], sys.argv[2]
s = io.open(p, encoding="utf-8").read()
m = re.search(r'(resource "cloudflare_record" "www" \{)(.*?)(\n\})', s, re.S)
if not m:
    sys.stderr.write("www record not found\n"); sys.exit(1)
body, n = re.subn(r'(\n  content = )[^\n]*', r'\g<1>"%s"' % want, m.group(2), count=1)
if n != 1:
    sys.stderr.write("www content line not found\n"); sys.exit(1)
io.open(p, "w", encoding="utf-8").write(s[:m.start(2)] + body + s[m.end(2):])
PYEDIT

  # Restore the A record where the flipped one stood, then (optionally) the move.
  restored_github_pages_block >> "$out" || die "could not append the restored record"
  if [[ "$with" == "yes" ]]; then
    reverse_block >> "$out" || die "could not append the reverse moved block"
  fi
  assert_scoped "$out"
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
    # REFUSE THE TEST SEAMS ON THE MUTATING PATH. `APEX_ROLLBACK_*` exist so the
    # suite can drive fixtures; the usage text calls them "tests only" and nothing
    # enforced it. An operator shell still carrying one exported from a local test
    # run would have this commit fixture content as dns.tf, push a real branch and
    # open a real PR carrying [ack-destroy] — output that looks exactly like a
    # correct rollback, which is what the input validation exists to refuse.
    for _seam in APEX_ROLLBACK_DNS_TF APEX_ROLLBACK_BASELINE; do
      [[ -z "${!_seam:-}" ]] || die "$_seam is set — refusing to open a real rollback PR built from a test seam"
    done
    validate_inputs
    command -v gh >/dev/null || die "gh is not available"
    # REFUSE A TREE THAT IS NOT A CLEAN CHECKOUT OF main. `git commit` commits the
    # INDEX, so anything already staged on an operator's machine mid-incident
    # rides into a PR whose body carries `[ack-destroy]` on its own line.
    [[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] \
      || die "working tree is not clean — refusing to build a rollback PR that would commit unrelated staged changes"
    git -C "$REPO_ROOT" fetch -q origin main 2>/dev/null || true
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor origin/main HEAD 2>/dev/null; then
      die "HEAD is behind origin/main — rebase before generating a rollback, or it will revert siblings"
    fi
    BRANCH="rollback-apex-cutover-$(date -u +%Y%m%d-%H%M%S)"
    # Owning trap (ADR-129): this path pushes and opens a PR, so any of the
    # `die`s below can exit between allocation and the `rm -f` at the end.
    export TMPDIR="${TMPDIR:-/var/tmp}"
    MSG_FILE="$(mktemp -t apex-rollback-msg.XXXXXXXX)" || die "mktemp failed"
    trap 'rm -f "$MSG_FILE"' EXIT INT TERM HUP
    # Generate and validate BEFORE touching the branch or the live file, so a
    # refusal leaves the operator exactly where they started. An earlier revision
    # branched first and overwrote dns.tf before the ack check, so a late `die`
    # left a mutated file on a new branch — and the re-run then refused with
    # "this tree is not post-flip", which was false and asserted under incident
    # pressure.
    STAGED_TF="$(mktemp -t apex-rollback-dns.XXXXXXXX)" || die "mktemp failed"
    trap 'rm -f "$MSG_FILE" "$STAGED_TF"' EXIT INT TERM HUP
    emit_tf "$STAGED_TF" yes
    emit_commit_msg "$MSG_FILE"
    git -C "$REPO_ROOT" checkout -b "$BRANCH" || die "could not create $BRANCH"
    cp "$STAGED_TF" "$DNS_TF" || die "could not install the generated dns.tf"
    # `-- "$DNS_TF"` so the commit carries this file and nothing else, even if
    # something slipped into the index between the cleanliness check and here.
    git -C "$REPO_ROOT" commit -F "$MSG_FILE" -- "$DNS_TF" || die "git commit failed"
    # AC53: assert the ack landed in the BRANCH COMMIT BODY. `gh pr view --json`
    # cannot see a commit body, and the ack landing in the squash message is the
    # single point of failure for the whole rollback.
    # HERESTRING, NOT A PIPE. Under `set -o pipefail`, `grep -q` exits on the
    # first match, the producer takes SIGPIPE (141), and `!` inverts that into a
    # `die` — aborting the rollback PR with "the ack is missing" at the exact
    # moment it is present. The sibling probe documents this trap; it was not
    # applied here.
    if ! grep -qE '^\[ack-destroy\]$' <<<"$(git -C "$REPO_ROOT" log -1 --format=%B)"; then
      die "[ack-destroy] is not on its own line in the commit body — the squash message would not carry it"
    fi
    git -C "$REPO_ROOT" push -u origin "$BRANCH" || die "push failed"
    gh pr create --title "revert(infra): roll the apex back to the GitHub Pages A record (ADR-194)" \
                 --body-file "$MSG_FILE" || die "gh pr create failed"
    rm -f "$MSG_FILE"
    ;;
  *) usage ;;
esac
