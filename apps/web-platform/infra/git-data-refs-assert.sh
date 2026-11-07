#!/usr/bin/env bash
#
# git-data-refs-assert.sh — the HOST-SIDE read that lets REFS-CONFIRMED be attained (#11431, epic #8211;
# plan knowledge-base/project/plans/2026-10-29-feat-git-data-cutover-refs-assert-plan.md; runbook
# git-data-luks-cutover-5274.md, "Reading REFS-CONFIRMED").
#
# HOW IT RUNS. git-data-cutover.sh MODE=refs_assert sends this file on STDIN to `bash -s` on the git-data
# host, as root, over the single ssh site (gd_capture, 60 s), with the one input as a %q-quoted VAR=value word
# in front of `bash -s`. It is NOT file()-bound into the host's user_data (the rung-2 evidence hash is
# unaffected) and it is NOT a test double: the suite drives THIS file over real git fixtures, and the host
# commands it calls are replaced only by PATH shims.
#
# WHAT IT PROVES, in ONE session (the repository directory's identity, owner included, is recorded before the read
# and compared after it): the store holds exactly ONE real repository (a directory named *.git, no symlink) that is
# owned by the git account, is self-contained (no objects/info/alternates or http-alternates), has no symlink in it
# (anywhere in it, objects/ included), none of the top-level entries that redirect a read to another repository
# (commondir, gitdir, worktrees, modules, config.worktree, reftable), and no symref and no loose ref that is not a
# 40-hex SHA-1 line under refs/soleur/worktrees/, and every ref under refs/soleur/worktrees/ in it is well formed
#   refs/soleur/worktrees/<id>/(heads|tags)/<name>
# with a 40-hex value of the right type (heads: a commit; tags: a commit, or an annotated tag whose chain of tags ends in one:
# %(*objecttype) peels the whole chain; a chain that ends in a tree or blob is rc 28), and at least one ref is a heads/ branch tip (tags-only never passes: the 2026-10-27
# failure was a rejected push to heads/main). A `shallow` file is EXPECTED (every depth-1 workspace push accepted under
# receive.shallowUpdate=true leaves one) and is not refused: a shallow store proves the tip commits exist and are
# commits, not their history or parents, and a corrupt `shallow` file fails the read itself (rc 26). It does NOT prove
# the repository is the synthetic account's, nor tree or history completeness beyond git receive-pack's own
# connectivity check at push time (runbook "Reading REFS-CONFIRMED").
#
# NO NAME LEAVES THE HOST. The one answer line carries counts and at most TWO commit shas of heads/ tips (the
# numerically smallest distinct ones, sorted by sha value, never by ref name). No repository name, worktree
# id, branch name or hash of one is printed or hashed. Names are read into shell variables for classification
# only; stdout and stderr of every command are discarded, and the only stderr this file writes is a fixed reason
# word and digits (gd_capture relays a failed session's stderr, so nothing else may reach it).
#
# NOTHING IS WRITTEN TO THE STORE, and nothing is fetched or run from a repository-local config: the read sets GIT_NO_LAZY_FETCH=1
# (a repo `config` with extensions.partialclone, remote.<n>.promisor and remote.<n>.uploadpack plus a missing tip object would
# otherwise make for-each-ref lazy-fetch and run that command as the git user; with the variable a missing object is just rc 128,
# read as refs_unreadable). The one thing this file writes anywhere is a transient scratch directory under
# /dev/shm (root-only, mode 0700) that holds git's own stderr for the ONE for-each-ref (it is tested for emptiness
# and never printed); the EXIT trap removes it. A SIGKILL would leave that directory, holding only git's warning
# text (which may name a ref), until the next boot; /dev/shm is a tmpfs, so it never reaches a disk.
#
# EXIT CODES (the session's rc IS the verdict; git-data-cutover.sh maps each to a word and a class). Anything
# not in this table, and every transport rc (124 timeout, 255 ssh), is `probe_failed rc=<n>` there:
#    0  refs_confirmed        REFS-CONFIRMED   the one answer line is printed
#   16  probe_failed          INCONCLUSIVE     an input, an instrument or a read failed, or xtrace is on (retryable, at most twice)
#   20  refs_repo_absent      FAILED           zero *.git entries (repos=0)
#   21  refs_repo_not_single  INCONCLUSIVE     repos>1, or an entry that is not a real *.git directory, or the repositories directory is a symlink or not on the store mount (not retryable)
#   23  refs_none             FAILED           the repository holds no ref under refs/soleur/worktrees/ ("provisioned, not replicated")
#   24  refs_no_branch_tip    FAILED           refs exist but none under heads/
#   26  refs_unreadable       INCONCLUSIVE     for-each-ref failed (a missing tip object, an unparsable `shallow` file), a 201st line, or a failed self-check (retryable, at most once: the single retry is always spent, a second identical result stops; no attempt is made to tell the transient read failure from the permanent causes, an unparsable `shallow` file and a 201st line)
#   27  refs_shape_failed     INCONCLUSIVE     a ref whose name is off-shape, or ANY output on git's stderr (git skips a broken ref silently, with only a warning), or a repository a push cannot have produced: reason repo_owner (not owned by git), repo_alternates (objects/info/alternates or http-alternates), repo_redirect (a top-level commondir, gitdir, worktrees, modules, config.worktree or reftable), repo_symlink (a symlink in it), ref_symref (a symref under refs/soleur/worktrees/, dangling or not), ref_content (a loose ref under refs/soleur/worktrees/ that is not exactly 40 hex plus LF) (not retryable)
#   28  refs_bad_sha          FAILED           a value that is not 40-hex, a heads/ object that is not a commit, or a tags/ object that does not peel to a commit
# Retry rule (ONE rule, the runbook states the same numbers): probe_failed at most twice, refs_unreadable at most once, three red runs in all
# since the rollback; every not-retryable cause and every FAILED word is never retried, and a dispatch is made only after R5 (no premature
# dispatch, so no FAILED word is read as "too early"). The one runner-side carve-out: flag_already_true (no host was dialed) is dispatched
# once more, after R5 reads disabled.
# Keep the table, the `die` calls below and the case in git-data-cutover.sh equal (the suite derives the set
# from all three, and the class column from the runbook Verdict map). Why there is no `set -e`: every failure
# below is an explicit `|| die N`, and a script that exits on its own would exit with a code outside this table.
#
# Inputs (validated before anything is read): REFS_REPOS, which must be exactly /mnt/git-data/repositories
# (the argument supplies no root of its own).
#
# Every read of the system goes through an EXTERNAL command (readlink, stat, find, mktemp, runuser): the suite
# replaces those by PATH shims, so this file carries no test seam (ADR-214).
#
# WHY ONE FUNCTION. `bash -s` reads its script from stdin as it executes it, and this file redirects stdin to
# /dev/null (so no command can eat the rest of the script). The whole body therefore lives in one function that
# is parsed completely before it runs.
set -uo pipefail
export LC_ALL=C

