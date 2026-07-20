#!/usr/bin/env bash
# context-reviewed-gate.sh — PreToolUse(Bash) audit tripwire for `last_reviewed`.
#
# Issue: #5999. ADR-094 (freshness-last-reviewed-source-fix-and-audit-tripwire).
#
# WHAT THIS IS: a DETECTIVE audit tripwire, NOT a preventive integrity guarantee.
# When a commit made through the Claude Code Bash tool REMOVES or CHANGES a
# `last_reviewed:` line in a `*.md` file, this gate requires the commit message
# to carry an explicit `Context-Reviewed:` trailer declaring that a human review
# actually happened. Undeclared attempts are DENIED and logged to the local
# incident ledger. The trailer is self-attestable — an automated writer that
# knows the convention can emit `Context-Reviewed: all` and pass — so this gate
# RELOCATES the honor-system boundary to a single greppable, incident-logged
# point; it does not prove human review. It is bypassed by commits outside the
# Bash tool (Warp / IDE / CI / Inngest) and by non-canonical key spellings. The
# real integrity comes from the source-level fixes to the known automated
# writers (see ADR-094 §Phase 4); this gate is the tripwire for future/unknown
# LOCAL agent bumps.
#
# Contract (PreToolUse(Bash)): reads `.tool_input.command` + `.cwd` on stdin.
#
# Fire (deny) ONLY when ALL hold:
#   1. the command is a real `git commit` (bodies/heredocs stripped first so a
#      message documenting `git commit` does not self-trigger — #5192);
#   2. the commit's `*.md` delta — SCOPED to what the commit records (staged for
#      a plain commit; working-tree-vs-HEAD for `-a`/`--all`; the named pathspec
#      for a `<path>`/`<dir>` commit) — REMOVES or CHANGES a `last_reviewed:`
#      line (a pure net-new ADDITION — only `+`, no `-` — is EXEMPT: no
#      trailer-fatigue, no self-trip on first adoption);
#   3. no `Context-Reviewed:` trailer is present in ANY message source
#      (multi -m, -am, --message=, -F/--file).
#
# Fail-open split:
#   * benign  (not a commit / no `*.md` delta / no removed-or-changed
#     `last_reviewed`) → silent `exit 0`.
#   * error   (unresolvable cwd on a real commit, -F file unreadable) →
#     `emit_incident … warn … hook_self_fault` then `exit 0` (NEVER bricks a
#     commit; distinct from benign so the fault is visible in the ledger).
#
# Mirrors follow-through-directive-gate.sh (the PreToolUse(Bash) precedent) for
# strip_command_bodies / resolve_command_cwd / emit_incident usage.

set -eo pipefail

# shellcheck source=lib/incidents.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/incidents.sh"

INPUT=$(cat)
eval "$(echo "$INPUT" | jq -r '@sh "CMD=\(.tool_input.command // "")"' 2>/dev/null || echo 'CMD=""')"
: "${CMD:=}"

# 1. Trigger only on a real `git commit`. Strip commit bodies/heredocs so a
#    message that merely documents `git commit` is not mistaken for one (#5192).
#    `[^&|;]*` keeps the git↔commit span inside a single command segment so
#    `git add . && git commit` still resolves to the real `git commit`.
SCAN=$(strip_command_bodies "$CMD")
if ! echo "$SCAN" | grep -qE '\bgit\b[^&|;]*\bcommit\b'; then
  exit 0
fi

# 2. Resolve the target repo (handles `git -C X` / `cd X && git commit`), not
#    bare `.cwd`. Unresolvable on a real commit → error fail-open + incident.
WORK_DIR=$(resolve_command_cwd "$CMD" "$INPUT")
if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
  emit_incident "context-reviewed-hook-self-fault" warn \
    "context-reviewed-gate: unresolvable cwd on git commit" "$CMD" PreToolUse hook_self_fault || true
  exit 0
fi

# 3. Compute the `last_reviewed` delta, SCOPED to what THIS commit will actually
#    record. Parse the `git … commit` segment quote-aware and classify its mode:
#      * -a/-am/--all → all tracked working-tree changes vs HEAD
#      * <pathspec…>  → working-tree vs HEAD restricted to the named pathspecs
#                       (bare paths, `-o`/`--only` targets, post-`--` paths)
#      * neither      → staged (--cached) only
#    This closes both a false-NEGATIVE the old all-markdown union missed (a
#    directory/pathspec commit of unstaged content — e.g. `git commit docs/` —
#    slipped through with no incident) AND false-POSITIVES it caused (an
#    unrelated unstaged `last_reviewed` edit ELSEWHERE, or an `-a`/`-o` flag in a
#    CHAINED non-commit segment like `git commit -m x && ls -la`, wedged a
#    legitimate commit). The last_reviewed regex (step 4) already restricts to
#    *.md, so pathspecs need no *.md intersection. Value-taking flags (-m/-F/-C/
#    -c and the --long forms) consume their argument so it is never mis-read as a
#    pathspec; `&&`/`||`/`;`/`|` end the segment so a chained command cannot flip
#    the mode. The parser reads $CMD (raw) — NOT the body-stripped SCAN — because
#    stripping blanks quoted flag values and would break value-flag skipping.
_parsed=$(printf '%s' "$CMD" | perl -0777 -ne '
  my @t;
  while (/\G\s*("(?:[^"\\]|\\.)*"|'\''(?:[^'\''\\]|\\.)*'\''|\S+)/gc) { push @t, $1; }
  my $c = -1;
  for (my $k=0; $k<@t; $k++) {
    next unless $t[$k] eq "git";
    my $j = $k+1;
    while ($j < @t && $t[$j] ne "commit") {
      if ($t[$j] eq "-C" || $t[$j] eq "-c") { $j += 2; }
      elsif ($t[$j] =~ /^-/) { $j++; } else { last; }
    }
    if ($j < @t && $t[$j] eq "commit") { $c = $j; last; }
  }
  exit 0 if $c < 0;
  my @seg;
  for (my $k=$c+1; $k<@t; $k++) { last if $t[$k] =~ /^(&&|\|\||;|\|)$/; push @seg, $t[$k]; }
  my %val = map { $_=>1 } qw(--message --file --reuse-message --reedit-message --author --date --fixup --squash);
  my ($mode, $ddash, @paths) = ("plain", 0);
  for (my $k=0; $k<@seg; $k++) {
    my $tok = $seg[$k];
    if ($ddash) { push @paths, $tok; next; }
    if ($tok eq "--") { $ddash = 1; next; }
    if ($tok eq "--all") { $mode = "all"; next; }
    if ($tok =~ /^--[a-z][a-z-]*=/) { next; }
    if ($val{$tok}) { $k++; next; }
    if ($tok =~ /^--/) { next; }
    if ($tok =~ /^-[A-Za-z]+$/) { $mode = "all" if $tok =~ /a/; $k++ if substr($tok,-1) =~ /[mFCc]/; next; }
    if ($tok =~ /^-/) { next; }
    (my $p = $tok) =~ s/^(["'\''])//; $p =~ s/(["'\''])$//;
    push @paths, $p;
  }
  $mode = "pathspec" if ($mode ne "all" && @paths);
  print "$mode\n"; print "$_\n" for @paths;
' 2>/dev/null || true)
_mode=$(printf '%s' "$_parsed" | head -1)
case "$_mode" in
  all)
    DELTA=$(git -C "$WORK_DIR" diff HEAD -U0 -- '*.md' 2>/dev/null || true) ;;
  pathspec)
    mapfile -t _paths < <(printf '%s\n' "$_parsed" | tail -n +2)
    DELTA=$(git -C "$WORK_DIR" diff HEAD -U0 -- "${_paths[@]}" 2>/dev/null || true) ;;
  *)
    DELTA=$(git -C "$WORK_DIR" diff --cached -U0 -- '*.md' 2>/dev/null || true) ;;
