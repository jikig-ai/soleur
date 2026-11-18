#!/usr/bin/env bash
# Probe 2: conflict leftovers (MERGE_AUTOSTASH), second-session behaviour, haves vs no haves, force-pushed upstream,
# alternate-refs child spawn during the isolated fetch.
set -u
source <(sed -n '/^setup()/,/^}/p;/^state()/,/^}/p;/^iso_fetch_handover()/,/^}/p' "$(dirname "$0")/probe1.sh")
R=/tmp/claude-1000/kbpull-probe/p2
rm -rf "$R"; mkdir -p "$R"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file
ID=(-c user.name=t -c user.email=t@example.invalid)

echo "== A. conflict + dirty non-KB: where does the dirty edit go, and what do abort / reset --hard / a second merge do"
for after in none abort reset second_merge; do
  C="$R/A-$after"
  ( setup "$C" >/dev/null 2>&1; cd "$C/ws"
    echo a-local > knowledge-base/a.md; git add knowledge-base/a.md; git "${ID[@]}" commit -qm "Auto-commit before sync pull"
    echo r-local > README
    iso_fetch_handover "$C" >/dev/null
    git "${ID[@]}" merge --no-edit --autostash "$T" >/dev/null 2>&1
    echo "[$after] after conflicted merge: MERGE_AUTOSTASH=$([ -f .git/MERGE_AUTOSTASH ] && echo yes || echo no) README=$(cat README)"
    case $after in
      abort) out=$(git merge --abort 2>&1); echo "   merge --abort rc=$? :: $(echo "$out" | tail -1)";;
      reset) out=$(git reset -q --hard 2>&1); echo "   reset --hard rc=$? :: $(echo "$out" | tail -1 | cut -c1-120)";;
      second_merge) out=$(git "${ID[@]}" merge --no-edit --autostash "$T" 2>&1); echo "   second merge rc=$? :: $(echo "$out" | tail -2 | tr '\n' '|' | cut -c1-200)";;
    esac
    echo "   README=$(cat README) MERGE_AUTOSTASH=$([ -f .git/MERGE_AUTOSTASH ] && echo yes || echo no) stash_list=$(git stash list | wc -l)"
    state "$C/ws"
  )
done

echo "== B. autostash-pop conflict (no MERGE_HEAD) then the push-side auto-commit would add KB markers"
C="$R/B"; ( setup "$C" >/dev/null 2>&1; cd "$C/ws"; echo a-local > knowledge-base/a.md
  iso_fetch_handover "$C" >/dev/null; git "${ID[@]}" merge --no-edit --autostash "$T" >/dev/null 2>&1; echo "   merge rc=$?"
  echo "   MERGE_HEAD=$([ -f .git/MERGE_HEAD ] && echo yes || echo no) porcelain-z-kb=$(git status --porcelain | grep knowledge-base | tr '\n' ';')"
  out=$(git add -- knowledge-base/a.md 2>&1; git "${ID[@]}" commit -qm auto 2>&1); echo "   add+commit rc=$? :: $(echo "$out" | tail -1)"
  echo "   committed blob has markers: $(git show HEAD:knowledge-base/a.md | grep -c '^<<<<<<<')" )

echo "== C. pack size: haves ref vs none"
for haves in yes no; do
  C="$R/C-$haves"
  ( setup "$C" >/dev/null 2>&1; W=$C/ws I=$C/iso
    mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads"; echo 'ref: refs/heads/main' > "$I/HEAD"
    printf '[core]\n\tbare = true\n' > "$I/config"; cp "$W/.git/shallow" "$I/shallow"
    ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file)
    [ "$haves" = yes ] && "${ISO[@]}" git update-ref refs/heads/have "$(git -C "$W" rev-parse HEAD)"
    "${ISO[@]}" GIT_TRACE_PACKET="$C/pkt" git fetch -q --no-tags "file://$C/o.git" refs/heads/main
    echo "   haves=$haves objects-received=$("${ISO[@]}" git count-objects -v | awk '/^(count|in-pack)/{s+=$2} END{print s}') have-lines=$(grep -c ' have ' "$C/pkt") shallow-changed=$(cmp -s "$W/.git/shallow" "$I/shallow" && echo no || echo yes)" )
done

echo "== D. alternate refs: does the isolated fetch spawn a git child against the workspace .git?"
for arc in default 'true'; do
  C="$R/D-$arc"
  ( setup "$C" >/dev/null 2>&1; W=$C/ws I=$C/iso
    git -C "$W" update-ref refs/heads/planted "$(git -C "$W" rev-parse HEAD)"
    mkdir -p "$I/objects/pack" "$I/objects/info" "$I/refs/heads"; echo 'ref: refs/heads/main' > "$I/HEAD"
    printf '[core]\n\tbare = true\n' > "$I/config"; cp "$W/.git/shallow" "$I/shallow"
    ISO=(env -i PATH="$PATH" HOME="$I" GIT_DIR="$I" GIT_ALTERNATE_OBJECT_DIRECTORIES="$W/.git/objects" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file GIT_TRACE="$C/trace" SENTINEL_TOKEN=tok123)
    XA=(); [ "$arc" = true ] && XA=(-c core.alternateRefsCommand=true)
    "${ISO[@]}" git "${XA[@]}" fetch -q --no-tags "file://$C/o.git" refs/heads/main
    echo "   alternateRefsCommand=$arc: child runs into workspace: $(grep -c "git-dir=$W/.git" "$C/trace") ; sample: $(grep -m1 'for-each-ref\|alternateRefs\|run_command: true' "$C/trace" | sed 's/^.*run_command/run_command/' | cut -c1-160)" )
done

echo "== E. force-pushed (unrelated) upstream"
C="$R/E"; ( setup "$C" >/dev/null 2>&1; cd "$C"
  git init -q -b main other; echo z > other/z; git -C other add -A; git -C other "${ID[@]}" commit -qm z
  git -C other push -q -f "file://$C/o.git" main
  cd ws; iso_fetch_handover "$C" >/dev/null 2>&1; out=$(git "${ID[@]}" merge --no-edit --autostash "$T" 2>&1); echo "   merge rc=$? :: $(echo "$out" | tail -1)" )
