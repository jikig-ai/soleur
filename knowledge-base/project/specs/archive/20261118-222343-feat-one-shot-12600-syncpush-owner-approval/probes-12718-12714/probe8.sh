#!/usr/bin/env bash
# Probe 8 (task 9.1 addendum, D26(3)): the isolated fetch from a store whose history would move the shallow roots of a
# shallow workspace. Measures the exit code and whether the destination ref is written (server/kb-sync-remote.ts maps an
# rc 0 with no ref, or a changed isolated `shallow` file, to `shallow_changed`).
set -u
R=/tmp/kbpull-probe/p8; rm -rf "$R"; mkdir -p "$R"; cd "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
echo "git: $(git --version)"
git init -q --bare -b main o.git; git init -q -b main seed; echo a > seed/a; git -C seed add -A; git -C seed "${ID[@]}" commit -qm c0
git -C seed push -q "file://$R/o.git" main
git clone -q --depth 1 "file://$R/o.git" ws; H=$(git -C ws rev-parse HEAD)
for i in 1 2 3; do echo $i >> seed/a; git -C seed "${ID[@]}" commit -qam "c$i"; done; git -C seed push -q "file://$R/o.git" main
# the remote store is itself a shallow push of a later, unrelated-depth history
git init -q --bare -b main s.git; git -C s.git config receive.shallowUpdate true
git clone -q --depth 1 "file://$R/o.git" sc; echo x >> sc/a; git -C sc "${ID[@]}" commit -qam X; git -C sc push -q "file://$R/s.git" main
I=$R/iso; mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads"; echo 'ref: refs/heads/main' > "$I/HEAD"
printf '[core]\n\tbare = true\n' > "$I/config"; cp ws/.git/shallow "$I/shallow"; S0=$(cat "$I/shallow")
ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$R/ws/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file)
"${ISO[@]}" git update-ref refs/heads/have-fetched-0 "$H"
ERR=$("${ISO[@]}" git -c core.alternateRefsCommand=true fetch --no-tags --no-recurse-submodules --no-write-fetch-head "file://$R/s.git" refs/heads/main:refs/heads/fetched 2>&1); RC=$?
"${ISO[@]}" git rev-parse --verify -q 'refs/heads/fetched^{commit}' >/dev/null; RP=$?
[ "$(cat "$I/shallow")" = "$S0" ] && SH=no || SH=yes
echo "shallow-store fetch: rc=$RC ref-written=$([ $RP = 0 ] && echo yes || echo no) isolated-shallow-changed=$SH"
echo "stderr: $(echo "$ERR" | grep -o 'shallow roots are not allowed to be updated' | head -1)"
