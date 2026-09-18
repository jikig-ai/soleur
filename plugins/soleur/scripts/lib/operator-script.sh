# shellcheck shell=bash
# operator-script.sh — shared primitives for Soleur-generated operator scripts.
#
# SOURCED, NEVER EXECUTED. That is why line 1 is the shellcheck directive and
# not a shebang: there is ONE distribution mode (the generated script `source`s
# this file), so there is no inlined copy to drift from and no `STAGES` byte
# identity marker to pin. Plan 2026-09-18-feat-ship-operator-bootstrap-wizard-
# merge-danger, revision R6.
#
# Home per ADR-178 §1: a shared bash primitive consumed by shipped plugin code
# lives inside `plugins/soleur/`, alongside `proc.sh`, `session-state.sh` and
# `domain-model-lib.sh`.
#
# Sourced (NEVER executed) by:
#   - plugins/soleur/skills/operator-bootstrap/template.sh
#       the template every generated <feature>/bootstrap.sh is authored from
#   - plugins/soleur/skills/provision-hetzner/scripts/provision-hetzner.sh
#       the proving consumer (plan D11)
#   - every script the `soleur:operator-bootstrap` skill generates
#
# SOURCING PRECONDITIONS — the caller satisfies all of these BEFORE the
# `source` line (the shape of apps/cla-evidence/scripts/_cf-admin-token.sh):
#   1. `set -euo pipefail` is already in effect. This file sets no shell options
#      of its own except `umask`, because a sourced library that changes the
#      caller's error handling changes the caller's control flow.
#   2. The caller carries its OWN xtrace-refusal and TLS-strip prologue ABOVE
#      the `source` line. It is DUPLICATED there, never moved in here:
#      `PROLOGUE_MAX_CMDS = 0` in scripts/lint-shell-trace-credential-refusal.py
#      makes a `source` line itself a counted command, and `find_preamble` only
#      ever scans a file's OWN lines — a caller sourcing a fully compliant
#      library still fails Rule A (measured, revision R26).
#   3. `mktemp`, `grep`, `awk`, `printenv`, `stat` and `chmod` are on PATH.
#      `gh` is required only by the two GitHub helpers.
#
# LIBRARY INVARIANT (revision R26) — THIS FILE NEVER EXPANDS A SECRET-SHAPED
# VARIABLE NAME. The credential linter's `^scripts/lib/` exclusion is
# repo-root-anchored, so a library under `plugins/soleur/scripts/lib/` IS
# scanned. If this file ever expanded a `*_TOKEN` / `*_KEY` / `*_SECRET` /
# `*_PASSWORD` / `*_PAT` name — or used `${!name}` indirection — it would come
# into scope and need its own `exit 78`, which on a `source` terminates the
# CALLER. So: secret values arrive as POSITIONAL PARAMETERS bound to neutral
# local names (`value`), skip variables are read with `printenv` rather than
# `${!name}`, and every expansion of a caller-named credential stays in the
# caller.
#
# EXIT CODES a generated script may return (revision R42 — the repo has no
# central table and code 3 is already overloaded, so the table lives here and in
# operator-bootstrap/SKILL.md rather than being re-derived by the next author):
#
#   0   success.
#   1   usage error, or a refused call — e.g. a secret-shaped name handed to the
#       GitHub *variable* helper, which writes on argv. Remedy: fix the call.
#   3   DPA-gate rejection (tenant provisioning scripts only). CONFLICT, stated
#       rather than renumbered: apps/cla-evidence/scripts/sentinel-pr.sh returns
#       3 for "missing tool on PATH" and "not inside a git repository" — a class
#       apps/cla-evidence/infra/bootstrap.sh returns 64 for. Do NOT re-derive 3
#       as "missing tool".
#   64  missing input — a required binary, a required environment variable, or a
#       prompt that cannot be answered because stdin is not a TTY. Remedy: the
#       marker line names the variable to set.
#   78  refusing to run under shell tracing while holding a live credential
#       (#7797). Remedy: re-run without `-x`.
#
# STDOUT MARKERS, not stderr. Agent runtimes surface stdout and swallow stderr,
# so a stderr-only refusal is invisible on the one surface that matters
# (provision-doppler.sh records the same reason at its own prologue):
#   SOLEUR_BOOTSTRAP_INPUT_REQUIRED   var=<NAME> tty=0   → exit 64
#   SOLEUR_BOOTSTRAP_UNSAFE_VARIABLE  name=<NAME>        → refused argv write
#   SOLEUR_BOOTSTRAP_ABORTED          stage=<kind>       → operator declined
#   SOLEUR_BOOTSTRAP_LIB_MISSING      path=<resolved>    → see below
#
# SOLEUR_BOOTSTRAP_LIB_MISSING is emitted by the CONSUMER, not by this file — a
# library that is not there cannot announce itself. Every consumer opens with,
# verbatim, and hard-exits rather than degrading to a stub (ADR-178 Context §1:
# fail-closed stubs made `cleanup-merged` refuse to reap forever):
#
#     SOLEUR_OP_LIB="${CLAUDE_PLUGIN_ROOT:-$SCRIPT_DIR/../../..}/scripts/lib/operator-script.sh"
#     if [[ ! -r "$SOLEUR_OP_LIB" ]]; then
#       printf 'SOLEUR_BOOTSTRAP_LIB_MISSING path=%s\n' "$SOLEUR_OP_LIB"
#       exit 64
#     fi
#
# <!-- Inspired by mattpocock/skills/skills/engineering/wizard/ (MIT, Copyright (c) 2026 Matt Pocock). -->
# What is adopted is the SHAPE — a wizard that walks named stages, one journey
# per stage, with the operator told what will happen before it happens. The code
# is extracted from in-repo prior art, not ported: five of the six primitives
# already existed here (apps/cla-evidence/infra/bootstrap.sh for stage progress,
# preflight and the closing summary; community/scripts/{x,bsky,discord}-setup.sh
# for the exact-key `.env` upsert; operator-digest/scripts/
# provision-operator-digest-repo.sh for the stdin-only secret write and the
# separate argv variable write). Only cross-platform URL opening is new.

