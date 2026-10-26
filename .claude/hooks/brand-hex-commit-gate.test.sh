#!/usr/bin/env bash
# Tests for .claude/hooks/brand-hex-commit-gate.sh.
# Deterministic — uses a temp git repo per test, no network. All hex
# fixtures are synthesised inline (cq-test-fixtures-synthesized-only); none
# are copied from app code.
set -euo pipefail
SUITE_TMP=$(mktemp -d)
[[ "$SUITE_TMP" == /* ]] || { echo "FATAL: SUITE_TMP is not absolute: $SUITE_TMP" >&2; exit 2; }
trap 'rm -rf "$SUITE_TMP"' EXIT

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Inline per-call `INCIDENTS_REPO_ROOT=… bash "$HOOK"` is what leaked here:
# it was set on some invocations and missed on others, which greps identically
# to full isolation. See the helper header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/brand-hex-commit-gate.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1))
    echo "[ok] $label"
  else
    fail=$((fail + 1))
    echo "[FAIL] $label $detail" >&2
  fi
}

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

# Build a payload string for the hook and capture its JSON decision.
_run() {
  local cwd="$1" tool="$2" command="$3"
  local payload
  payload=$(jq -nc \
    --arg t "$tool" \
    --arg c "$command" \
    '{tool_name: $t, tool_input: {command: $c}}')
  (cd "$cwd" && CLAUDE_PROJECT_DIR="$cwd" bash "$HOOK" <<<"$payload")
}

_decision() { echo "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty'; }
_reason()   { echo "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty'; }

# Seed a temp git repo that mirrors the design-token topology the hook
# discovers: apps/web-platform/app/globals.css with a :root token block.
# The palette here defines the "brand" colours; anything else is off-brand.
_seed_repo() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  (
    cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    mkdir -p apps/web-platform/app apps/web-platform/components/dashboard \
             apps/web-platform/server plugins/soleur/docs
    cat > apps/web-platform/app/globals.css <<'CSS'
:root,
:root[data-theme="dark"] {
  --brand-bg-base: #0a0a0a;
  --brand-text-on-accent: #1a1612;
  --brand-accent-gold-fill: #c9a962;
  --brand-accent-gradient-start: #d4b36a;
  --brand-accent-gradient-end: #b8923e;
}
CSS
    git add apps/web-platform/app/globals.css
    git commit -q -m "seed: design tokens"
  )
  echo "$tmp"
}

# Stage a file with given content into an already-seeded repo.
_stage() {
  local repo="$1" path="$2" content="$3"
  ( cd "$repo" && mkdir -p "$(dirname "$path")" && printf '%s\n' "$content" > "$path" && git add "$path" )
}

# ---- trigger-matching cases (mirror git-commit-secret-scan.test.sh) ----

t_non_bash_tool() {
  local out; out=$(_run "$REPO_ROOT" "Write" "irrelevant")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T1 non-Bash tool -> allow" ok \
    || _report "T1 non-Bash tool -> allow" fail "$(_decision "$out")"
}

t_bash_non_commit() {
  local out; out=$(_run "$REPO_ROOT" "Bash" "git status")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T2 'git status' -> allow" ok \
    || _report "T2 'git status' -> allow" fail "$(_decision "$out")"
}

t_substring_not_match() {
  local out; out=$(_run "$REPO_ROOT" "Bash" 'echo "the git commit example"')
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T3 substring 'git commit' in echo -> allow" ok \
    || _report "T3 substring 'git commit' in echo -> allow" fail "$(_decision "$out")"
}

t_commit_tree_not_matched() {
  local out; out=$(_run "$REPO_ROOT" "Bash" "git commit-tree abc123")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T4 'git commit-tree' NOT matched -> allow" ok \
    || _report "T4 'git commit-tree' NOT matched -> allow" fail "$(_decision "$out")"
}

# ---- UI / component enforcement ----

t_clean_component_tokenized() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const Banner = () => (
  <div className="bg-brand-accent-gold-fill text-brand-text-on-accent">hi</div>
);'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'tokenized banner'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T5 tokenized component (no raw hex) -> allow" ok \
    || _report "T5 tokenized component -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

t_component_tailwind_hex_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const Banner = () => (
  <div className="bg-[#2563eb]/10 text-[#2563eb]">hi</div>
);'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'add banner'")
  local d r; d=$(_decision "$out"); r=$(_reason "$out")
  if [[ "$d" == "deny" && "$r" == *"banner.tsx"* && "$r" == *"token"* ]]; then
    _report "T6 component Tailwind [#hex] -> deny (names file + token)" ok
  else
    _report "T6 component Tailwind [#hex] -> deny" fail "d=$d r=${r:0:120}"
  fi
  rm -rf "$repo"
}

t_component_inline_style_hex_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const Banner = () => (
  <div style={{ background: "#2563eb" }}>hi</div>
);'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'add banner'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T7 component inline 'background: #hex' -> deny" ok \
    || _report "T7 component inline style hex -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

# Even a brand-palette hex literal is blocked in a component: components MUST
# reference the token, never the literal (distinguishes UI strictness from the
# email path-scoped literal-hex exception).
t_component_brand_hex_still_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/app/page.tsx" \
'export default () => <a className="bg-[#c9a962]">x</a>;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'gold literal'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T8 component brand-palette literal still blocked (use token)" ok \
    || _report "T8 component brand literal -> deny" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

# ---- token-definition CSS exemption ----

t_token_css_exempt() {
  local repo; repo=$(_seed_repo)
  # Editing globals.css to add another token must NOT be blocked.
  ( cd "$repo" && printf '  --brand-extra: #336699;\n' >> apps/web-platform/app/globals.css \
      && git add apps/web-platform/app/globals.css )
  local out; out=$(_run "$repo" "Bash" "git commit -m 'add token'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T9 token-definition CSS (:root --x: #hex) -> allow (exempt)" ok \
    || _report "T9 token CSS exempt -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

# ---- email path-scoped exception ----

t_email_brand_hex_allowed() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/server/notifications.ts" \
'const cta = { background: "#c9a962", color: "#1a1612" };'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'email cta'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T10 email with brand-palette hex -> allow (exception)" ok \
    || _report "T10 email brand hex -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

t_email_offbrand_hex_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/server/notifications.ts" \
'const cta = { background: "#2563eb" };'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'email cta'")
  local d r; d=$(_decision "$out"); r=$(_reason "$out")
  if [[ "$d" == "deny" && "$r" == *"notifications.ts"* && "$r" == *"palette"* ]]; then
    _report "T11 email off-brand hex -> deny (names file + palette)" ok
  else
    _report "T11 email off-brand hex -> deny" fail "d=$d r=${r:0:140}"
  fi
  rm -rf "$repo"
}

# ---- trigger variants on a real finding ----

t_chained_commit_triggers() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const B = () => <div className="bg-[#2563eb]">x</div>;'
  local out; out=$(_run "$repo" "Bash" "git status && git commit -m 'add'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T12 chained '... && git commit' triggers scan -> deny" ok \
    || _report "T12 chained commit triggers -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

t_amend_triggers() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const B = () => <div className="bg-[#2563eb]">x</div>;'
  local out; out=$(_run "$repo" "Bash" "git commit --amend --no-edit")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T13 'git commit --amend' triggers scan -> deny" ok \
    || _report "T13 amend triggers -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

# Non-color '#abc' anchor fragments / href targets must not false-positive
# (only bracketed [#hex] and 'prop: #hex' shapes are colour literals).
t_anchor_fragment_not_flagged() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/nav.tsx" \
'export const Nav = () => <a href="#abc">Skip to content</a>;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'nav'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T14 href='#abc' anchor not flagged -> allow" ok \
    || _report "T14 anchor fragment -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

# ---- broadened colour-literal detection (review P1/P2) ----

t_svg_fill_attr_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/icon.tsx" \
'export const I = () => <svg><path fill="#2563eb" /></svg>;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'icon'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T15 SVG fill=\"#hex\" attribute -> deny" ok \
    || _report "T15 SVG fill attr -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

t_svg_url_ref_not_flagged() {
  local repo; repo=$(_seed_repo)
  # fill="url(#gradientId)" is a paint reference, not a colour literal — even
  # when the id is hex-shaped — and must not false-positive.
  _stage "$repo" "apps/web-platform/components/dashboard/icon.tsx" \
'export const I = () => <svg><path fill="url(#abc123)" /></svg>;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'icon'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T16 fill=\"url(#abc123)\" paint ref not flagged -> allow" ok \
    || _report "T16 url() paint ref -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

t_border_shorthand_hex_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/box.tsx" \
'export const B = () => <div style={{ border: "1px solid #2563eb" }} />;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'box'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T17 'border: 1px solid #hex' (hex not adjacent to colon) -> deny" ok \
    || _report "T17 border shorthand hex -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

t_gradient_offbrand_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/hero.tsx" \
'export const H = () => <div style={{ background: "linear-gradient(135deg, #2563eb, #1d4ed8)" }} />;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'hero'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T18 linear-gradient(#hex, #hex) -> deny" ok \
    || _report "T18 gradient hex -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

t_four_digit_bracket_blocked() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/box.tsx" \
'export const B = () => <div className="bg-[#1234]" />;'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'box'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T19 4-digit Tailwind [#rgba] -> deny" ok \
    || _report "T19 4-digit bracket -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

# ---- diff-base selection (review P2): flag-like text in the message must not
#      flip the base to HEAD and deny a clean-staged commit ----

t_message_flaglike_text_no_false_deny() {
  local repo; repo=$(_seed_repo)
  # Stage a CLEAN (tokenized) component; leave an UNSTAGED off-brand edit in a
  # different tracked file. A plain commit must only see the clean staged file.
  ( cd "$repo"
    mkdir -p apps/web-platform/components/dashboard
    printf '%s\n' 'export const A = () => <div className="bg-brand-accent-gold-fill" />;' \
      > apps/web-platform/components/dashboard/a.tsx
    printf '%s\n' 'export const B = () => <div className="bg-brand-accent-gold-fill" />;' \
      > apps/web-platform/components/dashboard/b.tsx
    git add apps/web-platform/components/dashboard/a.tsx apps/web-platform/components/dashboard/b.tsx
    git commit -q -m "seed components"
    # now: clean staged edit to a.tsx, unstaged off-brand edit to b.tsx
    printf '%s\n' 'export const A = () => <div className="bg-brand-accent-gold-fill p-2" />;' \
      > apps/web-platform/components/dashboard/a.tsx
    printf '%s\n' 'export const B = () => <div className="bg-[#2563eb]" />;' \
      > apps/web-platform/components/dashboard/b.tsx
    git add apps/web-platform/components/dashboard/a.tsx )
  local out; out=$(_run "$repo" "Bash" "git commit -m 'fix -a flag handling'")
  [[ "$(_decision "$out")" == "allow" ]] \
    && _report "T20 '-a' inside -m message does not flip base (no false deny)" ok \
    || _report "T20 message flag-like text -> allow" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

t_real_dash_a_scans_unstaged() {
  local repo; repo=$(_seed_repo)
  ( cd "$repo"
    mkdir -p apps/web-platform/components/dashboard
    printf '%s\n' 'export const B = () => <div className="bg-brand-accent-gold-fill" />;' \
      > apps/web-platform/components/dashboard/b.tsx
    git add apps/web-platform/components/dashboard/b.tsx
    git commit -q -m "seed"
    # off-brand edit, NOT staged — `git commit -a` will commit it
    printf '%s\n' 'export const B = () => <div className="bg-[#2563eb]" />;' \
      > apps/web-platform/components/dashboard/b.tsx )
  local out; out=$(_run "$repo" "Bash" "git commit -a -m 'tweak'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T21 'git commit -a' scans unstaged tracked off-brand edit -> deny" ok \
    || _report "T21 real -a scans unstaged -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

# ---- palette integrity (review P1): an unstaged worktree token edit must NOT
#      whitelist an off-brand email colour ----

t_palette_poison_via_unstaged_worktree() {
  local repo; repo=$(_seed_repo)
  # Poison globals.css in the WORKTREE only (do not stage it), declaring the
  # off-brand colour as a token. The email check must still use the committed
  # palette and block the off-brand hex.
  ( cd "$repo" && printf '  --sneaky: #2563eb;\n' >> apps/web-platform/app/globals.css )
  _stage "$repo" "apps/web-platform/server/notifications.ts" \
'const x = { color: "#2563eb" };'
  local out; out=$(_run "$repo" "Bash" "git commit -m 'email'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T22 unstaged worktree token poison does NOT whitelist email hex -> deny" ok \
    || _report "T22 palette poison -> deny" fail "$(_decision "$out") / $(_reason "$out")"
  rm -rf "$repo"
}

# ---- generalisation (review P3): single-line / minified token CSS still
#      yields a palette so the email off-brand check works ----

t_single_line_token_css_palette() {
  local tmp; tmp=$(mktemp -d -p "$SUITE_TMP")
  ( cd "$tmp"
    git init -q -b main
    git config user.email t@t; git config user.name t
    mkdir -p apps/web-platform/server design
    # Token sink is a non-globals .css on a single line (minified shape).
    printf '%s\n' ':root { --brand-gold: #c9a962; --brand-ink: #1a1612; }' > design/theme.css
    git add design/theme.css
    git commit -q -m "seed minified tokens" )
  # brand hex in email -> allow (palette discovered from single-line CSS)
  _stage "$tmp" "apps/web-platform/server/notifications.ts" 'const a = { color: "#c9a962" };'
  local out1; out1=$(_run "$tmp" "Bash" "git commit -m e1")
  # off-brand hex in email -> deny
  ( cd "$tmp" && git reset -q apps/web-platform/server/notifications.ts && rm -f apps/web-platform/server/notifications.ts )
  _stage "$tmp" "apps/web-platform/server/notifications.ts" 'const a = { color: "#2563eb" };'
  local out2; out2=$(_run "$tmp" "Bash" "git commit -m e2")
  if [[ "$(_decision "$out1")" == "allow" && "$(_decision "$out2")" == "deny" ]]; then
    _report "T23 single-line token CSS -> palette discovered (brand allow / off-brand deny)" ok
  else
    _report "T23 single-line token CSS palette" fail "brand=$(_decision "$out1") offbrand=$(_decision "$out2")"
  fi
  rm -rf "$tmp"
}

t_non_bash_tool
t_bash_non_commit
t_substring_not_match
t_commit_tree_not_matched
t_clean_component_tokenized
t_component_tailwind_hex_blocked
t_component_inline_style_hex_blocked
t_component_brand_hex_still_blocked
t_token_css_exempt
t_email_brand_hex_allowed
t_email_offbrand_hex_blocked
t_chained_commit_triggers
t_amend_triggers
t_anchor_fragment_not_flagged
t_svg_fill_attr_blocked
t_svg_url_ref_not_flagged
t_border_shorthand_hex_blocked
t_gradient_offbrand_blocked
t_four_digit_bracket_blocked
t_message_flaglike_text_no_false_deny
t_real_dash_a_scans_unstaged
t_palette_poison_via_unstaged_worktree
# Devin wire name `exec` reaches the gated scan (kind map, #8205).
t_devin_exec_triggers() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "apps/web-platform/components/dashboard/banner.tsx" \
'export const B = () => <div className="bg-[#2563eb]">x</div>;'
  local out; out=$(_run "$repo" "exec" "git commit -m 'add'")
  [[ "$(_decision "$out")" == "deny" ]] \
    && _report "T24 Devin exec tool_name reaches scan -> deny" ok \
    || _report "T24 Devin exec tool_name reaches scan -> deny" fail "$(_decision "$out")"
  rm -rf "$repo"
}

t_single_line_token_css_palette
t_devin_exec_triggers

# ---- #10793: the gate scans the repository a commit TARGETS, not the hook cwd ----
# A hook process anchored at a core.bare=true root cannot see a linked worktree through
# its own cwd, so `cd <wt> && git commit` and `git -C <wt> commit` went unscanned. The
# target is now read from the command text (lib/commit-target-roots.sh). Hex fixtures are
# synthesised inline; deny rows each carry an allow twin.

OFFBRAND_TSX='export const B = () => <div className="bg-[#2563eb]">x</div>;'
CLEAN_TSX='export const B = () => <div className="bg-brand-accent-gold-fill">x</div>;'
BANNER="apps/web-platform/components/dashboard/banner.tsx"

# Sets OUT (stdout), ERR (stderr), RC (hook exit status) and the journal watermark.
# $3 is an optional PATH directory (the hook then runs under that directory's bash only);
# HOOK_UNDER overrides the hook path (the lib-missing case runs a copy).
_run_cmd() {
  local cwd="$1" cmd="$2" pd="${3:-}" payload errf
  errf=$(mktemp -p "$SUITE_TMP")
  _JOURNAL_MARK=$({ wc -l < "$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"; } 2>/dev/null || echo 0)
  payload=$(jq -nc --arg w "$cwd" --arg c "$cmd" '{tool_name: "Bash", cwd: $w, tool_input: {command: $c}}')
  RC=0
  if [[ -n "$pd" ]]; then
    # shellcheck disable=SC2086  # RUN_ENV is a space-free VAR=value list from the test itself
    OUT=$(cd "$cwd" && env PATH="$pd" ${RUN_ENV:-} CLAUDE_PROJECT_DIR="$REPO_ROOT" "$pd/bash" "${HOOK_UNDER:-$HOOK}" <<<"$payload" 2>"$errf") || RC=$?
  else
    # shellcheck disable=SC2086
    OUT=$(cd "$cwd" && env ${RUN_ENV:-} CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "${HOOK_UNDER:-$HOOK}" <<<"$payload" 2>"$errf") || RC=$?
  fi
  ERR=$(cat "$errf"); rm -f "$errf"
}

# This hook's own incident rows since the last _run_cmd, as "<event>|<prefix>" lines.
_gate_rows() {
  local f="$SOLEUR_TEST_INCIDENT_ROOT/.claude/.rule-incidents.jsonl"
  [[ -f "$f" ]] || return 0
  tail -n "+$(( ${_JOURNAL_MARK:-0} + 1 ))" "$f" \
    | jq -r 'select(.rule_id | startswith("brand-hex-commit-gate")) | .event_type + "|" + .rule_text_prefix'
}

# A bare root (core.bare=true) with one linked worktree: sets BARE and WT as PHYSICAL paths
# (ctr_resolve_roots returns toplevels physically, so a symlinked tmpdir would break matching).
_seed_bare() {
  BARE=$(_seed_repo); BARE=$(cd "$BARE" && pwd -P)
  ( cd "$BARE" && git config core.bare true && git worktree add -q .worktrees/wt -b wtb )
  WT="$BARE/.worktrees/wt"
}

_phys() { ( cd "$1" && pwd -P ); }

# In $WT: commit a clean tracked banner, then leave an OFF-BRAND edit to it unstaged (tracked, modified,
# NOT staged), so only a working-tree diff base ('commit -a' / '-p') can see it. Paths are rooted at the
# guarded $WT, never at a cd, so the relative-path ratchet can prove them absolute.
_dirty_tracked_banner() {
  assert_fixture_dir "$WT"
  mkdir -p "$WT/$(dirname "$BANNER")"
  printf '%s\n' "$CLEAN_TSX" > "$WT/$BANNER"
  git -C "$WT" add "$BANNER"
  git -C "$WT" commit -q -m "seed banner"
  printf '%s\n' "$OFFBRAND_TSX" > "$WT/$BANNER"
}


# PATH directory carrying the tools the hook needs, and NOT perl (the lexer needs it).
_mk_path_dir() {
  local d t p
  d=$(mktemp -d "$SUITE_TMP/path.XXXXXX")
  for t in bash sh git jq mktemp grep cat dirname basename rm date flock sed awk tr head tail cut wc \
           sort env readlink realpath mkdir chmod touch id stat ls cp mv ln find xargs expr uname seq; do
    p=$(command -v "$t" 2>/dev/null) || continue
    [[ "$p" == /* ]] && ln -s "$p" "$d/$t"
  done
  echo "$d"
}

_is_deny()  { [[ "$(_decision "$OUT")" == deny ]]; }
_is_allow() { [[ "$(_decision "$OUT")" == allow ]]; }

# Assertion helper: _expect <label> <detail> <test-command...>
_expect() {
  local label="$1" detail="$2"; shift 2
  if "$@"; then _report "$label" ok; else _report "$label" fail "$detail"; fi
}

_expect_warn_allow() {
  local label="$1"
  if [[ "$(_decision "$OUT")" == allow && "$RC" -eq 0 && "$ERR" == *WARN* && "$ERR" == *"cannot determine"* \
        && "$OUT" != *'"deny"'* && "$OUT" != *'"ask"'* ]]; then
    _report "$label" ok
  else
    _report "$label" fail "d=$(_decision "$OUT") rc=$RC err=${ERR:0:160} out=${OUT:0:80}"
  fi
}

t_t25_cd_into_worktree_from_bare_root() {
  _seed_bare
  # Fixture self-check: the cwd really is a bare root (no work tree) and the target really is one.
  local bare_flag wt_flag
  bare_flag=$(git -C "$BARE" rev-parse --is-inside-work-tree 2>/dev/null || true)
  wt_flag=$(git -C "$WT" rev-parse --is-inside-work-tree 2>/dev/null || true)
  _expect "T25a fixture: bare root is not a work tree, worktree is" "bare=$bare_flag wt=$wt_flag" \
    test "$bare_flag" = false -a "$wt_flag" = true
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$BARE" "cd $WT && git commit -m x"
  _expect "T25 'cd <wt> && git commit' from a bare root, off-brand staged -> deny names file" \
    "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 120)" \
    bash -c '[[ "$1" == deny && "$2" == *banner.tsx* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")"
  _stage "$WT" "$BANNER" "$CLEAN_TSX"
  _run_cmd "$BARE" "cd $WT && git commit -m x"
  _expect "T25b same command, tokenized content -> allow" "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 120)" _is_allow
  rm -rf "$BARE"
}

t_t26_dash_c_worktree() {
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$BARE" "git -C $WT commit -m x"
  _expect "T26 'git -C <wt> commit' from a bare root, off-brand staged -> deny names file" \
    "d=$(_decision "$OUT") err=${ERR:0:120}" \
    bash -c '[[ "$1" == deny && "$2" == *banner.tsx* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")"
  _stage "$WT" "$BANNER" "$CLEAN_TSX"
  _run_cmd "$BARE" "git -C $WT commit -m x"
  _expect "T26b same command, tokenized content -> allow" "d=$(_decision "$OUT")" _is_allow
  # The strict regex needs the words adjacent, so `git -C W commit` never reached the scan, even
  # from inside a work tree: a -C that names a DIFFERENT repository was skipped entirely.
  local other; other=$(_seed_repo)
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$other" "git -C $WT commit -m x"
  _expect "T26c 'git -C <other repo> commit' from inside a clean work tree -> deny" "d=$(_decision "$OUT")" _is_deny
  rm -rf "$BARE" "$other"
}

t_t27_t28_no_cd_unchanged() {
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$BARE" "git commit -m x"
  _expect "T27 bare-root cwd, plain 'git commit' (no cd/-C) -> allow with no WARN (unchanged)" \
    "d=$(_decision "$OUT") err=${ERR:0:120}" \
    bash -c '[[ "$1" == allow && "$2" != *WARN* ]]' _ "$(_decision "$OUT")" "$ERR"
  rm -rf "$BARE"
  local repo; repo=$(_seed_repo)
  _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$repo" "git commit -m x"
  _expect "T28 no-cd path: repo cwd, off-brand staged -> deny, reason text unchanged" "d=$(_decision "$OUT")" \
    bash -c '[[ "$1" == deny && "$2" == "BLOCKED: brand-hex-commit-gate found 1 raw hex colour literal(s) in staged UI/template content. Locations: apps/web-platform/components/dashboard/banner.tsx:1 (component #2563eb;"* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")"
  _run_cmd "$repo" 'echo "git -C x commit"'
  _expect "T28b prose mention of 'git -C x commit' with off-brand staged -> allow (not a commit)" "d=$(_decision "$OUT")" _is_allow
  _run_cmd "$repo" "git commit-tree abc123"
  _expect "T28c 'git commit-tree' with off-brand staged -> allow" "d=$(_decision "$OUT")" _is_allow
  rm -rf "$repo"
}

t_t29_diff_base_follows_commit_all() {
  _seed_bare
  _dirty_tracked_banner
  _run_cmd "$BARE" "git -C $WT commit -a -m x"
  _expect "T29 'git -C <wt> commit -a' scans the unstaged tracked edit -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "git -C $WT commit -m x"
  _expect "T29b same fixture without -a (nothing staged) -> allow" "d=$(_decision "$OUT")" _is_allow
  _run_cmd "$BARE" "cd $WT && git commit -a -m x"
  _expect "T29c 'cd <wt> && git commit -a' scans the unstaged tracked edit -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "git -C $WT commit -m 'fix -a flag handling'"
  _expect "T29d '-a' inside the -m text does not flip the base for the -C form -> allow" "d=$(_decision "$OUT")" _is_allow
  rm -rf "$BARE"
}

t_t30_two_roots() {
  local a b
  a=$(_seed_repo); a=$(_phys "$a"); b=$(_seed_repo); b=$(_phys "$b")
  _stage "$b" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T30 clean cwd repo + 'cd <off-brand repo>' -> deny, finding prefixed with the target root" \
    "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 160)" \
    bash -c '[[ "$1" == deny && "$2" == *"[$3]"* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")" "$(basename "$b")"
  _stage "$b" "$BANNER" "$CLEAN_TSX"
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T30b both repos clean -> allow" "d=$(_decision "$OUT")" _is_allow
  # Union, not replacement: the cwd repo holds the finding, the named target is clean.
  _stage "$a" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T30c finding in the cwd repo, named target clean -> deny (cwd root still scanned)" \
    "d=$(_decision "$OUT")" \
    bash -c '[[ "$1" == deny && "$2" == *"[$3]"* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")" "$(basename "$a")"
  rm -rf "$a" "$b"
}

# A palette is discovered from THAT repository's committed CSS. The named target (scanned
# first) has #2563eb as a brand colour; the cwd repo does not. The same email-class hex is
# on-brand in the first and off-brand in the second: a palette leaked from the first root
# turns the cwd repo's real finding into an allow.
t_t31_palette_per_root() {
  local a b
  a=$(_seed_repo); a=$(_phys "$a"); b=$(_seed_repo); b=$(_phys "$b")
  ( cd "$b" && printf '  --brand-blue: #2563eb;\n' >> apps/web-platform/app/globals.css \
      && git add apps/web-platform/app/globals.css && git commit -q -m "blue token" )
  _stage "$b" "apps/web-platform/server/notifications.ts" 'const a = { color: "#2563eb" };'
  _stage "$a" "apps/web-platform/server/notifications.ts" 'const a = { color: "#2563eb" };'
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T31 palette is rebuilt per root: cwd repo's off-brand email hex still denies" \
    "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 160)" \
    bash -c '[[ "$1" == deny && "$2" == *"[$3]"* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")" "$(basename "$a")"
  ( cd "$a" && git reset -q apps/web-platform/server/notifications.ts )
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T31b twin: only the root where the hex IS a brand colour is staged -> allow" "d=$(_decision "$OUT")" _is_allow
  rm -rf "$a" "$b"
}

t_t32_relative_quoted_and_missing_targets() {
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$BARE" "cd ./.worktrees/wt && git commit -m x"
  _expect "T32 relative 'cd ./.worktrees/wt' resolves against the hook cwd -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "cd \"$WT\" && git commit -m x"
  _expect "T32b double-quoted literal path -> deny" "d=$(_decision "$OUT")" _is_deny
  _stage "$WT" "$BANNER" "$CLEAN_TSX"
  _run_cmd "$BARE" "cd ./.worktrees/wt && git commit -m x"
  _expect "T32c relative target, clean content -> allow" "d=$(_decision "$OUT")" _is_allow
  rm -rf "$BARE"
  local repo; repo=$(_seed_repo)
  _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$repo" "cd /nonexistent-dir-10793 && git commit -m x"
  _expect "T32d target that does not exist falls back to the cwd repo -> deny" "d=$(_decision "$OUT")" _is_deny
  rm -rf "$repo"
}

t_t33_undeterminable_warns_and_allows() {
  local repo; repo=$(_seed_repo)
  _stage "$repo" "$BANNER" "$OFFBRAND_TSX"   # the cwd repo would DENY if it were scanned
  local c rows
  # Single quotes on purpose: $WT / ~ / the glob must reach the hook as LITERAL text, unexpanded.
  for c in 'cd "$WT" && git commit -m x' 'cd ~/x && git commit -m x' 'cd wt* && git commit -m x' \
           'GIT_DIR=/x git commit -m x' 'git --git-dir=/x commit -m x'; do
    _run_cmd "$repo" "$c"
    _expect_warn_allow "T33 undeterminable target [$c] -> WARN + allow, no scan (cwd repo holds off-brand)"
    rows=$(_gate_rows)
    _expect "T33b [$c] records a bypass row" "rows=$rows" \
      bash -c '[[ "$1" == *"bypass|target undeterminable"* ]]' _ "$rows"
  done
  rm -rf "$repo"
}

t_t34_no_perl() {
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  local nop; nop=$(_mk_path_dir)
  [[ ! -e "$nop/perl" ]] || { _report "T34 fixture: PATH dir has no perl" fail "perl present"; return; }
  _run_cmd "$BARE" "git -C $WT commit -m x" "$nop"
  _expect_warn_allow "T34 no perl: 'git -C <wt> commit' -> WARN + allow"
  _expect "T34d ... the row names the lexer as the cause" "rows=$(_gate_rows)" \
    bash -c '[[ "$1" == *"target undeterminable: lexer unavailable"* ]]' _ "$(_gate_rows)"
  _run_cmd "$BARE" "cd $WT && git commit -m x" "$nop"
  _expect_warn_allow "T34b no perl: 'cd <wt> && git commit' -> WARN + allow"
  rm -rf "$BARE"
  # A perl-less host must not go silent on every plain commit.
  local repo; repo=$(_seed_repo)
  _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$repo" "git commit -m x" "$nop"
  _expect "T34c no perl: plain 'git commit' in a repo with off-brand staged -> deny (cwd path)" \
    "d=$(_decision "$OUT") err=${ERR:0:120}" _is_deny
  rm -rf "$repo"
}

t_t35_lib_missing() {
  local tmp="$SUITE_TMP/nolib"; mkdir -p "$tmp/lib"
  cp "$REPO_ROOT/.claude/hooks/brand-hex-commit-gate.sh" "$tmp/"
  cp "$REPO_ROOT"/.claude/hooks/lib/*.sh "$tmp/lib/"
  rm -f "$tmp/lib/commit-target-roots.sh"
  [[ ! -e "$tmp/lib/commit-target-roots.sh" ]] || { _report "T35 fixture: lib removed" fail "still present"; return; }
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  HOOK_UNDER="$tmp/brand-hex-commit-gate.sh" _run_cmd "$BARE" "git -C $WT commit -m x"
  _expect_warn_allow "T35 lib missing: 'git -C <wt> commit' -> WARN + allow"
  _expect "T35c ... the row names the missing lib as the cause" "rows=$(_gate_rows)" \
    bash -c '[[ "$1" == *"target undeterminable: lib missing"* ]]' _ "$(_gate_rows)"
  rm -rf "$BARE"
  local repo; repo=$(_seed_repo)
  _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  HOOK_UNDER="$tmp/brand-hex-commit-gate.sh" _run_cmd "$repo" "git commit -m x"
  _expect "T35b lib missing: plain 'git commit' with off-brand staged -> deny (unchanged cwd path)" \
    "d=$(_decision "$OUT")" _is_deny
  rm -rf "$repo" "$tmp"
}

t_t36_header_no_longer_claims_identity() {
  local hook="$REPO_ROOT/.claude/hooks/brand-hex-commit-gate.sh" n_ident n_lib
  n_ident=$(grep -cE 'identical (copy|to git-commit-secret-scan)' "$hook" || true)
  # the first 40 lines are the header paragraph; a `# shellcheck source=` directive further down is not it
  n_lib=$(sed -n 1,40p "$hook" | grep -c '^# .*lib/commit-target-roots.sh' || true)
  _expect "T36 header/in-body comments drop the 'identical to the secret scan' claim and name the lib" \
    "identical=$n_ident lib=$n_lib" test "$n_ident" -eq 0 -a "$n_lib" -ge 1
}

# Fixture control: the same off-brand worktree committed from INSIDE it, with no cd/-C, denies.
# A green deny in T25/T26 therefore means the TARGET was resolved, not that the fixture is odd.
t_t37_fixture_control() {
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$WT" "git commit -m x"
  _expect "T37 fixture control: commit from inside the worktree with no cd -> deny" "d=$(_decision "$OUT")" _is_deny
  rm -rf "$BARE"
}

t_t25_cd_into_worktree_from_bare_root
t_t26_dash_c_worktree
t_t27_t28_no_cd_unchanged
t_t29_diff_base_follows_commit_all
t_t30_two_roots
t_t31_palette_per_root
t_t32_relative_quoted_and_missing_targets
t_t33_undeterminable_warns_and_allows
t_t34_no_perl
t_t35_lib_missing
t_t36_header_no_longer_claims_identity
t_t37_fixture_control

# ---- review round (#10793): rows for the mutants the first battery could not reach ----

# Repos are cloned under a stable parent so two of them can share a basename.
_dup_basename_repos() {
  local x y
  x="$SUITE_TMP/dupx"; y="$SUITE_TMP/dupy"; mkdir -p "$x" "$y"
  DUPA=$(_seed_repo); mv "$DUPA" "$x/app"; DUPA=$(_phys "$x/app")
  DUPB=$(_seed_repo); mv "$DUPB" "$y/app"; DUPB=$(_phys "$y/app")
}

t_t38_target_config_cannot_run_code() {
  _seed_bare
  local mk="$SUITE_TMP/mk38" tc="$SUITE_TMP/tc38.sh" fm="$SUITE_TMP/fm38.sh"
  mkdir -p "$mk"
  printf '#!/bin/sh\n: > "%s/textconv"\ncat "$1"\n' "$mk" > "$tc"
  printf '#!/bin/sh\n: > "%s/fsmonitor"\nexit 0\n' "$mk" > "$fm"
  chmod +x "$tc" "$fm"
  assert_fixture_dir "$WT"
  printf '%s\n' '*.tsx diff=evil' > "$WT/.gitattributes"
  git -C "$WT" config diff.evil.textconv "$tc"
  git -C "$WT" config core.fsmonitor "$fm"
  _dirty_tracked_banner
  rm -f "$mk"/textconv "$mk"/fsmonitor
  _run_cmd "$BARE" "git -C $WT commit -a -m x"
  _expect "T38 a target repo's textconv driver and fsmonitor hook do not run in the gate (still denies)" \
    "d=$(_decision "$OUT") textconv=$([[ -e $mk/textconv ]] && echo RAN || echo no) fsmonitor=$([[ -e $mk/fsmonitor ]] && echo RAN || echo no)" \
    bash -c '[[ "$1" == deny && ! -e "$2/textconv" && ! -e "$2/fsmonitor" ]]' _ "$(_decision "$OUT")" "$mk"
  rm -rf "$BARE"
}

# Two repos, each with its OWN on-brand email colour, each staging it. Whatever order the roots are
# scanned in, a palette leaked from the first would turn the second's on-brand colour into a deny.
t_t39_palette_symmetric() {
  local a b
  a=$(_seed_repo); a=$(_phys "$a"); b=$(_seed_repo); b=$(_phys "$b")
  ( cd "$a" && printf '  --brand-x: #123456;\n' >> apps/web-platform/app/globals.css \
      && git add -A && git commit -q -m "token x" )
  ( cd "$b" && printf '  --brand-y: #654321;\n' >> apps/web-platform/app/globals.css \
      && git add -A && git commit -q -m "token y" )
  _stage "$a" "apps/web-platform/server/notifications.ts" 'const a = { color: "#123456" };'
  _stage "$b" "apps/web-platform/server/notifications.ts" 'const a = { color: "#654321" };'
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect "T39 each root's own on-brand email colour allows (cwd=a, target=b)" "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 140)" _is_allow
  _run_cmd "$b" "cd $a && git commit -m x"
  _expect "T39b each root's own on-brand email colour allows (cwd=b, target=a)" "d=$(_decision "$OUT") r=$(_reason "$OUT" | head -c 140)" _is_allow
  rm -rf "$a" "$b"
}

t_t40_inherited_git_dir_does_not_redirect_the_scan() {
  local a b
  a=$(_seed_repo); a=$(_phys "$a"); b=$(_seed_repo); b=$(_phys "$b")
  _stage "$a" "$BANNER" "$OFFBRAND_TSX"
  RUN_ENV="GIT_DIR=$b/.git" _run_cmd "$b" "cd $a && git commit -m x"
  _expect "T40 an inherited GIT_DIR (clean repo b) does not hide the named repo a's off-brand staged file" \
    "d=$(_decision "$OUT")" _is_deny
  rm -rf "$a" "$b"
}

t_t41_diff_base_comes_from_the_lexer() {
  _seed_bare
  _dirty_tracked_banner
  _run_cmd "$BARE" "ls -la && git -C $WT commit -m x"
  _expect "T41 'ls -la' before a -C commit does not read as commit -a -> allow" "d=$(_decision "$OUT")" _is_allow
  _run_cmd "$BARE" "git -C $WT commit -a -m 'do git commit now'"
  _expect "T41b a quoted 'git commit' in the message does not hide the real -a -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "git -C $WT commit -a -m x && git commit -m y"
  _expect "T41c '-C W commit -a' followed by a plain commit still sees the -a -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "cd $WT && git commit -p -m x"
  _expect "T41d 'cd W && git commit -p' takes the working-tree base -> deny" "d=$(_decision "$OUT")" _is_deny
  _run_cmd "$BARE" "cd $WT && git commit -m 'see git commit -a docs'"
  _expect "T41e '-a' inside a quoted 'git commit' in the message does not flip the base -> allow" "d=$(_decision "$OUT")" _is_allow
  rm -rf "$BARE"
}

t_t42_no_perl_fallback() {
  local nop repo; nop=$(_mk_path_dir)
  repo=$(_seed_repo); _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  local c
  for c in "git commit -m 'fix cd handling'" "GIT_AUTHOR_DATE=2020-01-01T00:00:00 git commit -m x" "git commit -C HEAD"; do
    _run_cmd "$repo" "$c" "$nop"
    _expect "T42 no perl: ordinary commit [$c] is still scanned -> deny" "d=$(_decision "$OUT") err=${ERR:0:100}" _is_deny
  done
  _run_cmd "$repo" "cd /tmp && git log --oneline --grep=commit" "$nop"
  _expect "T42b no perl: a non-commit that mentions cd and 'commit' -> silent allow (no WARN, no row)" \
    "d=$(_decision "$OUT") err=${ERR:0:100} rows=$(_gate_rows)" \
    bash -c '[[ "$1" == allow && "$2" != *WARN* && -z "$3" ]]' _ "$(_decision "$OUT")" "$ERR" "$(_gate_rows)"
  rm -rf "$repo"
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  for c in "env --chdir=$WT git commit -m x" "bash -c 'cd $WT && git commit -m x'" "git -c core.worktree=$WT commit -m x"; do
    _run_cmd "$BARE" "$c" "$nop"
    _expect_warn_allow "T42c no perl: target-moving form [${c%% *}...] -> WARN + allow"
  done
  rm -rf "$BARE"
}

# perl is present but the lexer cannot parse the text (an unterminated quote): the same WARN + allow.
t_t43_lexer_failure_with_perl() {
  local a b
  a=$(_seed_repo); b=$(_seed_repo)
  _stage "$b" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$a" "cd $b && git commit -m 'unterminated"
  _expect_warn_allow "T43 lexer cannot parse the command -> WARN + allow"
  _expect "T43b ... and the row names the lexer as the cause" "rows=$(_gate_rows)" \
    bash -c '[[ "$1" == *"bypass|target undeterminable: lexer unavailable"* ]]' _ "$(_gate_rows)"
  rm -rf "$a" "$b"
}

t_t44_cwd_equals_target_is_one_root() {
  local a; a=$(_seed_repo); a=$(_phys "$a")
  _stage "$a" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$a" "cd $a && git commit -m x"
  _expect "T44 target == cwd repo is ONE root: one finding, no [prefix]" "r=$(_reason "$OUT" | head -c 140)" \
    bash -c '[[ "$1" == deny && "$2" == *"found 1 raw"* && "$2" != *"["*"]"* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")"
  rm -rf "$a"
}

t_t45_unreadable_target_repo() {
  local a b; a=$(_seed_repo); b=$(_seed_repo)
  printf '[core\n bad' >> "$b/.git/config"
  _run_cmd "$a" "cd $b && git commit -m x"
  _expect_warn_allow "T45 a target repository git cannot read -> WARN + allow"
  rm -rf "$a" "$b"
}

t_t46_same_basename_roots_are_told_apart() {
  _dup_basename_repos
  _stage "$DUPB" "$BANNER" "$OFFBRAND_TSX"
  _stage "$DUPA" "$BANNER" "$OFFBRAND_TSX"
  _run_cmd "$DUPA" "cd $DUPB && git commit -m x"
  _expect "T46 two roots both named 'app': the finding prefixes carry the full paths" "r=$(_reason "$OUT" | head -c 200)" \
    bash -c '[[ "$1" == deny && "$2" == *"[$3] "* && "$2" == *"[$4] "* ]]' _ "$(_decision "$OUT")" "$(_reason "$OUT")" "$DUPA" "$DUPB"
  rm -rf "$SUITE_TMP/dupx" "$SUITE_TMP/dupy"
}

# U+2028 / U+0085 survive a [[:cntrl:]] strip in a non-UTF-8 locale; the WARN carries the target text.
t_t47_warn_text_is_locale_proof() {
  local repo sep nel; repo=$(_seed_repo)
  sep=$(printf '\342\200\250'); nel=$(printf '\302\205')
  RUN_ENV="LC_ALL=C" _run_cmd "$repo" "cd /x${sep}y${nel}z/\$HOME && git commit -m x"
  _expect "T47 the WARN holds no U+2028 / U+0085 bytes under LC_ALL=C" "err=$(printf '%s' "$ERR" | od -c | head -3)" \
    bash -c '[[ "$1" == *WARN* && "$1" != *"$2"* && "$1" != *"$3"* ]]' _ "$ERR" "$sep" "$nel"
  rm -rf "$repo"
}

# The perl-less mover test must see what the lexer would: a newline-separated cd, env -C, a cd after a
# shell keyword; and must NOT see a mover that only appears in a commit message.
t_t48_no_perl_movers_and_messages() {
  local nop repo c; nop=$(_mk_path_dir)
  _seed_bare
  _stage "$WT" "$BANNER" "$OFFBRAND_TSX"
  for c in "$(printf 'echo hi\ncd %s\ngit commit -m x' "$WT")" "env -C $WT git commit -m x" \
           "if cd $WT; then git commit -m x; fi" "'cd' $WT && git commit -m x"; do
    _run_cmd "$BARE" "$c" "$nop"
    _expect_warn_allow "T48 no perl: mover shape [${c:0:22}] -> WARN + allow"
  done
  rm -rf "$BARE"
  repo=$(_seed_repo); _stage "$repo" "$BANNER" "$OFFBRAND_TSX"
  for c in 'git commit -m "cd into dir fix"' "git commit -m 'document GIT_DIR and --chdir'" 'git commit -am "build && cd out"'; do
    _run_cmd "$repo" "$c" "$nop"
    _expect "T48b no perl: a mover named only in the message is still scanned [$c] -> deny" "d=$(_decision "$OUT") err=${ERR:0:100}" _is_deny
  done
  _run_cmd "$repo" "git -c user.name=x commit -m x" "$nop"
  _expect "T48c no perl: a loose-only commit form is allowed unscanned, but leaves a bypass row" \
    "d=$(_decision "$OUT") rows=$(_gate_rows)" \
    bash -c '[[ "$1" == allow && "$2" == *"lexer unavailable (loose form)"* ]]' _ "$(_decision "$OUT")" "$(_gate_rows)"
  rm -rf "$repo"
}

# The perl-less loose-commit regex is quadratic on a long run of `git` words (measured 5.4 s at 40 KB
# uncapped) and the command is model-controlled: the hook must return promptly. The fixture carries a
# mover (cd) so the loose test is actually reached, and no `git commit` so it stays loose-only.
t_t49_no_perl_regexes_are_bounded() {
  local nop repo big t0 ms; nop=$(_mk_path_dir)
  repo=$(_seed_repo)
  big=$(printf 'git %.0s' $(seq 1 10000))
  t0=$(date +%s%N)
  _run_cmd "$repo" "commit $big cd x" "$nop"
  ms=$(( ($(date +%s%N) - t0) / 1000000 ))
  _expect "T49 a 40 KB run of git words returns promptly without perl (${ms} ms)" "d=$(_decision "$OUT") ms=$ms" \
    bash -c '[[ "$1" == allow && "$2" -lt 2000 ]]' _ "$(_decision "$OUT")" "$ms"
  rm -rf "$repo"
}

# The harness's own deciders: a suite that cannot fail proves nothing. Drive each once with an input
# that MUST be rejected, then unwind the counters so the floor below stays exact.
_selftest_instrument() {
  local p0=$pass f0=$fail ok=1 saved_out="${OUT:-}"
  _report "selftest-pass" ok >/dev/null
  _report "selftest-fail" fail "expected (instrument self-test)" 2>/dev/null
  [[ "$pass" -eq $((p0 + 1)) && "$fail" -eq $((f0 + 1)) ]] || ok=0
  pass=$p0; fail=$f0
  OUT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  _is_deny && ok=0
  OUT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'
  _is_allow && ok=0
  _expect "selftest-expect" "expected (instrument self-test)" false 2>/dev/null
  [[ "$fail" -eq $((f0 + 1)) ]] || ok=0
  pass=$p0; fail=$f0; OUT="$saved_out"
  [[ "$ok" -eq 1 ]] || { printf 'FATAL: instrument self-test failed - the suite cannot report a failure\n' >&2; exit 1; }
}

t_t38_target_config_cannot_run_code
t_t39_palette_symmetric
t_t40_inherited_git_dir_does_not_redirect_the_scan
t_t41_diff_base_comes_from_the_lexer
t_t42_no_perl_fallback
t_t43_lexer_failure_with_perl
t_t44_cwd_equals_target_is_one_root
t_t45_unreadable_target_repo
t_t46_same_basename_roots_are_told_apart
t_t47_warn_text_is_locale_proof
t_t48_no_perl_movers_and_messages
t_t49_no_perl_regexes_are_bounded
_selftest_instrument

# Assertion floor: not equality (every added assertion would then be a spurious failure); reported with
# printf + exit, never through the helpers it backstops.
MIN_ASSERTIONS=97
if [[ $((pass + fail)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: only %s assertions ran, floor is %s - the suite is not asserting\n' "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
