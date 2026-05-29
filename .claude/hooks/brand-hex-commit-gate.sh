#!/usr/bin/env bash
# PreToolUse hook on Bash matching `git commit`. Scans the *added* lines of
# staged UI/template files for raw hex colour literals and denies the commit
# when a component/page references a literal colour instead of a design token,
# or when an email template uses an off-brand (non-palette) hex.
#
# Why this hook exists (the un-bypassable layer, issue #4644):
#   The workspace-invite UI and transactional emails shipped with off-brand
#   blue `#2563eb` (fixed in #4631/#4639). The only brand-adjacent gate —
#   `soleur:frontend-anti-slop` — is advisory-only and runs at review time, so
#   it is silently skippable: if `/review` is not run, off-brand colour ships.
#   This hook intercepts at the Bash-tool boundary BEFORE `git commit`,
#   regardless of `/review`, and cannot be bypassed by `git commit --no-verify`.
#   It is the FIRST net; the frontend-anti-slop scanner (#4635) is the second.
#
# Modelled on .claude/hooks/git-commit-secret-scan.sh — same trigger regex,
# same fail-open philosophy, same JSON permissionDecision contract.
#
# Decision mechanism: this hook emits the repo-standard PreToolUse JSON
# `{permissionDecision: deny}` with exit 0 (NOT a bare `exit 2`). Every sibling
# Bash PreToolUse gate in .claude/settings.json (guardrails, ship gates,
# secret-scan) uses this shape, and the hook test harness keys on the JSON
# decision. The deny is as un-bypassable as exit 2 — Claude Code honours
# permissionDecision:deny by refusing the tool call.
#
# Enforcement modes (a file is classified by path):
#   - UI / component / page / docs template (token-required): ANY raw hex
#     literal is blocked. These surfaces can reference CSS custom properties
#     / Tailwind token utilities, so there is no excuse for a literal colour.
#   - Email / server notification template (path-scoped literal-hex exception):
#     inline hex is permitted (email clients strip CSS custom properties), but
#     ONLY brand-palette hex. Off-brand hex is blocked. This closes the
#     off-brand-email half of the motivating incident.
#   - Token-definition CSS (globals.css, *.tokens.css, or any .css that defines
#     `--name: #hex`): fully exempt — literal hex IS the point there.
#
# Generalisation for Soleur users: the brand palette and the set of
# token-definition files are DISCOVERED from the project's own CSS at runtime
# (any `.css` that declares custom properties with hex values). The two path
# classes are overridable via SOLEUR_BRAND_HEX_UI_RE / SOLEUR_BRAND_HEX_EMAIL_RE
# so a project with a different layout can retarget the gate without editing it.
#
# Scan scope is the *added* lines of the diff (index-vs-HEAD, or worktree-vs-HEAD
# for `git commit -a`), not whole-file content: the gate stops NEW off-brand
# colour from landing without surprise-blocking unrelated edits to legacy files.
# The full-file forward-sweep + retroactive remediation is owned by the
# review-time frontend-anti-slop scanner (#4635).
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 always (JSON output controls the gate).
#
# Fail-open conditions (allow + optional warn): non-Bash tool; Bash command that
# is not `git commit`; not inside a git work tree; no in-scope changed files; no
# token-definition file discoverable (email palette check is skipped, UI check
# still applies). Environment/tooling gaps must not block every commit.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

deny() {
  local reason="$1"
  emit brand-hex-commit-gate deny "brand-hex-commit-gate: ${reason:0:80}"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

payload="$(cat)"
tool_name="$(echo "$payload" | jq -r '.tool_name // empty' 2>/dev/null)"

# Only fire on Bash.
[ "$tool_name" = "Bash" ] || allow

command="$(echo "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -n "$command" ] || allow

# Match `git commit` as a command-leading verb (identical to
# git-commit-secret-scan.sh): tolerates chains (`&&`, `||`, `;`, `|`, `$(`),
# rejects substring matches and `git commit-tree` / `git commit-graph`.
if ! echo "$command" | grep -qE '(^|[[:space:]]|&&|\|\||;|\$\()[[:space:]]*git[[:space:]]+commit([[:space:]]|$)'; then
  allow
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit brand-hex-commit-gate bypass "not inside git work tree"
  allow
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
[ -n "$repo_root" ] || allow
cd "$repo_root" || allow

# `git commit -a`/`--all` commits unstaged tracked changes too, so the diff
# base must be the working tree (vs HEAD) rather than the index. Detect a
# combined short flag containing `a` (e.g. -a, -am, -ma) or `--all`. `--amend`
# does not match (it starts with `--` so the `-[A-Za-z]*a` short-flag form
# cannot apply, and it is not `--all`).
commit_args="${command#*git commit}"
# Strip quoted argument values (e.g. -m '… -a …') first so flag-like text inside
# the commit message cannot flip the diff base and cause a false deny.
flag_scan="$(printf '%s' "$commit_args" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
if echo "$flag_scan" | grep -qE '(^|[[:space:]])(-[A-Za-z]*a[A-Za-z]*|--all)([[:space:]]|=|$)'; then
  NAME_REF="HEAD"
