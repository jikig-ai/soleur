#!/usr/bin/env bash
# PreToolUse(Bash) hook: blocks `gh pr ready` / `gh pr merge` when any commit on
# the branch (origin/main..HEAD) is authored OR committed by a non-CLA-sanctioned
# identity — `noreply@anthropic.com` (stage 1, specialized message) or any
# author/committer email outside the sanctioned set (stage 2, subset check).
#
# wg-cla-signed-author-before-merge — the required `cla-check` CI status fails on
# any commit authored by an unsigned identity: cla-check resolves
# commit.author.user.login via GraphQL and a real-but-wrong email
# (`git -c user.email=…` over a configured identity — #12027 `jean@jikig.ai`;
# #7218 `ops@jikigai.com`) resolves to a NULL login just like a fake one.
# SUBAGENTS that commit (e.g. the ux-design-lead agent's Pencil recovery-anchor
# stub) author as `Claude <noreply@anthropic.com>`, so a branch can pass local
# review yet block at merge time after a wasted CI cycle. This gate catches it
# BEFORE the cycle, with the filter-branch author-rewrite fix in the deny
# message. See
# knowledge-base/project/learnings/workflow-patterns/2026-06-04-subagent-commits-fail-cla-check.md
# (PR #4948 cla-check failure).
#
# Stage-2 SANCTIONED SET (author and committer slots evaluated separately on
# origin/main..HEAD — the committer-only WEB_COMMITTER_EMAIL carve-out does not
# cover the author slot):
#   1. the session's `git config user.email` (merged scopes, trimmed);
#   2. SANCTIONED_EMAILS — pinned CLA-allowlisted human emails (a non-noreply
#      signed email cannot be resolved to a login offline, so the sanctioned
#      `-c` override path for unset-config sessions must be pinned; provenance:
#      plugins/soleur/devin/INSTRUCTIONS.md §Devin-specific considerations);
#   3. `<id>+<login>@users.noreply.github.com` — OR the pre-2017 bare-login
#      form `login@users.noreply.github.com` (no `<id>+` prefix) — whose
#      <login>, case-folded on BOTH sides (GitHub logins compare
#      case-insensitively; the roster spells e.g. `Elvalio`), is in the
#      `allowlist:` key of origin/main's .github/workflows/cla.yml (the ref
#      pull_request_target executes — a branch cannot widen the roster that
#      sanctions its own commits) or in signedContributors[].name of
#      origin/cla-signatures:signatures/cla.json;
#   4. WEB_COMMITTER_EMAIL (`noreply@github.com`) in the COMMITTER slot only —
#      see the constant's comment for the measured evidence; an author-slot
#      noreply@github.com still denies.
# Rosters are read at remote-tracking refs (last fetch) — the stage-2 deny
# message tells the operator to `git fetch origin` and retry on fresh rosters.
# DENIED_EMAILS is evaluated BEFORE every admission source — deny overrides
# admit: devin-ai-integration[bot] is in neither roster (measured cla-check
# fail, PR #11690 / learning 2026-10-30), so it denies even when it equals the
# session's configured user.email.
#
# PreToolUse(Bash) input shape (sibling-hook parity):
#   .tool_input.command (string) — the bash command string
#   .cwd                (string) — absolute working directory
#
# Fail-open (exit 0 silently): missing/relative/nonexistent .cwd, bare-repo /
# non-worktree context, branch main/master/detached, refname fails validation,
# no upstream tracking ref (origin/<branch> absent — out of scope), or ALL
# dynamic sanctioned sources empty (config unset + cla.yml absent at
# origin/main + cla-signatures ref absent — an unevaluable run is not a deny).
# Per-source failure degrades that component only.
#
# Fail-closed (deny + emit_incident): any branch commit author/committer email
# equals noreply@anthropic.com (stage 1), or is outside the sanctioned set
# (stage 2, when evaluable).

set -eo pipefail
# -u (nounset) omitted: failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

UNSIGNED_EMAIL="noreply@anthropic.com"

# Stage 2 constants. DENIED_EMAILS is checked BEFORE any admission source —
# deny overrides admit, so a devin-bot identity denies even when it equals the
# session's configured user.email (a Devin session could in principle be
# configured with the bot noreply; no roster clause would catch that, and
# authorship is the only lever because pull_request_target reads cla.yml from
# main). devin-ai-integration[bot] is in NEITHER roster — measured cla-check
# fail on PR #11690 (learning 2026-10-30); it is NOT a sanctioned override.
DENIED_EMAILS="devin-ai-integration[bot]@users.noreply.github.com
158243242+devin-ai-integration[bot]@users.noreply.github.com"

