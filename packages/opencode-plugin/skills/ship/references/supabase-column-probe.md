# Post-merge Supabase column probe

Loaded from `soleur:ship` Phase 7 step 3.6 (post-merge migration verification) for each schema-addition migration.
Run the whole block as ONE Bash call; replace `<table>` and `<new_column>`. The key rides curl's stdin config, never argv.

```bash
SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
SUPABASE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
# argv shows in /proc/<pid>/cmdline: the key rides curl's stdin config. Bash only; `bash -x` would print the key.
(LC_ALL=C; case "$SUPABASE_KEY" in ''|*[!A-Za-z0-9._~+/=-]*) exit 1;; esac) || { echo "SUPABASE_KEY unset or not [A-Za-z0-9._~+/=-] (refused, not sent)" >&2; exit 1; }
curl --disable --proto '=https' -m 30 -sS --config - "$SUPABASE_URL/rest/v1/<table>?select=<new_column>&limit=1" \
  < <(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\n' "$SUPABASE_KEY" "$SUPABASE_KEY")
```
