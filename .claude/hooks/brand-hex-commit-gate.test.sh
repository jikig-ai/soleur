#!/usr/bin/env bash
# Tests for .claude/hooks/brand-hex-commit-gate.sh.
# Deterministic — uses a temp git repo per test, no network. All hex
# fixtures are synthesised inline (cq-test-fixtures-synthesized-only); none
# are copied from app code.
set -euo pipefail

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
  local tmp; tmp=$(mktemp -d)
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
  local tmp; tmp=$(mktemp -d)
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
t_single_line_token_css_palette

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
