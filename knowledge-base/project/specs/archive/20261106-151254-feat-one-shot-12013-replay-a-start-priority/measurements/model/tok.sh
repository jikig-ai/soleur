#!/usr/bin/env bash
cd /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12013-replay-a-start-priority
source scripts/lib/test-suite-lanes.sh
while IFS=$'\t' read -r tag label rest; do
  [[ "$tag" == SUITE_COMMAND ]] || continue
  IFS=$'\t' read -r -a argv <<<"$rest"
  t="$(lane_tokens_for "$label" "${argv[@]}" 2>/dev/null || printf '*')"
  printf '%s\t%s\n' "$label" "$t"
done < "$1"
