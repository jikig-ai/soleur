#!/usr/bin/env bash
# PreToolUse hook on Bash matching `git commit`. Scans the staged index for
# secret-shaped strings (PEM bodies, vendor tokens, AWS keys) via gitleaks
# and denies the commit if any are found.
#
# Why this hook exists alongside lefthook: lefthook's pre-commit hook is
# only triggered when a `.git/hooks/pre-commit` symlink is installed in
# the working repo (lefthook install). In Soleur's bare-repo + worktree
# topology, fresh worktrees do NOT inherit the hook from the bare repo
# unless `lefthook install` is re-run per worktree. The "Secret-scanning
# floor (#3121)" gate defined in lefthook.yml therefore never fires for
# many local commits — CI catches the leak only at push time. This
# PreToolUse hook closes the gap at the Bash-tool boundary, runs
# regardless of .git/hooks/ state, and cannot be bypassed by
# `git commit --no-verify`.
#
# Source rule: terraform-show-json leak incident (2026-05-25 learning).
# Routing: relies on the same `.gitleaks.toml` and gitleaks binary that
# lefthook would have used — no rule duplication.
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 always (JSON output controls the gate).
#
# Fail-open conditions (the hook allows the commit + emits a warn):
#   - gitleaks binary not installed on PATH          (bypass "gitleaks not installed")
#   - gitleaks on PATH but cannot run, e.g. an unpinned version-manager shim
#                                                    (bypass "gitleaks unrunnable (rc=N)")
#   - a RUNNABLE gitleaks exits non-zero with no report — plausibly transient
#                                                    (bypass "gitleaks exit=N, empty report")
#   - Not inside a git work tree
#   - .gitleaks.toml not present at the repo root
# These are operator-environment issues, not secret-leak signals — the
# user should fix their tooling but a missing binary should not block
# every commit. CI re-scans on every push as the load-bearing gate.
# The unrunnable case is split out because it is PERMANENT and machine-wide
# (#8266): folded into the "transient" branch it silently bypassed every
# commit on such a host under a reason that said otherwise.
#
# A `bypass` row is not proof the commit landed: where lefthook runs, its own
# `gitleaks-staged` step can still block the same commit (and, with an
# unrunnable gitleaks, fail it — see #8271).

set -euo pipefail

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
  emit git-commit-secret-scan deny "git-commit-secret-scan: $reason"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[git-commit-secret-scan] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

payload="$(cat)"
__HI_RAW="$payload"
# ADR-156: hook stdin is model-controlled. A non-string field is surfaced,
# never coerced — this hook never ran eval, but `jq -r` renders an array
# across lines, which matches none of its guards, so the payload would have
# slipped every gate below (#7164). ADR-157: it asks instead.
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "git-commit-secret-scan"
  hook_input_should_ask && { hook_input_emit_ask "git-commit-secret-scan"; exit 0; }
  exit 0
fi

tool_kind="$HOOK_TOOL_KIND"

# Only fire on Bash (or its Devin kind twin, exec — #8205).
[ "$tool_kind" = "Bash" ] || allow

command="$HOOK_CMD"
[ -n "$command" ] || allow

# Match `git commit` as a command-leading verb. Tolerates:
#   - bare `git commit ...`
#   - chained: `... && git commit ...`, `... ; git commit ...`, `... | git commit ...`
#   - leading whitespace
# Rejects:
#   - substring matches inside other args (e.g. `echo "git commit example"`)
#   - other git subcommands (git-commit-tree, git commit-graph)
#
# The regex anchors `git commit` after one of: start-of-string, whitespace
# after a chain operator (`&&`, `||`, `;`, `|`), or `$(`. Then requires a
# trailing space-or-end so `commit-tree` / `commit-graph` are not matched.
if ! grep -qE '(^|[[:space:]]|&&|\|\||;|\$\()[[:space:]]*git[[:space:]]+commit([[:space:]]|$)' <<<"$command"; then
  allow
fi

# At this point: the tool call is a `git commit` (or a chain containing one).
# Run gitleaks against the staged index. Fail-open if gitleaks is missing.

