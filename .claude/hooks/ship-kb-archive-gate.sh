#!/usr/bin/env bash
# PreToolUse(Bash) hook: denies `gh pr merge` when the merge's head diff vs
# origin/main adds or modifies KB session artifacts that are not under an
# archive/ directory — knowledge-base/project/{specs/<dir>/**, plans/*,
# brainstorms/*}.
#
# wg-kb-artifacts-archived-in-pr — closes the #10064 class: ship Phase 6
# step 5.5's archive run was a numbered item inside the "If an open PR
# exists" arm, so an agent that wrote the PR body itself never ran it and
# the PR merged with its spec dir live on main. The skill-side fix (ship
# `## Phase 6.45: KB Artifact Archival`) makes archival a named phase;
# this hook is the mechanical check that proves it ran. `gh pr ready` is
# deliberately NOT gated: ready marks review-readiness, not publication —
# the merge is the leak event (ruling, decision-challenges).
#
# Contract-inherited PreToolUse(Bash) input shape (sibling-hook parity,
# ship-unpushed-commits-gate.sh):
#   .tool_input.command  (string) — the bash command string
#   .cwd                 (string) — absolute path to the working directory
#   .tool_name           ("Bash") — confirms matcher dispatched correctly
#
# Fail-open conditions (exit 0):
#   - hook input lacks .cwd or path is not an absolute existing directory
#   - not a git repository (git rev-parse --git-dir fails)
#   - HEAD-path merges only: not a work tree (bare repo), detached HEAD,
#     branch is main/master, branch refname fails validation, no
#     origin/<branch> exists (never pushed — gh has no head to merge),
#     or origin/<branch> does not rev-parse — HEAD is not the merge's
#     measured object in those states. A numbered `gh pr merge <N>` or
#     `--match-head-commit <sha>` resolves a pushed object and gates on
#     EVERY checkout state (soleur:schedule merges from a main checkout).
#   - proven-foreign repo pointer (-R/--repo/GH_REPO/GH_HOST resolving to
#     a DIFFERENT repository) — the merge is not ours
#   - HEAD-path merges only: an in-command cd into a non-repository
#     directory — gh fails there; numbered/sha/-R merges still resolve
#     and deny instead
#   - SOLEUR_SKIP_KB_ARCHIVE_GATE=1 (named in every deny)
#   - `gh pr merge --help`/`-h` merges nothing (every invocation carries
#     --help → exit 0; a real merge alongside one still gates)
#   - unresolvable merge-base (shallow clone) or a census diff that
#     cannot run: git cannot compare. Both warn via headless_or_stderr —
#     no fail-open path is silent.
#
# Fail-closed conditions (deny + emit_incident):
#   - unresolvable merge target: the command names a target the resolver
#     cannot uniquely prove (mixed numbers, non-bare positional, foreign
#     cd, unprovable repo pointer, raw-vs-scan disagreement). A HEAD
#     fallback would mismeasure the object this gate exists to census —
#     simultaneously a false-pass and a false-deny.
#   - git fetch fails (origin main, refs/pull/<N>/head, or the pinned
#     sha): an unverifiable head is the silent-miss class this gate
#     exists to end.
#   - any added, modified, type-changed, or renamed-in (R/C dst) row at a
#     non-archive path under the three KB roots in
#     merge-base...head.
#
# The documented arm form (CTO rulings F3/G1/G2, 2026-11-28; #12697,
# #12963). Rule (i) admits one bare PR number beside one
# `--match-head-commit` whose operand is a literal 40-hex (censused as that
# sha) or one double-quoted simple expansion — "$H", "${H}", "${H:?msg}" —
# as the invocation's last argument (the PR head censused by number). Rule
# (ii) admits several invocations only as EXACTLY two byte-identical
# numbered copies (raw residues, stripped residues and raw operands) whose
# lead is empty or `bash "$SS_LIB" with_lock merge-main <N> --`, with
# nothing between them but the if/else skeleton (an allowlist): the
# locked/degrade-open if/else every skill documents. Residuals:
#   - restrict-only argument: `--match-head-commit` can only RESTRICT a
#     merge, so every merge the new form admits is one the already-admitted
#     `gh pr merge <N> --squash --auto` admits too — the census reads the PR
#     head at invoke time and `--auto` merges a later head either way;
#   - quoted-operand catch: a merge nested inside the quoted operand
#     (`"$(gh pr merge 999 …)"`) is caught because strip_command_bodies
#     blanks double-quoted spans while `_cmd_args` keeps them, so the raw
#     and stripped invocation sets disagree and the token comparison denies;
#   - census-vs-H window (stated, not fixed): with a variable sha the
#     census reads the PR head by number at hook time, BEFORE the command
#     runs, and `H` is read later by the command itself. Anything that moves
#     the PR head in between lands a head the census did not read — another
#     session's push, or the command text itself: `git push -f origin
#     <sha>:<pr-branch> && H=<sha> && gh pr merge 7 --squash
#     --match-head-commit "$H"` is admitted while it merges a head the census
#     never saw. It is the window `gh pr merge <N> --squash --auto` already
#     has (and --auto merges a later head anyway); postmerge Phase 5.8 is the
#     backstop that catches the landed result. No deny is added for it;
#   - admin hatch: settle-then-admin-merge.md's `gh pr merge <N> --squash
#     --admin --match-head-commit "$SHA"` is admitted by rule (i). Its
#     `--admin` reach is gated by admin-merge-ready.sh exiting 0 immediately
#     before it; the KB census is orthogonal to that gate.
#
# Hook ordering: wired after ship-unpushed-commits-gate.sh in
# .claude/settings.json (itself after pre-merge-rebase.sh so auto-sync
# pushes land first). The hook mutates nothing — only fetches.

set -eo pipefail
# -u (nounset) omitted: hook failure paths must return JSON, not crash silently.

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input
# undefined, the hook dies at the call under `set -e`, prints nothing, exits
# non-zero, and the tool proceeds — defect 2 of #7164.
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[ship-kb-archive-gate] hook-input helper missing — guards did NOT run for this call" >&2
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
# Parse hook stdin WITHOUT shell evaluation (ADR-156: stdin is
# model-controlled and untrusted). ADR-157: a hook that cannot fully parse
# its input asks; the exit lives at the call site, not inside the library.
if ! hook_parse_input "$INPUT"; then
  hook_input_report "ship-kb-archive-gate"
  hook_input_should_ask && { hook_input_emit_ask "ship-kb-archive-gate"; exit 0; }
  exit 0
fi
CMD="$HOOK_CMD"
WORK_DIR="$HOOK_CWD"
: "${CMD:=}"
: "${WORK_DIR:=}"

# Deliberate one-keystroke repair for a wedged gate — named in every deny
# message (sibling parity: SOLEUR_SKIP_OPERATOR_STEP_GATE et al.).
if [[ "${SOLEUR_SKIP_KB_ARCHIVE_GATE:-}" == "1" ]]; then
  exit 0
fi

SCAN=$(strip_command_bodies "$CMD")

# Trigger boundary (ruling): the sibling's `(^|&&|\|\||;)` set widened per
# the review enumeration — `|` (x | gh pr merge), `\(` ($()/subshell),
# `` ` `` (backtick substitution), `\{` (brace-group body),
# `[[:space:]]--[[:space:]]` (the sanctioned `with_lock merge-main 600 --
# gh pr merge` arming form, #3689 class) plus a repeated invocation-prefix
# clause (env assignments, control/keyword words, and argument-taking
# launchers: `FOO=1 gh`, `time gh`, `timeout 60 gh`, `sudo -u root gh`,
# `env -i FOO=1 gh`, `xargs -t gh`). `_GH_GFLAGS` admits Cobra global
# flags between `gh` and `pr` (`gh -R o/r pr merge`, `gh --repo=x pr
# merge`) — a form the merge-args census cannot see, handled by the
# fail-closed global-flags arm below, never silently passed.
# `gh pr merge` ONLY — the sibling's `ready` alternation is deliberately
# not absorbed. Documented residuals, shared with every sibling: quoted
# `bash -c '…'` payloads (blanked by strip_command_bodies), `eval`
# indirection, `$GH` variable invocation, `gh api …/merge`, path-qualified
# `gh` (/usr/bin/gh), `\gh` alias-skip, `case`-branch merges, tokens split
# by line-continuation (`gh pr` + backslash-newline + `merge`), remote
# executors (`ssh host gh pr merge`), launcher binaries beyond the
# enumerated prefix list, partial-word quoting (`gh pr m"erge"` — a
# whole-WORD quote after `gh`/`pr` denies via the miss-arm detect; a
# mid-word quote slips), and function CALL SITES (`f() { gh pr merge; }`
# — the body now fires and denies; only a definition's `f` invocation
# slips, unprovable without executing the shell), UI merges, and the
# Monitor matcher (the whole merge-gate family is unbound there) — none
# fire; postmerge Phase 5.8 is the net. The census reads the head at
# invoke time but `--auto` merges the queue-time head — a post-arm push
# of live-path artifacts slips every gate in this family; Phase 5.8
# catches the landed result. The census is always against
# `merge-base(origin/main, head)`: a `gh pr merge <N>` whose PR targets
# a stacked feature branch rather than main inherits the parent branch's
# live-path rows into the deny — fail-closed (the hatch covers), because
# this repo's pipeline never ships a non-main base.
_MERGE_BOUNDARY='(^|&&|\|\||\||;|\(|`|\{|&|[[:space:]]--[[:space:]])'
# #10248: the rtk atom joins the first group's per-word alternation — the
# whole `rtk run …` chain consumes as ONE atom (its inner members span
# words), keeping this file's own env-asn/keyword/arg-launcher superset
# intact rather than narrowing it to the shared fragment. The
# `:-RTK_UNPROVISIONED_10248` default is a never-matching literal for the
# fail-soft arm, since the atom position cannot tolerate an empty
# expansion (it would match the empty string at every word boundary).
_MERGE_PREFIX='(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]&#|;()]+|if|while|until|then|do|elif|else|!|time|command|builtin|exec|nohup|'"${SOLEUR_RTK_RE:-RTK_UNPROVISIONED_10248}"')[[:space:]]+)*((sudo|env|timeout|nice|stdbuf|ionice|setsid|xargs|watch|flock|doas|pkexec)([[:space:]]+[^[:space:];&|()]+)*[[:space:]]+)?'
_GH_GFLAGS='([[:space:]]+--?[A-Za-z0-9-]+(=[^[:space:]]+)?([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'

