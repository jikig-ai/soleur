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

# Units the repo's RESTART_MAP expects a reconciliation verdict for (#7103 R2 3.8). Derived
# from the handler exactly as the file count is, so adding a unit ratchets the contract rather
# than silently widening what the gate accepts as complete. One unit per line.
infra_config_expected_restart_units() {
  local apply_script="$1"
  sed -n '/^RESTART_MAP=(/,/^)/p' "$apply_script" | sed -n 's/^[[:space:]]*"\([^|]*\)|.*"$/\1/p'
}

# Classify each FILE_MAP row as "dest<TAB>basename<TAB>class":
#   comparable — repo ships <infra_dir>/<basename>; the bytes the host received are
#                that file, so its delivered sha256 must equal the repo file's.
#   template   — repo ships <basename>.tmpl and the delivered file is Terraform-
#                rendered with secrets interpolated (hooks.json ← hooks.json.tmpl;
#                /etc/default/soleur-doppler-token ← soleur-doppler-token.tmpl, #7095),
#                so its bytes are NOT repo-comparable. Excluded from the BYTE compare, but
#                still required to have an ok per-dest delivery entry (see #7095 R7 below).
#   missing    — neither present; a repo/FILE_MAP drift the gate must fail loud on.
# The exclusion MEMBERSHIP is DERIVED from the .tmpl property, never hardcoded (no dest
# path is named in code). The expected CARDINALITY is pinned: infra_config_content_assert
# asserts exactly TWO template dests (hooks.json + soleur-doppler-token, #7095). That pin is
# fail-loud on purpose — a NEW template-backed FILE_MAP dest (or either .tmpl renamed) reds the
# gate until the count is deliberately updated, rather than silently widening the set of files
# skipped from the content check. Membership auto-tracks; cardinality is a reviewed constant.
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
# a missing/failed delivery entry, or a repo/FILE_MAP drift. Also asserts the pinned
# template-exclusion CARDINALITY — if that derivation drifts, fail loud rather than silently
# skip content checks. Keyed off FILE_MAP, NOT the status JSON files[] (the handler appends
# orphan_hook_command entries to files[] that have no repo counterpart).
infra_config_content_assert() {
  local status_json="$1" infra_dir="$2" apply_script="$3"
  local rc=0 template_count=0 dest base class repo_sha host_sha host_status
  local local_var_name expected_rendered_sha
  while IFS=$'\t' read -r dest base class; do
    case "$class" in
      template)
        template_count=$((template_count + 1))
        # #7095 (R7) — a template dest is excluded from the BYTE comparison because the repo
        # ships the unrendered .tmpl, but it must NOT thereby fall out of content checking
        # altogether. Before this, adding a template-backed dest silently moved it into the
        # "verified only by files_written == files_total" bucket — which is precisely the
        # latched false-green of #6594, where a stale host reported a clean 15/15 while the
        # instrument that was supposed to have been delivered never arrived.
        #
        # Two tiers, so the assert is never weaker than what the caller can actually prove:
        #   1. ALWAYS: this dest has its own ok entry with a non-empty sha256 in the status
        #      JSON. Per-dest, so a stale status that simply omits the new file fails loudly
        #      instead of passing on an aggregate count.
        #   2. WHEN AVAILABLE: full byte comparison against the digest of the rendered payload
        #      the caller holds, exported as INFRA_CONFIG_RENDERED_SHA_<DEST_WITH_NON_ALNUM_AS_
        #      UNDERSCORES_UPPERCASED>. The rendering needs the secret, so only the apply
        #      workflow (which already runs under `doppler run`) can supply it; a caller
        #      without it still gets tier 1 rather than nothing.
        host_status=$(jq -r --arg d "$dest" 'first(.files[]? | select(.file==$d) | .status) // ""' "$status_json" 2>/dev/null)
        host_sha=$(jq -r --arg d "$dest" 'first(.files[]? | select(.file==$d) | .sha256) // ""' "$status_json" 2>/dev/null)
        if [[ -z "$host_sha" || "$host_status" != "ok" ]]; then
          echo "::error::content_mismatch:$dest — template-backed dest has no ok delivery entry in the status JSON (status='${host_status:-none}'). The apply did not report a clean write for this file; a Terraform-rendered dest is still required to be DELIVERED even though its bytes are not repo-comparable."
          rc=1
        else
          local_var_name="INFRA_CONFIG_RENDERED_SHA_$(printf '%s' "$dest" | tr -c '[:alnum:]' '_' | tr '[:lower:]' '[:upper:]')"
          expected_rendered_sha="${!local_var_name:-}"
          if [[ -n "$expected_rendered_sha" && "$host_sha" != "$expected_rendered_sha" ]]; then
            echo "::error::content_mismatch:$dest — host sha256=$host_sha but the rendered payload this apply pushed digests to $expected_rendered_sha. The status did not originate from an apply of THIS render (stale or mis-delivered apply, #6594/#7095)."
            rc=1
          fi
        fi
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
          # host_sha is the digest of the payload the handler decoded on the apply
          # that PRODUCED this status (infra-config-apply.sh sha256's the staged temp,
          # not the installed file), so a mismatch means the status was produced by an
          # apply whose payload differs from this commit's repo file — i.e. a stale or
          # mis-delivered status, not necessarily the bytes currently on disk. That
          # stale-status shape IS #6594 (a status latched from an earlier, smaller apply).
          echo "::error::content_mismatch:$dest — host sha256=$host_sha but repo sha256=$repo_sha. This status did not originate from an apply of this commit's ${base} (stale or mis-delivered apply, #6594)."
          rc=1
        fi
        ;;
    esac
  done < <(infra_config_classify_files "$apply_script" "$infra_dir")

  if [[ "$template_count" -ne 2 ]]; then
    echo "::error::content_gate_template_exclusion_drift — expected exactly 2 Terraform-rendered FILE_MAP dests (hooks.json ← hooks.json.tmpl, /etc/default/soleur-doppler-token ← soleur-doppler-token.tmpl, #7095), found $template_count. The .tmpl-derived content-exclusion invariant drifted; refusing to skip content checks blindly."
    rc=1
  fi
  return "$rc"
}

