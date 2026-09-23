#!/usr/bin/env bash
# Follow-through probe: deferred scope-out from the PR #8644 review (test-helpers sandbox leak).
#
# Credential posture: none. Reads only tracked files in the sweeper's checkout; no network.
#
# Close criterion (exit 0): no plugins/soleur/test/*.test.sh installs an EXIT trap AFTER
# sourcing test-helpers.sh without also calling _soleur_sb_cleanup. Such a trap replaces the
# helper's composed EXIT trap, so a direct run (INCIDENTS_REPO_ROOT unset) leaks a
# soleur-inc-* sandbox dir.
#   0 = PASS  (class gone; the sweeper closes the tracker)
#   1 = FAIL  (offending suites listed on stdout; the tracker stays open)
#   3 = CANNOT ESTABLISH (the probe could not measure; says why)
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace (see #7797)\n' >&2; exit 78 ;;
esac

# soleur:followthrough-stub v1

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)" || exit 3
dir="$root/plugins/soleur/test"
if [[ ! -f "$dir/test-helpers.sh" ]]; then
  echo "CANNOT ESTABLISH: $dir/test-helpers.sh is missing" >&2
  exit 3
fi

sourcing=0
offenders=()
for f in "$dir"/*.test.sh; do
  [[ -f "$f" ]] || continue
  verdict="$(awk '
    src == 0 && /^[[:space:]]*(source|\.)[[:space:]].*test-helpers\.sh/ { src = NR }
    src && NR > src && /^[[:space:]]*trap .*EXIT/ { late = 1 }
    /_soleur_sb_cleanup/ { ok = 1 }
    END { print (src ? 1 : 0), ((late && !ok) ? 1 : 0) }
  ' "$f")" || { echo "CANNOT ESTABLISH: awk failed on $f" >&2; exit 3; }
  read -r sources leaks <<<"$verdict"
  (( sources == 1 )) && sourcing=$((sourcing + 1))
  (( leaks == 1 )) && offenders+=("${f#"$root"/}")
done

# Anti-vacuity: a walk that found almost no helper consumers measured nothing.
if (( sourcing < 20 )); then
  echo "CANNOT ESTABLISH: only $sourcing suites source test-helpers.sh (expected >= 20)" >&2
  exit 3
fi

if (( ${#offenders[@]} == 0 )); then
  echo "PASS: none of $sourcing test-helpers consumers installs an after-source EXIT trap without _soleur_sb_cleanup"
  exit 0
fi
echo "FAIL: ${#offenders[@]} of $sourcing test-helpers consumers still replace the composed EXIT trap:"
printf '  %s\n' "${offenders[@]}"
exit 1