# Pinned CLA-allowlisted human emails. A non-noreply signed email cannot be
# resolved to a login offline, so the sanctioned `-c` override path for
# unset-config sessions (plugins/soleur/devin/INSTRUCTIONS.md §Commit author
# identity) must be pinned here — reviewed in the same diff as this gate.
SANCTIONED_EMAILS="jean.deruelle@jikigai.com"

# Committer-slot-only carve-out (verified 2026-11, review-panel finding):
# `git log origin/main --format='%an | %ce' -25` shows EVERY landed commit
# carries committer `GitHub <noreply@github.com>` — the squash-merge path is
# uniformly web-flow — and cla.yml's contributor-assistant resolves only
# `commit.author.user.login` (its own comments document this), so committer
# identity is never evaluated by the required check. A web-authored branch
# commit (web edit, suggestion-commit, "Update branch") therefore passes
# cla-check with a sanctioned author while this committer fails every offline
# source. COMMITTER-SLOT ONLY by design: an AUTHOR `noreply@github.com`
# resolves to the unsigned web-flow login and still denies — fail-closed.
WEB_COMMITTER_EMAIL="noreply@github.com"

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164, reintroduced one line
# above where every test points.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[cla-signed-author-gate] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

# Shared context-sanitize lib (#10395). When it is unreadable the same-name
# fallback carries this site's pre-change strip set (C0 minus \t\n, DEL, plus
# the LS/PS sed) — never weaker than today.
_ctx_lib="$(dirname "${BASH_SOURCE[0]}")/lib/context-sanitize.sh"
# shellcheck source=/dev/null
[[ -r "$_ctx_lib" ]] && . "$_ctx_lib" || true
declare -F soleur_ctx_sanitize_lines >/dev/null 2>&1 \
  || soleur_ctx_sanitize_lines() { LC_ALL=C tr -d '\000-\010\013-\037\177' | LC_ALL=C sed -e $'s/\xe2\x80\xa8//g' -e $'s/\xe2\x80\xa9//g'; }