# Guard against double-source within a single shell.
if [[ "${_SOLEUR_OPERATOR_SCRIPT_LOADED:-}" == "1" ]]; then
  return 0 2>/dev/null || true
fi
_SOLEUR_OPERATOR_SCRIPT_LOADED=1

# The generated `.env` holds live credentials on the founder's own disk, and a
# default umask writes it 0644 into a directory that may sit under a cloud-sync
# client. 077 here, and `chmod 600` asserted after every upsert.
umask 077

# ---------------------------------------------------------------------------
# Output helpers (shape from apps/cla-evidence/infra/bootstrap.sh)
# ---------------------------------------------------------------------------

SOLEUR_OP_GREEN='\033[32m'
SOLEUR_OP_RED='\033[31m'
SOLEUR_OP_YELLOW='\033[33m'
SOLEUR_OP_NC='\033[0m'

soleur_op_red()    { printf '%b%s%b\n' "$SOLEUR_OP_RED"    "$*" "$SOLEUR_OP_NC" >&2; }
soleur_op_green()  { printf '%b%s%b\n' "$SOLEUR_OP_GREEN"  "$*" "$SOLEUR_OP_NC"; }
soleur_op_yellow() { printf '%b%s%b\n' "$SOLEUR_OP_YELLOW" "$*" "$SOLEUR_OP_NC"; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

# soleur_op_require_bins <bin>...
#   Exit 64 naming the first missing binary. The ladder (environment → Doppler →
#   MCP/CLI/REST) runs BEFORE any prompt; a value outside the two interactive
#   carve-outs that is missing is a hard failure with a named remedy, never a
#   prompt.
soleur_op_require_bins() {
  local bin
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || {
      soleur_op_red "missing ${bin} on PATH"
      exit 64
    }
  done
}

# ---------------------------------------------------------------------------
# Run ledger — one JSON line per stage, BEFORE and AFTER. Names, never values.
# ---------------------------------------------------------------------------
#
# Layer 7 (cli-stdout-artifact): stdout alone is an explicit P1 rejection because
# it does not survive the session, so the synchronous markers above are paired
# with this durable artifact. It is committed in the FOUNDER's repository; both
# candidate paths are gitignored in this one, so nothing here is ever committed.
# Nothing is transmitted and no alert target exists — the surface is the
# founder's own machine, and routing it to Soleur infrastructure would be a
# data-controller event, not an observability improvement.

SOLEUR_OP_RUN_ID=""
SOLEUR_OP_TOTAL_STAGES=0

soleur_op_ledger_path() {
  printf '%s' "${SOLEUR_BOOTSTRAP_LEDGER:-.soleur/bootstrap-runs.jsonl}"
}

soleur_op_now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }

# Minimal JSON string escaping: backslash and double quote, then control chars
# collapsed to a space. Enough for the field set below, which is names and small
# integers by construction.
soleur_op_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/[[:cntrl:]]/ /g'
}