# _deny is defined BEFORE the trigger check below because the miss arm can
# deny (quoted/IFS-split subcommand spellings the trigger cannot see).
_deny() {
  local reason="$1"
  emit_incident "wg-kb-artifacts-archived-in-pr" deny \
    "Archive KB artifacts into archive/ inside the" "$CMD"
  jq -n --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

if ! grep -qE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge([[:space:]]|$)" <<<"$SCAN"; then
  # Quoted or IFS-joined subcommand spellings — `gh pr 'merge'`,
  # `gh 'pr' merge`, `gh${IFS}pr${IFS}merge`, `gh pr${IFS}merge` —
  # survive strip_command_bodies only as blanks, so the trigger can
  # never see them while gh executes them fine. Deliberately narrow:
  # the quote or $-expansion must sit INSIDE the `gh…pr` tokens — a
  # fully-quoted `'gh pr merge'` documentation string has its quote
  # BEFORE `gh`, and `gh pr view --jq '.x'` has none inside the
  # subcommand tokens; both stay exempt. Partial-word quoting
  # (`gh pr m"erge"`) is a documented residual (see header).
  if grep -qE 'gh[[:space:]]*\$\{?IFS|gh[[:space:]]+pr[[:space:]]*\$|gh[[:space:]]+["'\''`][[:space:]]*pr|gh[[:space:]]+pr[[:space:]]+["'\''`]' <<<"$CMD"; then
    _deny "unparseable gh pr merge spelling (quoted or \${IFS}-split subcommand tokens) — re-invoke unquoted so the KB-archive census can run. Escape hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 (audited)."
  fi
  exit 0
fi

