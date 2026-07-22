#!/usr/bin/env bash
# run-scan.sh — orchestrate the five category checks, aggregate verdict,
# emit markdown findings + mandatory disclaimer footer, write .scan-meta.json
# (with PII redaction).
#
# Stdin: SKILL.md content. Or: positional file path.
# Stdout: markdown findings table + disclaimer footer.
# Exit code: 0 always (advisory).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCANNER_VERSION="0.1.0"

# Resolve input file
if [ "$#" -ge 1 ] && [ -f "$1" ]; then
  INPUT="$1"
  CLEANUP=""
else
  INPUT="$(mktemp -t skill-scan-input-XXXXXX)"
  CLEANUP="$INPUT"
  cat > "$INPUT"
fi
trap '[ -n "$CLEANUP" ] && rm -f "$CLEANUP"' EXIT

# ---------------------------------------------------------------------------
# Self-defense: rule-pack SHA validation (per Phase 5)
# ---------------------------------------------------------------------------
manifest="$SKILL_DIR/references/rules/manifest.yaml"
rule_pack_sha="unknown"
rule_pack_version="unknown"
if [ -f "$manifest" ]; then
  rule_pack_version="$(awk '/^version:/ { gsub(/^version:[[:space:]]*"?|"?$/, ""); print; exit }' "$manifest")"
  # Compute current manifest SHA over the manifest file itself for traceability.
  rule_pack_sha="$(sha256sum "$manifest" | cut -d' ' -f1)"
  # Validate per-file SHAs declared in manifest. Tampered file → flag and
  # short-circuit to REVIEW. Manifest format: list of `- path:`/`sha256:`
  # tuples relative to the rules/ directory.
  tampered=""
  while IFS= read -r line; do
    case "$line" in
      *path:*)
        cur_path="${line#*path:}"
        cur_path="${cur_path// /}"
        cur_path="${cur_path//\"/}"
        cur_path="${cur_path//\'/}"
        ;;
      *sha256:*)
        cur_sha="${line#*sha256:}"
        cur_sha="${cur_sha// /}"
        cur_sha="${cur_sha//\"/}"
        cur_sha="${cur_sha//\'/}"
        actual="$(sha256sum "$SKILL_DIR/references/$cur_path" 2>/dev/null | cut -d' ' -f1 || echo "")"
        if [ -n "$actual" ] && [ "$actual" != "$cur_sha" ]; then
          tampered+="$cur_path "
        fi
        cur_path=""
        ;;
    esac
  done < "$manifest"
  if [ -n "$tampered" ]; then
    # Tamper short-circuits to HIGH-RISK (deny-by-default), not REVIEW.
    # Rationale: REVIEW maps to `ask` in the PreToolUse hook, which an operator
    # can confirm-through; an attacker with rule-pack write access could then
    # downgrade a real HIGH-RISK skill to REVIEW and have the operator accept.
    # HIGH-RISK on tamper forces an override-artifact path and audit trail.
    cat <<EOF
# skill-security-scan verdict: HIGH-RISK

**Self-defense:** rule pack tampered. Files with SHA mismatch:

$(echo "$tampered" | tr ' ' '\n' | grep -v '^$' | sed 's/^/  - /')