soleur_op_ledger_write() {
  local path line
  path="$(soleur_op_ledger_path)"
  line="$1"
  mkdir -p "$(dirname "$path")" 2>/dev/null || true
  printf '%s\n' "$line" >> "$path" 2>/dev/null || true
}

# soleur_op_ledger_init <total-stages> <script-name>
soleur_op_ledger_init() {
  SOLEUR_OP_TOTAL_STAGES="$1"
  SOLEUR_OP_RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
  soleur_op_ledger_write "$(printf '{"ts":"%s","run_id":"%s","event":"run_begin","total_stages":%s,"script":"%s"}' \
    "$(soleur_op_now)" "$SOLEUR_OP_RUN_ID" "$1" "$(soleur_op_json_escape "${2:-unknown}")")"
}

# soleur_op_ledger_note <kind> <name> <detail>
#   `name` is a KEY NAME or a SECRET NAME. `detail` is metadata — never a value.
#   Guard 3 drives a mutation that swaps a value into `detail` and asserts the
#   suite reddens, because "names never values" is otherwise a comment.
soleur_op_ledger_note() {
  soleur_op_ledger_write "$(printf '{"ts":"%s","run_id":"%s","kind":"%s","name":"%s","detail":"%s"}' \
    "$(soleur_op_now)" "$SOLEUR_OP_RUN_ID" \
    "$(soleur_op_json_escape "$1")" "$(soleur_op_json_escape "$2")" "$(soleur_op_json_escape "${3:-}")")"
}

# soleur_op_stage_begin <index> <name>
soleur_op_stage_begin() {
  printf '\n→ [%s/%s] %s\n' "$1" "$SOLEUR_OP_TOTAL_STAGES" "$2"
  soleur_op_ledger_write "$(printf '{"ts":"%s","run_id":"%s","event":"stage","phase":"begin","stage_index":%s,"total_stages":%s,"stage_name":"%s","outcome":"pending","exit_code":null}' \
    "$(soleur_op_now)" "$SOLEUR_OP_RUN_ID" "$1" "$SOLEUR_OP_TOTAL_STAGES" "$(soleur_op_json_escape "$2")")"
}

# soleur_op_stage_end <index> <name> <outcome> <exit-code>
soleur_op_stage_end() {
  soleur_op_ledger_write "$(printf '{"ts":"%s","run_id":"%s","event":"stage","phase":"settle","stage_index":%s,"total_stages":%s,"stage_name":"%s","outcome":"%s","exit_code":%s}' \
    "$(soleur_op_now)" "$SOLEUR_OP_RUN_ID" "$1" "$SOLEUR_OP_TOTAL_STAGES" \
    "$(soleur_op_json_escape "$2")" "$(soleur_op_json_escape "$3")" "${4:-0}")"
}

# soleur_op_stage_should_run <index>
#   Resume (revision R21c). Without it the only supported action after a partial
#   run is "re-run from stage 1", straight back into the non-idempotent create
#   that produced the partial run. `verify-bootstrap-run.sh --ledger <p> --last`
#   prints the index to resume from.
soleur_op_stage_should_run() {
  [[ "$1" -ge "${SOLEUR_BOOTSTRAP_START_STAGE:-1}" ]]
}

# ---------------------------------------------------------------------------
# Prompts — R8's THREE carve-out classes
# ---------------------------------------------------------------------------
#
#   class 1  ladder value / credential ENTRY
#            → named skip variable; no TTY + unset ⇒ exit 64 naming it.
#   class 2  per-command destructive-write acknowledgement
#            → NO SKIP VARIABLE AT ALL. No TTY ⇒ exit 64 unconditionally.
#              An environment variable set once is exactly the "prior approval
#              extending to a new command" hr-menu-option-ack-not-prod-write-auth
#              forbids, so automation must not be able to supply this.
#   class 3  out-of-band completion barrier ("Token created? Type 'yes'")
#            → named skip variable, AND the caller MUST follow it with an
#              independent verification of the thing attested. A barrier that is
#              skippable and unverified attests nothing.
#
# A fourth class requires an ADR amendment (ADR-226).

# --- MUTATION ANCHOR: start of prompt helpers ---

# soleur_op_skip_value <VAR-NAME>
#   `printenv`, deliberately, NOT `${!name}`: indirect expansion would put this
#   file into the credential linter's scope (library invariant, above).
soleur_op_skip_value() {
  printenv "$1" 2>/dev/null || true
}

