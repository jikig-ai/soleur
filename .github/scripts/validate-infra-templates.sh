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
# TERRAFORM RULES ON GRAMMAR; THE STUB MAP IS STILL A GUESS
# ---------------------------------------------------------
# KEYS come from the .tf call site — the authoritative statement of what
# templatefile() actually receives, so loop-locals and function names can never
# enter the map. Nothing is rendered blind: `terraform console` judges every
# expression and its message is surfaced verbatim at exit 2.
#
# But TYPES are derived by regex from the body, and that IS a guess — this
# script types exactly two things, bool (a key named in a `%{ if ... }`
# condition) and string (everything else). Known narrowings, all of which fail
# LOUD at exit 2 rather than mis-validating, none present in today's corpus:
#   - a list/map var (`%{ for h in hosts ~}`) stubs as "x" -> "Iteration over
#     non-iterable value";
#   - a key compared with an operator the carve-out misses (`%{ if n >= 2 }`,
#     `%{ if length(xs) > 0 }`) mis-types.
# Because these red a CORRECT template — the #6454 dynamic — the exit-2 branch
# prints the derived stub map next to terraform's error, so the gate's guess is
# visible at the moment it is wrong. If exit 2 or exit 4 ever fires on a .tf that
# is genuinely correct, replace the derivation with a declared per-template var
# map rather than patching the regex further.
#
# EXIT CONTRACT — every path is loud; none is a skip:
#   0 pass · 1 validation failed · 2 render failed · 3 stub var leaked
#   4 attribution failure (absent/ambiguous call site, empty or escaping map)
#   5 coverage shortfall (counter mismatch, or a call site discovery cannot read)
#   6 tooling absent
#
# Tests: .github/scripts/test/fixtures-validate-infra-templates.sh — named
# `fixtures-*`, NOT `test-*`, to stay OUT of run-all.sh's `test-*.sh` glob. That glob
# feeds `guard-script-fixture-tests`, a REQUIRED, path-filter-free bare-bash job; this
# suite needs terraform + cloud-init, and apt-installing them there would put a package
# mirror on the merge queue's critical path for every PR in the repo. So it runs in
# infra-validation.yml's `deploy-script-tests` job instead, which is ADVISORY — this
# suite does not block merge today. See the step comment there and the contract note in
# run-all.sh; #6480 tracks making the gate a real required context.

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