esac

# 4. Fire only on a REMOVED or CHANGED `last_reviewed` line. A re-bump shows
#    `-old`/`+new`; a deletion shows `-old`; a net-new adoption shows only
#    `+new` (no `-` line) and is EXEMPT. Widened for quoting / space-before-
#    colon / case (grep -E: `[[:space:]]`, not `\s`). The `--- a/<file>` diff
#    header starts with `-` but carries no `last_reviewed` token, so it never
#    false-matches.
if ! echo "$DELTA" | grep -qE '^-.*["'"'"']?[Ll]ast_[Rr]eviewed["'"'"']?[[:space:]]*:'; then
  exit 0
fi

# 5. Extract the commit message from ALL sources so a trailer in any of them is
#    honored: every -m/--message/--message= value (multi-`-m` concatenated), the
#    combined `-am` message arg, and -F/--file contents. An -F file unreadable
#    at hook time on a real last_reviewed commit → error fail-open + incident.
MSG=$(printf '%s' "$CMD" | perl -0777 -ne '
  my @m;
  while (/(?:^|\s)(?:-[A-Za-z]*m|--message)(?:=|\s+)("(?:[^"\\]|\\.)*"|'"'"'(?:[^'"'"'\\]|\\.)*'"'"'|[^\s]+)/g) {
    my $v=$1; $v=~s/^["'"'"']//; $v=~s/["'"'"']$//; push @m,$v;
  }
  print join("\n",@m);
' 2>/dev/null || true)

BODY_FILE=$(printf '%s' "$CMD" | grep -oE -- '(^|[[:space:]])(-F|--file)[[:space:]]+[^[:space:]]+' | head -1 | awk '{print $NF}' || true)
if [[ -n "$BODY_FILE" ]]; then
  [[ "$BODY_FILE" != /* ]] && BODY_FILE="$WORK_DIR/$BODY_FILE"
  if [[ -r "$BODY_FILE" ]]; then
    MSG+=$'\n'
    MSG+=$(cat "$BODY_FILE" 2>/dev/null || true)
  else
    emit_incident "context-reviewed-hook-self-fault" warn \
      "context-reviewed-gate: -F message file unreadable on commit" "$CMD" PreToolUse hook_self_fault || true
    exit 0
  fi
fi

# 6. Trailer present → allow (attributable). Absent → deny + incident.
if printf '%s' "$MSG" | grep -qE 'Context-Reviewed:[[:space:]]*(all|[^[:space:]]+)'; then
  exit 0
fi

emit_incident "context-reviewed-gate" deny \
  "last_reviewed change committed without a Context-Reviewed trailer" "$CMD" || true
jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "BLOCKED: this commit removes or changes a `last_reviewed:` line in a Markdown file but carries no `Context-Reviewed:` trailer. `last_reviewed` is a cooperative freshness signal (ADR-094) — an undeclared bump silently ages the review clock so downstream staleness checks read false confidence. If a human review actually happened, add a final commit-message paragraph declaring it: `Context-Reviewed: all` (or `Context-Reviewed: <path>`). If this is an automated reconcile that did NOT review the doc, bump `last_updated` instead and leave `last_reviewed` unchanged. This gate is a detective audit tripwire, not a wall; the attempt has been logged to the local incident ledger."
  }
}'
exit 0
