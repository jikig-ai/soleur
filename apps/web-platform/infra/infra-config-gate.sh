#!/usr/bin/env bash
# Sourceable adjudicator for the infra-config apply gate (#6594, PR-B).
#
# Extracted from the inline "Verify infra-config apply succeeded" step of
# .github/workflows/apply-deploy-pipeline-fix.yml so the adjudication is readable
# AND testable — infra-config-gate.test.sh sources this file and drives the fixtures
# without any network or prod access.
#
# WHY (#6594): the pre-fix gate asserted only a COUNT (files_total == repo FILE_MAP
# length). A stale host with the SAME count (15/15, exit_code=0, files_failed=0)
# sailed through while #6577's ci-deploy.sh never actually landed, and terraform
# latched the non-delivery as success. The content assert below closes that: it
# compares each delivered file's reported sha256 against the repo file the apply ran
# from, so a stale-but-same-count payload FAILS naming the diverging file.
#
# CONTENT MISMATCH IS TERMINAL. The caller MUST run adjudicate_infra_config (which
# contains the content assert) OUTSIDE the poll/retry loop. Inside the loop each
# retry re-fetches — a fresh Cloudflare connector selection — so asserting content
# there is "retry until SOME host matches" = any-of-3, which is exactly the coin
# flip #6594 exists to kill. PR-A pinned the ingress so connector selection is now
# deterministic, but the assert stays terminal on principle: a real content mismatch
# must never be retried away.
#
# Sourceable: defines functions only, no top-level execution.

# Number of delivered files the repo FILE_MAP expects. NOT hardcoded — auto-tracks
# FILE_MAP additions. Echoes the integer; the caller validates it is a positive int.
infra_config_expected_count() {
  local apply_script="$1"
  sed -n '/^FILE_MAP=(/,/^)/p' "$apply_script" | grep -cE '_B64\|'
}

# Classify each FILE_MAP row as "dest<TAB>basename<TAB>class":
#   comparable — repo ships <infra_dir>/<basename>; the bytes the host received are
#                that file, so its delivered sha256 must equal the repo file's.
#   template   — repo ships <basename>.tmpl and the delivered file is Terraform-
#                rendered with secrets interpolated (hooks.json ← hooks.json.tmpl),
#                so its content is NOT comparable. Excluded from the content assert.
#   missing    — neither present; a repo/FILE_MAP drift the gate must fail loud on.
# The template exclusion is DERIVED from the .tmpl property, never hardcoded — and
# adjudicate_infra_config asserts there is exactly one, so a drift in that property
# (a new template dest, or hooks.json.tmpl renamed) fails loud instead of silently
# widening the set of files skipped from the content check.
infra_config_classify_files() {
  local apply_script="$1" infra_dir="$2"
  local dest base
  sed -n '/^FILE_MAP=(/,/^)/p' "$apply_script" \
    | grep -E '_B64\|' \
    | sed -E 's/^[[:space:]]*"//; s/"[[:space:]]*$//' \
    | while IFS='|' read -r _ dest _ _; do
        base=$(basename "$dest")
        if [[ -f "$infra_dir/$base" ]]; then
          printf '%s\t%s\tcomparable\n' "$dest" "$base"
        elif [[ -f "$infra_dir/$base.tmpl" ]]; then
          printf '%s\t%s\ttemplate\n' "$dest" "$base"
        else
          printf '%s\t%s\tmissing\n' "$dest" "$base"
        fi
      done
}

# Pre-fix COUNT invariant — the #6178 logic that shipped and still runs as the poll
# loop's fast-path break condition. Quiet boolean: returns 0 when the status JSON
# passes exit_code==0, files_failed==0, files_written==files_total, and
# files_total==EXPECTED(repo FILE_MAP). This is the logic #6594 proved insufficient;
# it is kept as its own named function so the test can demonstrate the bug — a
# stale-same-count payload PASSES this — before the content assert catches it.
infra_config_count_invariant() {
  local status_json="$1" apply_script="$2"
  local expected exit_code files_failed files_written files_total
  expected=$(infra_config_expected_count "$apply_script")
  exit_code=$(jq -r '.exit_code // "MISSING"' "$status_json" 2>/dev/null)
  files_failed=$(jq -r '.files_failed // "MISSING"' "$status_json" 2>/dev/null)
  files_written=$(jq -r '.files_written // "MISSING"' "$status_json" 2>/dev/null)
  files_total=$(jq -r '.files_total // "MISSING"' "$status_json" 2>/dev/null)
  [[ "$exit_code" == "0" ]] || return 1
  [[ "$files_failed" == "0" ]] || return 1
  [[ "$files_total" != "MISSING" && "$files_total" != "null" ]] || return 1
  [[ "$files_written" == "$files_total" ]] || return 1
  [[ "$files_total" == "$expected" ]] || return 1
  return 0
}