# soleur_op_input_required <VAR-NAME-or-reason>
#   The no-TTY refusal. Emitted BEFORE any read, never after. Today's behaviour
#   in provision-hetzner.sh is fail-closed but MUTE — EOF read into an empty ACK
#   and `exit 1` with "Aborted." — the right outcome with an unattributed cause.
soleur_op_input_required() {
  printf 'SOLEUR_BOOTSTRAP_INPUT_REQUIRED var=%s tty=0\n' "$1"
  exit 64
}

# soleur_op_value <SKIP-VAR> <prompt> <out-var-name>   [class 1]
#   Writes the answer into the named variable with `printf -v` rather than to
#   stdout. Deliberate: a `$(...)` capture would run the helper in a SUBSHELL,
#   where `exit 64` kills only the subshell and the script sails on past a
#   prompt it never answered.
soleur_op_value() {
  local var_name="$1" prompt_text="$2" out_name="$3" skip reply
  skip="$(soleur_op_skip_value "$var_name")"
  if [[ -n "$skip" ]]; then
    printf -v "$out_name" '%s' "$skip"
    return 0
  fi
  [[ -t 0 ]] || soleur_op_input_required "$var_name"
  read -r -p "$prompt_text" reply
  printf -v "$out_name" '%s' "$reply"
}

# soleur_op_barrier <SKIP-VAR> <prompt>               [class 3]
#   MUST be followed by an independent verification of the thing attested.
soleur_op_barrier() {
  local var_name="$1" prompt_text="$2" skip reply
  skip="$(soleur_op_skip_value "$var_name")"
  if [[ -n "$skip" ]]; then
    printf '  [skip] %s (%s is set; the caller still runs its own verification)\n' "$prompt_text" "$var_name"
    return 0
  fi
  [[ -t 0 ]] || soleur_op_input_required "$var_name"
  read -r -p "$prompt_text" reply
  [[ "$reply" == "yes" ]] || {
    printf 'SOLEUR_BOOTSTRAP_ABORTED stage=barrier\n'
    exit 1
  }
}

# soleur_op_ack_or_die <prompt>                       [class 2]
#   NO skip variable, by design and by rule. Do not add one.
soleur_op_ack_or_die() {
  local prompt_text="$1" reply
  [[ -t 0 ]] || soleur_op_input_required "destructive-write-ack(no-skip-variable-by-design)"
  read -r -p "$prompt_text" reply
  [[ "$reply" == "yes" ]] || {
    printf 'SOLEUR_BOOTSTRAP_ABORTED stage=ack\n'
    exit 1
  }
}

# --- MUTATION ANCHOR: end of prompt helpers ---

# ---------------------------------------------------------------------------
# .env upsert — EXACT-KEY, and the mechanism is the trailing `=`
# ---------------------------------------------------------------------------
#
# Revision R41: exact-key is the MAJORITY precedent, not a correction to one.
# Three of the four community setup scripts already chain `grep -v '^KEY='`
# filters (x-setup.sh, bsky-setup.sh, discord-setup.sh); only linkedin-setup.sh
# spells the PREFIX form `grep -v '^LINKEDIN_'`, which is correct only for a
# fixed block of keys sharing that prefix. Drop the `=` and upserting `X_API_KEY`
# silently removes `X_API_KEY_SECRET`.
#
# No precedent fsyncs, and none handles a concurrent writer. This library
# inherits that limitation: acceptable for a single-operator script on the
# founder's own machine, and stated rather than assumed.

# soleur_op_env_upsert <env-file> <KEY> <value>
soleur_op_env_upsert() {
  local env_file="$1" key="$2" value="$3" tmp before_count
  if [[ -z "$key" ]]; then
    printf 'SOLEUR_BOOTSTRAP_BAD_ARG helper=env_upsert reason=empty-key\n'
    return 1
  fi
  [[ -f "$env_file" ]] || : > "$env_file"
  before_count="$(grep -c '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file" 2>/dev/null || true)"
  tmp="$(mktemp "${env_file}.XXXXXX")" || {
    printf 'SOLEUR_BOOTSTRAP_BAD_ARG helper=env_upsert reason=mktemp-failed\n'
    return 1
  }
  grep -v "^${key}=" "$env_file" > "$tmp" || true
  mv "$tmp" "$env_file"
  chmod 600 "$env_file"
  printf '%s=%s\n' "$key" "$value" >> "$env_file"
  soleur_op_ledger_note env_upsert "$key" "keys_before=${before_count}"
}