GL_REMEDIATION="CI pins gitleaks 8.24.2 — install that version or pin it in your version manager (e.g. 'mise use gitleaks@8.24.2')."

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[git-commit-secret-scan] WARN: gitleaks not installed — skipping scan. $GL_REMEDIATION" >&2
  emit git-commit-secret-scan bypass "gitleaks not installed"
  allow
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  emit git-commit-secret-scan bypass "not inside git work tree"
  allow
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$repo_root" ] || [ ! -f "$repo_root/.gitleaks.toml" ]; then
  echo "[git-commit-secret-scan] WARN: .gitleaks.toml not found at repo root — skipping scan." >&2
  emit git-commit-secret-scan bypass ".gitleaks.toml absent"
  allow
fi

# Placed AFTER the cheap repo/config guards on purpose: the probe spawns
# timeout+gitleaks and costs ~400 ms (measured). Above them it paid that on
# EVERY `git commit`, including ones outside a repo or in a repo with no
# .gitleaks.toml — calls that exit without ever scanning.

# RESOLVABLE IS NOT RUNNABLE (#8266). `command -v` only proves the name resolves;
# an unpinned mise shim resolves and exits non-zero on every call. Probe by
# running the tool. Bound it with timeout when one exists — stock macOS has
# neither `timeout` nor `gtimeout`, and a missing bound must never be misread as
# a broken gitleaks, or every macOS commit would skip the scan.
gl_to=()
if command -v timeout >/dev/null 2>&1; then gl_to=(timeout 10)
elif command -v gtimeout >/dev/null 2>&1; then gl_to=(gtimeout 10); fi
# `${a[@]+"${a[@]}"}`, not `"${a[@]}"`: bash 3.2 (stock macOS /bin/bash) treats an
# EMPTY array as unbound under `set -u`, which is exactly the no-timeout host.
gl_probe_rc=0
gl_probe_err="$( { ${gl_to[@]+"${gl_to[@]}"} gitleaks version >/dev/null; } 2>&1 )" || gl_probe_rc=$?
# A BOUND EXPIRY IS NOT AN UNRUNNABLE BINARY. `timeout` reports 124 when the bound
# expires (137 when it escalates to SIGKILL) — that is a statement about host LOAD,
# not about gitleaks. Treating it as "unrunnable" bypasses the scan on a host whose
# only problem is that it is busy, and prints a remediation (install/pin 8.24.2)
# that cannot fix it. This matters here specifically: #8231 exists to run these
# suites in PARALLEL, and concurrency is what expires a 10 s bound. Retry once at a
# wider bound before concluding anything.
case "$gl_probe_rc" in
  124|137)
    gl_retry_to=()
    if command -v timeout >/dev/null 2>&1; then gl_retry_to=(timeout 60)
    elif command -v gtimeout >/dev/null 2>&1; then gl_retry_to=(gtimeout 60); fi
    gl_probe_rc=0
    gl_probe_err="$( { ${gl_retry_to[@]+"${gl_retry_to[@]}"} gitleaks version >/dev/null; } 2>&1 )" || gl_probe_rc=$?
    case "$gl_probe_rc" in
      124|137)
        printf '[git-commit-secret-scan] WARN: the gitleaks probe timed out twice (rc=%s) — this host is too loaded to verify the scanner, so the staged content was NOT scanned. This is a load condition, not a broken install; re-run the commit when the machine is quieter.\n' \
          "$gl_probe_rc" >&2
        emit git-commit-secret-scan-probe-timeout bypass "gitleaks probe timed out (rc=$gl_probe_rc)"
        allow
        ;;
    esac
    ;;
esac
if [ "$gl_probe_rc" -ne 0 ]; then
  printf '[git-commit-secret-scan] WARN: gitleaks is on PATH but cannot run (rc=%s, %q) — skipping scan. %s\n' \
    "$gl_probe_rc" "${gl_probe_err%%$'\n'*}" "$GL_REMEDIATION" >&2
  emit git-commit-secret-scan bypass "gitleaks unrunnable (rc=$gl_probe_rc)"
  allow
fi

# Run the same scan lefthook.yml configures, against the staged index only.
# `--exit-code 1` makes gitleaks return non-zero on findings.
# `--redact` ensures the matched secret bytes do not appear in stderr.
# `--no-banner` reduces output noise.
# `--report-format json` + `--report-path` capture findings for the deny
# reason without printing the raw secrets to the hook's stdout/stderr.
report_file="$(mktemp -t gitleaks-staged-XXXXXX.json)"
nodiff_dir="$(mktemp -d -t gitleaks-nodiff-XXXXXX)"
nodiff_report="$(mktemp -t gitleaks-nodiff-XXXXXX.json)"
trap 'rm -f "$report_file" "$nodiff_report"; rm -rf "$nodiff_dir"' EXIT INT TERM

