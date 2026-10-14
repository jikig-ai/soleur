#!/usr/bin/env bash
# OUT OF SCOPE: `${!arr[@]}` is associative-array KEY expansion, not `${!name}`
# indirect expansion. It yields index names, never a credential value, and it is
# the only way bash can iterate an associative array — so treating it as a secret
# signal put every such script in scope. Synthesized, not copied (#7935).
set -uo pipefail

declare -A rows=()
rows["engineering/alpha.md"]="Alpha"
rows["project/beta.md"]="Beta"

for rel in "${!rows[@]}"; do
  printf '%s -> %s\n' "$rel" "${rows[$rel]}"
done

for rel in "${!rows[*]}"; do
  printf 'star-form: %s\n' "$rel"
done
