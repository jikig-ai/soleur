#!/usr/bin/env bash
# Probe 7 (task 9.1): `merge --no-overwrite-ignore` refusal and `merge-tree --write-tree` exit codes.
set -u
R=/tmp/claude-1000/kbpull-probe/p7; rm -rf "$R"; mkdir -p "$R"; cd "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
echo "git: $(git --version)"
git init -q --bare -b main o.git; git init -q -b main seed; mkdir -p seed/knowledge-base
echo a > seed/knowledge-base/a.md; echo 'build/' > seed/.gitignore; git -C seed add -A; git -C seed "${ID[@]}" commit -qm c0
git -C seed push -q "file://$R/o.git" main; git clone -q --depth 1 "file://$R/o.git" ws
mkdir -p ws/build; echo local-ignored > ws/build/out.txt
mkdir -p seed/build; echo upstream > seed/build/out.txt; git -C seed add -f build/out.txt; git -C seed "${ID[@]}" commit -qm c1
git -C seed push -q "file://$R/o.git" main; git -C ws fetch -q origin
T=$(git -C ws rev-parse origin/main)
out=$(git -C ws "${ID[@]}" merge --no-edit --autostash --no-overwrite-ignore "$T" 2>&1); rc=$?
echo "no-overwrite-ignore: rc=$rc MERGE_HEAD=$([ -e ws/.git/MERGE_HEAD ] && echo yes || echo no) file=$(cat ws/build/out.txt) msg=$(echo "$out" | head -1 | cut -c1-90)"
# merge-tree --write-tree: clean (0), conflict (1), unrelated (?)
git init -q -b main m; cd m
echo base > f; git add f; git "${ID[@]}" commit -qm b; B=$(git rev-parse HEAD)
git checkout -q -b x; echo x > f; git "${ID[@]}" commit -qam x; X=$(git rev-parse HEAD)
git checkout -q main; echo y > f; git "${ID[@]}" commit -qam y; Y=$(git rev-parse HEAD)
git checkout -q -b z "$B"; echo z > g; git add g; git "${ID[@]}" commit -qm z; Z=$(git rev-parse HEAD)
git checkout -q --orphan u; git rm -rfq .; echo u > u; git add u; git "${ID[@]}" commit -qm u; U=$(git rev-parse HEAD)
git merge-tree --write-tree "$Y" "$Z" >/dev/null 2>&1; echo "merge-tree clean: rc=$?"
git merge-tree --write-tree "$Y" "$X" >/dev/null 2>&1; echo "merge-tree conflict: rc=$?"
git merge-tree --write-tree "$Y" "$U" >/dev/null 2>&1; echo "merge-tree unrelated: rc=$?"
git merge-tree --write-tree "$Y" 0000000000000000000000000000000000000001 >/dev/null 2>&1; echo "merge-tree missing object: rc=$?"
git -C . merge-base "$Y" "$U" >/dev/null 2>&1; echo "merge-base unrelated: rc=$?"
