#!/usr/bin/env bash
# domain-model-lib.sh — reusable tokenizer for the domain-model drift analyzer (#5754).
#
# Sourced by scripts/domain-model-drift.sh. Factored out so the enforcement gates
# tracked in #5871 can reuse the extraction without re-parsing. Pure functions:
# they read files and emit to stdout; they never write, never eval migration
# content, and treat all SQL as DATA (grep -F / awk -v only).
#
# DETERMINISM: every sort in this lib uses `LC_ALL=C sort`; callers must also
# pin LC_ALL=C so the assembled output is byte-identical across locales/runners.

# Fail-closed secret-shape regex. Prefixed shapes derived from scripts/extract-api-spend.sh:83,
# with the `org_` alternative DELIBERATELY OMITTED: extract-api-spend scans a cost-record JSON,
# but this scans migration-derived structural text where `org_` substring-matches legitimate
# column names (`org_id`, `org_slug`) → a false-refuse that would break extraction on any repo
# using that naming. The Doppler `org_`-token leak vector is not plausible in structural-fact text.
DM_SECRET_RE='sk-ant|sk_(live|test)|ghp_|ghs_|github_pat_|AKIA[0-9A-Z]{16}|xoxb-|sbp_|-----BEGIN'

# dm_secret_scan <text> — exit 0 if a secret-shaped substring is present (i.e. UNSAFE).
dm_secret_scan() {
  printf '%s' "${1:-}" | grep -qiE "$DM_SECRET_RE"
}

# dm_find_migrations_dir <repo-root> — print the supabase/migrations dir, or nothing.
# Prefers the conventional web-platform path (AP-010), else the first match anywhere.
dm_find_migrations_dir() {
  local repo="$1" conv
  conv="$repo/apps/web-platform/supabase/migrations"
  if [[ -d "$conv" ]]; then printf '%s' "$conv"; return 0; fi
  find "$repo" -type d -path '*/supabase/migrations' -not -path '*/node_modules/*' 2>/dev/null \
    | LC_ALL=C sort | head -1
}

# dm_base_migrations <migrations-dir> — list base migration files in apply order.
# Excludes *.down.sql rollbacks (they corrupt last-writer-wins replay — data-integrity P0).
# LC_ALL=C sort == apply order for zero-padded numeric prefixes.
dm_base_migrations() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f -name '*.sql' -not -name '*.down.sql' 2>/dev/null \
    | LC_ALL=C sort
}