ra_main() {
  case "$-" in
    *x*) printf 'refs-assert: refusing to run under xtrace\n' >&2; exit 16 ;;
  esac
  # fd 3 = the original stderr, fd 4 = the original stdout; from here on every command's own stdout and stderr
  # are discarded, so nothing read from the store can reach either stream by accident.
  exec 3>&2 4>&1 1>/dev/null 2>/dev/null </dev/null

  readonly RA_MOUNT=/mnt/git-data
  readonly RA_BOUND=200
  readonly RA_CAP=2
  say() { printf '%s\n' "$*" >&3; }
  die() { local rc="$1"; shift; say "refs-assert: rc=$rc reason=$*"; exit "$rc"; }
  sd=""
  ra_exit() { local rc=$?; trap - EXIT; if [ -n "$sd" ]; then rm -f -- "$sd/err"; rmdir -- "$sd"; fi; exit "$rc"; }
  trap ra_exit EXIT
  trap 'exit 16' HUP INT TERM PIPE

  # ---- 1. the input: exactly the store's repositories directory (one literal; no charset or ".." rule can add to it) --
  local repos="${REFS_REPOS-}"
  [ "$repos" = "$RA_MOUNT/repositories" ] || die 16 arg_repos

  # ---- 2. the repositories directory: a real directory, on the store mount, recorded for the re-check -------
  local real dty mnt id0 id1 rid0 rid1
  real="$(readlink -f -- "$repos")" || die 16 readlink_failed
  [ "$real" = "$RA_MOUNT/repositories" ] || die 21 repositories_dir_not_plain
  dty="$(stat -c %F -- "$repos")" || die 16 stat_failed
  [ "$dty" = directory ] || die 21 repositories_dir_not_plain
  mnt="$(stat -c %m -- "$repos")" || die 16 stat_failed
  [ "$mnt" = "$RA_MOUNT" ] || die 21 repositories_dir_not_plain
  id0="$(stat -c %d:%i:%F -- "$repos")" || die 16 stat_failed

  # ---- 3. ONE NUL-delimited, typed enumeration: the count and the single name, before any ref is read -------
  # The typed predicate of git-data-wipe-assert.sh (the bootstrap's `_repo_count` exclusions, narrowed to the type
  # they stand for). The end record exists only if find itself exited 0: a failed find never reads as "zero".
  local rec t n name="" nrepo=0 nbad=0 saw_end=0
  while IFS= read -r -d '' rec; do
    t="${rec%%$'\t'*}"
    n="${rec#*$'\t'}"
    [ "$t" != "$rec" ] || die 16 record_shape
    if [ "$t" = E ]; then saw_end=1; break; fi
    [[ "$t" =~ ^[dflcbpsDU]$ ]] || die 16 record_type
    [ -n "$n" ] || die 16 record_empty
    case "$n" in *[[:cntrl:]]*) die 16 record_control ;; esac
    nrepo=$((nrepo + 1))
    if [ "$t" = d ] && [[ "$n" =~ ^[A-Za-z0-9._-]+\.git$ ]]; then name="$n"; else nbad=$((nbad + 1)); fi
  done < <(find -H "$repos" -mindepth 1 -maxdepth 1 ! \( -type f \( -name '.*.init.lock' -o -name '.init.lock' \) \) ! \( -type d -name lost+found -empty \) -printf '%y\t%f\0' && printf 'E\tEND\0')
  [ "$saw_end" = 1 ] || die 16 enumeration_failed
  [ "$nrepo" -ge 1 ] || die 20 repos_absent
  [ "$nrepo" -le 1 ] || die 21 repos_not_single "repos=$nrepo"
  [ "$nbad" = 0 ] || die 21 repos_entry_not_repository
  local repo="$repos/$name"
  rid0="$(stat -c %d:%i:%F:%U -- "$repo")" || die 16 stat_failed
  # An explicit --git-dir skips git's own ownership check, so it is made here: the repository must be owned by the account
  # replication pushes as. The owner is part of the identity string, so a chown between here and the re-check is caught too.
  [ "${rid0##*:}" = git ] || die 27 repo_owner

  # ---- 4. a repository a push cannot have produced is not read: alternates, redirectors, symlinks, symref and off-shape ref files --
  # ONE typed find, no name printed, a distinct character per cause (-P: a link is never followed). A `shallow` file is NOT probed:
  # every depth-1 workspace push leaves one, and a corrupt one fails the read itself (rc 26).
  #   a  objects/info/alternates or http-alternates (objects that live outside the store)
  #   r  a top-level entry that redirects the read to another repository (DENYLIST: no legitimate producer in a store built by
  #      git init plus receive-pack): commondir, gitdir, worktrees, modules, config.worktree, reftable
  #   s  a symlink anywhere in the repository, objects/ included (a redirected refs/ or objects/)
  #   y  a loose ref file under the namespace that starts `ref:` (a symref, DANGLING OR NOT: git skips a dangling symref silently,
  #      rc 0 and no stderr, so for-each-ref can never show it)
  #   u  any other loose ref file under the namespace that is not exactly 40 hex plus LF (a SHA-256 value, a ref without its LF,
  #      garbage, an empty file); a .lock file is a push in flight, not a ref
  # A symref created between this probe and the read is caught only if it resolves (the %(symref) field below).
  local lnk
  lnk="$(find -P "$repo" \( -path "$repo/objects/info/alternates" -o -path "$repo/objects/info/http-alternates" \) -printf a -o \( -path "$repo/commondir" -o -path "$repo/gitdir" -o -path "$repo/worktrees" -o -path "$repo/modules" -o -path "$repo/config.worktree" -o -path "$repo/reftable" \) -printf r -o -type l -printf s -o \( -path "$repo/refs/soleur/worktrees/*" -type f ! -name '*.lock' \( -exec grep -q '^ref:' {} \; -printf y -o ! -size 41c -printf u -o ! -exec grep -q -x -E '[0-9a-f]{40}' {} \; -printf u \) \))" || die 16 shape_probe
  case "$lnk" in *a*) die 27 repo_alternates ;; esac
  case "$lnk" in *r*) die 27 repo_redirect ;; esac
  case "$lnk" in *s*) die 27 repo_symlink ;; esac
  case "$lnk" in *y*) die 27 ref_symref ;; esac
  [ -z "$lnk" ] || die 27 ref_content

  # ---- 5. the read: one for-each-ref, as the git user, hardened -----------------------------------------------
  # runuser is called bare (resolved by root's PATH, as the push line in mode_probe is). git's stderr goes to a
  # root-owned file under /dev/shm and is never printed; ANY output there, even with rc 0, is rc 27, because git
  # skips a broken ref (heads/a..b, a garbage loose file) and says so only with a `warning: ignoring ...`. There
  # is no -c safe.directory: GIT_CONFIG_NOSYSTEM=1 means the bootstrap's system safe.directory is never read. The
  # ownership claim does not rest on git (--git-dir skips git's ownership check): section 3 makes it (repo_owner).
  local out="" grc=0
  sd="$(mktemp -d -p /dev/shm)" || die 16 scratch_failed
  out="$(cd / && runuser -u git -- /usr/bin/env -i PATH=/usr/bin:/bin HOME=/nonexistent GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_NO_LAZY_FETCH=1 GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat /usr/bin/git -c core.fsmonitor=false -c core.hooksPath=/dev/null -c core.pager=cat --git-dir="$repo" for-each-ref --count=$((RA_BOUND + 1)) --format='%(refname)%09%(objectname)%09%(objecttype)%09<%(*objecttype)>%09<%(symref)>' refs/soleur/worktrees/ 3>&- 4>&- 2>"$sd/err")" || grc=$?
  [ "$grc" -eq 0 ] || die 26 refs_unreadable
  [ ! -s "$sd/err" ] || die 27 refs_shape_failed

  # ---- 6. classify every line (current shell; counters survive the loop) -----------------------------------
  local ref sha ty pty sym id nm nlines=0 refs=0 heads=0 bad_shape=0 bad_sha=0 bad_sym=0 ty_kind
  local -A ids=() hs=()
  local re_pty='^[<]([a-z]*)[>]$' re_sym='^[<].+[>]$'
  if [ -n "$out" ]; then
    # The two optional fields are wrapped in a non-whitespace sentinel: tab is IFS whitespace, so `read` collapses an empty
    # field and a symref target would otherwise land in the peel-type field.
    while IFS=$'\t' read -r ref sha ty pty sym; do
      nlines=$((nlines + 1))
      [ "$nlines" -le "$RA_BOUND" ] || die 26 refs_unreadable
      refs=$((refs + 1))
      if [[ "$pty" =~ $re_pty ]]; then pty="${BASH_REMATCH[1]}"; else bad_shape=1; continue; fi
      if [ "$sym" != '<>' ]; then
        if [[ "$sym" =~ $re_sym ]]; then bad_sym=1; else bad_shape=1; fi
        continue
      fi
      if [[ "$ref" =~ ^refs/soleur/worktrees/([A-Za-z0-9._-]+)/(heads|tags)/([A-Za-z0-9._/-]+)$ ]]; then
        id="${BASH_REMATCH[1]}"; ty_kind="${BASH_REMATCH[2]}"; nm="${BASH_REMATCH[3]}"
      else
        bad_shape=1; continue
      fi
      if [ "$id" = . ] || [ "$id" = .. ] || [[ "$nm" == *..* ]] || [[ "$nm" == */ ]] || [[ "$nm" == *.lock ]] || [[ "$nm" == -* ]]; then
        bad_shape=1; continue
      fi
      if ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then bad_sha=1; continue; fi
      if [ "$ty_kind" = heads ]; then
        if [ "$ty" = commit ]; then heads=$((heads + 1)); hs["$sha"]=1; else bad_sha=1; continue; fi
      else
        case "$ty:$pty" in commit:* | tag:commit) : ;; *) bad_sha=1; continue ;; esac
      fi
      ids["$id"]=1
    done <<< "$out"
  fi

  # ---- 7. refuse in a fixed order: 23, 27 (symref, then shape), 28, 24 -----------------------------------------------------------
  [ "$refs" -ge 1 ] || die 23 refs_none
  [ "$bad_sym" = 0 ] || die 27 ref_symref
  [ "$bad_shape" = 0 ] || die 27 refs_shape_failed
  [ "$bad_sha" = 0 ] || die 28 refs_bad_sha
  [ "$heads" -ge 1 ] || die 24 refs_no_branch_tip

  # ---- 8. the two numerically smallest distinct heads/ shas (sort, then an array slice: no head under pipefail) -----
  local -a sorted=()
  mapfile -t sorted < <(printf '%s\n' "${!hs[@]}" | sort)
  # the fail-closed self-check: a sort that returned fewer (or no) lines than there are distinct shas, or counts the script
  # cannot reconcile with each other, is never printed
  [ "${#sorted[@]}" -eq "${#hs[@]}" ] || die 26 refs_unreadable
  [ "${#sorted[@]}" -ge 1 ] && [ "${#ids[@]}" -le "$refs" ] && [ "$heads" -le "$refs" ] || die 26 refs_unreadable
  # ... and every sha that will be printed is one that was read from a heads/ commit (a sort that returns the right NUMBER of wrong lines)
  local -a pick=("${sorted[@]:0:$RA_CAP}")
  local s
  for s in "${pick[@]}"; do [ -n "${hs[$s]+x}" ] || die 26 refs_unreadable; done

  # ---- 9. the repository is the one that was counted: nothing was swapped under the read --------------------
  id1="$(stat -c %d:%i:%F -- "$repos")" || die 16 stat_failed
  rid1="$(stat -c %d:%i:%F:%U -- "$repo")" || die 16 stat_failed
  [ "$id1" = "$id0" ] && [ "$rid1" = "$rid0" ] || die 16 identity_changed

  local IFS=,
  printf 'refs_assert ok repos=1 namespaces=%s refs=%s heads=%s shas=%s\n' "${#ids[@]}" "$refs" "$heads" "${pick[*]}" >&4 || die 16 answer_write
  return 0
}
ra_main; exit $?
