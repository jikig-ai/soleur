#!/usr/bin/env bash
# Render-then-validate every infra template in an infra-root dir (#6454).
#
# WHY THIS EXISTS
# ---------------
# infra-validation.yml used to run `cloud-init schema -c cloud-init.yml` against
# the RAW Terraform templatefile. apps/web-platform/infra/cloud-init.yml carries
# `%{ if web_colocate_inngest ~}` at column 1; YAML reads a leading '%' as a
# directive indicator and hard-fails before schema-checking begins. So the job
# was red on EVERY PR touching apps/*/infra/** since #6344 — and, being
# pull_request-only, invisible on main. A permanently-red gate trains operators
# to ignore it, and it shared a red light with `terraform fmt`/`terraform
# validate`, which are real gates.
#
# It also validated exactly ONE of the repo's templates (`if [[ -f
# cloud-init.yml ]]`), so three cloud-inits and hooks.json.tmpl were never
# validated at all. Loud false-red and silent false-green, same root cause.
#
# DISCOVERY IS STRUCTURAL, NEVER A FILENAME ALLOWLIST
# ---------------------------------------------------
# Members = A union B:
#   (A) every file referenced by a `templatefile()` call in the dir's *.tf —
#       the consumer's own declaration of template-ness, the most authoritative
#       signal available;
#   (B) every cloud-init*.yml present — backstops a cloud-init consumed via
#       file() that (A) would miss.
# A validator that only knows about files it was told about BY NAME is the same
# class of defect as the bug it fixes. This is what lets #6448's
# docker-daemon.json be covered the day it becomes a templatefile(), with no
# edit here.
#
# TERRAFORM IS THE GRAMMAR AUTHORITY
# ----------------------------------
# The script never pre-judges Terraform's expression grammar. It derives map
# KEYS from the .tf call site (the authoritative statement of what
# templatefile() actually receives — loop-locals and function names can never
# enter it) and TYPES from the body, then renders and lets `terraform console`
# rule. A missing key, a bad type, or an expression shape we mis-derived all
# surface as terraform's own message, verbatim, at exit 2. Guessing is how a
# fix re-creates #6454.
#
# EXIT CONTRACT — every path is loud; none is a skip:
#   0 pass · 1 validation failed · 2 render failed · 3 stub var leaked
#   4 template<->.tf drift · 5 counter mismatch · 6 tooling absent
#
# Tests: .github/scripts/test/test-validate-infra-templates.sh (runs in the
# REQUIRED, path-filter-free `guard-script-fixture-tests` job).

set -uo pipefail

DIR_ARG="${1:-}"
if [[ -z "$DIR_ARG" ]]; then
  echo "usage: $0 <infra-root-dir>" >&2
  exit 2
fi
if [[ ! -d "$DIR_ARG" ]]; then
  echo "error: not a directory: $DIR_ARG" >&2
  exit 2
fi
ROOT=$(cd "$DIR_ARG" && pwd)

TMP=$(mktemp -d)
TFDIR=$(mktemp -d)   # empty scratch: templatefile() is a builtin, so `terraform
                     # console` needs no init, no providers, no credentials —
                     # preserving the validate job's credential-free contract.
trap 'rm -rf "$TMP" "$TFDIR"' EXIT

# --- Discovery: A union B -------------------------------------------------

# The anchored call-syntax pattern. A loose `templatefile(.*<name>` also matches
# PROSE COMMENTS — ci-ssh-key.tf's comment literally reads "`templatefile()`
# interpolation map so `cloud-init.yml`'s" — which yields an empty key map and a
# failed render. \Q..\E literal-quotes the filename so dots are not metachars.
tf_call_pattern() { printf 'templatefile\\(\\s*"\\$\\{path\\.module\\}/\\Q%s\\E"' "$1"; }