# One line per REAL `gh pr merge` invocation, carrying its post-`merge`
# argument text. The awk extracts after the FIRST `pr[ \t]+merge` in the
# line — a sed `s/^.*gh…//` would greedily strip to the LAST, and a
# residue containing a second literal (`gh pr merge 5 --subject gh pr
# merge`) would collapse a numbered merge onto the HEAD path. `$(`/`)`
# are excluded from the residue class so a nested `$(gh pr merge N)`
# surfaces as its own invocation line (the `(` boundary matches it) and
# the multi-invocation deny fires. Residues are then cleaned for the
# consumers below: `#`-comments dropped (a `# -R o/r` mention is text,
# never a pointer), `)`/`}`/backtick chars removed (`x=$(gh pr merge 5)`
# leaves `5)`), and redirect words (`> /tmp/log`, `>log`, `5>log`,
# `2>&1`, `< file`) removed — none are merge operands.
# `|| true`: a no-match grep exits 1 under pipefail and would abort the hook.
_merge_args() {
  grep -oE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|$\`()]*)?" <<<"$1" \
    | awk '{ match($0, /pr[[:space:]]+merge/); print substr($0, RSTART+RLENGTH) }' \
    | sed -E 's/#.*//' \
    | tr -d ')}\`' \
    | sed -E 's/[[:space:]][0-9]*[<>]+(&[0-9-]+)?([[:space:]]*[^[:space:]&|;()]+)?//g' || true
}
_scan_args=$(_merge_args "$SCAN")

# Help pass-through (#9454, verbatim semantics from pre-merge-rebase.sh):
# `gh pr merge --help` / `-h` merges nothing, so when EVERY invocation in
# the quote-stripped $SCAN carries an argument token exactly `--help` or
# `-h`, exit 0 now. Quoted text is blanked in $SCAN, so `--body "--help"`
# is not a help form; a single real merge anywhere keeps the hook running.
# No invocation parsed → no skip. A trailing shell comment is cut first.
if [[ -n "$_scan_args" ]] \
   && awk '{ sub(/[[:space:]]#.*$/, "") } $0 !~ /(^|[[:space:]])(--help|-h)([[:space:]]|$)/ { bad = 1 } END { exit bad }' <<<"$_scan_args"; then
  exit 0
fi

# Validate WORK_DIR: absolute path AND existing directory. Defense against
# argument injection — `git -C "-x"` would treat the arg as a flag (CWE-88).
if [[ "$WORK_DIR" != /* ]] || [[ ! -d "$WORK_DIR" ]]; then
  exit 0
fi
# `rev-parse --git-dir`, NOT --is-inside-work-tree (ruling): a bare repo
# must still reach the numbered-resolution path — only the HEAD path needs
# a work tree.
if ! git -C "$WORK_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  exit 0
fi

# --- begin verbatim import -------------------------------------------------
# The five helpers below are copied byte-for-byte from
# .claude/hooks/pre-merge-rebase.sh (#8778/#9401 resolver) and are pinned
# byte-equal by ship-kb-archive-gate.test.sh's parity case, per the repo's
# copied-helper convention (assert_fixture_dir precedent). Do not reword
# one side only — a hand-edited copy reintroduces the #8778 false-pass /
# false-deny pair the source absorbed two shipped fixes for. If the source
# changes, re-copy.
#
# _merge_args above is a documented exception: its boundary alternation is
# widened per the trigger ruling, so the parity pin diffs the five helpers
# below only.

# _repo_url_parts <url-or-operand> → "host<TAB>owner/repo" lowercased, or a
# blank pair when unparseable. Covers https://h/o/r(.git), ssh://[u@]h[:p]/o/r,
# scp-style [u@]h:o/r, a HOST/o/r operand, and a bare o/r (empty host).
_repo_url_parts() {
  local u="$1" host="" slug="" rest=""
  case "$u" in
    *://*)  rest="${u#*://}"
            [[ "$rest" == */* ]] || { printf '\t\n'; return; }
            host="${rest%%/*}"; slug="${rest#*/}" ;;
    *:*/*)  host="${u%%:*}"; slug="${u#*:}" ;;   # scp-style [user@]host:o/r
    */*/*)  host="${u%%/*}"; slug="${u#*/}" ;;   # HOST/OWNER/REPO operand
    */*)    slug="$u" ;;                         # bare OWNER/REPO
    *)      printf '\t\n'; return ;;
  esac
  host="${host##*@}"; host="${host%%:*}"
  slug="${slug%/}"; slug="${slug%.git}"
  [[ -n "$slug" && "$slug" == */* && "$slug" != */*/* ]] || { host=""; slug=""; }
  # tr, not ${x,,} — bash 4 case-folding is a parse error on stock macOS bash
  # 3.2 (repo convention; the failure would silently dead-code the -R arm).
  printf '%s\t%s\n' "$host" "$slug" | tr '[:upper:]' '[:lower:]'
}

# _repo_flag_operands — one "R<tab><operand>" line per -R/--repo sighting in a
# `_merge_args` residue, "F" for a flag form that names no operand. Only the
# token shapes the deny arm's regex recognises are emitted; anything else is
# left for the bare-number arm below.
# The -R/--repo token grammar is enumerated in THREE places that must drift
# together: the sighting regex (the `_REPO_PTR` grep below), this extractor,
# and _strip_repo_flags. Drift fails closed (an unproven form is denied), but
# keep them aligned.
_repo_flag_operands() {
  awk '{
    for (i = 1; i <= NF; i++) {
      t = $i
      if (t == "-R" || t == "--repo") {
        if (i < NF) { print "R\t" $(i+1); i++ } else { print "F" }
      } else if (t ~ /^--repo=/) {
        print "R\t" substr(t, 8)   # empty operand parses to nothing → refuse
      } else if (t ~ /^-[A-Za-z]*R$/) {            # bundled short form: -dR, -sR
        if (i < NF) { print "R\t" $(i+1); i++ } else { print "F" }
      } else if (t ~ /^-[A-Za-z]*R./) {            # attached operand: -Ro/r
        print "R\t" substr(t, index(t, "R") + 1)
      }
    }
  }'
}

# _repo_env_operands <text> — "R<tab><v>" per GH_REPO=, "H<tab><v>" per
# GH_HOST= assignment, the same anchored shapes the deny arm scans for.
_repo_env_operands() {
  local _t=$'\t'
  # The value ends at whitespace OR a command separator — an unquoted `;`/`&`/`|`
  # belongs to the shell, not the assignment (`export GH_REPO=o/r; gh pr merge`).
  # NOTE: this scans the RAW command too, so a quoted `GH_REPO=` mention (text
  # that never executes) fails the same-repo proof → deny. Fail-closed, low
  # rate — the pre-change posture for any env sighting was also deny.
  grep -oE '(^|[^A-Za-z0-9_])GH_(REPO|HOST)=[^[:space:];&|]*' <<<"$1" \
    | sed -E "s/^[^A-Za-z0-9_]?GH_REPO=/R${_t}/; s/^[^A-Za-z0-9_]?GH_HOST=/H${_t}/" || true
}

# _repo_pointers_same_repo — 0 iff EVERY repo-pointer operand in both arg
# residues and both raw/scan texts resolves to this checkout's origin repo.
# Reads ambient state ($_scan_args, $_cmd_args, $SCAN, $CMD, $WORK_DIR) — the
# caller must set those before invoking.
# Hostless operands (o/r, HOST/owner/repo handled above) resolve against
# GH_HOST= when set — gh's documented override — else gh's default github.com.
_repo_pointers_same_repo() {
  local _oparts _ohost _oslug _ops _gh_host _bad=0
  # Ambient env counts as operands: gh honors GH_HOST/GH_REPO exported in the
  # session env even when the command text carries none, so a hostless -R or a
  # flagless merge is steered by them. Seeding the proof from them keeps both
  # directions honest (a foreign ambient host → deny; a matching ambient host
  # lets a hostless operand prove same-repo on a GHE checkout).
  _gh_host="${GH_HOST:-}"
  # config --get, NOT remote get-url: get-url resolves url.insteadOf rewrites,
  # collapsing distinct configured URLs onto their rewrite targets — the raw
  # configured URL is what identifies the repository gh would act on.
  _oparts=$(_repo_url_parts "$(git -C "$WORK_DIR" config --get remote.origin.url 2>/dev/null || true)")
  _ohost="${_oparts%%$'\t'*}"; _oslug="${_oparts#*$'\t'}"
  [[ -n "$_oslug" ]] || return 1   # local-path or unparseable origin proves nothing
  _ops=$({ _repo_flag_operands <<<"$_scan_args"; _repo_flag_operands <<<"$_cmd_args"
          _repo_env_operands "$SCAN"; _repo_env_operands "$CMD"
          [[ -n "${GH_REPO:-}" ]] && printf 'R\t%s\n' "$GH_REPO"
          [[ -n "${GH_HOST:-}" ]] && printf 'H\t%s\n' "$GH_HOST"; :; } ) || _ops=""
  [[ -n "$_ops" ]] || return 1
  local _k _op _h _pp _ph _ps
  while IFS=$'\t' read -r _k _op; do
    [[ "$_k" == "H" ]] || continue
    _h="${_op#*://}"; _h="${_h%%/*}"; _h="${_h%%:*}"
    _h=$(printf '%s' "$_h" | tr '[:upper:]' '[:lower:]')
    [[ -n "$_h" && "$_h" == "$_ohost" ]] || _bad=1
    _gh_host="$_h"
  done <<<"$_ops"
  while IFS=$'\t' read -r _k _op; do
    case "$_k" in
      H) : ;;   # judged above
      F) _bad=1 ;;   # a flag without its operand cannot be verified
      R) _pp=$(_repo_url_parts "$_op"); _ph="${_pp%%$'\t'*}"; _ps="${_pp#*$'\t'}"
         if [[ -z "$_ps" || "$_ps" != "$_oslug" ]] \
            || [[ -n "$_ph" && "$_ph" != "$_ohost" ]] \
            || [[ -z "$_ph" && "${_gh_host:-github.com}" != "$_ohost" ]]; then
           _bad=1
         fi ;;
    esac
  done <<<"$_ops"
  [[ "$_bad" == "0" ]]
}

# _strip_repo_flags — drop every -R/--repo token(+operand) from a `_merge_args`
# residue. Runs ONLY after _repo_pointers_same_repo proved every operand
# same-repo; a residue it cannot clean must never reach the checks below.
# Shape table mirrors _repo_flag_operands and the sighting regex — see the
# cross-reference comment there.
_strip_repo_flags() {
  awk '{
    out = ""
    for (i = 1; i <= NF; i++) {
      t = $i
      if (t == "-R" || t == "--repo" || t ~ /^-[A-Za-z]*R$/) { i++; continue }
      if (t ~ /^--repo=/ || t ~ /^-[A-Za-z]*R./) continue
      out = out (out == "" ? "" : " ") t
    }
    print out
  }'
}
# --- end verbatim import ---------------------------------------------------

# _repo_pointers_all_parsed — 0 iff at least one repo-pointer operand was
# sighted AND every sighted operand parses to a concrete (host, slug) pair.
# SCAN-SIDE operands only ($_ptr_args + $_inv_prefixes + ambient env) —
# a `-R`/`GH_REPO=` inside a comment or quoted span is text that never
# executes, and admitting it as an operand turned the proven-foreign arm
# into a silent false-pass (`gh pr merge 42 # -R other/repo` → exit 0).
# Used with _repo_pointers_same_repo to discriminate "unprovable" (some
# operand unparseable or flag-without-operand → deny) from "proven
# foreign" (every operand parses and the set is not all-same-repo → exit
# 0, the merge is not ours).
_repo_pointers_all_parsed() {
  local _ops _k _op _pp _ps _have=0
  _ops=$({ _repo_flag_operands <<<"$_ptr_args"
          _repo_env_operands "$_inv_prefixes"
          [[ -n "${GH_REPO:-}" ]] && printf 'R\t%s\n' "$GH_REPO"
          [[ -n "${GH_HOST:-}" ]] && printf 'H\t%s\n' "$GH_HOST"; :; } ) || _ops=""
  [[ -n "$_ops" ]] || return 1
  while IFS=$'\t' read -r _k _op; do
    case "$_k" in
      F) return 1 ;;
      H) _have=1
         [[ -n "${_op#*://}" ]] || return 1 ;;
      R) _have=1
         _pp=$(_repo_url_parts "$_op"); _ps="${_pp#*$'\t'}"
         [[ -n "$_ps" ]] || return 1 ;;
    esac
  done <<<"$_ops"
  [[ "$_have" == "1" ]]
}

_cmd_args=$(_merge_args "$CMD")
# Comments out of the env-pointer gather — `_repo_env_operands` scans the
# whole text, and `# GH_REPO=o/r` must never count as a sighted operand.
SCAN_NOCOMMENT=$(sed 's/#.*//' <<<"$SCAN")

