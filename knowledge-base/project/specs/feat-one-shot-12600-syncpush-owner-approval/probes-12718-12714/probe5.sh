#!/usr/bin/env bash
# Probe 5 (CTO X1 dissent): upstream 3 commits ahead of a --depth 1 workspace; isolated fetch with and without --depth 1.
set -u
R=/tmp/claude-1000/kbpull-probe/p5; rm -rf "$R"; mkdir -p "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
for depth in none 1; do C="$R/d-$depth"; mkdir -p "$C"; cd "$C"
  git init -q --bare -b main o.git; git init -q -b main seed; mkdir -p seed/knowledge-base seed/src
  echo a > seed/knowledge-base/a.md; echo x > seed/src/x.ts; git -C seed add -A; git -C seed "${ID[@]}" commit -qm c0
  git -C seed push -q "file://$C/o.git" main; git clone -q --depth 1 "file://$C/o.git" ws
  for i in 1 2 3; do echo "u$i" >> seed/src/x.ts; git -C seed "${ID[@]}" commit -qam "u$i"; done; git -C seed push -q "file://$C/o.git" main
  W=$C/ws I=$C/iso; mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads"; echo 'ref: refs/heads/main' > "$I/HEAD"
  printf '[core]\n\tbare = true\n' > "$I/config"; cp "$W/.git/shallow" "$I/shallow"; H=$(git -C "$W" rev-parse HEAD)
  ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file)
  "${ISO[@]}" git update-ref refs/heads/have "$H"
  DA=(); [ "$depth" = 1 ] && DA=(--depth 1)
  "${ISO[@]}" git -c core.alternateRefsCommand=true fetch -q --no-tags "${DA[@]}" "file://$C/o.git" refs/heads/main; T=$("${ISO[@]}" git rev-parse FETCH_HEAD)
  sh=$(cmp -s "$W/.git/shallow" "$I/shallow" && echo no || echo yes)
  "${ISO[@]}" git rev-list --objects "$T" --not "$H" | "${ISO[@]}" git pack-objects --stdout -q | git -C "$W" unpack-objects -q
  git -C "$W" update-ref --no-deref refs/remotes/origin/main "$T"
  mo=$(git -C "$W" "${ID[@]}" merge --no-edit --autostash "$T" 2>&1); mrc=$?
  git -C "$W" rev-list --objects HEAD >/dev/null 2>"$C/rl.err"; rlrc=$?
  git -C "$W" fsck --connectivity-only >/dev/null 2>"$C/fsck.err"; frc=$?
  echo "depth=$depth isolated-shallow-changed=$sh merge rc=$mrc ($(echo "$mo" | tail -1 | cut -c1-80)) rev-list rc=$rlrc ($(head -1 "$C/rl.err" | cut -c1-90)) fsck rc=$frc ($(head -1 "$C/fsck.err" | cut -c1-90))"
done