shopt -s nullglob
TF_FILES=("$ROOT"/*.tf)
MEMBERS=()

# (A) templatefile() referents
if [[ ${#TF_FILES[@]} -gt 0 ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && MEMBERS+=("$ref")
  done < <(grep -hoP 'templatefile\(\s*"\$\{path\.module\}/\K[^"]+' "${TF_FILES[@]}" 2>/dev/null | sort -u)
fi

# (B) cloud-init*.yml present
for f in "$ROOT"/cloud-init*.yml; do
  MEMBERS+=("$(basename "$f")")
done
shopt -u nullglob

# Dedupe the union.
if [[ ${#MEMBERS[@]} -gt 0 ]]; then
  mapfile -t MEMBERS < <(printf '%s\n' "${MEMBERS[@]}" | sort -u)
fi

if [[ ${#MEMBERS[@]} -eq 0 ]]; then
  echo "no infra templates in $ROOT (no templatefile() referents, no cloud-init*.yml)"
  exit 0
fi

DISCOVERED=${#MEMBERS[@]}

# --- Fail closed on missing tooling (deliberately NOT a self-SKIP) ---------
# An advisory test may skip; a gate may not. A gate that skips when its tools
# are missing is a gate that reports green having checked nothing.
if ! command -v terraform >/dev/null 2>&1; then
  echo "error: terraform not found on PATH — cannot render templates. Failing closed (not skipping)." >&2
  exit 6
fi
NEEDS_CLOUD_INIT=0
for m in "${MEMBERS[@]}"; do
  [[ "$m" == cloud-init*.yml ]] && NEEDS_CLOUD_INIT=1
done
if [[ "$NEEDS_CLOUD_INIT" -eq 1 ]] && ! command -v cloud-init >/dev/null 2>&1; then
  echo "error: cloud-init not found on PATH but cloud-init templates are present. Failing closed (not skipping)." >&2
  exit 6
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found on PATH — needed to decode the render. Failing closed (not skipping)." >&2
  exit 6
fi

# --- Helpers --------------------------------------------------------------

# Real template syntax, under negative lookbehind so TF-escaped `$${SHELL_VAR}`
# and `%%{http_code}` are NOT misread as template syntax. The live
# `%%{http_code}` curl strings in cloud-init-inngest.yml depend on this.
# No `head -N` truncation: an existence grep must see the whole file.
has_template_syntax() { # file
  grep -qP '(?<!\$)\$\{' "$1" 2>/dev/null && return 0
  grep -qP '(?<!%)%\{' "$1" 2>/dev/null && return 0
  return 1
}

validate_by_type() { # rendered_path original_basename label
  local rendered="$1" base="$2" label="$3" out rc
  case "$base" in
    cloud-init*.yml)
      out=$(cloud-init schema -c "$rendered" 2>&1); rc=$?
      if [[ "$rc" -ne 0 ]]; then
        echo "FAIL [$base$label]: rendered document violates cloud-init schema" >&2
        echo "$out" | grep -vE 'log_util|schema\.py.*WARNING|datasource not detected' >&2
        return 1
      fi
      ;;
    *.json|*.json.tmpl)
      if ! jq empty "$rendered" 2>"$TMP/jqerr"; then
        echo "FAIL [$base$label]: rendered document is not valid JSON" >&2
        cat "$TMP/jqerr" >&2
        return 1
      fi
      ;;
    *)
      # Render-only. Still real: the render itself catches TF var/type errors,
      # and the stub-var leak assertion runs for every member.
      ;;
  esac
  return 0
}

# --- Main loop ------------------------------------------------------------

VALIDATED=0
TOTAL_BOOLS=0

for base in "${MEMBERS[@]}"; do
  path="$ROOT/$base"

  if [[ ! -f "$path" || ! -r "$path" ]]; then
    # Do NOT increment. The counter assertion below turns this into exit 5 —
    # the structural guarantee that we never report success having validated
    # fewer members than we discovered.
    echo "ERROR [$base]: discovered but not readable — refusing to count it as validated" >&2
    continue
  fi

  # --- raw path: no real template syntax -> validate as-is
  if ! has_template_syntax "$path"; then
    if validate_by_type "$path" "$base" " (raw)"; then
      echo "  ok  $base (raw — no template syntax)"
      VALIDATED=$((VALIDATED + 1))
    else
      exit 1
    fi
    continue
  fi

  # --- attribute the member to its .tf call site (anchored, comment-proof)
  pat=$(tf_call_pattern "$base")
  sites=""
  if [[ ${#TF_FILES[@]} -gt 0 ]]; then
    # -H is load-bearing: grep omits the filename prefix when handed exactly ONE
    # file, so `${sites%%:*}` would parse the LINE NUMBER as the filename. The
    # real infra roots ship many *.tf and would have masked this forever.
    sites=$(grep -nHP "$pat" "${TF_FILES[@]}" 2>/dev/null)
  fi
  n_sites=$(printf '%s' "$sites" | grep -c . )

  if [[ "$n_sites" -eq 0 ]]; then
    echo "ERROR [$base]: has template syntax but NO templatefile() call site in $ROOT/*.tf" >&2
    echo "  A template nobody renders cannot be validated, and will break at apply." >&2
    exit 4
  fi
  if [[ "$n_sites" -gt 1 ]]; then
    echo "ERROR [$base]: referenced by $n_sites templatefile() call sites — ambiguous var map:" >&2
    printf '%s\n' "$sites" >&2
    echo "  Refusing to silently pick one." >&2
    exit 4
  fi

  tf_file=${sites%%:*}
  rest=${sites#*:}
  tf_line=${rest%%:*}

  # --- KEYS from the .tf map, TYPES from the body (Design Decision 2c).
  # Start AFTER the call-site line: the naive form captures the enclosing
  # `user_data = base64gzip(templatefile(...` assignment as a phantom key.
  # Only real map keys can enter, so a `%{ for x in list ~}` loop-local can
  # never be mistaken for a var — the false-red a body-scanner would ship.
  keys=$(awk -v start="$tf_line" '
    NR > start {
      if ($0 ~ /^[[:space:]]*\}\)/) exit
      print
    }' "$tf_file" \
    | grep -oE '^[[:space:]]*[a-z_][a-zA-Z0-9_]*[[:space:]]*=' \
    | grep -oE '[a-z_][a-zA-Z0-9_]*' \
    | sort -u)

  n_keys=$(printf '%s' "$keys" | grep -c .)
  if [[ "$n_keys" -eq 0 ]]; then
    echo "ERROR [$base]: parsed an EMPTY var map from $tf_file:$tf_line" >&2
    echo "  A template with syntax but no vars cannot be right; refusing to render blind." >&2
    exit 4
  fi

  # A key used as `%{ if <key> ...}` is a bool; everything else stubs as "x".
  bools=()
  strings=()
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if grep -qP "%\{[[:space:]]*if[[:space:]]+${k}\b" "$path" 2>/dev/null; then
      bools+=("$k")
    else
      strings+=("$k")
    fi
  done <<< "$keys"

  TOTAL_BOOLS=$((TOTAL_BOOLS + ${#bools[@]}))

  # Two passes when the file has directives: all-bools-true and all-bools-false.
  # For the current corpus this is COMPLETE (cloud-init.yml has exactly one
  # bool, web_colocate_inngest, so 2 passes = 2 of 2 states) — and the false arm
  # is the DEFAULT production document (variables.tf default = false), which a
  # directive-strip never produces at all. At N>=2 bools this covers 2 of 2^N:
  # a conscious, documented narrowing (see the follow-up issue).
  if [[ ${#bools[@]} -eq 0 ]]; then
    arms=("noop")
  else
    arms=("true" "false")
  fi

  for arm in "${arms[@]}"; do
    map=""
    for k in "${strings[@]}"; do map="${map}${k} = \"x\", "; done
    for k in "${bools[@]}"; do map="${map}${k} = ${arm}, "; done
    map="${map%, }"

    label=""
    [[ "$arm" != "noop" ]] && label=" (bools=$arm)"

    rendered="$TMP/rendered-$base-$arm"
    # jsonencode + double-decode. The prior art's `<<EOT` first/last-line strip
    # is broken two ways: terraform console emits a QUOTED STRING (not a
    # heredoc) for a short template, so the strip yields `"x=hi"` with quotes
    # intact rather than the document; and it breaks on any rendered doc
    # containing a bare `EOT` line. console re-quotes the jsonencode result, so
    # TWO jq passes are required — one is not enough.
    printf 'jsonencode(templatefile("%s", { %s }))\n' "$path" "$map" \
      | terraform -chdir="$TFDIR" console > "$TMP/console.out" 2>"$TMP/console.err"
    tf_rc=$?

    if [[ "$tf_rc" -ne 0 ]]; then
      echo "ERROR [$base$label]: terraform failed to render the template." >&2
      echo "  Terraform is the authority on its own grammar; its message follows verbatim:" >&2
      sed 's/^/  | /' "$TMP/console.err" >&2
      exit 2
    fi

    if ! jq -r . < "$TMP/console.out" 2>/dev/null | jq -r . > "$rendered" 2>/dev/null; then
      echo "ERROR [$base$label]: could not decode terraform console output." >&2
      echo "  Is terraform_wrapper: false set on setup-terraform? The wrapper corrupts stdout." >&2
      sed 's/^/  | /' "$TMP/console.out" | head -5 >&2
      exit 2
    fi

    # Stub-var leak: assert no MAP KEY survives as ${key}. Deliberately NOT a
    # blanket `${...}` grep — that false-fails on legitimately-rendered shell
    # seams (`${DOPPLER_SHA256}`, `${TMPENV:-...}`) which TF-escaped `$${...}`
    # correctly renders TO. private-nic-guard.test.sh's blanket assertion only
    # survives in its own file because those seams use `:-` defaults.
    for k in "${strings[@]}" "${bools[@]}"; do
      if grep -qF "\${$k}" "$rendered" 2>/dev/null; then
        echo "ERROR [$base$label]: stub var \${$k} survived into the rendered document" >&2
        exit 3
      fi
    done

    if ! validate_by_type "$rendered" "$base" "$label"; then
      exit 1
    fi
    echo "  ok  $base$label ($(wc -l < "$rendered") lines)"
  done

  VALIDATED=$((VALIDATED + 1))
done

# --- Counter assertion: the silent-skip guard -----------------------------
# This is the machine-checkable evidence that the gate RAN rather than skipped.
# It is the #6454 class recurring that this catches: a gate quietly validating
# nothing while reporting green.
if [[ "$VALIDATED" -ne "$DISCOVERED" ]]; then
  echo "ERROR: validated $VALIDATED of $DISCOVERED discovered template(s) — refusing to report success." >&2
  exit 5
fi

echo "infra template validation: rendered+validated $VALIDATED/$DISCOVERED file(s) in $ROOT"
echo "  (bool directives across corpus: $TOTAL_BOOLS)"
exit 0