# Pointer-sighting inputs (CTO ruling G1, 2026-11-28). Both only ever SHRINK
# what can prove a merge foreign, so each turns an exit 0 into a census:
#   (b) an env pointer counts only in an invocation's OWN prefix — the text
#       between its command boundary and `gh` (`GH_REPO=o/r gh pr merge`,
#       `env GH_HOST=h gh pr merge`). `; : GH_HOST=evil.example` or
#       `&& echo GH_REPO=o/r` points gh nowhere and took the foreign exit.
#       An `export GH_REPO=…;` earlier in the command is no longer a pointer
#       either: the merge is then censused as this checkout's, which can
#       only deny (gh acting on another repository is not this gate's object).
#   (c) a `-R…` token that is the VALUE of a value-taking flag is text:
#       `--body -Ro/r` read as a foreign pointer and exited 0. gh (pflag)
#       hands a value-taking flag its value in four spellings, and each is
#       dropped here: spaced (`-b V`, `--body V`), attached (`-bV`), a short
#       bundle that ENDS in the flag (`-sb V`, `-db V`) or carries the value
#       attached after it (`-sbV`), and `--body=V`. The value-taking flags
#       are every one `gh pr merge --help` lists: -t/--subject, -b/--body,
#       -F/--body-file, -A/--author-email, --match-head-commit. A bundle is
#       walked left to right over the boolean shorthands (-d/-m/-r/-s/-h);
#       it stops, keeping the token as a pointer, at `R`, and keeps it
#       untouched at `=` or any other character.
# _drop_flag_values strips those values from a residue copy used ONLY for
# sighting and gathering; the residues themselves are untouched.
_drop_flag_values() {
  awk '{
    out = ""
    for (i = 1; i <= NF; i++) {
      t = $i
      if (t == "--subject" || t == "--body" || t == "--body-file" \
          || t == "--author-email" || t == "--match-head-commit") { i++; continue }
      if (t ~ /^--(subject|body|body-file|author-email|match-head-commit)=/) continue
      if (t ~ /^-[^-]/) {
        drop = 0
        for (j = 2; j <= length(t); j++) {
          c = substr(t, j, 1)
          if (index("tbFA", c)) { drop = (j < length(t)) ? 1 : 2; break }
          if (!index("dmrsh", c) || substr(t, j + 1, 1) == "=") break
        }
        if (drop == 2) i++
        if (drop) continue
      }
      out = out (out == "" ? "" : " ") t
    }
    print out
  }'
}
_ptr_args=$(_drop_flag_values <<<"$_scan_args")
_inv_prefixes=$(grep -oE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge" <<<"$SCAN_NOCOMMENT" \
                | awk '{ match($0, /pr[[:space:]]+merge/); print substr($0, 1, RSTART - 1) }' || true)

_REPO_PTR=0
_REPO_SAME=0
# Sighting regex — third member of the -R grammar triple (see
# _repo_flag_operands). SCAN-SIDE only: a `-R`/`GH_REPO=` inside quoted or
# comment text is a mention, not a pointer (the proven-foreign arm's
# exit-0 makes raw-text sightings false-PASSES, not just false-denies).
if grep -qE '(^|[[:space:]])(--repo([[:space:]=]|$)|-[A-Za-z]*R)' <<<"$_ptr_args" \
   || grep -qE '(^|[^A-Za-z0-9_])GH_(REPO|HOST)=' <<<"$_inv_prefixes"; then
  _REPO_PTR=1
  # Subshell-rebind the ambient vars the pinned body gathers from —
  # $CMD/$SCAN (env operands, here the invocations' own prefixes),
  # $_scan_args (flag operands, here with message-flag values dropped) AND
  # $_cmd_args (raw-side flag operands, which carries quoted `-R` mentions:
  # `gh pr merge -R jikig-ai/soleur 5 --body "-R other/repo"` would
  # otherwise read as a mixed pointer set and exit 0 on a same-repo merge).
  # Its body stays byte-equal to pre-merge-rebase.sh's for the T43 parity
  # pin; if the source helper ever gathers from a fifth ambient variable,
  # the parity pin re-copies the body and this rebind MUST be extended.
  ( CMD="$_inv_prefixes"; SCAN="$_inv_prefixes"; _scan_args="$_ptr_args"; _cmd_args=""; _repo_pointers_same_repo ) && _REPO_SAME=1
fi
if [[ "$_REPO_SAME" == "1" ]]; then
  _scan_args=$(_strip_repo_flags <<<"$_scan_args")
  _cmd_args=$(_strip_repo_flags <<<"$_cmd_args")
fi

# Which head is being merged. Every REAL `gh pr merge` invocation is parsed
# with the detector's own anchor, in BOTH $SCAN (quoted text blanked) and
# $CMD (raw): a number must survive quote-stripping unchanged (`877"9"`
# strips to `877`), and text that merely mentions `gh pr merge 1` (an
# `echo`, a comment) is not an invocation.
_tok_scan=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_scan_args" || true)
_tok_cmd=$(awk '{ print ($1 == "" ? "-" : $1) }' <<<"$_cmd_args" || true)
MERGE_TARGET_WHY=""
TARGET_KIND=""       # sha | pr | head
PR_HEAD_NUMBER=""
HEAD_OID=""

# Cobra global flags between `gh` and `pr` (`gh -R o/r pr merge`, `gh
# --hostname ghe pr merge`, `gh --verbose pr merge`) are valid syntax the
# merge-args residue never sees — the repo-pointer census cannot prove
# them, and stripping them would silently gate on THIS repo while gh
# merges ANOTHER. Fail-closed: deny and name the canonical
# `gh pr merge [-R owner/repo]` form. The detect requires a `-`-leading
# token right after `gh` — `gh pr merge` itself never matches — and runs
# on SCAN_NOCOMMENT so a `# gh -R o/r pr merge` mention cannot deny.
if grep -qE 'gh[[:space:]]+-[^[:space:];&|()]+([[:space:]]+[^[:space:];&|()]+)*[[:space:]]+pr[[:space:]]+merge' <<<"$SCAN_NOCOMMENT"; then
  MERGE_TARGET_WHY="global flags between 'gh' and 'pr' cannot be verified — spell it 'gh pr merge [-R owner/repo] <N>'"
fi

# xargs feeds the merge operand via stdin — invisible to the residue.
# `echo 5 | xargs gh pr merge` would read flag-only and census the HEAD
# path while gh merges a NUMBERED PR: deny the composition outright.
if [[ -z "$MERGE_TARGET_WHY" ]] \
   && grep -qE 'xargs([[:space:]]+[^[:space:];&|()]+)*[[:space:]]+gh([[:space:]]+[^[:space:];&|()]+)*[[:space:]]+pr[[:space:]]+merge' <<<"$SCAN_NOCOMMENT"; then
  MERGE_TARGET_WHY="xargs supplies the merge's operand via stdin; spell the PR number on the command line ('gh pr merge <N>')"
fi

# Operand-loss deny: a `$`/`~`-leading TOKEN in the raw invocation text
# is an operand the resolver cannot prove (`gh pr merge $PR_NUM` reads
# flag-only after the `$`-exclusion and would miscensus the HEAD path).
# Leading-token only — a `>$f` redirect target or `--subject=$(date)`
# inside a flag value does not trip it; `$(…)` still surfaces as its own
# invocation via the `(` boundary. Checked on the RAW match text — the
# residue class itself drops the `$`.
_operand_hits=$(grep -oE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|]*)?" <<<"$SCAN_NOCOMMENT" || true)
if [[ -z "$MERGE_TARGET_WHY" ]] \
   && grep -qE '[[:space:]][$~]' <<<"$_operand_hits"; then
  MERGE_TARGET_WHY="the merge operand is a variable or home path the hook cannot resolve; spell the PR number literally ('gh pr merge <N>')"
fi

# Invocation counts, taken on the _merge_args PIPE rather than on the
# captured residues: `$(…)` drops trailing newlines, so a trailing arg-less
# invocation (`gh pr merge 5 && gh pr merge`) vanished from
# `wc -l <<<"$_scan_args"` and the bare HEAD-path merge went uncensused.
# Rule (ii) below denies whenever these disagree with the captured residues.
_n_scan=$(_merge_args "$SCAN" | wc -l | tr -d ' ')
_n_cmd=$(_merge_args "$CMD" | wc -l | tr -d ' ')