# GITATTRIBUTE BYPASS GUARD. `gitleaks git` reads a PATCH, so a path marked
# `-diff` renders as `Binary files a/x and b/x differ` with no `+` lines and
# scans clean — measured: `.git/info/attributes` containing `creds.txt -diff`
# took a staged AWS key from rc=1/1 finding to rc=0/0 findings. No colour pin
# closes it, and neither does `core.attributesFile=/dev/null` nor
# `GIT_ATTR_NOSYSTEM=1` (both measured): those govern the GLOBAL and SYSTEM
# attributes files, while `.git/info/attributes` is per-repo and always read.
# This is the same class the colour pin above exists for — ambient local git
# config silently disarming the scanner — so it is closed here, not documented.
#
# `check-attr` discriminates precisely: an explicit `-diff` reports `unset`,
# while an auto-detected binary (a PNG) reports `unspecified` (measured), so a
# legitimately-binary staged file is never caught by this.
# Affected paths are re-scanned from their STAGED blobs with `detect --no-git`,
# which never consults git's diff machinery at all — the same mechanism
# code-to-prd.sh's Layer 3 already relies on.
gl_nodiff=()
while IFS= read -r -d '' _p; do
  [ -n "$_p" ] || continue
  if [ "$(git -C "$repo_root" check-attr diff -- "$_p" 2>/dev/null | sed 's/.*: //')" = "unset" ]; then
    gl_nodiff+=("$_p")
  fi
done < <(git -C "$repo_root" diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)

# `gitleaks git --pre-commit --staged` scans only files added to the index
# (matches the lefthook-staged invocation byte-for-byte). The hook's CWD
# may not be the repo root, so cd into it first.
#
# COLOUR IS PINNED OFF for this invocation. `gitleaks git` runs git itself and
# inherits the user's config; under color.ui=always or color.diff=always it
# parses ANSI-wrapped patch lines and reports ZERO findings on a staged key
# (measured). lefthook.yml's gitleaks-staged step carries the same two pins.
#
# BOTH config surfaces must be pinned, not just GIT_CONFIG_COUNT.
# GIT_CONFIG_PARAMETERS is a SEPARATE source that git reads AFTER the
# GIT_CONFIG_COUNT list, so it beats the count-list pin outright — and `git -c
# <anything>` EXPORTS it into every hook git spawns. Measured: with only the
# count-list pin, `git -c color.diff=always commit` on a staged AWS key scanned
# rc=0 / 0 findings and the key landed in history; appending the pin to
# GIT_CONFIG_PARAMETERS restores rc=1 / 1 finding. We APPEND rather than replace
# so a caller's own `-c` settings survive.
#
# Within GIT_CONFIG_COUNT later entries win, so appending is the correct
# direction there too. But the append is only safe when the caller's count is a
# shape git AND this clamp agree on: git tolerates a leading space (" 2"), which
# the clamp below rewrites to 0, so the pin would then OVERWRITE the caller's
# first two entries rather than follow them. That is safe for the colour pin
# itself (it still lands, and still wins) and is why the clamp stays.
#
# A `-diff` gitattribute defeats colour pinning entirely (it removes the `+`
# lines rather than decorating them); that is closed separately by the
# check-attr guard above, not by these two pins.
gl_cfg_n="${GIT_CONFIG_COUNT:-0}"
case "$gl_cfg_n" in ''|*[!0-9]*) gl_cfg_n=0 ;; esac
scan_rc=0
(
  cd "$repo_root" || exit 1
  env "GIT_CONFIG_COUNT=$((gl_cfg_n + 2))" \
    "GIT_CONFIG_KEY_${gl_cfg_n}=color.ui" "GIT_CONFIG_VALUE_${gl_cfg_n}=never" \
    "GIT_CONFIG_KEY_$((gl_cfg_n + 1))=color.diff" "GIT_CONFIG_VALUE_$((gl_cfg_n + 1))=never" \
    "GIT_CONFIG_PARAMETERS=${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'color.ui'='never' 'color.diff'='never'" \
    gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 \
      --report-format json --report-path "$report_file" >/dev/null 2>&1
) || scan_rc=$?

