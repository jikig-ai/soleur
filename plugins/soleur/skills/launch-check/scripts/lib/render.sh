# shellcheck shell=bash
# Report rendering and the living-file diff. Contract: TARGET, WORK, FACTS, JUDGED (may be empty), DRY, CAT
# (combined catalog), REPORT_REL, STACK are set by the caller. All prose comes from references/ and the catalog;
# this file only lays out structure. Markdown is built in $WORK/report.md and written ONLY via lc_emit_checked.
#
# Trust model: render never takes the facts file, the judged file or the previous report on trust. Facts are
# validated against the catalog and sanitized (lc_clean_facts), the judged file against a closed schema
# (lc_validate_judged), the previous report against the state-line grammar (lc_prev_state). A finding is only
# ever CLOSED on positive evidence that its check ran and came back clean.

lc_phrase() { awk -F= -v k="$1" '$1==k {sub(/^[^=]*=/, ""); print; exit}' "$SKILL_DIR/references/phrases.txt"; }

# Secret-class findings are counts only: their evidence must match a fixed phrase, never a path.
LC_COUNT_ONLY_IDS="SEC-01 SEC-02"

lc_domain_label() {
  case "$1" in
    security) printf 'Security & secrets' ;;
    tests-ci) printf 'Tests & CI/CD' ;;
    tech-debt) printf 'Tech debt & architecture' ;;
    reliability-ops) printf 'Reliability, performance & ops' ;;
    *) printf '%s' "$1" ;;
  esac
}

# lc_clean_facts: validate $FACTS against the catalog and write a sanitized copy ($WORK/facts.clean), then point FACTS at it.
# Every non-judged catalog id must have exactly one row with a known status; evidence outside the path/count grammar
# is withheld (only the fixed phrases the detectors emit, a bare path, or path:line pass), and count-only ids keep only their fixed phrases.
lc_clean_facts() {
  local out
  out=$(awk -F'\t' -v OFS='\t' -v cat="$CAT" -v facts="$FACTS" -v counted="$LC_COUNT_ONLY_IDS" -v cleaned="$WORK/facts.clean" '
    BEGIN { n = split(counted, c, " "); for (i = 1; i <= n; i++) co[c[i]] = 1 }
    FILENAME == cat { if ($1 != "" && $4 != "judged") need[$1] = 1; next }
    /^#/ || /^$/ { print $0 > cleaned; next }
    { if (NF != 3) { print "line " FNR ": field-count"; bad = 1; exit }
      if (!($1 in need)) { print "line " FNR ": unknown-id " $1; bad = 1; exit }
      if ($1 in seen) { print "line " FNR ": duplicate-id " $1; bad = 1; exit }
      seen[$1] = 1
      if ($2 != "ok" && $2 != "gap" && $2 != "na" && $2 != "unsupported-stack") { print "line " FNR ": status"; bad = 1; exit }
      ev = $3
      if ($1 in co) { if (ev !~ /^(none found|no commits yet|stack is [a-z]+|-|[0-9]+ (finding\(s\)|file\(s\)); (locations|names) withheld, run scan --show-secrets locally to see them)$/) ev = "(evidence withheld)" }
      else if (length(ev) > 200 || ev !~ /^(-|none found|not identified in the files read|no source files recognized|no package\.json|not a Next\.js project|dependency-cruiser configured|no commits yet|stack is [a-z]+|(artifact|original form) present, advisory\/unverified|missing: [A-Za-z0-9._\/@+, -]+|[0-9]+ test files \/ [0-9]+ source files( \(under 5%\))?|[0-9]+ markers|[A-Za-z0-9._\/@+-]+(:[0-9]+)?)$/) ev = "(evidence withheld)"
      print $1, $2, ev > cleaned }
    END { if (bad) exit 1; miss = ""; for (id in need) if (!(id in seen)) miss = miss (miss == "" ? "" : ",") id
          if (miss != "") { print "missing: " miss; exit 2 } }' "$CAT" "$FACTS") || {
    case "$out" in missing:*) lc_abort facts-incomplete 2 "$out (re-run scan)" ;; *) lc_abort facts-invalid 2 "$out" ;; esac
  }
  FACTS="$WORK/facts.clean"
}