# Raw-invocation reader (rules (i) and (ii), CTO ruling F3). The residues
# stop at `$`, so for the documented arm (`--match-head-commit "${H:?…}"`)
# both `_scan_args` and `_cmd_args` end `--match-head-commit "` and never
# hold the operand. This reads it from the raw text, at EACH invocation's
# own byte offset (an `echo --match-head-commit "$H"` decoy or a `#`
# comment elsewhere cannot supply it), with the residue regex itself
# locating the invocations. `$_inv_j` is $CMD with every backslash-newline
# replaced by two spaces (byte offsets kept), so an invocation continued
# from `with_lock … -- \` shows its real prefix. One record per invocation,
# four lines each:
#   lead     — the text on its (joined) line before `gh`
#   operand  — `"<rest of the line>` when the residue ends at a
#              `--match-head-commit "` followed by `$`, else `-`
#   tail     — the rest of its (joined) line after the residue
#   gap      — `ok`, or `!<first offending line>`: the RAW lines strictly
#              between the previous invocation's line and this one's, judged
#              against rule (ii)'s skeleton allowlist (`-` for the first).
#              Read from the raw $CMD at the same offsets (the join keeps
#              them), so a comment ending in a backslash cannot swallow the
#              line after it.
# LC_ALL=C: grep -b counts bytes, so the awk must too.
_inv_j=${CMD//$'\\\n'/  }
_inv_hits=$(grep -boE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge([[:space:]][^;&|$\`()]*)?" <<<"$_inv_j" || true)
_inv_spec=""
while IFS= read -r _h; do
  [[ -n "$_h" ]] || continue
  _inv_spec+="${_h%%:*}:$(printf '%s' "${_h#*:}" | LC_ALL=C wc -c | tr -d ' ') "
done <<<"$_inv_hits"
# Rule (ii)'s skeleton allowlist — the only lines the documented
# locked/degrade-open if/else (ship, merge-pr, product-roadmap) carries
# between its two copies: blank, a `#` comment, `rc=$?`, `else`, `then`,
# `fi`, and the degrade-open echo. The `if … flock …; then` opener sits
# BEFORE the first copy in every documented block, so it is not admitted
# here. Anything else — `cd`, `pushd`, `export GH_REPO=…`, `H=<sha>`,
# `git push`, an alias or function — could steer the second copy.
_inv_reads=$(printf '%s' "$_inv_j" | _INV_RAW="$CMD" LC_ALL=C awk -v hits="$_inv_spec" '
  function gap(a, b,    g, L, q, x, v) {
    if (b <= a) return "ok"
    g = substr(ENVIRON["_INV_RAW"], a, b - a); v = "ok"
    q = split(g, L, "\n")
    for (x = 1; x <= q; x++) {
      if (L[x] ~ /^[ \t]*(#.*|rc=\$\?|else|then|fi|echo "SOLEUR_SESSION_STATE_UNAVAILABLE path=\$SS_LIB reason=running-unlocked")?[ \t]*$/) continue
      v = "!" substr(L[x], 1, 80); break
    }
    return v
  }
  { s = s $0 "\n" }
  END {
    n = split(hits, H, " "); pe = 0
    for (k = 1; k <= n; k++) {
      split(H[k], P, ":"); o = P[1] + 0; l = P[2] + 0
      ls = o; while (ls > 0 && substr(s, ls, 1) != "\n") ls--
      m = substr(s, o + 1, l); head = m
      if (match(m, /pr[[:space:]]+merge/)) head = substr(m, 1, RSTART - 1)
      sub(/gh[[:space:]]+$/, "", head)
      r = substr(s, o + l + 1); e = index(r, "\n"); if (e) r = substr(r, 1, e - 1)
      print substr(s, ls + 1, o - ls) head
      print (m ~ /[[:space:]]--match-head-commit[[:space:]]+"$/ ? "\"" r : "-")
      print r
      print (k == 1 ? "-" : gap(pe + 1, ls))
      pe = o + l + (e ? e : length(r) + 1)
    }
  }' || true)
# The operand shapes rule (i) admits, anchored at both ends: exactly one
# double-quoted simple expansion — "$NAME", "${NAME}" or "${NAME:?msg}" —
# then the end of the shell word. NAME excludes every special parameter
# (`$@`, `$*`, `$1`, `$!`, `$#`) and every indirect/array/length form
# (`${!N}`, `${A[@]}`, `${#H}`); msg excludes `$`, backtick, `(`, `)`, `\`,
# `"`, `}` (no substitution can hide in it); a default (`${H:-…}`) or a
# second expansion (`"$H$G"`) does not match.
_MHC_VAR_RE='^("\$[A-Za-z_][A-Za-z0-9_]*"|"\$\{[A-Za-z_][A-Za-z0-9_]*\}"|"\$\{[A-Za-z_][A-Za-z0-9_]*:\?[^$`()\\"}]*\}")([[:space:];&|)]|$)'
_inv_leads=""
_inv_ops=""
_inv_tails=""   # per record: the line's text after the operand (or residue)
_inv_gaps=""    # per record: the gap verdict (see the reader above)
_inv_n=0
while IFS= read -r _lead && IFS= read -r _op && IFS= read -r _tail && IFS= read -r _gap; do
  _inv_n=$((_inv_n + 1))
  _inv_leads+="${_lead}"$'\n'
  _inv_gaps+="${_gap}"$'\n'
  if [[ "$_op" == "-" ]]; then
    _inv_ops+="-"$'\n'
    _inv_tails+="${_tail}"$'\n'
  elif [[ "$_op" =~ $_MHC_VAR_RE ]]; then
    _inv_ops+="${BASH_REMATCH[1]}"$'\n'
    _inv_tails+="${_op:${#BASH_REMATCH[1]}}"$'\n'
  else
    _inv_ops+="!${_op}"$'\n'   # a `$`-operand outside the admitted shapes
    _inv_tails+="!"$'\n'
  fi
done <<<"$_inv_reads"
# The reader must see exactly the invocations the residues see; a mismatch
# (a continuation that joins or hides one) leaves every record unproven.
[[ "$_inv_n" == "$_n_cmd" ]] || { _inv_ops="!"$'\n'; _inv_leads="!"$'\n'; _inv_tails="!"$'\n'; _inv_gaps="!"$'\n'; }

# Rule (ii) — several invocations, in place of the old blanket
# multi-invocation deny (one census object per command). More than one
# `gh pr merge` is admitted only as the documented locked/degrade-open
# if/else, censused as ONE object, when ALL of these hold:
#   - no repository pointer that is not proven same-repo (G1 a: several
#     invocations never reach the proven-foreign exit below, so a foreign
#     `-R` on one cannot launder an uncensused other);
#   - the raw and stripped residue counts agree, and every raw residue
#     (quotes kept) and every stripped residue is byte-identical — a merge
#     nested in a quoted operand surfaces on the raw side only;
#   - each residue starts with a bare PR number: the HEAD path is mutable
#     between two invocations (`git checkout x` between them), a number is not;
#   - each invocation's lead is empty (it starts its line, e.g. after an
#     `else` line) or exactly `bash "$SS_LIB" with_lock merge-main <N> --`:
#     an env-assignment or launcher prefix (`GH_REPO=o/r`, `GIT_DIR=`,
#     `env -C`) is invisible to the residues and could steer one copy;
#   - every raw --match-head-commit operand is byte-identical (the residues
#     are cut at `$` and cannot see it);
#   - there are EXACTLY two invocations (the if/else has two arms), the
#     first copy's line ends at its operand (or residue), and every raw line
#     strictly between the two copies is on the skeleton allowlist (see the
#     reader above). Byte-identical copies are not one object on their own:
#     `cd /other-repo`, `export GH_REPO=…` or `H=<other-sha>` between them
#     makes copy 2 merge something else.
# Anything else keeps the deny (counts: see _n_scan above).
_LOCK_LEAD_RE='^[[:space:]]*bash[[:space:]]+"\$SS_LIB"[[:space:]]+with_lock[[:space:]]+merge-main[[:space:]]+[0-9]+[[:space:]]+--[[:space:]]+$'
_MULTI_WHY="more than one gh pr merge invocation in one command; merge one PR per call"
# Triggered on the SCAN side, as the arm it replaces was: a raw-only extra
# invocation (a merge inside quoted text) falls to the token deny below.
if [[ -z "$MERGE_TARGET_WHY" ]] && [[ "$_n_scan" -gt 1 ]]; then
  _several_why=""
  _counts_ok=1
  [[ "$_n_scan" == "$_n_cmd" ]] || _counts_ok=0
  [[ "$_n_scan" == "$(wc -l <<<"$_scan_args" | tr -d ' ')" ]] || _counts_ok=0
  [[ "$_n_cmd" == "$(wc -l <<<"$_cmd_args" | tr -d ' ')" ]] || _counts_ok=0
  if [[ "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]]; then
    _several_why="a repository pointer (-R/--repo, GH_REPO or GH_HOST) beside several gh pr merge invocations; merge one PR per call"
  elif [[ "$_n_scan" -gt 2 || "$_n_cmd" -gt 2 ]]; then
    _several_why="more than one gh pr merge invocation in one command, and more than the two copies the locked/degrade-open if/else carries; merge one PR per call"
  elif [[ "$_counts_ok" != "1" ]] \
       || [[ "$(sort -u <<<"$_cmd_args" | wc -l)" -ne 1 ]] \
       || [[ "$(sort -u <<<"$_scan_args" | wc -l)" -ne 1 ]] \
       || [[ ! "$(awk '{ print $1 }' <<<"$_scan_args" | sort -u)" =~ ^[0-9]{1,9}$ ]]; then
    _several_why="$_MULTI_WHY"
  else
    while IFS= read -r _lead; do
      [[ "$_lead" =~ ^[[:space:]]*$ || "$_lead" =~ $_LOCK_LEAD_RE ]] && continue
      _several_why="$_MULTI_WHY"
      break
    done < <(printf '%s' "$_inv_leads")
    if [[ -z "$_several_why" && "$(printf '%s' "$_inv_ops" | sort -u | wc -l)" -ne 1 ]]; then
      _several_why="more than one gh pr merge invocation in one command and their --match-head-commit operands differ; merge one PR per call"
    fi
    _first_tail=$(head -n 1 <<<"$_inv_tails")
    _last_gap=$(sed -n '2p' <<<"$_inv_gaps")
    if [[ -z "$_several_why" && ! "$_first_tail" =~ ^[[:space:]]*$ ]]; then
      _several_why="more than one gh pr merge invocation in one command, and the first copy's line continues past its operand ('${_first_tail:0:60}'); end that line at the operand, as the documented if/else does"
    elif [[ -z "$_several_why" && "$_last_gap" != "ok" ]]; then
      _several_why="more than one gh pr merge invocation in one command, and the text between the two copies is not the documented locked/degrade-open if/else skeleton (only blank, '#' comment, 'rc=\$?', 'then', 'else', 'fi' and the SOLEUR_SESSION_STATE_UNAVAILABLE echo may sit between them; found '${_last_gap#!}'); merge one PR per call"
    fi
  fi
  [[ -z "$_several_why" ]] || MERGE_TARGET_WHY="$_several_why"
fi

# Proven-foreign exit — AFTER rule (ii) above (a `-R
# other/repo` on invocation 1 must not launder an uncensused invocation
# 2) but BEFORE the positional census (a foreign `-R`'s operand is a
# non-numeric positional that would falsely deny an exit-0 merge).
if [[ -z "$MERGE_TARGET_WHY" && "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]] && _repo_pointers_all_parsed; then
  # Every pointer parses and the set is not all-same-repo → the merge
  # targets another repository. Not ours to census (ruling:
  # proven-foreign exits 0; unprovable is the deny arm below).
  exit 0
fi

if [[ -z "$MERGE_TARGET_WHY" && "$_tok_scan" != "$_tok_cmd" ]]; then
  MERGE_TARGET_WHY="the gh pr merge invocations differ once quoted text is removed"
fi

# --match-head-commit <40-hex> (the admin hatch's exact merged sha) takes
# precedence when present; a flag sighted without a valid operand denies.
_mhc_scan=$(grep -oE -- '--match-head-commit([[:space:]]+|=)[0-9a-f]{40}([^0-9a-f]|$)' <<<"$_scan_args" \
            | grep -oE '[0-9a-f]{40}' | sort -u || true)
_mhc_cmd=$(grep -oE -- '--match-head-commit([[:space:]]+|=)[0-9a-f]{40}([^0-9a-f]|$)' <<<"$_cmd_args" \
            | grep -oE '[0-9a-f]{40}' | sort -u || true)
# Rule (i) (CTO ruling F3): one literal bare PR number (`^[0-9]{1,9}$`, so
# a 40-digit sha is never read as a number) as the FIRST token, beside
# exactly one --match-head-commit:
#   - a literal 40-hex operand → census that sha, as before;
#   - one double-quoted simple expansion ($_MHC_VAR_RE, read raw by the
#     invocation reader above) → census the PR head BY NUMBER. Nothing may
#     follow the operand in the residue (the quote span is blanked in
#     $SCAN, so the flag must be the residue's last token), the command's
#     comment-free raw --match-head-commit count must equal its invocation
#     count, and a nameref (`declare/local/typeset -n`) anywhere denies: it
#     makes a plain "$H" evaluate its target's subscript, which can run a
#     command substitution.
# Several invocations reach this only as rule (ii)'s identical copies, so
# the first residue and the first operand stand for all of them.
_r1_first=$(awk 'NR == 1 { print $1 }' <<<"$_scan_args")
_r1_rest=$(awk 'NR == 1 { for (i = 2; i <= NF; i++) print $i }' <<<"$_scan_args")
if [[ -z "$MERGE_TARGET_WHY" ]]; then
  if [[ "$_mhc_scan" != "$_mhc_cmd" ]]; then
    MERGE_TARGET_WHY="the gh pr merge invocations differ once quoted text is removed"
  elif [[ -n "$_mhc_scan" ]] && [[ "$(grep -c . <<<"$_mhc_scan" || true)" != "1" ]]; then
    MERGE_TARGET_WHY="more than one --match-head-commit sha; merge one PR per command"
  elif [[ -n "$_mhc_scan" ]]; then
    _mhc_extra=$(printf '%s\n' "$_scan_args" \
                  | sed -E 's/--match-head-commit([[:space:]]+|=)[0-9a-f]{40}/ /g' \
                  | awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^-/) print $i }' | sort -u || true)
    if [[ -z "$_mhc_extra" ]]; then
      TARGET_KIND="sha"; HEAD_OID="$_mhc_scan"
    elif [[ "$_mhc_extra" == "$_r1_first" && "$_r1_first" =~ ^[0-9]{1,9}$ ]]; then
      TARGET_KIND="sha"; HEAD_OID="$_mhc_scan"
    elif [[ "$_mhc_extra" == "$_r1_first" ]]; then
      MERGE_TARGET_WHY="the positional beside --match-head-commit is not a bare PR number"
    else
      MERGE_TARGET_WHY="extra operands alongside --match-head-commit"
    fi
  elif grep -q -- '--match-head-commit' <<<"$_scan_args"; then
    _r1_op=$(head -n 1 <<<"$_inv_ops")
    if [[ "$_r1_op" == "-" ]] && grep -qE -- '--match-head-commit=([[:space:]]|$)' <<<"$_scan_args"; then
      MERGE_TARGET_WHY="a --match-head-commit=<variable> spelling names no 40-hex sha; a variable operand needs the space-separated spelling (--match-head-commit \"\$H\")"
    elif [[ "$_r1_op" == "-" || "$_r1_op" == '!'* ]]; then
      MERGE_TARGET_WHY="a --match-head-commit flag names no 40-hex sha and no single double-quoted simple variable (\"\$NAME\", \"\${NAME}\" or \"\${NAME:?msg}\")"
    elif [[ ! "$_r1_first" =~ ^[0-9]{1,9}$ ]]; then
      MERGE_TARGET_WHY="a --match-head-commit variable needs one bare PR number right after 'gh pr merge'"
    elif [[ "$(grep -c -- '^--match-head-commit$' <<<"$_r1_rest" || true)" != "1" ]]; then
      MERGE_TARGET_WHY="more than one --match-head-commit flag; merge one PR per command"
    elif [[ "$(tail -n 1 <<<"$_r1_rest")" != "--match-head-commit" ]]; then
      MERGE_TARGET_WHY="the --match-head-commit variable operand must be the invocation's LAST argument (nothing may follow it); move every flag before --match-head-commit"
    elif grep -qv -- '^-' <<<"$_r1_rest"; then
      MERGE_TARGET_WHY="a second positional beside the bare PR number; name one bare PR number right after 'gh pr merge'"
    elif [[ "$(sed -E 's/(^|[[:space:]])#.*//' <<<"$CMD" | grep -o -- '--match-head-commit' | wc -l | tr -d ' ')" != "$_n_cmd" ]]; then
      MERGE_TARGET_WHY="the command names --match-head-commit more times than it invokes gh pr merge"
    # Nameref sighting on the command after QUOTE REMOVAL (quote and
    # backslash characters deleted): `declare '-n' H=…`, `declare -\n H=…`
    # and `"declare" -n H=…` all run `declare -n`, and the quoted spellings
    # hid the option from a raw-text match. An option word that is itself an
    # expansion (`declare $o H=…`, `declare $'-n' …`) cannot be proven
    # nameref-free and denies the same way.
    elif tr -d "\"'\\\\" <<<"$CMD" \
         | grep -qE '(^|[^A-Za-z0-9_])(declare|local|typeset)[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*n|\$)'; then
      MERGE_TARGET_WHY="the command declares a nameref (declare/local/typeset -n, or an option word the hook cannot read), which can make the --match-head-commit variable run code"
    else
      TARGET_KIND="pr"; PR_HEAD_NUMBER="$_r1_first"
    fi
  fi
fi

if [[ -z "$MERGE_TARGET_WHY" && -z "$TARGET_KIND" ]]; then
  # Positional = any token not beginning with '-', across every residue.
  _pos_scan=$(awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^-/) print $i }' <<<"$_scan_args" | sort -u || true)
  if [[ -z "$_pos_scan" ]]; then
    # Flag-only invocation (e.g. `gh pr merge --squash --auto`): no named
    # target, so the merge's object is the session's pushed branch — the
    # HEAD path (ruling: a purely flag-only invocation correctly takes it).
    TARGET_KIND="head"
  else
    # Every invocation's FIRST token must be the same bare PR number.
    _firsts_ok=1
    while IFS= read -r _t; do
      [[ -n "$_t" ]] || continue
      [[ "$_t" =~ ^#?[0-9]+$ ]] || _firsts_ok=0
    done <<<"$_tok_scan"
    _pr_nums=$(sed 's/^#//' <<<"$_pos_scan" | grep -E '^[0-9]+$' | sort -u || true)
    if [[ "$_firsts_ok" == "1" ]] \
       && [[ "$(grep -c . <<<"$_pos_scan" || true)" == "1" ]] \
       && [[ "$(grep -c . <<<"$_pr_nums" || true)" == "1" ]]; then
      TARGET_KIND="pr"; PR_HEAD_NUMBER="$_pr_nums"
    else
      MERGE_TARGET_WHY="a gh pr merge invocation does not name a bare PR number; put the number right after 'gh pr merge'"
    fi
  fi
fi

# Repo pointer sighted but not proven same-repo (and not proven foreign —
# that arm exits above): unprovable → deny.
if [[ -z "$MERGE_TARGET_WHY" && "$_REPO_PTR" == "1" && "$_REPO_SAME" != "1" ]]; then
  MERGE_TARGET_WHY="the command points gh at another repository or one the hook cannot prove is this checkout's origin (-R/--repo, GH_REPO or GH_HOST); drop the pointer and re-issue"
fi

# In-command dir changes. Rules:
#   - A cd/pushd into a DIFFERENT origin → deny (verbatim arm).
#   - Any dir-change the resolver cannot prove → deny: popd, `cd -`,
#     bare `cd`, quoted/blanked/$VAR/~/leading-dash/nonexistent operands.
#     A flag-only merge in an unknown checkout censuses the wrong branch.
#   - A same-origin cd before the merge → the merge RUNS there, so the
#     head is resolved from that dir's branch — WORK_DIR is rebound to the
#     CUMULATIVE last cd (`cd a && cd b` executes from b, not a). A cd
#     sighted at an offset AFTER the first merge invocation cannot steer
#     it (`gh pr merge && cd /clean` is not a miscensus; treating it as
#     one was the position-blind defect).
# Scanned on SCAN_NOCOMMENT with the merge boundary set — `{ cd x; … }`,
# `` `cd x` `` and ` -- cd x` shapes reach the same enumeration.
if [[ -z "$MERGE_TARGET_WHY" ]]; then
  _origin=$(git -C "$WORK_DIR" remote get-url origin 2>/dev/null || true)
  _merge_off=$(grep -boE "${_MERGE_BOUNDARY}[[:space:]]*${_MERGE_PREFIX}gh${_GH_GFLAGS}[[:space:]]+pr[[:space:]]+merge" <<<"$SCAN_NOCOMMENT" | head -1 | cut -d: -f1 || true)
  _cd_acc="$WORK_DIR"
  _cd_bad=0
  while IFS=: read -r _off _seg; do
    # A cd at or after the first merge invocation cannot steer it.
    [[ -n "$_merge_off" && "$_off" -ge "$_merge_off" ]] && continue
    _kw=$(printf '%s' "$_seg" | grep -oE '(cd|pushd|popd)' | head -1 || true)
    if [[ "$_kw" == "popd" ]]; then _cd_bad=1; break; fi
    # Subshell scope: `(cd x; make) && gh pr merge` — the cd is inside a
    # paren group that closes before the merge, so it never steered the
    # parent env; a `(cd x; gh pr merge)` keeps its group open THROUGH
    # the merge (no `)` between them) and correctly rebinds.
    if [[ -n "$_merge_off" && "${SCAN_NOCOMMENT:$_off:$((_merge_off - _off))}" == *')'* ]]; then
      _cd_bad=1; break
    fi
    _op=$(printf '%s' "$_seg" | awk '{print $NF}')
    if [[ "$_op" == "cd" || "$_op" == "pushd" || "$_op" == "-" || "$_op" == -* \
       || "$_op" == *'$'* || "$_op" == *'~'* ]]; then
      _cd_bad=1; break
    fi
    if [[ "$_op" == /* ]]; then _cd_acc="$_op"; else _cd_acc="${_cd_acc%/}/${_op}"; fi
  done < <(grep -boE "${_MERGE_BOUNDARY}[[:space:]]*(cd|pushd|popd)([[:space:]]+[^;&|()[:space:]]+|[^[:alnum:]_]|$)" <<<"$SCAN_NOCOMMENT" || true)
  if [[ -z "$MERGE_TARGET_WHY" ]]; then
    if [[ "$_cd_bad" == "1" ]]; then
      MERGE_TARGET_WHY="the command changes directory in a way the hook cannot resolve (popd, cd -, or a quoted, variable, missing, or nonexistent operand)"
    elif [[ "$_cd_acc" != "$WORK_DIR" ]]; then
      _cd_real=$(cd -P "$_cd_acc" 2>/dev/null && pwd -P || true)
      if [[ -z "$_cd_real" || ! -d "$_cd_real" ]]; then
        MERGE_TARGET_WHY="the command cd's into a directory the hook cannot resolve"
      elif ! git -C "$_cd_real" rev-parse --git-dir >/dev/null 2>&1; then
        # cd into a non-repo dir: a HEAD-path merge fails there — nothing
        # to measure (same contract as a non-git .cwd). But a NUMBERED or
        # sha merge — and any -R/env-resolved one — still resolves a
        # remote PR from a non-repo cwd, so this exit is head-path-only.
        [[ "$TARGET_KIND" == "head" ]] && exit 0
        MERGE_TARGET_WHY="the command cd's into a non-repository directory while naming a merge target"
      else
        _dir_origin=$(git -C "$_cd_real" remote get-url origin 2>/dev/null || true)
        if [[ -n "$_dir_origin" && "$_dir_origin" != "$_origin" ]]; then
          MERGE_TARGET_WHY="the command cd's into a checkout of another repository"
        else
          WORK_DIR="$_cd_real"
        fi
      fi
    fi
  fi
fi

if [[ -n "$MERGE_TARGET_WHY" ]]; then
  _deny "BLOCKED: cannot prove which head this merge lands (${MERGE_TARGET_WHY}). This gate censuses the exact head's diff for unarchived KB artifacts; a HEAD fallback would measure the wrong object. Re-issue with one bare PR number ('gh pr merge <N>'), a clean '--match-head-commit <40-hex>', or the documented arm 'gh pr merge <N> … --match-head-commit \"\$H\"' (the quoted variable operand LAST; see plugins/soleur/skills/review/references/review-evidence-comment.md#arm-check). Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
fi

# Toplevel-normalize: the census pathspecs are relative to git's cwd —
# a `.cwd` or a same-origin cd into a SUBDIRECTORY would make
# `git -C <subdir> diff -- knowledge-base/…` resolve to
# <subdir>/knowledge-base/…, match nothing, and pass a leaky head
# vacuously. Bare repos have no toplevel; they stay as-is (tree-relative
# pathspecs already behave there).
_wt_top=$(git -C "$WORK_DIR" rev-parse --show-toplevel 2>/dev/null || true)
[[ -n "$_wt_top" ]] && WORK_DIR="$_wt_top"

# --- resolve the head object ---------------------------------------------

# Network bound for the PR-number census reads (ls-remote, the
# refs/pull/<N>/head fetch, the origin/main fetch): the documented arm
# reaches them on every merge, and a hung origin would otherwise hold the
# hook until the harness kills it — a non-blocking exit that lets the merge
# through. Each consumer treats a timeout as a failure, which denies.
# timeout, else gtimeout (stock macOS), else unbounded (pre-change posture)
# — sibling pattern, pre-merge-rebase.sh.
_NET_TO=()
if command -v timeout >/dev/null 2>&1; then _NET_TO=(timeout -k 2 20)
elif command -v gtimeout >/dev/null 2>&1; then _NET_TO=(gtimeout -k 2 20); fi

CURRENT_BRANCH=$(git -C "$WORK_DIR" symbolic-ref --short -q HEAD 2>/dev/null || echo "")

if [[ "$TARGET_KIND" == "head" ]]; then
  # HEAD-path fail-opens (ruling): exempt ONLY this path — the measured
  # object is the session branch, meaningless in these states.
  if [[ "$(git -C "$WORK_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]]; then
    exit 0
  fi
  if [[ -z "$CURRENT_BRANCH" ]] || [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
    exit 0
  fi
  # Refname validation: defense against argument injection into git argv.
  if [[ ! "$CURRENT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$CURRENT_BRANCH" == -* ]]; then
    exit 0
  fi
  # `gh pr merge` merges the PR's REMOTE head — census origin/<branch>, not
  # local HEAD, which can lag it (a live artifact pushed from elsewhere
  # under-measures the same way; ship-unpushed-commits-gate.sh pays the
  # same fetch cost). Explicit refspec, NOT `fetch origin <branch>`: a
  # checkout could carry a `remote.origin.fetch` mapping that leaves a
  # stale refs/remotes/origin/<branch> behind — the census must read the
  # object the remote actually serves. A branch with no upstream has no
  # mergeable head — gh fails before this gate's subject exists.
  if ! git -C "$WORK_DIR" fetch --no-tags --quiet origin "+refs/heads/${CURRENT_BRANCH}:refs/remotes/origin/${CURRENT_BRANCH}" >/dev/null 2>&1; then
    if git -C "$WORK_DIR" rev-parse --verify -q "refs/remotes/origin/${CURRENT_BRANCH}" >/dev/null 2>&1; then
      _deny "BLOCKED: \`git fetch origin ${CURRENT_BRANCH}\` failed; cannot verify the pushed head for live-path KB artifacts. Run the fetch manually, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
    exit 0
  fi
  HEAD_OID=$(git -C "$WORK_DIR" rev-parse "origin/${CURRENT_BRANCH}" 2>/dev/null || echo "")
  if [[ ! "$HEAD_OID" =~ ^[0-9a-f]{40}$ ]]; then
    exit 0
  fi
elif [[ "$TARGET_KIND" == "pr" ]]; then
  # refs/pull/<N>/head, not refs/heads/<name>: needs no branch name in a
  # git argv, and no `gh` dependency — the ref is a git object.
  # `ls-remote`, NOT fetch-then-FETCH_HEAD: FETCH_HEAD is a shared mutable
  # file, and a concurrent fetch in this clone (another session's hooks,
  # a parallel drain) between the fetch and the rev-parse substitutes a
  # DIFFERENT valid oid — the census then measures a head that is not the
  # merge's. Pin the oid first, then fetch only if the object is missing
  # (the fetch is for objects only; nothing reads FETCH_HEAD after).
  # Fail-CLOSED on read/fetch failure (sibling T9 posture): an
  # unverifiable head is the silent-miss class this gate exists to end.
  # `|| HEAD_OID=""` (CTO ruling G2): under `set -eo pipefail` a failing
  # ls-remote (unreachable origin) killed the hook silently — no JSON, a
  # non-blocking exit, and the merge proceeded. Now it reaches the deny.
  # `${_NET_TO[@]}`: a hung origin times out into that same deny.
  HEAD_OID=$("${_NET_TO[@]}" git -C "$WORK_DIR" ls-remote origin "refs/pull/${PR_HEAD_NUMBER}/head" 2>/dev/null | awk '{print $1; exit}') || HEAD_OID=""
  if [[ ! "$HEAD_OID" =~ ^[0-9a-f]{40}$ ]]; then
    _deny "BLOCKED: \`git ls-remote origin refs/pull/${PR_HEAD_NUMBER}/head\` returned no commit (or timed out); cannot verify the merge head for live-path KB artifacts against an unfetched object. Check the PR number and network/origin, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
  fi
  if ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    if ! "${_NET_TO[@]}" git -C "$WORK_DIR" fetch --no-tags --quiet origin "refs/pull/${PR_HEAD_NUMBER}/head" >/dev/null 2>&1 \
       || ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
      _deny "BLOCKED: \`git fetch origin refs/pull/${PR_HEAD_NUMBER}/head\` failed (or timed out); cannot verify the merge head for live-path KB artifacts against an unfetched object. Retry the fetch manually (check network/origin), then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
  fi
else
  # --match-head-commit: the exact object GitHub will merge (the admin
  # hatch's pinned sha). Present locally, or fetch it; unreachable → deny.
  if ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
    if ! git -C "$WORK_DIR" fetch --no-tags --quiet origin "$HEAD_OID" >/dev/null 2>&1 \
       || ! git -C "$WORK_DIR" cat-file -e "${HEAD_OID}^{commit}" 2>/dev/null; then
      _deny "BLOCKED: --match-head-commit ${HEAD_OID:0:12} is not fetchable from origin; cannot verify the merge head for live-path KB artifacts. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
    fi
  fi
fi

# Refresh origin/main. Redirect BOTH stdout and stderr (git fetch prints
# progress to stderr; mixing with hook JSON corrupts the harness-side jq
# parse). Fail-CLOSED: a fetch failure means the merge-base cannot be
# trusted, and silent-miss is the exact class this gate exists to prevent.
# A timeout is a failure here too.
if ! "${_NET_TO[@]}" git -C "$WORK_DIR" fetch --no-tags origin main >/dev/null 2>&1; then
  _deny "BLOCKED: \`git fetch origin main\` failed (or timed out); cannot census the merge head's KB artifacts against a stale origin/main. Run \`git fetch origin main\` manually, then re-issue. Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
fi

BASE=$(git -C "$WORK_DIR" merge-base origin/main "$HEAD_OID" 2>/dev/null || true)
if [[ -z "$BASE" ]]; then
  # Unresolvable merge-base = shallow-clone class: git genuinely cannot
  # compare, and denying every merge from a shallow checkout would wedge
  # drain/schedule sessions. archive-kb.sh already degrades on the same
  # condition, so the exposure predates this hook. Warn — never silent.
  headless_or_stderr warn "[ship-kb-archive-gate] merge-base unresolvable (shallow clone?); skipping KB-artifact census for this merge."
  exit 0
fi

# Census: A/M/R/C/T rows under the three KB roots, non-archive only.
#   - Only `<root>/archive/` is exempt — a file inside a LIVE spec dir's
#     own `archive/` subdir is still live. (`*/archive/*` anywhere would
#     exempt `specs/<live>/archive/x`.)
#   - R/C rows carry TWO -z records (status, src, dst): the destination
#     path is what lands on main, so a `git mv <archive|live> <live-path>`
#     un-archive must be judged on DST. `--diff-filter=AM` missed R
#     entirely — silent pass for the rename-in class.
#   - specs/ requires depth ≥ 2 (specs/<dir>/<file>); a root-level
#     specs/.gitkeep never fires.
#   - learnings/ and the domain KB dirs are never archived and never
#     gated — not session artifacts.
# -z + read -d '': --name-status alone quotes paths containing special
# characters. Under -z each entry is `STATUS\0PATH\0` (A/M/T) or
# `STATUS\0SRC\0DST\0` (R/C) — two NUL-terminated fields per path.
# --quiet probe first: rc 0 = clean, 1 = differences (proceed), >1 = the
# diff could not run — warn + pass, never a silent unverified pass.
_diff_rc=0
git -C "$WORK_DIR" diff --quiet --diff-filter=AMRCT "$BASE" "$HEAD_OID" -- \
      knowledge-base/project/specs \
      knowledge-base/project/plans \
      knowledge-base/project/brainstorms >/dev/null 2>&1 || _diff_rc=$?
if [[ "$_diff_rc" -gt 1 ]]; then
  headless_or_stderr warn "[ship-kb-archive-gate] census diff failed (rc=${_diff_rc}); skipping KB-artifact census for this merge."
  exit 0
fi

# The probe above covers the common failure; the census diff itself gets
# an rc check too — a second-call failure must not degrade to an empty
# LEAKY silent pass.
_census_f=$(mktemp "${TMPDIR:-/tmp}/kb-census.XXXXXX")
trap 'rm -f "$_census_f"' EXIT
if ! git -C "$WORK_DIR" diff --name-status -z --diff-filter=AMRCT \
       "$BASE" "$HEAD_OID" -- \
       knowledge-base/project/specs \
       knowledge-base/project/plans \
       knowledge-base/project/brainstorms > "$_census_f" 2>/dev/null; then
  rm -f "$_census_f"
  headless_or_stderr warn "[ship-kb-archive-gate] census diff failed; skipping KB-artifact census for this merge."
  exit 0
fi

LEAKY=""
count=0
while IFS= read -r -d '' _st; do
  if [[ "$_st" == R* || "$_st" == C* ]]; then
    IFS= read -r -d '' _src || break
    IFS= read -r -d '' _path || break
  else
    IFS= read -r -d '' _path || break
  fi
  [[ -n "$_path" ]] || continue
  case "$_path" in
    knowledge-base/project/specs/archive/*|knowledge-base/project/plans/archive/*|knowledge-base/project/brainstorms/archive/*) continue ;;
    # spec dirs are the convention, but a depth-1 file (specs/foo.md)
    # leaks just the same — only the repo's .gitkeep stays exempt.
    knowledge-base/project/specs/.gitkeep) continue ;;
    knowledge-base/project/specs/*|knowledge-base/project/plans/*|knowledge-base/project/brainstorms/*) ;;
    *) continue ;;
  esac
  LEAKY+="${_st}"$'\t'"${_path}"$'\n'
  count=$((count + 1))
  [[ "$count" -ge 10 ]] && break
done < "$_census_f"
rm -f "$_census_f"

if [[ -z "$LEAKY" ]]; then
  # Sibling-convention silent exit on pass.
  exit 0
fi

# Sanitize the row list: C0 control bytes except \t and \n, DEL, U+2028-9,
# 80-char truncation (sibling precedent; CWE-117/CWE-532).
ROWS=$(printf '%s' "$LEAKY" \
  | soleur_ctx_sanitize_lines \
  | awk '{ if (length($0) > 80) print substr($0,1,79)"…"; else print $0 }')

# Branch-aware remediation: the deny may fire on a checkout that is NOT
# the PR's head branch (a numbered merge from main/drain, or a detached
# --match-head-commit). The fix block then names where the artifacts live
# and how a push reaches them.
_TARGET_NOTE=""
if [[ "$TARGET_KIND" == "pr" ]]; then
  _TARGET_NOTE="The artifacts live on PR #${PR_HEAD_NUMBER}'s head branch, not necessarily this checkout — run the fix there (\`gh pr checkout ${PR_HEAD_NUMBER}\`, or that branch's worktree) and push to ITS branch, then re-issue."
elif [[ "$TARGET_KIND" == "sha" ]]; then
  _TARGET_NOTE="The artifacts live on the branch the pinned head tracks; an archive push CHANGES the head sha — re-resolve --match-head-commit before re-issuing."
fi

_deny "BLOCKED: this merge lands KB artifacts at live paths — archive them inside the PR (rule wg-kb-artifacts-archived-in-pr).

Unarchived artifacts in the merge head's diff vs origin/main (≤10 shown):
${ROWS}
${_TARGET_NOTE}
Fix (from the repo root, on the PR's head branch): bash plugins/soleur/skills/archive-kb/scripts/archive-kb.sh
then: git add -A knowledge-base && git commit -m \"chore(kb): archive <branch> artifacts at ship\" && git push
(the check reads the pushed PR head — a local-only archive does not clear it).
For an M-row on specs/<dir>/ — archive-kb refuses to collapse a modified live spec dir BY DESIGN, because an M row can be a drive-by edit to a sibling feature's in-flight spec: verify the dir is THIS feature's first (if not, revert the edit with \`git checkout origin/main -- <path>\` then commit+push — plain \`git checkout --\` restores from HEAD, which already contains it); if it is, the manual path is
  git mv knowledge-base/project/specs/<dir> knowledge-base/project/specs/archive/\$(date +%Y%m%d-%H%M%S)-<dir> && git commit && git push
Ordering: archive only AFTER ship's last live-path reads — Phase 6 step 2.5 (decision-challenges render) and step 5 (Operator Holds). It belongs inside ship \"## Phase 6.45: KB Artifact Archival\".
Hatch: SOLEUR_SKIP_KB_ARCHIVE_GATE=1 bypasses."