else
  NAME_REF="--cached"
fi

# Gather the files about to be committed (NUL-delimited; bash-native read, no
# `grep -z` — host grep is ugrep where -z means --decompress).
mapfile -d '' -t changed_files < <(git diff "$NAME_REF" --name-only -z 2>/dev/null)
[ "${#changed_files[@]}" -gt 0 ] || allow

# ---- path classification (overridable for non-Soleur layouts) ----
UI_RE="${SOLEUR_BRAND_HEX_UI_RE:-^(apps/web-platform/(app|components)/.*\.(tsx|jsx|ts|css)|plugins/soleur/docs/.*\.(njk|html|css))$}"
EMAIL_RE="${SOLEUR_BRAND_HEX_EMAIL_RE:-^apps/web-platform/server/.*(notification|email|mail).*\.(ts|tsx)$}"

_file_content() {
  local f="$1"
  if [ -f "$f" ]; then cat -- "$f"; else git show ":$f" 2>/dev/null || true; fi
}

# Content of the file AS IT WILL BE COMMITTED: the index blob for a normal
# commit (so a poisoned-but-unstaged worktree edit cannot whitelist colours),
# the worktree for `git commit -a` (where the worktree IS what gets committed).
_committed_content() {
  local f="$1"
  if [ "$NAME_REF" = "--cached" ]; then
    git show ":$f" 2>/dev/null || true
  else
    if [ -f "$f" ]; then cat -- "$f"; else git show "HEAD:$f" 2>/dev/null || true; fi
  fi
}

# A .css file is a token-definition file (exempt) if its basename is the
# conventional token sink OR it declares custom properties with hex values.
# The custom-property probe is intentionally NOT line-anchored so single-line /
# minified CSS (`:root { --x: #hex; }`) is still recognised.
is_token_def() {
  local f="$1" base; base="$(basename -- "$f")"
  case "$base" in
    globals.css) return 0 ;;
    *.tokens.css) return 0 ;;
  esac
  case "$f" in
    *.css)
      _committed_content "$f" | grep -qE -- '--[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*#[0-9a-fA-F]{3,8}' && return 0
      ;;
  esac
  return 1
}

# Normalise a hex literal: strip leading #, lowercase, expand #rgb -> #rrggbb,
# drop the alpha byte of an 8-digit value for palette membership.
norm_hex() {
  local h="${1#\#}"
  h="$(printf '%s' "$h" | tr 'A-F' 'a-f')"
  if [ "${#h}" -eq 3 ]; then h="${h:0:1}${h:0:1}${h:1:1}${h:1:1}${h:2:1}${h:2:1}"; fi
  if [ "${#h}" -eq 8 ]; then h="${h:0:6}"; fi
  printf '#%s' "$h"
}

# ---- palette discovery (from the project's own token-definition CSS) ----
declare -A PALETTE=()
declare -A PALETTE_NAME=()
palette_built=0
build_palette() {
  [ "$palette_built" -eq 0 ] || return 0
  palette_built=1
  local f decl name hex
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    is_token_def "$f" || continue
    while IFS= read -r decl; do
      name="$(printf '%s' "$decl" | sed -E 's/^[[:space:]]*(--[A-Za-z0-9_-]+).*/\1/')"
      hex="$(printf '%s' "$decl" | grep -oE '#[0-9a-fA-F]{3,8}' | head -1)"
      [ -n "$hex" ] || continue
      hex="$(norm_hex "$hex")"
      PALETTE["$hex"]=1
      [ -n "${PALETTE_NAME[$hex]:-}" ] || PALETTE_NAME["$hex"]="$name"
    done < <(_committed_content "$f" | grep -oE -- '--[A-Za-z0-9_-]+[[:space:]]*:[[:space:]]*#[0-9a-fA-F]{3,8}')
  done < <(git ls-files -- '*.css' 2>/dev/null)
}