INPUT=$(cat)
# Single jq fork, and NO shell evaluation of hook input. The previous comment
# here claimed `@sh` quoting meant attacker bytes could not inject. That was
# true only for a STRING value; an ARRAY became a command (#7164).
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). A non-string field is surfaced, never
# coerced — coercion closes the RCE and leaves the guards evaded (#7164).
# ADR-157: a hook that cannot fully parse its input asks. The exit lives
# HERE, at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "cla-signed-author-gate"
  hook_input_should_ask && { hook_input_emit_ask "cla-signed-author-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Fire on gh pr ready OR gh pr merge. Word-boundary + chain-operator anchored
# (matches sibling pre-merge-rebase.sh / ship-unpushed-commits-gate.sh style).
# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh) so a
# commit message documenting `gh pr merge` is not mistaken for one (#5192).
SCAN=$(strip_command_bodies "$CMD")
if ! grep -qE '(^|&&|\|\||;)\s*('"${SOLEUR_BOUNDARY_PFX:-}"'[[:space:]]+)*gh\s+pr\s+(ready|merge)(\s|$)' <<<"$SCAN"; then
  exit 0
fi

# Validate WORK_DIR: absolute + existing dir (CWE-88 arg-injection defense).
# The definition is byte-equal to the canonical helper in
# plugins/soleur/test/test-helpers.sh — the fixture-safety suites pin that
# shape corpus-wide (fixture-dir-operand-assert "inline definition drift"
# arm), and the relative-operand scanner (#7708) clears the git -C sites
# below only behind an executed assert_fixture_dir statement. The `|| exit 0`
# wrapper keeps this hook fail-OPEN: a malformed payload exits the boundary
# command silently rather than as a hook error.
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
assert_fixture_dir "$WORK_DIR" || exit 0
[[ -d "$WORK_DIR" ]] || exit 0
if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
  exit 0
fi

CURRENT_BRANCH=$(git -C "$WORK_DIR" symbolic-ref --short -q HEAD 2>/dev/null || echo "")
if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  exit 0
fi
# Refname validation (arg-injection defense into git rev-list).
if [[ ! "$CURRENT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$CURRENT_BRANCH" == -* ]]; then
  exit 0
fi

# No origin/main → out of scope (the merge fails earlier with a clearer error).
# Scan the two-dot range origin/main..HEAD — equivalent to
# merge-base(origin/main,HEAD)..HEAD — so the set is exactly the branch's own
# commits (commits reachable only from main are excluded; this matches what the
# upstream cla-check evaluates against base=main).
BASE_REF="origin/main"
git -C "$WORK_DIR" rev-parse --verify "$BASE_REF" >/dev/null 2>&1 || exit 0

# Collect any branch commit whose AUTHOR or COMMITTER email is the unsigned id.
# %ae = author email, %ce = committer email; match either.
OFFENDERS=$(git -C "$WORK_DIR" log "${BASE_REF}..HEAD" --format='%h %ae %ce %s' 2>/dev/null \
  | awk -v e="$UNSIGNED_EMAIL" '$2 == e || $3 == e { print }' \
  | head -15 \
  | soleur_ctx_sanitize_lines \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

# ===========================================================================
# Stage-2 sanctioned-set evaluation — computed BEFORE the stage-1 deny so a
# stage-1 block can name the stage-2 offenders too: ONE filter-branch rewrite
# then fixes both classes instead of masking the second class until a retry
# (review panel, #12027). Every dynamic read is `|| true`-guarded: under
# `set -eo pipefail` a bare failing `$()` would abort the hook before the deny
# JSON can emit, and per-source failure must degrade that component only.
# ===========================================================================

# Source 1 — session's configured identity (merged local+global+system),
# whitespace/CR-trimmed.
_cfg_email=$(git -C "$WORK_DIR" config --get user.email 2>/dev/null || true)
_cfg_email="${_cfg_email//[[:space:]]/}"

# Source 2 — allowlist logins read at origin/main (the ref pull_request_target
# executes — a branch cannot widen the roster that sanctions its own commits).
# Anchored `^[[:space:]]+allowlist:` + first match only: the word "allowlist"
# also appears in cla.yml's comment block. GitHub logins are
# case-insensitive: the roster is folded to lower HERE so it compares on the
# same case as the extracted login (roster spells e.g. `Elvalio`, a noreply
# can spell `elvalio`).
_allowlist_logins=""
_cla_yml=$(git -C "$WORK_DIR" show "origin/main:.github/workflows/cla.yml" 2>/dev/null || true)
if [[ -n "$_cla_yml" ]]; then
  _al_line=$(printf '%s\n' "$_cla_yml" | grep -m1 -E '^[[:space:]]+allowlist:[[:space:]]*"' || true)
  if [[ -n "$_al_line" ]]; then
    _al_val="${_al_line#*\"}"; _al_val="${_al_val%%\"*}"
    _allowlist_logins=$(printf '%s' "$_al_val" | tr ',' '\n' \
      | sed 's/^[[:space:]]*//' | tr '[:upper:]' '[:lower:]' | grep -v '^$' || true)
  fi
fi

# Source 3 — signed contributor logins at origin/cla-signatures (absent on
# partial clones — degrades to empty). `// empty` absorbs schema drift. Same
# case-fold as the allowlist.
_signed_logins=$(git -C "$WORK_DIR" show "origin/cla-signatures:signatures/cla.json" 2>/dev/null \
  | jq -r '.signedContributors[]?.name // empty' 2>/dev/null \
  | tr '[:upper:]' '[:lower:]' || true)

# Membership predicate — exact literal equality everywhere (no regex on the
# login: the `+`→`@` substring surgery treats it as a literal token, which
# kills metacharacter edge cases by construction). Accepts BOTH noreply forms
# GitHub has issued: the canonical `<id>+<login>` and the pre-2017 bare
# `login@users.noreply.github.com` — the roster check is identical.
is_sanctioned_email() {
  local e="$1" lcl idp login
  grep -qxF "$e" <<<"$SANCTIONED_SET" && return 0
  case "$e" in
    *@users.noreply.github.com) ;;
    *) return 1 ;;
  esac
  lcl="${e%@users.noreply.github.com}"   # "<id>+<login>" or bare "<login>"
  if [[ "$lcl" == *+* ]]; then
    # Canonical <digits>+<login> shape.
    idp="${lcl%%+*}"
    login="${lcl#*+}"
    [[ "$idp" =~ ^[0-9]+$ && -n "$login" ]] || return 1
  else
    # Pre-2017 bare-login form — the local part IS the login.
    login="$lcl"
    [[ -n "$login" ]] || return 1
  fi
  # Roster lines were lowercased at collection; fold the login to match.
  login=$(printf '%s' "$login" | tr '[:upper:]' '[:lower:]')
  grep -qxF "$login" <<<"$_allowlist_logins" && return 0
  grep -qxF "$login" <<<"$_signed_logins" && return 0
  return 1
}