# soleur_op_env_reset <env-file> <KEY>
#   Revision R21a: a WRONG credential is otherwise permanent. The value is
#   persisted before it can be validated, and the environment-first ladder means
#   a re-run never re-prompts — it fails identically forever. This is the
#   `--reset <KEY>` path every generated script exposes.
soleur_op_env_reset() {
  local env_file="$1" key="$2" tmp
  [[ -f "$env_file" ]] || return 0
  tmp="$(mktemp "${env_file}.XXXXXX")" || return 1
  grep -v "^${key}=" "$env_file" > "$tmp" || true
  mv "$tmp" "$env_file"
  chmod 600 "$env_file"
  soleur_op_ledger_note env_reset "$key" ""
}

# ---------------------------------------------------------------------------
# GitHub writes — two helpers, deliberately NOT one
# ---------------------------------------------------------------------------
#
# Argv is CORRECT for a login and WRONG for a credential. Merging the two "for
# symmetry" is the mutation Guard 3 drives, because the merged helper would let
# a secret take the argv path — visible in /proc/<pid>/cmdline to every process
# on the machine, and in shell history when re-run by hand.

# soleur_op_gh_secret_set <repo> <SECRET-NAME> <value>
#   STDIN ONLY. The write's own output is redirected — a third-party CLI can dump
#   unrelated secrets as a side effect of a write (the case
#   .claude/hooks/doppler-secrets-delete-redirect.sh already blocks) — and the
#   result is confirmed by a SEPARATE read.
soleur_op_gh_secret_set() {
  local repo="$1" sec_name="$2" value="$3" listed
  printf '%s' "$value" | gh secret set "$sec_name" -R "$repo" >/dev/null 2>&1 || {
    printf 'SOLEUR_BOOTSTRAP_SECRET_WRITE_FAILED name=%s repo=%s\n' "$sec_name" "$repo"
    return 1
  }
  listed="$(gh secret list -R "$repo" 2>/dev/null || true)"
  if ! grep -q "${sec_name}" <<<"$listed"; then
    printf 'SOLEUR_BOOTSTRAP_SECRET_VERIFY_FAILED name=%s repo=%s\n' "$sec_name" "$repo"
    return 1
  fi
  soleur_op_ledger_note gh_secret "$sec_name" "repo=${repo}"
}

# soleur_op_gh_variable_set <repo> <VARIABLE-NAME> <value>
#   Argv, because a repo VARIABLE is not confidential and masking it would make a
#   delivery failure harder to diagnose (the reason
#   provision-operator-digest-repo.sh writes OPERATOR_GH_LOGIN this way).
#
#   The refusal below is NOVEL — no in-repo precedent has it. It is what stops
#   this helper from quietly becoming a secret path.
soleur_op_gh_variable_set() {
  local repo="$1" var_name="$2" value="$3"
  if [[ "$var_name" =~ ^(.*_)?(TOKEN|KEY|SECRET|PASSWORD|PAT)$ ]]; then
    printf 'SOLEUR_BOOTSTRAP_UNSAFE_VARIABLE name=%s reason=secret-shaped-name-on-argv\n' "$var_name"
    return 1
  fi
  gh variable set "$var_name" -R "$repo" --body "$value" >/dev/null 2>&1 || {
    printf 'SOLEUR_BOOTSTRAP_VARIABLE_WRITE_FAILED name=%s repo=%s\n' "$var_name" "$repo"
    return 1
  }
  soleur_op_ledger_note gh_variable "$var_name" "repo=${repo}"
}

# ---------------------------------------------------------------------------
# Cross-platform URL opening — the one genuinely new primitive
# ---------------------------------------------------------------------------
#
# ADDITIVE ONLY. The URL is printed FIRST and the opener's exit code is NEVER
# branched on, so a headless box, a locked-down desktop or a broken handler
# degrades to "here is the URL" rather than to a failed stage. In-repo prior art
# (community/scripts/linkedin-setup.sh) is `xdg-open`/`open` only; the WSL arm is
# new — `wslview`, `explorer.exe` and `$WSL_DISTRO_NAME` detection appear nowhere
# else in this repository.
soleur_op_open_url() {
  local url="$1"
  printf '  %s\n' "$url"
  if [[ -n "${WSL_DISTRO_NAME:-}${WSL_INTEROP:-}" ]]; then
    if command -v wslview >/dev/null 2>&1; then
      wslview "$url" >/dev/null 2>&1 || true
    elif command -v explorer.exe >/dev/null 2>&1; then
      explorer.exe "$url" >/dev/null 2>&1 || true
    fi
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Closing summary
# ---------------------------------------------------------------------------

soleur_op_summary_begin() {
  printf '\n'
  soleur_op_green "$1"
  soleur_op_green "Operator follow-ups:"
}

soleur_op_summary_line() {
  soleur_op_green "  $1"
}
