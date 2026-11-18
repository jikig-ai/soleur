#!/usr/bin/env bash
set -u
source <(sed -n '/^setup()/,/^}/p' "$(dirname "$0")/probe1.sh")
R=/tmp/claude-1000/kbpull-probe/p4; rm -rf "$R"; mkdir -p "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
mkiso() { mkdir -p "$1/objects/pack" "$1/objects/info" "$1/refs/heads"; echo 'ref: refs/heads/main' > "$1/HEAD"; printf '[core]\n\tbare = true\n' > "$1/config"; cp "$2/.git/shallow" "$1/shallow"; }
echo "== C'. with alternateRefsCommand=true: haves ref needed?"
for haves in yes no; do C="$R/C-$haves"; ( setup "$C" >/dev/null 2>&1; W=$C/ws I=$C/iso; mkiso "$I" "$W"
  ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file)
  [ $haves = yes ] && "${ISO[@]}" git update-ref refs/heads/have "$(git -C "$W" rev-parse HEAD)"
  "${ISO[@]}" GIT_TRACE_PACKET="$C/pkt" git -c core.alternateRefsCommand=true fetch -q --no-tags "file://$C/o.git" refs/heads/main; rc=$?
  T=$("${ISO[@]}" git rev-parse FETCH_HEAD)
  n=$("${ISO[@]}" git rev-list --objects "$T" --not "$(git -C "$W" rev-parse HEAD)" | wc -l)
  echo "   haves=$haves rc=$rc received=$("${ISO[@]}" git count-objects -v | awk '/^(count|in-pack)/{s+=$2} END{print s}') have-lines=$(grep -c ' have ' "$C/pkt") handover-objects=$n" ); done
echo "== push from the isolated dir: alternate-refs child?"
C="$R/P"; ( setup "$C" >/dev/null 2>&1; W=$C/ws I=$C/iso; mkiso "$I" "$W"
  cd "$W"; git fetch -q origin; git merge -q --no-edit origin/main 2>/dev/null; echo k > knowledge-base/k.md; git add -A; git "${ID[@]}" commit -qm k
  H=$(git rev-parse HEAD); cp .git/shallow "$I/shallow"
  env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file GIT_TRACE="$C/trace" \
    git push -q "file://$C/o.git" "$H:refs/heads/main"; echo "   push rc=$? child-into-workspace=$(grep -c "git-dir=$W/.git" "$C/trace")" )