# All dynamic sources empty -> stage 2 is unevaluable -> NOT a deny (fail
# open; the pinned SANCTIONED_EMAILS constant deliberately does NOT count
# toward evaluability: on a stripped/partial clone it would otherwise deny
# every branch not authored by the pinned human). Stage 1 still applies
# below.
_offender_emails=""
_fix_email_args=""
_fix_manual=""
if [[ -n "$_cfg_email" || -n "$_allowlist_logins" || -n "$_signed_logins" ]]; then

SANCTIONED_SET="${SANCTIONED_EMAILS}"$'\n'
[[ -n "$_cfg_email" ]] && SANCTIONED_SET+="${_cfg_email}"$'\n'

# Author and committer sets are evaluated SEPARATELY: the
# WEB_COMMITTER_EMAIL carve-out applies to the committer slot only.
_author_emails=$(git -C "$WORK_DIR" log "${BASE_REF}..HEAD" --format='%ae' 2>/dev/null | sort -u || true)
_committer_emails=$(git -C "$WORK_DIR" log "${BASE_REF}..HEAD" --format='%ce' 2>/dev/null | sort -u || true)

while IFS= read -r _e; do
  [[ -z "$_e" ]] && continue
  # Explicit exclusion precedes admission (deny overrides admit).
  if grep -qxF "$_e" <<<"$DENIED_EMAILS" || ! is_sanctioned_email "$_e"; then
    _offender_emails+="${_e}"$'\n'
  fi
done <<<"$_author_emails"
while IFS= read -r _e; do
  [[ -z "$_e" ]] && continue
  if grep -qxF "$_e" <<<"$DENIED_EMAILS"; then
    _offender_emails+="${_e}"$'\n'
    continue
  fi
  # Committer slot only: noreply@github.com is GitHub's web-merge identity
  # (see the WEB_COMMITTER_EMAIL comment for the measured evidence). An
  # author-slot noreply@github.com still denies via the author loop above.
  [[ "$_e" == "$WEB_COMMITTER_EMAIL" ]] && continue
  is_sanctioned_email "$_e" || _offender_emails+="${_e}"$'\n'
done <<<"$_committer_emails"
# sort is `|| true`-guarded like every other dynamic read (a sort failure must
# not abort the hook before the stage-1 deny can emit). UNSIGNED_EMAIL is
# dropped from the stage-2 set — stage-1's own clause and message already own
# it, so re-listing it would print a redundant offender and a duplicate `for e
# in` arg on every stage-1 deny.
_offender_emails=$(printf '%s' "$_offender_emails" | sort -u | grep -vxF "$UNSIGNED_EMAIL" || true)

# Remedy-arg validation: %ae/%ce bytes are attacker-influenceable — `$(…)`,
# backticks, quotes and `;` survive git's ident sanitization into %ae
# VERBATIM (measured), so interpolating an unchecked offender email into the
# printed executable env-filter would ship a paste-able injection. Only
# RFC-5322-ish addresses are emitted as executable `for e in` args; anything
# else is reported as a manual-rewrite line (context-sanitized) instead.
while IFS= read -r _e; do
  [[ -z "$_e" ]] && continue
  if [[ "$_e" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]]; then
    _fix_email_args+="\"${_e}\" "
  else
    _fix_manual+="manual rewrite required for: $(printf '%s\n' "$_e" | soleur_ctx_sanitize_lines)"$'\n'
  fi
done <<<"$_offender_emails"

fi

# Stage 1 — the dedicated noreply@anthropic.com deny still emits FIRST: its
# specialized remedy names the modal subagent-commit class (order is the
# property — a generic stage-2 deny would bury that remedy). Stage-2
# offenders, already computed above, ride along in the message and in the
# env-filter loop so ONE rewrite round fixes both classes.
if [[ -n "$OFFENDERS" ]]; then

emit_incident "wg-cla-signed-author-before-merge" deny \
  "Every branch commit MUST be authored by a CLA-sign" "$CMD"

