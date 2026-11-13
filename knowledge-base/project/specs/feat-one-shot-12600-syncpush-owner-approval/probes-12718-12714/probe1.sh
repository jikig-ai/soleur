#!/usr/bin/env bash
# Probe 1: current `pull --no-rebase --autostash` vs isolated fetch + handover + token-free local merge.
set -u
R=/tmp/claude-1000/kbpull-probe/p1
rm -rf "$R"; mkdir -p "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)
echo "git: $(git --version)"

setup() { # $1 case dir
  local C=$1; mkdir -p "$C"; cd "$C" || exit 1
  git init -q --bare -b main o.git
  git init -q -b main seed
  mkdir -p seed/knowledge-base seed/src
  echo a1 > seed/knowledge-base/a.md; echo c1 > seed/knowledge-base/c.md; echo x1 > seed/src/x.ts; echo r1 > seed/README
  git -C seed add -A; git -C seed "${ID[@]}" commit -qm c0
  echo a1b > seed/knowledge-base/a.md; git -C seed "${ID[@]}" commit -qam c1
  git -C seed push -q "file://$C/o.git" main
  git clone -q --depth 1 "file://$C/o.git" ws
  # upstream moves: kb a.md, src x.ts, new src/new.ts
  echo a2 > seed/knowledge-base/a.md; echo x2 > seed/src/x.ts; echo n2 > seed/src/new.ts
  git -C seed add -A; git -C seed "${ID[@]}" commit -qm c2
  git -C seed push -q "file://$C/o.git" main
}

state() { # $1 label
  local W=$1
  local mh="no"; [ -f "$W/.git/MERGE_HEAD" ] && mh="yes"
  local mk; mk=$(grep -rl '^<<<<<<<' "$W/knowledge-base" "$W/src" "$W/README" 2>/dev/null | sed "s|$W/||" | tr '\n' ',' )
  local st; st=$(git -C "$W" stash list | wc -l)
  local por; por=$(git -C "$W" status --porcelain | tr '\n' ';' | cut -c1-120)
  local head; head=$(git -C "$W" log -1 --format=%s)
  echo "   MERGE_HEAD=$mh markers=[${mk}] stash=$st head='$head' status=[$por]"
}

iso_fetch_handover() { # $1 case dir; prints T
  local C=$1 W=$1/ws I=$1/iso
  mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads" "$I/refs/tags"
  echo 'ref: refs/heads/main' > "$I/HEAD"
  printf '[core]\n\trepositoryformatversion = 0\n\tbare = true\n' > "$I/config"
  cp "$W/.git/shallow" "$I/shallow"
  local H; H=$(git -C "$W" rev-parse HEAD)
  ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file)
  "${ISO[@]}" git update-ref refs/heads/have "$H"
  "${ISO[@]}" git fetch -q --no-tags "file://$C/o.git" refs/heads/main 2>&1 | head -3
  T=$("${ISO[@]}" git rev-parse FETCH_HEAD)
  "${ISO[@]}" git rev-list --objects "$T" --not "$H" | "${ISO[@]}" git pack-objects --stdout -q > "$C/hand.pack"
  git -C "$W" unpack-objects -q < "$C/hand.pack"
  git -C "$W" update-ref --no-deref refs/remotes/origin/main "$T"
}

run_case() { # $1 name, $2 prep-function, $3 mode (pull|merge|ffonly)
  local N=$1 PREP=$2 MODE=$3 C="$R/$1-$3"
  ( setup "$C" >/dev/null 2>&1; cd "$C/ws"; $PREP
    local out rc
    if [ "$MODE" = pull ]; then
      out=$(git "${ID[@]}" pull --no-rebase --autostash 2>&1); rc=$?
    else
      iso_fetch_handover "$C" >/dev/null
      if [ "$MODE" = merge ]; then out=$(git "${ID[@]}" merge --no-edit --autostash "$T" 2>&1); rc=$?
      else out=$(git "${ID[@]}" merge --ff-only --autostash "$T" 2>&1); rc=$?; fi
    fi
    echo "[$N/$MODE] rc=$rc :: $(echo "$out" | grep -v '^ ' | tail -3 | tr '\n' '|' | cut -c1-230)"
    state "$C/ws"
  )
}

p_clean() { :; }
p_dirty_kb_autocommitted() { echo c-local > knowledge-base/c.md; git add knowledge-base/c.md; git "${ID[@]}" commit -qm "Auto-commit before sync pull"; }
p_dirty_kb_uncommitted_untouched() { echo c-local > knowledge-base/c.md; }
p_dirty_kb_uncommitted_overlap() { echo a-local > knowledge-base/a.md; }
p_dirty_nonkb_untouched() { echo r-local > README; }
p_dirty_nonkb_overlap() { echo x-local > src/x.ts; }
p_untracked_collide() { echo n-local > src/new.ts; }
p_conflict_committed() { echo a-local > knowledge-base/a.md; git add knowledge-base/a.md; git "${ID[@]}" commit -qm "Auto-commit before sync pull"; }
p_conflict_plus_dirty_nonkb() { p_conflict_committed; echo r-local > README; }

for c in clean dirty_kb_autocommitted dirty_kb_uncommitted_untouched dirty_kb_uncommitted_overlap dirty_nonkb_untouched dirty_nonkb_overlap untracked_collide conflict_committed conflict_plus_dirty_nonkb; do
  for m in pull merge ffonly; do run_case "$c" "p_$c" "$m"; done
done