# Colour-literal segments. Four shapes, all anchored on a colour-relevant
# token so `href="#abc"` anchor fragments, `url(#gradient-id)` SVG refs, and
# non-colour hex are NOT matched:
#   1. Tailwind arbitrary value `[#hex]` (3-8 hex digits → covers #rgb, #rgba,
#      #rrggbb, #rrggbbaa).
#   2. url-SAFE colour props (color/border/outline/shadows/…) with the hex
#      ANYWHERE in the value, bounded to the declaration (no `;{}`): catches
#      `border: 1px solid #hex`, `box-shadow: 0 0 4px #hex`, `color: #hex`.
#   3. url-PRONE props (background/fill/stroke/…) with the hex DIRECTLY after
#      the `:`/`=` separator (optionally quoted): catches `fill="#hex"` and
#      `background: #hex` but NOT `fill="url(#ref)"` / `background: url(#id)`.
#   4. gradient functions with a hex argument: `linear-gradient(…, #hex …)`.
# Both `:` (CSS / JS object) and `=` (JSX/SVG attribute) separators are matched.
q="\"'"
COLOR_RE="\\[#[0-9a-fA-F]{3,8}\\]"
COLOR_RE="$COLOR_RE|(color|border|outline|box-shadow|text-shadow|boxShadow|textShadow|caret-color|accent-color|text-decoration-color|column-rule|outlineColor|borderColor)[A-Za-z-]*[[:space:]]*[:=][^;{}]*#[0-9a-fA-F]{3,8}"
COLOR_RE="$COLOR_RE|(background|backgroundColor|fill|stroke|flood-color|floodColor|lighting-color|stop-color|stopColor)[A-Za-z-]*[[:space:]]*[:=][[:space:]]*[$q]?#[0-9a-fA-F]{3,8}"
COLOR_RE="$COLOR_RE|(linear-gradient|radial-gradient|conic-gradient)\\([^;{}]*#[0-9a-fA-F]{3,8}"

findings=()

for f in "${changed_files[@]}"; do
  [ -n "$f" ] || continue
  # Token-definition files are exempt even though they match the UI .css glob.
  if is_token_def "$f"; then continue; fi

  klass=""
  if echo "$f" | grep -qE "$EMAIL_RE"; then
    klass="email"
  elif echo "$f" | grep -qE "$UI_RE"; then
    klass="ui"
  else
    continue
  fi

  build_palette

  # Walk the added lines (the `+` side), tracking new-file line numbers.
  while IFS=$'\t' read -r lno content; do
    [ -n "$content" ] || continue
    segs="$(printf '%s' "$content" | grep -oE "$COLOR_RE" 2>/dev/null || true)"
    [ -n "$segs" ] || continue
    while IFS= read -r seg; do
      [ -n "$seg" ] || continue
      # A segment may carry more than one hex (e.g. a two-stop gradient);
      # classify every hex it contains, not just the first.
      while IFS= read -r hexraw; do
        [ -n "$hexraw" ] || continue
        hex="$(norm_hex "$hexraw")"
        if [ "$klass" = "email" ]; then
          # Email exception: literal hex allowed only if it is a brand-palette
          # colour. Fail open if no palette could be discovered.
          if [ "${#PALETTE[@]}" -eq 0 ]; then
            continue
          fi
          if [ -n "${PALETTE[$hex]:-}" ]; then
            continue
          fi
          findings+=("$f:$lno (email, off-brand $hex)")
        else
          # Component/page/docs: literal colour is never allowed — must use a
          # token. Name the matching brand token in the remediation if known.
          tok="${PALETTE_NAME[$hex]:-}"
          if [ -n "$tok" ]; then
            findings+=("$f:$lno (component $hex; use token $tok)")
          else
            findings+=("$f:$lno (component $hex; use a design token)")
          fi
        fi
      done < <(printf '%s' "$seg" | grep -oE '#[0-9a-fA-F]{3,8}')
    done <<< "$segs"
  done < <(git diff "$NAME_REF" -U0 --no-color -- "$f" 2>/dev/null | awk '
    /^@@/      { if (match($0, /\+[0-9]+/)) { ln = substr($0, RSTART+1, RLENGTH-1) + 0 } ; next }
    /^\+\+\+/  { next }
    /^\+/      { print ln "\t" substr($0, 2); ln++ }
  ')
done

if [ "${#findings[@]}" -eq 0 ]; then
  allow
fi

# Build a terse, redaction-free deny reason (hex colours are not secrets).
count="${#findings[@]}"
locs=""
i=0
for fnd in "${findings[@]}"; do
  i=$((i + 1))
  [ "$i" -le 8 ] || break
  locs="${locs:+$locs; }$fnd"
done
[ "$count" -le 8 ] || locs="$locs; … (+$((count - 8)) more)"

reason="BLOCKED: brand-hex-commit-gate found ${count} raw hex colour literal(s) in staged UI/template content. Locations: ${locs}. Remediation: components/pages MUST reference a design token (var(--…) or the bg-/text-/border- token utility from globals.css), never a raw hex literal; email templates permit inline hex but ONLY brand-palette colours (off-palette hex is off-brand). Palette + token names are discovered from the project's token-definition CSS. See knowledge-base/marketing/brand-guide.md. This gate is the un-bypassable commit-time layer (#4644); the review-time frontend-anti-slop scanner (#4635) is the second net."

deny "$reason"