FIX="FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
if [ \"\$GIT_AUTHOR_EMAIL\" = \"${UNSIGNED_EMAIL}\" ]; then export GIT_AUTHOR_NAME=\"<Your Name>\"; export GIT_AUTHOR_EMAIL=\"<you@domain>\"; fi
if [ \"\$GIT_COMMITTER_EMAIL\" = \"${UNSIGNED_EMAIL}\" ]; then export GIT_COMMITTER_NAME=\"<Your Name>\"; export GIT_COMMITTER_EMAIL=\"<you@domain>\"; fi"
if [[ -n "$_fix_email_args" ]]; then
FIX+="
for e in ${_fix_email_args}; do
  if [ \"\$GIT_AUTHOR_EMAIL\" = \"\$e\" ]; then export GIT_AUTHOR_NAME=\"<Your Name>\"; export GIT_AUTHOR_EMAIL=\"<you@domain>\"; fi
  if [ \"\$GIT_COMMITTER_EMAIL\" = \"\$e\" ]; then export GIT_COMMITTER_NAME=\"<Your Name>\"; export GIT_COMMITTER_EMAIL=\"<you@domain>\"; fi
done"
fi
FIX+="
' ${BASE_REF}..HEAD   # then: git push --force-with-lease"
[[ -n "$_fix_manual" ]] && FIX+=$'\n'"${_fix_manual%$'\n'}"

_stage2_note=""
[[ -n "$_offender_emails" ]] && _stage2_note=$'\n\nAdditional emails outside the CLA-sanctioned set on this branch (rewrite them in the SAME pass):\n'"${_offender_emails%$'\n'}"

jq -n \
  --arg email "$UNSIGNED_EMAIL" \
  --arg offenders "$OFFENDERS" \
  --arg fix "$FIX" \
  --arg stage2 "$_stage2_note" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: branch commit(s) authored by the non-CLA-signed identity " + $email + " — the required `cla-check` CI status will fail (typically a subagent commit, e.g. a Pencil recovery-anchor stub).\n\nOffending commits (h author committer subject):\n" + $offenders + "\n\nRewrite the author/committer to your CLA-signed identity, then re-push:\n" + $fix + $stage2)
    }
  }'
exit 0

fi

if [[ -z "$_offender_emails" ]]; then
  exit 0
fi

# Sample commits carrying an offender in either identity slot.
OFFENDER_DETAIL=$(git -C "$WORK_DIR" log "${BASE_REF}..HEAD" --format='%h %ae %ce %s' 2>/dev/null \
  | awk -v ems="$_offender_emails" 'BEGIN { n=split(ems,b,"\n"); for (i=1;i<=n;i++) if (b[i] != "") bad[b[i]]=1 } ($2 in bad) || ($3 in bad)' \
  | head -15 \
  | soleur_ctx_sanitize_lines \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

emit_incident "wg-cla-signed-author-before-merge" deny \
  "Every branch commit MUST be authored by a CLA-sign" "$CMD"

# Generalized filter-branch remedy — quoted literal list, no glob/case-pattern
# interpolation (`[bot]` in a case pattern is a bracket expression). Only
# charset-validated emails are emitted as `for e in` args (validation loop
# above): a non-conforming offender is reported as a manual-rewrite line,
# never an executable arg.
if [[ -n "$_fix_email_args" ]]; then
FIX="FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --env-filter '
for e in ${_fix_email_args}; do
  if [ \"\$GIT_AUTHOR_EMAIL\" = \"\$e\" ]; then export GIT_AUTHOR_NAME=\"<Your Name>\"; export GIT_AUTHOR_EMAIL=\"<you@domain>\"; fi
  if [ \"\$GIT_COMMITTER_EMAIL\" = \"\$e\" ]; then export GIT_COMMITTER_NAME=\"<Your Name>\"; export GIT_COMMITTER_EMAIL=\"<you@domain>\"; fi
done
' ${BASE_REF}..HEAD   # then: git push --force-with-lease"
else
FIX="(no executable remedy — every offending email failed charset validation; see the manual-rewrite list)"
fi
[[ -n "$_fix_manual" ]] && FIX+=$'\n'"${_fix_manual%$'\n'}"

jq -n \
  --arg emails "$_offender_emails" \
  --arg offenders "$OFFENDER_DETAIL" \
  --arg fix "$FIX" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("BLOCKED: branch commit(s) carry author/committer email(s) outside the CLA-sanctioned set — the required `cla-check` CI status resolves commit.author.user.login via GitHub and fails on unresolvable identities (a wrong `git -c user.email=…` override, an unsigned identity, or devin-ai-integration[bot], which is in neither roster).\n\nOffending emails:\n" + $emails + "\nSanctioned set: the session'"'"'s `git config user.email`; a `<id>+<login>@users.noreply.github.com` (or the pre-2017 `login@users.noreply.github.com`) whose login case-insensitively matches cla.yml'"'"'s `allowlist:` (read at origin/main) or cla-signatures `signedContributors[].name`; a pinned CLA-allowlisted email; or `noreply@github.com` in the committer slot only. Rosters are read at remote-tracking refs — if one changed recently, `git fetch origin` and retry.\n\nOffending commits (h author committer subject):\n" + $offenders + "\n\nRewrite the author/committer to your CLA-signed identity, then re-push:\n" + $fix)
    }
  }'
exit 0