# (A) templatefile() referents.
#
# Read the .tf files as a STREAM, not line-by-line: `terraform fmt` happily
# accepts the wrapped call style
#
#   hooks_json = templatefile(
#     "${path.module}/hooks.json.tmpl",
#     { webhook_deploy_secret = var.webhook_deploy_secret }
#   )
#
# and a line-based grep finds ZERO referents in it — the template silently leaves
# the corpus, the count drops 5/5 -> 4/4, and BOTH numbers stay self-consistent so
# the counter below cannot see it. That is #6454's own class: green having checked
# less. `-z` + a `\s*` that may span newlines makes the match line-independent.
if [[ ${#TF_FILES[@]} -gt 0 ]]; then
  while IFS= read -r ref; do
    [[ -n "$ref" ]] && MEMBERS+=("$ref")
  done < <(grep -hozP 'templatefile\(\s*"\$\{path\.module\}/\K[^"]+' "${TF_FILES[@]}" 2>/dev/null \
             | tr '\0' '\n' | sort -u)
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

# Containment: a referent must be a plain basename inside ROOT. `[^"]+` above will
# happily capture `../../../../etc/passwd`, which then gets read, classified "raw",
# and COUNTED AS VALIDATED — manufacturing a green N/N out of files that are not
# templates at all. Reject anything with a path separator or a leading dot.
for m in "${MEMBERS[@]}"; do
  if [[ "$m" == */* || "$m" == .* || "$m" == *\\* ]]; then
    echo "ERROR: templatefile() referent '$m' is not a plain basename within $ROOT" >&2
    echo "  Refusing to read outside the infra root." >&2
    exit 4
  fi
done

if [[ ${#MEMBERS[@]} -eq 0 ]]; then
  # Emit the summary line here too. AC10 greps for `rendered+validated N/N`, and a
  # root that prints only prose is indistinguishable from a gate that never ran —
  # the exact ambiguity the line exists to remove. 0/0 is the honest answer.
  echo "no infra templates in $ROOT (no templatefile() referents, no cloud-init*.yml)"
  echo "infra template validation: rendered+validated 0/0 file(s) in $ROOT"
  exit 0
fi

DISCOVERED=${#MEMBERS[@]}

# INDEPENDENT discovery floor. The counter at the bottom compares VALIDATED against
# DISCOVERED — but both are derived from the SAME discovery pass, so it is
# mathematically incapable of noticing a template that discovery never found. This
# floor is the second, independent opinion: count `templatefile(` occurrences with a
# trivially-robust grep and require discovery to have found at least that many. If a
# call site exists that discovery cannot parse, this reds instead of shrinking
# silently.
if [[ ${#TF_FILES[@]} -gt 0 ]]; then
  # Strip comments BEFORE counting. A bare `grep -c 'templatefile('` also matches
  # PROSE — `ci-ssh-key.tf`'s comment says "`templatefile()` interpolation map", and
  # server.tf's own #6454 note names it too — so the floor would red a correct corpus.
  # (Same trap the anchored attribution pattern below exists to dodge; it is easy to
  # reintroduce in a new guard.) `sed` here can also truncate at a `#` inside a string
  # literal, which can only LOSE a call — biasing the floor toward under-counting, i.e.
  # toward a weaker guard rather than a false red. That asymmetry is deliberate.
  tf_calls=$(sed -E 's|//.*$||; s|#.*$||' "${TF_FILES[@]}" 2>/dev/null \
               | grep -c 'templatefile(' || true)
  set_a_count=$(grep -hozP 'templatefile\(\s*"\$\{path\.module\}/\K[^"]+' "${TF_FILES[@]}" 2>/dev/null \
                  | tr '\0' '\n' | grep -c . || true)
  if [[ "$set_a_count" -lt "$tf_calls" ]]; then
    echo "ERROR: found $tf_calls 'templatefile(' call(s) in $ROOT/*.tf but discovery parsed only $set_a_count referent(s)." >&2
    echo "  A call site exists that discovery cannot read — it would be silently unvalidated." >&2
    echo "  (Non-\${path.module} referents, e.g. templatefile(local.p, …), are not yet supported.)" >&2
    exit 5
  fi
fi

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
  # Attribution must be line-INDEPENDENT for the same reason discovery is: the
  # wrapped call style (`templatefile(\n  "${path.module}/x.yml",`) is fmt-clean, and
  # a line-based `grep -nP` finds no site -> exit 4 on a correct .tf. Match against
  # the whole file with -z, take the BYTE offset with -b, and convert it to a line
  # number by counting newlines before it. (-H is still load-bearing when grep gets
  # exactly one file: without it the filename prefix is omitted and the line number
  # would be parsed as the filename.)
  sites=""
  for tf in "${TF_FILES[@]}"; do
    # `-z` makes the match line-independent; `-b` gives the byte offset, which we
    # convert to a line number for the awk extractor below. The `tr` is required:
    # -z output is NUL-separated, and a downstream grep would call it binary and
    # refuse to print.
    while IFS= read -r off; do
      [[ -z "$off" ]] && continue
      ln=$(( $(head -c "$off" "$tf" | tr -cd '\n' | wc -c) + 1 ))
      sites+="${tf}:${ln}"$'\n'
    done < <(grep -zboaP "$pat" "$tf" 2>/dev/null | tr '\0' '\n' | sed -nE 's/^([0-9]+):.*/\1/p')
  done
  sites=$(printf '%s' "$sites" | sed '/^[[:space:]]*$/d')
  n_sites=$(printf '%s' "$sites" | grep -c . || true)

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

  # Belt-and-braces: an empty tf_file would make the awk below read STDIN and
  # hang forever (a wedged CI job burns the whole runner timeout and reports
  # nothing — strictly worse than a red one). The exit-4 branches above already
  # make this unreachable; keep the guard so a future edit to them degrades to a
  # loud failure instead of a hang.
  if [[ -z "$tf_file" || ! -f "$tf_file" || ! "$tf_line" =~ ^[0-9]+$ ]]; then
    echo "ERROR [$base]: could not resolve a call site (file='$tf_file' line='$tf_line')" >&2
    exit 4
  fi

  # --- KEYS from the .tf map, TYPES from the body (Design Decision 2c).
  # Only real map keys can enter, so a `%{ for x in list ~}` loop-local can
  # never be mistaken for a var — the false-red a body-scanner would ship.
  #
  # Extract the map body by tracking brace DEPTH from the `{` that opens the
  # templatefile map to its matching `}`. Four ordinary shapes each defeat a
  # simpler scan, and every one of them is a false-red on a CORRECT file — the
  # #6454 dynamic this script exists to end:
  #   - a ONE-LINE map (`templatefile("...", { greeting = var.greeting })`);
  #   - a nested value whose `})` lands at column 0 (truncates the map early);
  #   - a brace inside a STRING value (`greeting = "hi}there"`) — not structural;
  #   - the WRAPPED call, where `templatefile(` and the filename are on different
  #     lines (fmt-clean, and it silently dropped a whole template from the corpus).
  # Hence an explicit state machine rather than line anchors:
  #   0 find `templatefile(`  ->  1 skip the quoted filename arg (may span lines)
  #                           ->  2 find the map `{`  ->  3 accumulate to its match
  map_text=$(awk -v start="$tf_line" '
    BEGIN { state = 0; depth = 0; qseen = 0; instr = 0 }
    NR < start { next }
    {
      line = $0
      if (state == 0) {
        i = index(line, "templatefile(")
        if (i == 0) next
        line = substr(line, i + 13)
        state = 1
      }
      out = ""
      n = length(line)
      for (j = 1; j <= n; j++) {
        c = substr(line, j, 1)
        prev = (j > 1) ? substr(line, j - 1, 1) : ""
        if (state == 1) {
          # Skip the filename argument. It is "${path.module}/<name>" — which
          # contains a `{` of its own, so hunting the map brace before the closing
          # quote latches onto the filename and treats it as the map.
          if (c == "\"" && prev != "\\") { qseen++; if (qseen == 2) state = 2 }
          continue
        }
        if (state == 2) {
          if (c == "{") { state = 3; depth = 1 }
          continue
        }
        if (c == "\"" && prev != "\\") { instr = !instr }
        if (c == "{" && !instr) { depth++ }
        else if (c == "}" && !instr) {
          depth--
          if (depth == 0) { if (length(out)) print out; exit }
        }
        out = out c
      }
      if (state == 3 && length(out)) print out
    }' "$tf_file")

  # Keys are `ident =` at the start of a line OR after a `,`/`{` (one-line maps
  # and nested objects put several on one line). `(?!=)` excludes `==`, so a
  # comparison never reads as an assignment. Keys harvested from a NESTED object
  # are phantoms, but templatefile() tolerates unused map keys (verified), so a
  # phantom is inert — whereas a MISSING key fails loud at exit 2. Bias
  # permissive.
  keys=$(printf '%s\n' "$map_text" \
    | grep -oP '(?:^|[,{])\s*\K[a-z_][a-zA-Z0-9_]*(?=\s*=(?!=))' \
    | sort -u)

  n_keys=$(printf '%s' "$keys" | grep -c .)
  if [[ "$n_keys" -eq 0 ]]; then
    echo "ERROR [$base]: parsed an EMPTY var map from $tf_file:$tf_line" >&2
    echo "  A template with syntax but no vars cannot be right; refusing to render blind." >&2
    exit 4
  fi

  # TYPES: a key referenced by a `%{ if ... }` / `%{ elseif ... }` directive is a
  # bool. Matching only `%{ if <key>` (key immediately after `if`) misreads
  # `%{ if !flag ~}` and `%{ if a && b ~}` — both ordinary — as strings, and the
  # render then dies at exit 2 on a correct template. Harvest the whole
  # condition expression instead and treat any map key named in it as a bool,
  # EXCEPT one adjacent to a comparison operator (`%{ if tier == "prod" ~}`
  # makes tier a string, and stubbing it `true` would be the type error).
  # `~?` covers the LEFT-strip form `%{~ if x ~}` — legal Terraform, and without it the
  # key types as a string and `!"x"` / a bare `"x"` condition is a type error: exit 2 on a
  # correct template.
  if_exprs=$(grep -oP '(?<!%)%\{~?\s*(?:if|elseif)\s+\K[^~}]*' "$path" 2>/dev/null || true)

  bools=()
  strings=()
  while IFS= read -r k; do
    [[ -z "$k" ]] && continue
    if [[ -n "$if_exprs" ]] \
      && grep -qP "\b${k}\b" <<<"$if_exprs" \
      && ! grep -qP "(\b${k}\b\s*(==|!=|<|>))|((==|!=|<|>)\s*\b${k}\b)" <<<"$if_exprs"; then
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
      # The stub map is THIS SCRIPT's guess, and terraform's error blames the
      # template — so on a mis-type the operator reads "cloud-init.yml:3: condition
      # must be bool" about a template that is perfectly correct. Print the map so
      # the guess is visible next to the complaint.
      echo "  Derived stub map (this gate's guess — types are inferred, see header):" >&2
      echo "    { $map }" >&2
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
    #
    # Terraform always substitutes a key that IS in the map, so this cannot fire
    # on a healthy render. It is the backstop for the case where the decode hands
    # back the RAW template — i.e. we would be validating un-rendered text while
    # believing it rendered, which is #6454 itself. Skip a key the source escapes
    # as `$${key}`: that renders to a literal `${key}` BY DESIGN and is a shell
    # seam, not a leak (only reachable when a lowercase shell var collides with a
    # map key name).
    for k in "${strings[@]}" "${bools[@]}"; do
      grep -qF "\$\${$k}" "$path" 2>/dev/null && continue
      if grep -qF "\${$k}" "$rendered" 2>/dev/null; then
        echo "ERROR [$base$label]: stub var \${$k} survived into the rendered document" >&2
        echo "  The render did not substitute it. If the decode returned the RAW template," >&2
        echo "  this gate would be validating un-rendered text — the #6454 defect itself." >&2
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
