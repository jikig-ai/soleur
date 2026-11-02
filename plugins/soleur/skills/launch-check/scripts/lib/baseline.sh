# shellcheck shell=bash
# The Soleur-baseline checks, derived at run time from the guard manifest. Nothing here names a guard:
# membership comes from guards.tsv; only the domain and severity LABEL of a guard comes from
# references/baseline-domains.tsv (default: tech-debt / medium).

lc_guards_tsv() { printf '%s' "${LAUNCH_CHECK_GUARDS_TSV:-$PLUGIN_DIR/skills/verification-scaffold/references/guards.tsv}"; }

# lc_guard_rows <tier-regex>: "name<TAB>emits<TAB>source_files" for each manifest row whose tier matches. Columns resolved by header name.
lc_guard_rows() {
  awk -F'\t' -v want="$1" '
    /^#/ || /^$/ { next }
    !h && $1 == "name" { for (i = 1; i <= NF; i++) c[$i] = i; h = 1; next }
    h && c["tier"] && c["emits"] && $c["tier"] ~ want { print $c["name"] "\t" $c["emits"] "\t" (c["source_files"] ? $c["source_files"] : "-") }' "$(lc_guards_tsv)"
}

# lc_baseline_rows: catalog rows (12 columns) for every v1 guard. An empty or unreadable manifest is a hard failure.
lc_baseline_rows() {
  local rows name emits src dom sev labels="$SKILL_DIR/references/baseline-domains.tsv"
  rows=$(lc_guard_rows '^v1$')
  [ -n "$rows" ] || lc_abort baseline-source-empty 2 "$(lc_guards_tsv)"
  while IFS=$'\t' read -r name emits src; do
    dom=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$labels" 2>/dev/null); dom=${dom:-tech-debt}
    sev=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$labels" 2>/dev/null); sev=${sev:-medium}
    printf 'BASE-%s\t%s\tbaseline\tguard\tSoleur guard: %s\t%s\tany\t%s\t%s\tpresent\tbash "${CLAUDE_PLUGIN_ROOT}/skills/verification-scaffold/scripts/verification-scaffold.sh" --guards %s\tInstall this guard, advisory first, with verification-scaffold.\n' \
      "$name" "$dom" "$name" "$sev" "$emits" "$src" "$name"
  done <<<"$rows"
}

# lc_build_catalog <outfile>: checks.tsv rows followed by the derived baseline rows.
lc_build_catalog() {
  local base rc=0
  awk -F'\t' '!/^#/ && $1 != "id" && $1 != "" { print }' "$SKILL_DIR/references/checks.tsv" > "$1"
  base=$(lc_baseline_rows) || rc=$?
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$base"; exit "$rc"; fi
  printf '%s\n' "$base" >> "$1"
}