# The Phase-3 CONTENT assert. For each comparable FILE_MAP dest, compare the host's
# reported sha256 (status JSON files[]) against sha256 of the repo file the apply ran
# from. Emits ::error::content_mismatch:<dest> and returns 1 on the first mismatch,
# a missing/failed delivery entry, or a repo/FILE_MAP drift. Also asserts exactly ONE
# template exclusion — if that derivation drifts, fail loud rather than silently skip
# content checks. Keyed off FILE_MAP, NOT the status JSON files[] (the handler appends
# orphan_hook_command entries to files[] that have no repo counterpart).
infra_config_content_assert() {
  local status_json="$1" infra_dir="$2" apply_script="$3"
  local rc=0 template_count=0 dest base class repo_sha host_sha host_status
  while IFS=$'\t' read -r dest base class; do
    case "$class" in
      template)
        template_count=$((template_count + 1))
        ;;
      missing)
        echo "::error::content_gate_repo_file_missing:$dest — no repo file $infra_dir/$base (nor ${base}.tmpl). FILE_MAP/repo drift; refusing to certify an un-checkable delivery."
        rc=1
        ;;
      comparable)
        repo_sha=$(sha256sum "$infra_dir/$base" | awk '{print $1}')
        host_status=$(jq -r --arg d "$dest" 'first(.files[]? | select(.file==$d) | .status) // ""' "$status_json" 2>/dev/null)
        host_sha=$(jq -r --arg d "$dest" 'first(.files[]? | select(.file==$d) | .sha256) // ""' "$status_json" 2>/dev/null)
        if [[ -z "$host_sha" || "$host_status" != "ok" ]]; then
          echo "::error::content_mismatch:$dest — no ok delivery entry in the status JSON (status='${host_status:-none}'). The apply did not report a clean write for this file."
          rc=1
        elif [[ "$host_sha" != "$repo_sha" ]]; then
          echo "::error::content_mismatch:$dest — host sha256=$host_sha but repo sha256=$repo_sha. The apply reported success while the host is serving different bytes than the commit it applied (#6594)."
          rc=1
        fi
        ;;
    esac
  done < <(infra_config_classify_files "$apply_script" "$infra_dir")

  if [[ "$template_count" -ne 1 ]]; then
    echo "::error::content_gate_template_exclusion_drift — expected exactly 1 Terraform-rendered FILE_MAP dest (hooks.json ← hooks.json.tmpl), found $template_count. The .tmpl-derived content-exclusion invariant drifted; refusing to skip content checks blindly."
    rc=1
  fi
  return "$rc"
}

# TERMINAL adjudication: count invariant (with specific diagnostics) + content assert.
# The caller runs this ONCE after the poll loop, never inside it. Returns non-zero on
# any failure with a named ::error:: line for each.
adjudicate_infra_config() {
  local status_json="$1" infra_dir="$2" apply_script="$3"
  local rc=0 expected exit_code files_failed files_written files_total
  expected=$(infra_config_expected_count "$apply_script")
  exit_code=$(jq -r '.exit_code // "MISSING"' "$status_json" 2>/dev/null)
  files_failed=$(jq -r '.files_failed // "MISSING"' "$status_json" 2>/dev/null)
  files_written=$(jq -r '.files_written // "MISSING"' "$status_json" 2>/dev/null)
  files_total=$(jq -r '.files_total // "MISSING"' "$status_json" 2>/dev/null)

  if [[ "$exit_code" != "0" ]]; then
    echo "::error::infra-config-apply reported exit_code=$exit_code (partial failure or no prior apply)."
    rc=1
  fi
  if [[ "$files_failed" != "0" ]]; then
    echo "::error::infra-config-apply reported files_failed=$files_failed — one or more files did not land on the host."
    rc=1
  fi
  if [[ "$files_total" == "MISSING" || "$files_total" == "null" || "$files_written" != "$files_total" ]]; then
    echo "::error::infra-config-apply landed-files mismatch: files_written=$files_written files_total=$files_total (expected equal and non-null)."
    rc=1
  fi
  if [[ "$files_total" != "$expected" ]]; then
    echo "::error::infra-config-apply UNDER-DELIVERED: host reported files_total=$files_total but the repo FILE_MAP expects $expected (#6178 false-green fix). This is NOT a pass."
    rc=1
  fi

  # Content assert runs only when the count invariant holds — a broken count already
  # fails the gate, and content diagnostics on a broken count are noise. When counts
  # are clean, the content assert is the #6594 catch: same count, stale bytes.
  if [[ "$rc" -eq 0 ]]; then
    if ! infra_config_content_assert "$status_json" "$infra_dir" "$apply_script"; then
      rc=1
    fi
  fi
  return "$rc"
}
