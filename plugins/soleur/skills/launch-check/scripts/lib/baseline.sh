# shellcheck shell=bash
# The Soleur-baseline checks, derived at run time from the guard manifest. Nothing here names a guard:
# membership comes from guards.tsv; only the domain and severity LABEL of a guard comes from
# references/baseline-domains.tsv (default: tech-debt / medium).

lc_guards_tsv() { lc_seam LAUNCH_CHECK_GUARDS_TSV "$PLUGIN_DIR/skills/verification-scaffold/references/guards.tsv"; }

# lc_guard_rows <tier-regex>: "name<TAB>emits<TAB>source_files" for each manifest row whose tier matches. Columns resolved by header name.
lc_guard_rows() {
  awk -F'\t' -v want="$1" '
    /^#/ || /^$/ { next }
    !h && $1 == "name" { for (i = 1; i <= NF; i++) c[$i] = i; h = 1; next }
    h && c["tier"] && c["emits"] && $c["tier"] ~ want { print $c["name"] "\t" $c["emits"] "\t" (c["source_files"] && $c["source_files"] != "" ? $c["source_files"] : "-") }' "$(lc_guards_tsv)"
}

# lc_baseline_rows: catalog rows (12 columns) for every v1 guard. An empty or unreadable manifest is a hard failure.
lc_baseline_rows() {
  local rows name emits src dom sev labels="$SKILL_DIR/references/baseline-domains.tsv" g
  g=$(lc_guards_tsv)
  rows=$(lc_guard_rows '^v1$')
  if [ -z "$rows" ]; then
    # A manifest whose header lost a column we resolve by name is malformed, not merely empty.
    awk -F'\t' '$1 == "name" { h = 1; for (i = 1; i <= NF; i++) if ($i == "tier" || $i == "emits") n++ } END { exit (h && n != 2) }' "$g" 2>/dev/null \
      || lc_abort baseline-source-malformed 2 "$g lacks a name/tier/emits header"
    lc_abort baseline-source-empty 2 "$g"
  fi
  while IFS=$'\t' read -r name emits src; do
    [[ "$name" =~ ^[A-Za-z0-9-]+$ ]] || lc_abort baseline-source-malformed 2 "guard name outside [A-Za-z0-9-]"
    { [ -n "$emits" ] && [ "$emits" != "-" ]; } || lc_abort baseline-source-malformed 2 "guard $name emits nothing"
    dom=$(awk -F'\t' -v n="$name" '$1==n {print $2}' "$labels" 2>/dev/null); dom=${dom:-tech-debt}
    sev=$(awk -F'\t' -v n="$name" '$1==n {print $3}' "$labels" 2>/dev/null); sev=${sev:-medium}
    printf 'BASE-%s\t%s\tbaseline\tguard\tSoleur guard: %s\t%s\tany\t%s\t%s\tpresent\tsoleur:verification-scaffold --guards %s\tInstall this guard, advisory first, with the soleur:verification-scaffold skill.\n' \
      "$name" "$dom" "$name" "$sev" "$emits" "${src:--}" "$name"
  done <<<"$rows"
}

# lc_build_catalog <outfile>: checks.tsv rows followed by the derived baseline rows.
lc_build_catalog() {
  local base rc=0 bad
  # The catalog is read by column POSITION downstream, so a malformed row must stop the run here: the header must
  # carry the expected column names and every row exactly 12 non-empty cells ("-" marks an empty cell).
  bad=$(awk -F'\t' '/^#/ { next } $1 == "id" { hdr = hdr + 1; if ($2 != "domain" || $4 != "kind" || $6 != "severity" || $12 != "remedy" || NF != 12) print "header"; next } $1 == "" { next }
    { if (NF != 12) { print "row " $1 ": " NF " cells"; next } for (i = 1; i <= NF; i++) if ($i == "") { print "row " $1 ": empty cell " i; break } }
    END { if (hdr != 1) print "header count " hdr + 0 }' "$SKILL_DIR/references/checks.tsv")
  [ -z "$bad" ] || lc_abort catalog-malformed 2 "$(printf '%s' "$bad" | head -n 1)"
  awk -F'\t' '!/^#/ && $1 != "id" && $1 != "" { print }' "$SKILL_DIR/references/checks.tsv" > "$1"
  base=$(lc_baseline_rows) || rc=$?
  if [ "$rc" -ne 0 ]; then printf '%s\n' "$base"; exit "$rc"; fi
  printf '%s\n' "$base" >> "$1"
}
