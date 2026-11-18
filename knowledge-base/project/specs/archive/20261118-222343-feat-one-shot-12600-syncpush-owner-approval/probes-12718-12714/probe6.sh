#!/usr/bin/env bash
# Probe 6 (#12714 held count): commit count vs tree diff, before and after the held commit is squash-merged upstream.
set -u
R=/tmp/claude-1000/kbpull-probe/p6; rm -rf "$R"; mkdir -p "$R"; cd "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
git init -q --bare -b main o.git; git init -q -b main seed; mkdir -p seed/knowledge-base seed/src
echo a > seed/knowledge-base/a.md; echo x > seed/src/x.ts; git -C seed add -A; git -C seed "${ID[@]}" commit -qm c0; git -C seed push -q "file://$R/o.git" main
git clone -q --depth 1 "file://$R/o.git" ws; cd ws
echo f1 >> src/x.ts; git "${ID[@]}" commit -qam F1; echo k1 > knowledge-base/k.md; git add -A; git "${ID[@]}" commit -qm K1
count() { local T; T=$(git rev-parse origin/main)
  echo "  $1: rev-list --no-merges non-KB=$(git rev-list --count --no-merges "$T"..HEAD -- . ':(exclude)knowledge-base/') diff non-KB files=$(git diff --name-only "$T" HEAD -- . ':(exclude)knowledge-base/' | wc -l)"; }
count "held F1 (+ K1)"
# upstream squash-merges F1's change (same tree change, new commit), then the session-start pull merges it
cd ../seed; echo f1 >> src/x.ts; git "${ID[@]}" commit -qam "Squash F1 (#1)"; git push -q "file://$R/o.git" main; cd ../ws
git fetch -q origin; git "${ID[@]}" merge -q --no-edit origin/main 2>&1 | tail -1
count "after squash-merge + pull"
cd ../seed; echo u2 > src/u.ts; git add -A; git "${ID[@]}" commit -qm U2; git push -q "file://$R/o.git" main; cd ../ws
git fetch -q origin; git "${ID[@]}" merge -q --no-edit origin/main 2>&1 | tail -1
count "after an unrelated upstream change + pull"