# lc_validate_judged <judged-file>: closed schema. id<TAB>status<TAB>severity<TAB>evidence-ids, nothing else.
lc_validate_judged() {
  local out
  out=$(awk -F'\t' -v cat="$CAT" -v facts="$FACTS" '
    FILENAME == cat   { if ($4 == "judged") j[$1] = 1; next }
    FILENAME == facts { f[$1] = 1; next }
    /^#/ || /^$/ { next }
    { bad = ""
      if (NF != 4) bad = "field-count"
      else if (!($1 in j)) bad = "unknown-or-non-judged-id"
      else if ($1 in seen) bad = "duplicate-id"
      else if ($2 != "ok" && $2 != "gap" && $2 != "na") bad = "status"
      else if ($2 == "gap" && $3 != "high" && $3 != "medium" && $3 != "low") bad = "severity"
      else if ($2 != "gap" && $3 != "-") bad = "severity-must-be-dash-unless-gap"
      else if ($2 == "gap" && $4 == "-") bad = "evidence-required"
      else if ($4 != "-") { k = split($4, ev, ","); for (i = 1; i <= k; i++) if (!(ev[i] in f)) bad = "evidence-id" }
      seen[$1] = 1
      if (bad != "") { print "line " FNR ": " bad; exit 1 } }' "$CAT" "$FACTS" "$1") || lc_abort judged-schema 2 "$out"
}

# lc_prev_state <report-file> <outfile>: "id<TAB>status<TAB>rest" lines from the fenced state block. CRLF-tolerant;
# duplicate ids resolve last-wins; lines outside the grammar are written to <outfile>.bad instead of being guessed at.
# A report that exists but carries no state block is refused: overwriting it would silently drop every acceptance.
lc_prev_state() {
  local rc=0
  : > "$2"; : > "$2.bad"
  [ -f "$1" ] || return 0
  tr -d '\r' < "$1" | awk -v bad="$2.bad" '
    /^```launch-check-state$/ { f = 1; seen = 1; next }
    /^```$/ && f { f = 0; next }
    f && /^finding / {
      if ($2 ~ /^[A-Z]+-[A-Za-z0-9-]+$/ && ($3 == "open" || $3 == "accepted")) {
        rest = ""; for (i = 4; i <= NF; i++) rest = rest (i > 4 ? " " : "") $i
        if (!($2 in idx)) { idx[$2] = ++n; order[n] = $2 }
        st[$2] = $3; rs[$2] = rest
      } else print substr($0, 1, 120) > bad
      next }
    f && $0 != "" && $0 !~ /^(schema_version|catalog_hash)=/ { print substr($0, 1, 120) > bad }
    END { if (!seen) exit 3; for (i = 1; i <= n; i++) printf "%s\t%s\t%s\n", order[i], st[order[i]], rs[order[i]] }' > "$2" || rc=$?
  [ "$rc" -eq 0 ] || lc_abort prev-report-invalid 2 "no state block in $REPORT_REL (restore it from git, or delete the file to start fresh)"
}

lc_render() {
  local rep="$WORK/report.md" prev="$WORK/prev.tsv" gaps="$WORK/gaps.tsv" judged_in="$WORK/judged.in"
  local has_prev=0 has_judged=0 prev_hash prev_schema cat_hash today catalog_changed=0
  [ -n "${JUDGED:-}" ] && has_judged=1
  if [ "$has_judged" = 1 ]; then cp "$JUDGED" "$judged_in"; else : > "$judged_in"; fi
  lc_prev_state "$TARGET/$REPORT_REL" "$prev"
  [ -f "$TARGET/$REPORT_REL" ] && has_prev=1
  cat_hash=$(git hash-object --stdin < "$CAT")
  today=$(date -u +%F)

  # Open gaps (deterministic facts + judged), sorted critical -> low then id.
  awk -F'\t' -v OFS='\t' -v cat="$CAT" -v facts="$FACTS" -v judged="$judged_in" '
    function rank(s) { return s == "critical" ? 1 : s == "high" ? 2 : s == "medium" ? 3 : 4 }
    FILENAME == cat   { if ($1 != "") { dom[$1]=$2; cls[$1]=$3; title[$1]=$5; sev[$1]=$6; clos[$1]=$11; rem[$1]=$12; known[$1]=1 } next }
    FILENAME == facts { if ($2 == "gap" && ($1 in known)) print rank(sev[$1]), $1, dom[$1], cls[$1], sev[$1], title[$1], $3, clos[$1], rem[$1]; next }
    FILENAME == judged { if ($0 !~ /^#/ && $2 == "gap" && ($1 in known)) print rank($3), $1, dom[$1], cls[$1], $3, title[$1], "relies on " $4, clos[$1], rem[$1] }
  ' "$CAT" "$FACTS" "$judged_in" | sort -t "$(printf '\t')" -k1,1n -k2,2 > "$gaps"

  # Partition by the previous state: accepted stays out of the open table.
  awk -F'\t' '$2 == "accepted" {print $1}' "$prev" | sort > "$WORK/prev.accepted.ids"
  cut -f2 "$gaps" | sort > "$WORK/cur.ids"
  comm -23 "$WORK/cur.ids" "$WORK/prev.accepted.ids" > "$WORK/open.ids"
  comm -12 "$WORK/cur.ids" "$WORK/prev.accepted.ids" > "$WORK/accepted.ids"
  cut -f1 "$prev" | sort > "$WORK/prev.ids"
  cut -f1 "$CAT" | sort > "$WORK/cat.ids"
  if [ "$has_prev" = 1 ]; then comm -23 "$WORK/open.ids" "$WORK/prev.ids" > "$WORK/new.ids"; else : > "$WORK/new.ids"; fi
  # Positive evidence that a check ran clean: a deterministic fact with status ok, or a judged line saying ok/na.
  awk -F'\t' '$2 == "ok" {print $1}' "$FACTS" | sort -u > "$WORK/ok.ids"
  awk -F'\t' '!/^#/ && ($2 == "ok" || $2 == "na") {print $1}' "$judged_in" | sort -u > "$WORK/judged.settled.ids"
  # Closed: previously reported, still in the catalog, no longer a gap AND positively settled. Anything else (a check
  # that was not applicable, an unsupported stack, an AI-assisted item not reviewed this run) is carried, not closed.
  : > "$WORK/closed.ids"; : > "$WORK/retired.ids"; : > "$WORK/carry.lines"
  while IFS=$'\t' read -r pid pst prest; do
    [ -n "$pid" ] || continue
    if ! grep -qxF "$pid" "$WORK/cat.ids"; then printf '%s\n' "$pid" >> "$WORK/retired.ids"; continue; fi
    if grep -qxF "$pid" "$WORK/cur.ids"; then continue; fi
    case "$pid" in
      JDG-*) grep -qxF "$pid" "$WORK/judged.settled.ids" && { printf '%s\n' "$pid" >> "$WORK/closed.ids"; continue; } ;;
      *) grep -qxF "$pid" "$WORK/ok.ids" && { printf '%s\n' "$pid" >> "$WORK/closed.ids"; continue; } ;;
    esac
    printf 'finding %s %s%s\n' "$pid" "$pst" "${prest:+ $prest}" >> "$WORK/carry.lines"
  done < "$prev"

  # Not assessed: checks that did not produce a verdict this run, and AI-assisted items nobody reviewed.
  awk -F'\t' '!/^#/ && ($2 == "na" || $2 == "unsupported-stack") { print $1 "\t" $2 ": " $3 }' "$FACTS" | sort > "$WORK/notassessed.tsv"
  awk -F'\t' '$4 == "judged" {print $1}' "$CAT" | sort > "$WORK/jdg.ids"
  awk -F'\t' '!/^#/ {print $1}' "$judged_in" | sort -u > "$WORK/jdg.seen.ids"
  comm -23 "$WORK/jdg.ids" "$WORK/jdg.seen.ids" | while IFS= read -r id; do printf '%s\t%s\n' "$id" "$(lc_phrase jdg_unreviewed)"; done >> "$WORK/notassessed.tsv"

  prev_hash=$(awk -F= '/^catalog_hash=/ {print $2; exit}' "$TARGET/$REPORT_REL" 2>/dev/null | tr -d '\r')
  prev_schema=$(awk -F= '/^schema_version=/ {print $2; exit}' "$TARGET/$REPORT_REL" 2>/dev/null | tr -d '\r')
  if [ "$has_prev" = 1 ] && { [ "$prev_hash" != "$cat_hash" ] || [ "${prev_schema:-1}" != 1 ]; }; then
    catalog_changed=1
    printf 'SOLEUR_LAUNCH_CHECK_CATALOG_CHANGED retired=%s\n' "$(grep -c . "$WORK/retired.ids")"
  fi

  {
    printf -- '---\nlaunch_check_schema: 1\nrun_date: %s\nstack: %s\n---\n\n' "$today" "$STACK"
    printf '# Launch check report\n\n'
    cat "$SKILL_DIR/references/banner.txt"
    printf '\n'
    [ "$STACK" = node ] || printf '%s\n\n' "$(lc_phrase partial_stack)"
    [ "$catalog_changed" = 1 ] && printf '%s\n\n' "$(lc_phrase catalog_changed)"

    printf '## Summary\n\n| Domain | Critical | High | Medium | Low |\n|---|---|---|---|---|\n'
    local d c
    for d in security tests-ci tech-debt reliability-ops; do
      c=$(awk -F'\t' -v d="$d" -v open="$WORK/open.ids" 'BEGIN { while ((getline l < open) > 0) o[l] = 1 } $3 == d && ($2 in o) { n[$5]++ } END { printf "%d | %d | %d | %d", n["critical"], n["high"], n["medium"], n["low"] }' "$gaps")
      printf '| %s | %s |\n' "$(lc_domain_label "$d")" "$c"
    done
    printf '\n## Findings\n\n'
    if [ -s "$WORK/open.ids" ]; then
      printf '| ID | Severity | Domain | Finding | Evidence | Fix |\n|---|---|---|---|---|---|\n'
      # shellcheck disable=SC2034
      while IFS=$'\t' read -r _ id dom cls sev title ev clos rem; do
        grep -qxF "$id" "$WORK/open.ids" || continue
        ev=${ev//|/\\|}
        fix=$rem; [ "$clos" != "-" ] && fix="$rem Command: \`$clos\`"
        printf '| %s | %s | %s | %s | %s | %s |\n' "$id" "$sev" "$(lc_domain_label "$dom")" "$title" "$ev" "$fix"
      done < "$gaps"
    elif [ -s "$WORK/accepted.ids" ]; then
      printf '%s\n' "$(lc_phrase only_accepted)"
    else
      printf '%s\n' "$(lc_phrase no_open)"
    fi
    [ -s "$WORK/carry.lines" ] && printf '\n%s\n' "$(lc_phrase not_refreshed)"
    printf '\n## Not assessed in this run\n\n'
    if [ -s "$WORK/notassessed.tsv" ]; then
      printf '%s\n\n' "$(lc_phrase not_assessed_intro)"
      while IFS=$'\t' read -r id why; do printf -- '- %s: %s\n' "$id" "$why"; done < "$WORK/notassessed.tsv"
    else printf '%s\n' "$(lc_phrase none)"; fi
    printf '\n## Not installable yet\n\n'
    local v2; v2=$(lc_guard_rows '^v2$' | cut -f1 | tr '\n' ' ')
    if [ -n "${v2// /}" ]; then printf '%s %s\n' "$(lc_phrase v2_intro)" "$v2"; else printf '%s\n' "$(lc_phrase none)"; fi

    printf '\n## New since last run\n\n'
    if [ "$has_prev" = 0 ]; then printf '%s\n' "$(lc_phrase first_run)"; elif [ -s "$WORK/new.ids" ]; then sed 's/^/- /' "$WORK/new.ids"; else printf '%s\n' "$(lc_phrase none)"; fi
    printf '\n## Closed since last run\n\n'
    if [ "$has_prev" = 0 ]; then printf '%s\n' "$(lc_phrase first_run)"; elif [ -s "$WORK/closed.ids" ]; then sed 's/^/- /' "$WORK/closed.ids"; else printf '%s\n' "$(lc_phrase none)"; fi
    printf '\n## Accepted\n\n'
    if [ -s "$WORK/accepted.ids" ]; then
      while IFS= read -r id; do printf -- '- %s: %s\n' "$id" "$(awk -F'\t' -v id="$id" '$1==id {print $3; exit}' "$prev")"; done < "$WORK/accepted.ids"
    else printf '%s\n' "$(lc_phrase none)"; fi
    printf '\n## Retired checks\n\n'
    if [ -s "$WORK/retired.ids" ]; then
      while IFS= read -r id; do
        printf -- '- %s: %s%s\n' "$id" "$(awk -F'\t' -v id="$id" '$1==id {print $3; exit}' "$SKILL_DIR/references/retired-checks.tsv" 2>/dev/null | grep . || printf '%s' "$(lc_phrase retired_default)")" \
          "$(awk -F'\t' -v id="$id" '$1==id && $2=="accepted" {print " (was accepted: " $3 ")"; exit}' "$prev")"
      done < "$WORK/retired.ids"
    else printf '%s\n' "$(lc_phrase none)"; fi
    if [ -s "$prev.bad" ]; then
      printf '\n## Unrecognised state lines (ignored)\n\n%s\n\n' "$(lc_phrase unrecognised_intro)"
      while IFS= read -r l; do printf -- '- `%s`\n' "$(lc_scrub "${l//\`/}")"; done < "$prev.bad"
    fi

    printf '\n---\n\n'
    cat "$SKILL_DIR/references/footer.txt"
    printf '\n\n```launch-check-state\nschema_version=1\ncatalog_hash=%s\n' "$cat_hash"
    while IFS= read -r id; do printf 'finding %s open\n' "$id"; done < "$WORK/open.ids"
    while IFS= read -r id; do printf 'finding %s accepted%s\n' "$id" "$(awk -F'\t' -v id="$id" '$1==id && $3!="" {print " " $3; exit}' "$prev")"; done < "$WORK/accepted.ids"
    [ -s "$WORK/carry.lines" ] && cat "$WORK/carry.lines"
    printf '```\n'
  } > "$rep" || lc_abort render-failed 2 "report assembly"
  # shellcheck disable=SC2034  # read by cmd_render
  LC_OPEN_COUNT=$(grep -c . "$WORK/open.ids")
}