# Re-scan any `-diff` path from its STAGED blob before trusting a clean verdict.
# `gitleaks git` structurally could not see these (no `+` lines), so "clean" above
# is not a statement about them. `detect --no-git` reads file CONTENT and never
# consults git's diff machinery, so no gitattribute can reach it.
if (( ${#gl_nodiff[@]} > 0 )); then
  nodiff_rc=0
  for _p in "${gl_nodiff[@]}"; do
    mkdir -p "$nodiff_dir/$(dirname "$_p")" 2>/dev/null || true
    git -C "$repo_root" show ":$_p" > "$nodiff_dir/$_p" 2>/dev/null || true
  done
  gitleaks detect --no-git --source "$nodiff_dir" --redact --no-banner --exit-code 1 \
    --report-format json --report-path "$nodiff_report" >/dev/null 2>&1 || nodiff_rc=$?
  if [ "$nodiff_rc" -eq 1 ] && [ -s "$nodiff_report" ] && grep -q '"RuleID"' "$nodiff_report" 2>/dev/null; then
    nd_count="$(jq -r 'length' "$nodiff_report" 2>/dev/null || echo 0)"
    nd_files="$(printf '%s, ' "${gl_nodiff[@]}")"
    deny "BLOCKED: gitleaks found ${nd_count} secret-shaped string(s) in staged file(s) carrying a \`-diff\` gitattribute: ${nd_files%, }. A \`-diff\` attribute makes git emit \"Binary files … differ\" with no added lines, so the normal staged scan sees NOTHING in these files — they were re-scanned from their staged blobs. Recovery: (1) scrub the secret bytes (never commit-then-rotate); (2) if the \`-diff\` attribute is not deliberate, remove it from .gitattributes / .git/info/attributes."
  fi
  if [ "$nodiff_rc" -ne 0 ] && [ "$nodiff_rc" -ne 1 ]; then
    echo "[git-commit-secret-scan] WARN: the \`-diff\` re-scan exited $nodiff_rc without a findings report; those paths were NOT verified." >&2
    emit git-commit-secret-scan-nodiff-rescan-failed bypass "-diff re-scan exit=$nodiff_rc, empty report"
  fi
fi

if [ "$scan_rc" -eq 0 ]; then
  allow
fi

# scan_rc != 0 → findings present (or gitleaks crashed). Build a redacted
# deny reason that names the files + rule IDs but never the secret body.
findings_count=0
findings_summary=""
if [ -s "$report_file" ]; then
  findings_count="$(jq -r 'length' "$report_file" 2>/dev/null || echo 0)"
  # Each finding: {RuleID, File, StartLine}. Cap at 5 to keep the deny
  # reason terse; the operator can re-run gitleaks locally to see the rest.
  findings_summary="$(jq -r '
    [.[] | "\(.File):\(.StartLine) (\(.RuleID))"] | .[0:5] | join("; ")
  ' "$report_file" 2>/dev/null || echo "")"
fi

if [ "$findings_count" = "0" ] || [ -z "$findings_summary" ]; then
  # gitleaks exited non-zero but the report file is empty/missing — likely
  # a transient gitleaks error rather than a real finding. Fail-open with
  # a warn so a broken binary doesn't block every commit.
  echo "[git-commit-secret-scan] WARN: gitleaks exited $scan_rc but produced no findings report; allowing commit. Run 'gitleaks git --pre-commit --staged' locally to diagnose." >&2
  emit git-commit-secret-scan bypass "gitleaks exit=$scan_rc, empty report"
  allow
fi

reason="BLOCKED: gitleaks found ${findings_count} secret-shaped string(s) in the staged index. Locations: ${findings_summary}. The default action is to scrub the secrets — never commit-then-rotate. Recovery: (1) unstage the offending file(s) with 'git restore --staged <path>'; (2) redact the secret bytes in place; (3) re-stage and retry. If the staged content is a captured-real fixture from 'terraform show -json' or similar, strip the '.variables' block — terraform-show-json embeds sensitive HCL variables verbatim regardless of sensitive=true. See knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md."

deny "$reason"