Re-run with \`scripts/run-self-test.sh --regenerate-manifest\` (dev) or fix
the rule pack before scanning. Override requires a structured artifact under
\`knowledge-base/engineering/security/skill-overrides/\`.

---
Advisory static analysis only. LOW-RISK does not constitute a security audit,
certification, or warranty of safety. The skill executes in your environment
under your account; you remain responsible for review.

Scanner version: $SCANNER_VERSION  Rule pack: ${rule_pack_sha:0:12}  Scanned: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Run the five category checks. Each consumes stdin (the SKILL.md content)
# and emits a JSON document on stdout. We collect into a temp dir.
# ---------------------------------------------------------------------------
results_dir="$(mktemp -dt skill-scan-results-XXXXXX)"
trap '[ -n "$CLEANUP" ] && rm -f "$CLEANUP"; rm -rf "$results_dir"' EXIT

run_category() {
  local script="$1" out="$2"
  bash "$SCRIPT_DIR/$script" < "$INPUT" > "$out" 2>/dev/null || \
    echo '{"verdict":"REVIEW","category":"unknown","findings":[{"rule_id":"check-failed","severity":"REVIEW","line":0,"snippet":"category script error"}]}' > "$out"
}

run_category check-codeexec.sh           "$results_dir/code-execution.json" &
run_category check-prompt-injection.sh   "$results_dir/prompt-injection.json" &
run_category check-supply-chain.sh       "$results_dir/supply-chain.json" &
run_category check-filesystem-boundary.sh "$results_dir/filesystem-boundary.json" &
run_category check-telemetry-surface.sh  "$results_dir/telemetry-surface.json" &
wait

# Aggregate verdict (max-severity wins).
agg_verdict="LOW-RISK"
for f in "$results_dir"/*.json; do
  v="$(jq -r '.verdict' "$f" 2>/dev/null || echo "REVIEW")"
  case "$v" in
    HIGH-RISK) agg_verdict="HIGH-RISK"; break ;;
    REVIEW)    [ "$agg_verdict" = "LOW-RISK" ] && agg_verdict="REVIEW" ;;
  esac
done

# Build findings_summary JSON (with PII + secret redaction).
# Per GDPR-DataMin-1 (PII) and security review P2-4 (high-entropy secrets):
# redact email/IPv4/IBAN PLUS JWT, Anthropic/OpenAI keys, GitHub PAT/OAuth,
# Doppler tokens, GitLab PAT, Slack tokens, AWS access keys.
redact_pii() {
  sed -E '
    s/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/<email>/g;
    s/\b([0-9]{1,3}\.){3}[0-9]{1,3}\b/<ip>/g;
    s/\b[A-Z]{2}[0-9]{2}[A-Z0-9]{4,}\b/<iban>/g;
    s/eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/<jwt>/g;
    s/sk-ant-[A-Za-z0-9_-]{8,}/<anthropic-key>/g;
    s/sk-[A-Za-z0-9]{20,}/<openai-key>/g;
    s/\bghp_[A-Za-z0-9]{20,}/<github-pat>/g;
    s/\bgho_[A-Za-z0-9]{20,}/<github-oauth>/g;
    s/\bghs_[A-Za-z0-9]{20,}/<github-server>/g;
    s/\bghr_[A-Za-z0-9]{20,}/<github-refresh>/g;
    s/\bglpat-[A-Za-z0-9_-]{8,}/<gitlab-pat>/g;
    s/dp\.ct\.[A-Za-z0-9_-]{20,}/<doppler-token>/g;
    s/dp\.pt\.[A-Za-z0-9_-]{20,}/<doppler-token>/g;
    s/dp\.st\.[A-Za-z0-9_-]{20,}/<doppler-token>/g;
    s/xox[bopas]-[A-Za-z0-9-]{10,}/<slack-token>/g;
    s/\bAKIA[A-Z0-9]{16}\b/<aws-access-key>/g
  '
}

# ARGV CEILING (#6736). Both the per-category body and the accumulated summary are
# kept in FILES and bound with `--rawfile … | fromjson`, never `--argjson`. A shell
# variable bound via --argjson is ONE argv argument, and the kernel caps a SINGLE argv
# argument at MAX_ARG_STRLEN = 131,072 B — verified by bisect on this host: 131,071 B
# passes, 131,072 B fails E2BIG. This is NOT `getconf ARG_MAX` (2,097,152 B, the
# argv+envp total); a payload at 6% of ARG_MAX still dies.
#
# Nothing bounds this: snippets are capped at 200 chars by apply_yaml_rules, but the
# FINDING COUNT is uncapped (one grep hit per matching line), and $findings_summary is
# the sum over all five categories — so it crosses the ceiling before any single
# category does. Pre-fix this died with `Argument list too long` mid-scan, after the
# per-category checks had already succeeded.
#
# The scratch files live in "$results_dir/.agg" rather than "$results_dir" itself:
# the markdown-table loop below re-globs "$results_dir"/*.json, and a summary file
# sitting there would be read back as a sixth bogus category row. A dot-prefixed
# subdirectory is invisible to that glob and is still cleaned by the existing
# `rm -rf "$results_dir"` EXIT trap, so this adds no new cleanup obligation.
agg_dir="$results_dir/.agg"
mkdir -p "$agg_dir"
summary_file="$agg_dir/findings-summary.json"
body_file="$agg_dir/body-redacted.json"
echo '{}' > "$summary_file"
for f in "$results_dir"/*.json; do
  cat="$(jq -r '.category' "$f")"
  jq '{verdict, findings}' "$f" | redact_pii > "$body_file"
  jq --arg c "$cat" --rawfile b "$body_file" '. + {($c): ($b | fromjson)}' \
    "$summary_file" > "$summary_file.next"
  mv "$summary_file.next" "$summary_file"
done

# Write .scan-meta.json next to input (or to runtime dir for stdin).
# umask 077 ensures persisted findings are not world-readable on shared hosts.
ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
meta_base="${SKILL_SCAN_META_BASE:-${XDG_RUNTIME_DIR:-/tmp}}"

# Bound the per-invocation meta_dir leak (#6789). Each run creates
# skill-security-scan-<pid>/ and NOTHING removes it: measured 12,889 leaked
# dirs. The fix is a STARTUP age-reap of OLDER siblings — deliberately NOT a
# `trap 'rm -rf "$meta_dir"' EXIT`. `.scan-meta.json` is GDPR Art. 32 evidence:
# override-mechanism.md instructs the operator to reference this path in an
# override artifact AFTER the scan exits (see the "written to:" line below), so
# a naive EXIT trap would delete the very artifact the override flow needs (R1).
# The current process's own dir is created after this reap and is never a
# candidate here, so the artifact this run writes always survives this run.
# Age-only is the correct sole dimension: these dirs are per-pid and single-use,
# so an OLD one is definitionally abandoned (unlike the /tmp scratch reaper,
# where age alone is unsafe). SKILL_SCAN_META_REAP_MIN defaults to 24h.
_reap_min="${SKILL_SCAN_META_REAP_MIN:-1440}"
if [ -d "$meta_base" ]; then
  # -maxdepth 1 -type d, older than the floor, own the current uid. `-mmin` on
  # each dir is safe here: the dir is written once at creation and never touched
  # again, so its own mtime IS the run's age. rm failures (a sibling reaping the
  # same dir) are tolerated.
  find "$meta_base" -mindepth 1 -maxdepth 1 -type d \
    -name 'skill-security-scan-*' -user "$(id -u)" -mmin "+${_reap_min}" \
    -exec rm -rf {} + 2>/dev/null || true
fi

(umask 077; mkdir -p "$meta_base/skill-security-scan-$$")
meta_dir="$meta_base/skill-security-scan-$$"
meta_path="$meta_dir/.scan-meta.json"
jq -n \
  --arg sv "$SCANNER_VERSION" \
  --arg rpv "$rule_pack_version" \
  --arg sha "$rule_pack_sha" \
  --arg v "$agg_verdict" \
  --arg ts "$ts" \
  --rawfile fs "$summary_file" \
  '{scanner_version: $sv, rule_pack_version: $rpv, rule_pack_sha256: $sha, verdict: $v, timestamp: $ts, findings_summary: ($fs | fromjson)}' \
  > "$meta_path"

# Emit markdown findings table + mandatory disclaimer.
echo "# skill-security-scan verdict: $agg_verdict"
echo ""
echo "| Category | Verdict | Findings |"
echo "|---|---|---|"
for f in "$results_dir"/*.json; do
  cat="$(jq -r '.category' "$f")"
  v="$(jq -r '.verdict' "$f")"
  n="$(jq -r '.findings | length' "$f")"
  echo "| $cat | $v | $n |"
done
echo ""
echo "Per-finding details (operator-facing, unredacted):"
echo ""
for f in "$results_dir"/*.json; do
  v="$(jq -r '.verdict' "$f")"
  if [ "$v" != "LOW-RISK" ]; then
    cat="$(jq -r '.category' "$f")"
    echo "## $cat ($v)"
    echo ""
    jq -r '.findings[] | "- **\(.rule_id)** (\(.severity)) line \(.line): `\(.snippet)`"' "$f"
    echo ""
  fi
done
echo ".scan-meta.json written to: $meta_path"
echo ""
cat <<EOF
---
Advisory static analysis only. LOW-RISK does not constitute a security audit,
certification, or warranty of safety. The skill executes in your environment
under your account; you remain responsible for review.

Scanner version: $SCANNER_VERSION  Rule pack: ${rule_pack_sha:0:12}  Scanned: $ts
EOF
