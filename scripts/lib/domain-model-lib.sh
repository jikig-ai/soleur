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

# Fail-closed secret-shape regex (ported from scripts/extract-api-spend.sh:83).
# Matches PREFIXED secret shapes — the dominant leak vector for anything embedded
# in a migration literal or function body.
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
      BEGIN { indq = 0; stmt = "" }
      {
        line = $0
        # blind-spot: dynamic policy composition — never statically analyzable
        if (line ~ /EXECUTE[ \t]+format\(/ || line ~ /DO[ \t]+\$\$/) {
          emit("blind", "", "", "dynamic SQL (DO $$ / EXECUTE format) — not statically analyzed")
        }
        # toggle dollar-quote state on each $$ occurrence in the line
        tmp = line
        while (match(tmp, /\$\$/)) { indq = !indq; tmp = substr(tmp, RSTART + 2) }
        stmt = stmt " " line
        if (indq == 0 && line ~ /;/) { process(stmt); stmt = "" }
      }
      END { if (stmt ~ /[^ ]/) process(stmt) }
      function process(s,   t, o, pred) {
        if (s ~ /ALTER[ \t]+POLICY/) {
          emit("blind", "", "", "ALTER POLICY (partial-modify not merged) — not statically analyzed")
          return
        }
        if (match(s, /CREATE[ \t]+POLICY[ \t]+"?[A-Za-z0-9_]+"?[ \t]+ON[ \t]+"?[A-Za-z0-9_.]+"?/)) {
          o = s; sub(/.*CREATE[ \t]+POLICY[ \t]+"?/, "", o); sub(/"?[ \t]+ON.*/, "", o)
          t = s; sub(/.*ON[ \t]+"?/, "", t); sub(/"?[ \t\(].*/, "", t)
          pred = s; sub(/.*(USING|WITH[ \t]+CHECK)[ \t]*\(/, "", pred); sub(/;[ \t]*$/, "", pred)
          emit("policy_create", t, o, pred)
          return
        }
        if (match(s, /DROP[ \t]+POLICY[ \t]+"?[A-Za-z0-9_]+"?[ \t]+ON[ \t]+"?[A-Za-z0-9_.]+"?/)) {
          o = s; sub(/.*DROP[ \t]+POLICY[ \t]+(IF[ \t]+EXISTS[ \t]+)?"?/, "", o); sub(/"?[ \t]+ON.*/, "", o)
          t = s; sub(/.*ON[ \t]+"?/, "", t); sub(/"?[ \t;].*/, "", t)
          emit("policy_drop", t, o, "")
          return
        }
        if (s ~ /CREATE[ \t]+(OR[ \t]+REPLACE[ \t]+)?FUNCTION/ && s ~ /SECURITY[ \t]+DEFINER/) {
          o = s; sub(/.*FUNCTION[ \t]+"?/, "", o); sub(/"?[ \t\(].*/, "", o)
          emit("guard", "", o, "SECURITY DEFINER function")
          return
        }
        if (match(s, /CREATE[ \t]+TABLE[ \t]+"?[A-Za-z0-9_.]+"?/)) {
          t = s; sub(/.*CREATE[ \t]+TABLE[ \t]+(IF[ \t]+NOT[ \t]+EXISTS[ \t]+)?"?/, "", t); sub(/"?[ \t\(].*/, "", t)
          if (s ~ /PRIMARY[ \t]+KEY/) { pred = s; sub(/.*PRIMARY[ \t]+KEY[ \t]*\(/, "", pred); sub(/\).*/, "", pred); emit("constraint", t, t "_pkey", "PRIMARY KEY (" pred ")") }
          if (s ~ /CHECK[ \t]*\(/)   { pred = s; sub(/.*CHECK[ \t]*\(/, "", pred); sub(/\).*/, "", pred); emit("constraint", t, t "_check", "CHECK (" pred ")") }
          if (s ~ /UNIQUE[ \t]*\(/)  { pred = s; sub(/.*UNIQUE[ \t]*\(/, "", pred); sub(/\).*/, "", pred); emit("constraint", t, t "_unique", "UNIQUE (" pred ")") }
          return
        }
        if (match(s, /ALTER[ \t]+TABLE[ \t]+"?[A-Za-z0-9_.]+"?[ \t]+ADD[ \t]+CONSTRAINT[ \t]+"?[A-Za-z0-9_]+"?/)) {
          t = s; sub(/.*ALTER[ \t]+TABLE[ \t]+(ONLY[ \t]+)?"?/, "", t); sub(/"?[ \t].*/, "", t)
          o = s; sub(/.*ADD[ \t]+CONSTRAINT[ \t]+"?/, "", o); sub(/"?[ \t].*/, "", o)
          emit("constraint", t, o, "constraint")
        }
      }
    ' "$f"
  done
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