# dm_tokenize <base-migration-file>... — emit newline-delimited events (TSV):
#   EVENT<TAB>kind<TAB>file<TAB>table<TAB>object<TAB>detail
# kinds: policy_create | policy_drop | policy_alter | constraint | guard | blind
# Dollar-quote aware (`$$` / `$tag$`): statement splitting on `;` is suspended
# inside a dollar-quoted body so DO-blocks and function bodies do not mis-split.
dm_tokenize() {
  local f
  for f in "$@"; do
    local base; base="$(basename "$f")"
    awk -v FILE="$base" '
      function emit(kind, table, object, detail) {
        gsub(/[\t\r\n]+/, " ", detail); gsub(/  +/, " ", detail)
        gsub(/^ +| +$/, "", detail)
        printf "EVENT\t%s\t%s\t%s\t%s\t%s\n", kind, FILE, table, object, detail
      }
      # extract a policy/table/function NAME token: quoted ("Any words") or bare
      # (schema-qualified). Returns the unquoted inner text, or "" if unparseable.
      # The Postgres default schema `public.` is stripped from the bare form so anchors
      # are `<table>.<object>` per ADR-076 item 3 (#5871); non-default schemas the
      # register cites verbatim (storage., auth.) are preserved.
      function name_after(s, kw,   m, tok) {
        # kw is a regex fragment like "CREATE[ \t]+POLICY" or "ON"
        if (match(s, kw "[ \t]+\"[^\"]+\"")) { tok = substr(s, RSTART, RLENGTH); sub(kw "[ \t]+\"", "", tok); sub(/\"$/, "", tok); return tok }
        if (match(s, kw "[ \t]+[A-Za-z0-9_.]+"))  { tok = substr(s, RSTART, RLENGTH); sub(kw "[ \t]+", "", tok); sub(/^public\./, "", tok); return tok }
        return ""
      }
      BEGIN { indq = 0; dqtag = ""; stmt = "" }
      {
        line = $0
        # blind-spot: dynamic policy composition — never statically analyzable.
        # `DO[ \t]+\$` catches DO $$ AND DO $tag$ blocks.
        if (line ~ /EXECUTE[ \t]+format\(/ || line ~ /DO[ \t]+\$/) {
          emit("blind", "", "", "dynamic SQL (DO $...$ / EXECUTE format) — not statically analyzed")
        }
        # dollar-quote state: match arbitrary $tag$ delimiters (must pair by tag,
        # so a $$-body and a $function$-body nest correctly and neither mis-splits).
        tmp = line
        while (match(tmp, /\$[A-Za-z0-9_]*\$/)) {
          tag = substr(tmp, RSTART, RLENGTH)
          if (indq == 0) { indq = 1; dqtag = tag }
          else if (tag == dqtag) { indq = 0; dqtag = "" }
          tmp = substr(tmp, RSTART + RLENGTH)
        }
        stmt = stmt " " line
        if (indq == 0 && line ~ /;/) { process(stmt); stmt = "" }
      }
      END { if (stmt ~ /[^ ]/) process(stmt) }
      function process(s,   t, o, pred) {
        if (s ~ /ALTER[ \t]+POLICY/) {
          emit("blind", "", "", "ALTER POLICY (partial-modify not merged) — not statically analyzed")
          return
        }
        if (s ~ /CREATE[ \t]+POLICY/) {
          o = name_after(s, "CREATE[ \t]+POLICY"); t = name_after(s, "ON")
          # fail-safe: a CREATE POLICY the parser cannot fully resolve becomes a
          # blind_spot — never silently invisible (code-quality P1-a).
          if (o == "" || t == "") { emit("blind", "", "", "CREATE POLICY not statically parseable (quoted/complex name)"); return }
          pred = s; sub(/.*(USING|WITH[ \t]+CHECK)[ \t]*\(/, "", pred); sub(/;[ \t]*$/, "", pred)
          emit("policy_create", t, o, pred)
          return
        }
        if (s ~ /DROP[ \t]+POLICY/) {
          o = name_after(s, "DROP[ \t]+POLICY([ \t]+IF[ \t]+EXISTS)?"); t = name_after(s, "ON")
          if (o == "" || t == "") { emit("blind", "", "", "DROP POLICY not statically parseable"); return }
          emit("policy_drop", t, o, "")
          return
        }
        if (s ~ /SECURITY[ \t]+DEFINER/ && s ~ /CREATE[ \t]+(OR[ \t]+REPLACE[ \t]+)?FUNCTION/) {
          o = name_after(s, "FUNCTION"); sub(/\(.*/, "", o)
          # fail-safe: an unresolved SECURITY DEFINER name becomes a blind_spot
          # (code-quality P1-b — $tag$ bodies could previously hide it entirely).
          if (o == "") { emit("blind", "", "", "SECURITY DEFINER function name not statically parseable"); return }
          emit("guard", "", o, "SECURITY DEFINER function")
          return
        }
        if (match(s, /CREATE[ \t]+TABLE[ \t]+(IF[ \t]+NOT[ \t]+EXISTS[ \t]+)?"?[A-Za-z0-9_.]+"?/)) {
          t = name_after(s, "CREATE[ \t]+TABLE([ \t]+IF[ \t]+NOT[ \t]+EXISTS)?")
          if (t == "") return
          # table-level PRIMARY KEY (...) — column-level `id uuid PRIMARY KEY` has no
          # parens, so record the pkey object without a garbage predicate (P2-a).
          if (s ~ /PRIMARY[ \t]+KEY[ \t]*\(/) { pred = s; sub(/.*PRIMARY[ \t]+KEY[ \t]*\(/, "", pred); sub(/\).*/, "", pred); emit("constraint", t, t "_pkey", "PRIMARY KEY (" pred ")") }
          else if (s ~ /PRIMARY[ \t]+KEY/)    { emit("constraint", t, t "_pkey", "PRIMARY KEY (column-level)") }
          if (s ~ /CHECK[ \t]*\(/)  { pred = s; sub(/.*CHECK[ \t]*\(/, "", pred); sub(/\).*/, "", pred); emit("constraint", t, t "_check", "CHECK (" pred ")") }
          if (s ~ /UNIQUE/)         { emit("constraint", t, t "_unique", "UNIQUE constraint present") }
          return
        }
        if (match(s, /ALTER[ \t]+TABLE[ \t]+(ONLY[ \t]+)?"?[A-Za-z0-9_.]+"?[ \t]+ADD[ \t]+CONSTRAINT/)) {
          t = name_after(s, "ALTER[ \t]+TABLE([ \t]+ONLY)?"); o = name_after(s, "ADD[ \t]+CONSTRAINT")
          if (t != "" && o != "") emit("constraint", t, o, "constraint")
        }
      }
    ' "$f"
  done
}

# dm_register_code_citations <register-file> — emit code-citation pairs (TSV):
#   CITE<TAB>file<TAB>symbol
# Scans the WHOLE row (Statement + Source cells) of every `| ... |` table row —
# the canonical guard citation lives in a Statement cell, not the Source cell
# (data-integrity P1 / Kieran P0). Pairs each backticked `*.ts`/`*.sql` file token
# with every backticked bare-identifier token in the same row.
dm_register_code_citations() {
  local reg="$1"
  [[ -f "$reg" ]] || return 0
  grep -E '^\|' "$reg" 2>/dev/null | awk '
    {
      nfile = 0; nsym = 0
      line = $0
      # collect every backticked token on the row
      while (match(line, /`[^`]+`/)) {
        tok = substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
        if (tok ~ /\.(ts|tsx|sql)$/) { files[++nfile] = tok }
        else if (tok ~ /^[A-Za-z_][A-Za-z0-9_]*$/) { syms[++nsym] = tok }
      }
      for (i = 1; i <= nfile; i++)
        for (j = 1; j <= nsym; j++)
          print "CITE\t" files[i] "\t" syms[j]
      delete files; delete syms
    }
  ' | LC_ALL=C sort -u
}

# dm_guards_from_ts <repo-root> — emit guard events for named TS resolver/guard symbols.
# Scoped to the canonical resolver file; exact-token (word-boundary) matching so a
# cited `resolveActiveWorkspace` never substring-matches `resolveActiveWorkspaceKbRoot`.
dm_guards_from_ts() {
  local repo="$1" f
  f="$repo/apps/web-platform/server/workspace-resolver.ts"
  [[ -f "$f" ]] || return 0
  grep -nE '^[[:space:]]*export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+[A-Za-z0-9_]+' "$f" 2>/dev/null \
    | sed -E 's/.*function[[:space:]]+([A-Za-z0-9_]+).*/\1/' \
    | LC_ALL=C sort -u \
    | while IFS= read -r sym; do
        [[ -n "$sym" ]] && printf 'EVENT\tguard\t%s\t\t%s\t%s\n' "workspace-resolver.ts" "$sym" "TS resolver/guard"
      done
}