# TERMINAL adjudication: count invariant (with specific diagnostics) + content assert.
# The caller runs this ONCE after the poll loop, never inside it. Returns non-zero on
# any failure with a named ::error:: line for each.
#
# EVERY PATH THAT REACHES A ZERO RETURN (#7220 A6.4 — enumerated because this function gained a
# message-suppression mode, and suppression is the exact shape that turns a safety gate into a
# bypass). `rc` starts at 0 and this function returns it. It stays 0 only if ALL of:
#   1. exit_code == 0;                         2. files_failed == 0;
#   3. files_written == files_total (non-null); 4. files_total == repo FILE_MAP count;
#   5. infra_config_content_assert passed (per-dest sha + template-cardinality pin);
#   6. every RESTART_MAP unit has a verdict, and none is `failed`/unrecognised/rc!=0;
#   7. the RESTART_MAP derivation was non-empty.
# There is NO other `return`. The #7220 fatal branch below only ever SETS rc=1 and silences
# other MESSAGES; it can never clear rc, and `fatal_line` is not a path to zero.
adjudicate_infra_config() {
  local status_json="$1" infra_dir="$2" apply_script="$3"
  local rc=0 expected exit_code files_failed files_written files_total
  local fatal_line fatal_rc fatal_cmd fatal_mode=0
  expected=$(infra_config_expected_count "$apply_script")
  exit_code=$(jq -r '.exit_code // "MISSING"' "$status_json" 2>/dev/null)
  files_failed=$(jq -r '.files_failed // "MISSING"' "$status_json" 2>/dev/null)
  files_written=$(jq -r '.files_written // "MISSING"' "$status_json" 2>/dev/null)
  files_total=$(jq -r '.files_total // "MISSING"' "$status_json" 2>/dev/null)

  # --- #7220 fatal attribution -------------------------------------------------------------
  # A frame carrying a non-zero fatal_line means the handler died at a KNOWN line and every
  # step after it did not run. That single fact explains the count shortfall and the missing
  # activation verdicts, so repeating them as separate failures buries the one line the
  # operator needs. Suppression is of MESSAGES ONLY — see the enumeration above.
  fatal_line=$(jq -r '.fatal_line // 0' "$status_json" 2>/dev/null || echo 0)
  fatal_rc=$(jq -r '.fatal_rc // 0' "$status_json" 2>/dev/null || echo 0)
  fatal_cmd=$(jq -r '.fatal_cmd // ""' "$status_json" 2>/dev/null || echo "")
  [[ "$fatal_line" =~ ^[0-9]+$ ]] || fatal_line=0
  [[ "$fatal_rc"   =~ ^[0-9]+$ ]] || fatal_rc=0
  [[ "$fatal_line" -gt 0 ]] && fatal_mode=1

  if [[ "$fatal_mode" -eq 1 ]]; then
    # The COMMAND leads, and the line is labelled as a DEPLOYED-handler coordinate. `fatal_line`
    # indexes the handler as it exists ON THE HOST, which terraform_data.deploy_pipeline_fix
    # documents can lag this checkout by one apply — and #7220's own fix moved the reload from
    # line 415 to 520 within a single PR, where 415 then held an unrelated statement. Rendering
    # it bare invites the operator to open the repo at a line that means something else. This is
    # the same reason cq-cite-content-anchor-not-line-number exists, applied to a runtime value.
    echo "::error::infra-config-apply DIED running: ${fatal_cmd:-<unrecorded>} (rc=${fatal_rc}, at line ${fatal_line} of the handler AS DEPLOYED — that number may not match this checkout)"
    echo "::error::every step after this line did not run, which is why no unit has an activation verdict below (and why any count shortfall is a stopping point, not a delivery failure)."
    echo "::error::what is still true: files_written=${files_written} of ${expected} delivered. The files that DID land are on the host; this is an ACTIVATION failure, not necessarily a delivery one."
    echo "::error::next: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_CONFIG_FATAL"
    # NAMES THE FORBIDDEN TARGET, not just the command. A prohibition on a command PREFIX is
    # uncheckable and self-contradicting here: this same workflow legitimately prescribes
    # `-replace=terraform_data.infra_config_handler_bootstrap` for the 000/502/503 shape. A
    # reader who takes the bare form literally is stranded; one who notices the stock
    # justification cannot apply to a terraform_data resource goes looking for a target — and
    # nothing told them WHICH one destroys the host. The previous incident destroyed via a target.
    echo "::error::This does NOT mean the host is bricked. Do NOT run \`terraform apply -replace=hcloud_server.web\` — that host cannot be re-provisioned (\`cx33\`, 0/6 stock). Replacing \`terraform_data.infra_config_handler_bootstrap\` is a DIFFERENT and safe operation, but it is the right lever only when the status endpoint returns 000/502/503, which is not this failure."
    rc=1
  fi

  if [[ "$exit_code" != "0" ]]; then
    # KEPT in fatal mode: it is accurate, and it is the verdict the gate adjudicates on first.
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
    # SUPPRESSED (message only) in fatal mode — fatal_line already explains the shortfall, and
    # in #7220 this line said "files_total=0" about an apply that had written 19 of 19.
    if [[ "$fatal_mode" -eq 0 ]]; then
      echo "::error::infra-config-apply UNDER-DELIVERED: host reported files_total=$files_total but the repo FILE_MAP expects $expected (#6178 false-green fix). This is NOT a pass."
    fi
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

  # --- Activation contract (#7103 R2 3.8) ---
  # TERMINAL ONLY. This must never be added to infra_config_count_invariant: that function is
  # the poll BREAK-condition, so a timing race there would burn all three attempts and become an
  # unretried terminal red. Two synchronous try-restarts can outlast the ~18s poll window, which
  # is exactly the race that would happen.
  #
  # STAGED. A handler predating this contract emits no schema_version, and the ONLY route to
  # replacing that handler is the SSH handler-bootstrap leg — which ADR-154 records can be dead
  # on a host that cannot be replaced. Failing here would red adjudicate_infra_config, which
  # skips the `if: success()`-gated redeploy step, so the files land and activation never
  # happens. Warn and pass; the hard-on-absent flip belongs in a follow-up once one apply has
  # demonstrably delivered the contract, and it is recorded on #7103 rather than smuggled in.
  local schema_version
  schema_version=$(jq -r '.schema_version // 0' "$status_json" 2>/dev/null || echo 0)
  [[ "$schema_version" =~ ^[0-9]+$ ]] || schema_version=0

  if [[ "$schema_version" -lt 2 ]]; then
    echo "::warning::infra_config_handler_predates_restarts: host reported schema_version=$schema_version (<2), so this apply carries no unit-activation verdict. The handler is replaced over the terraform_data.infra_config_handler_bootstrap SSH leg; until that runs, delivery is verified but activation is not."
  else
    local unit verdict action reason r_rc r_active missing=0
    while IFS= read -r unit; do
      [[ -n "$unit" ]] || continue
      verdict=$(jq -c --arg u "$unit" '.restarts[]? | select(.unit == $u)' "$status_json" 2>/dev/null)
      if [[ -z "$verdict" ]]; then
        # SUPPRESSED (message only) in #7220 fatal mode. "An absent entry is indistinguishable
        # from a unit that was never considered" is the right thing to say when the handler ran
        # to completion — but when fatal_line names the line it died on, the entry is absent
        # for a KNOWN reason and this line competes with it for the operator's attention.
        # The verdict is unchanged: rc=1 either way.
        if [[ "$fatal_mode" -eq 0 ]]; then
          echo "::error::infra-config activation contract: no verdict for $unit. A schema_version>=2 frame must carry one entry per RESTART_MAP unit — an absent entry is indistinguishable from a unit that was never considered."
        fi
        rc=1; missing=$((missing + 1)); continue
      fi
      action=$(jq -r '.action  // "MISSING"' <<<"$verdict")
      reason=$(jq -r '.reason  // "MISSING"' <<<"$verdict")
      r_rc=$(jq   -r '.rc      // "MISSING"' <<<"$verdict")
      r_active=$(jq -r '.active // "MISSING"' <<<"$verdict")

      # HARD FAIL BY DENY-LIST, keyed on `action` first.
      #
      # This was an ALLOW-LIST of three reason strings and never keyed on action at all, which
      # meant every verdict outside those three passed SILENTLY — measured against the shipped
      # function: reason=timestamp_unparseable, an unrecognised reason, and even
      # action=failed/reason=anything each returned rc=0 with no output, not even a warning.
      # The handler's vocabulary is larger than three and grows whenever a new fault is named,
      # so an allow-list classifies every future fault as inert. That is the same fail-open shape
      # the repo already documents for terraform action verbs: deny-list what is known to be
      # harmless, never allow-list what is known to be dangerous.
      #
      # A `failed` action is a failure whatever the reason says. No host topology makes it
      # legitimate — each means the handler tried to activate a delivered drop-in and could not,
      # or could not measure whether it had. This is ADR-159 proposition 1's defect exactly.
      case "$action" in
        restarted)
          : ;;
        skipped)
          case "$reason" in
            # KNOWN-INERT skips only. unit_inactive/unit_absent are co-location facts and get the
            # warning arm below; not_stale means the running process already postdates its inputs.
            not_stale|unit_inactive|unit_absent)
              : ;;
            *)
              echo "::error::infra-config activation for $unit reports an UNRECOGNISED skip reason: reason=$reason (action=$action rc=$r_rc active=$r_active). The gate fails closed on reasons it does not know: a verdict this adjudicator cannot classify is not evidence that the unit is running its drop-in."
              rc=1
              ;;
          esac
          ;;
        failed)
          echo "::error::infra-config activation FAILED for $unit: action=$action reason=$reason rc=$r_rc active=$r_active. The drop-in was delivered but the unit is not running it."
          rc=1
          ;;
        *)
          echo "::error::infra-config activation for $unit reports an UNRECOGNISED action: action=$action (reason=$reason rc=$r_rc active=$r_active)."
          rc=1
          ;;
      esac
      if [[ "$r_rc" != "0" ]]; then
        echo "::error::infra-config activation for $unit returned rc=$r_rc (action=$action reason=$reason)."
        rc=1
      fi

      # WARN, not fail, when a unit the handler never ATTEMPTED is not active.
      #
      # The plan called for failing on any active != active. That is right for a unit we acted
      # on — and every such case is already covered by the `failed` arm above, which fires
      # whether or not the unit ended up active. Extending it to SKIPPED units would fail the
      # gate on a host where the unit legitimately does not run, and a permanently-red deploy
      # gate on a correct host is a worse failure than the one being guarded against.
      #
      # Note this arm is now genuinely an edge case rather than the steady state. While
      # inngest-heartbeat.service was in RESTART_MAP it fired on essentially every apply — that
      # unit is a timer-driven Type=oneshot with no RemainAfterExit, so `inactive` was its
      # normal condition — which is precisely the alert fatigue that trains a reader to skip
      # warnings. It has been removed from the map; see the rationale there.
      #
      # "Is vector actually shipping?" is a real question, and it is R3's — the absence helper's
      # `unshipping` outcome answers it against the sink, which is where it can be answered
      # truthfully. Asserting it here would duplicate that check in the one place that cannot
      # distinguish "not running" from "not supposed to be running".
      if [[ "$action" == "skipped" && "$r_active" != "active" ]]; then
        echo "::warning::infra_config_unit_not_active: $unit is $r_active (reason=$reason); no restart was attempted. Delivery is unaffected; whether this unit should be running here is answered by the telemetry absence check, not by this gate."
      fi
    done < <(infra_config_expected_restart_units "$apply_script")

    # Non-vacuity: a broken derivation would yield an empty unit list and this whole block
    # would pass having checked nothing.
    local expected_units
    # `grep -c` prints 0 AND EXITS 1 on no match. Unguarded, that non-zero propagates out of the
    # command substitution and — on any future call site that is not `if ! adjudicate …` —
    # aborts before the very check below can report the vacuity it exists to report.
    expected_units=$(infra_config_expected_restart_units "$apply_script" | grep -c . || true)
    [[ "$expected_units" =~ ^[0-9]+$ ]] || expected_units=0
    if [[ "$expected_units" -lt 1 ]]; then
      echo "::error::infra-config activation contract: derived ZERO units from the handler's RESTART_MAP — the parse is broken and every activation assertion above was vacuous."
      rc=1
    fi
  fi
  return "$rc"
}
