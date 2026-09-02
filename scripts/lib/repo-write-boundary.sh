#!/usr/bin/env bash
# The repo-write boundary: what `scripts/test-all.sh` inspects when it claims a suite wrote to the
# live repository, and — equally — what it does not (#7652).
#
# WHY THIS IS A LIB AND NOT FOUR MORE LINES IN THE RUNNER.
#
# The runner's boundary check has always printed `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY`
# while inspecting `git rev-parse HEAD` and `git status --porcelain` and nothing else. Those two
# are blind to the write that motivated the message: on 2026-08-20 a fixture put
# `commit.gpgsign=false` into the SHARED bare-repo config — no HEAD move, no porcelain entry — and
# six commits were then silently created unsigned, across every worktree on the machine, for as
# long as nobody audited signatures. A message that names a cause the run did not measure is an
# AP-021/ADR-166 violation, and it is the same claim-outruns-check defect #7652 is about, sitting
# inside the guard filed to close it.
#
# So the claim has to be RENDERED FROM THE CHECK. `_repo_state` records a manifest of the
# dimensions it actually captured, and `repo_boundary_render_inspected` renders the operator-facing
# "inspected:" list from that manifest — never from a literal list in the runner. A stale copy of
# this lib measuring three dimensions therefore prints a three-dimension claim; it cannot print a
# four-dimension claim over a three-dimension check, which is precisely the failure one layer up
# across this new module seam.
#
# WHY VALUES ARE DIGESTED. This output is operator-facing and gets pasted into issues. A config
# projection that printed values would print `credential.helper` and, in CI, `http.*.extraheader`
# — which is how GitHub Actions injects its token. Digesting every value means there is no
# redaction allowlist that can be incomplete. The salt is per-run because a bare digest of a
# low-entropy value (`credential.helper` ranges over a handful of strings) is dictionary-reversible
# and comparable across logs; the digest only has to be stable WITHIN one before/after pair.
#
# WHOLE-FUNCTION DEGRADE-OPEN. If HEAD is unreadable, `_repo_state` returns non-zero and the caller
# prints an honest "this run is not evidence" NOTE. A per-dimension degrade is representable in the
# manifest — and that is exactly why it is safe: the rendered claim shrinks with it, so a partial
# measurement can never sit beneath a whole-coverage claim.

# Guard against double-sourcing: the runner sources this once, but the SUT sandbox suites build
# runners that may source it again.
if [[ -n "${_REPO_BOUNDARY_LIB_LOADED:-}" ]]; then return 0 2>/dev/null || true; fi
_REPO_BOUNDARY_LIB_LOADED=1

# Per-run salt. Deliberately NOT derived from anything stable across runs.
: "${REPO_BOUNDARY_SALT:=$(head -c 32 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n')}"
: "${REPO_BOUNDARY_SALT:=fallback-$$-${RANDOM:-0}}"

# Populated by _repo_state. One line per dimension: `<dim>\t<measured|not-measured>`.
_REPO_BOUNDARY_MANIFEST=""

# Operator-facing text is scrubbed before it is printed. Git accepts ESC, CR, BEL, DEL and U+2028
# inside a config subsection name — all verified — and every one of them round-trips into the FATAL
# block. A CR-bearing key OVERWRITES the preceding terminal line, which includes the
# "A SUITE WROTE TO THE LIVE REPOSITORY" header itself. The repo already ships the right primitive
# and it was simply not wired in.
_RWB_STRIP_LIB="$(dirname "${BASH_SOURCE[0]}")/strip-log-injection.sh"
if [[ -r "$_RWB_STRIP_LIB" ]]; then
  # shellcheck source=scripts/lib/strip-log-injection.sh
  source "$_RWB_STRIP_LIB"
fi

# Redact userinfo before a config KEY reaches the operator. `url.<url>.insteadOf`,
# `http.<url>.extraheader` and `credential.<url>.*` parameterise the KEY by URL, and git accepts
# `https://user:token@host` there — so naming keys (which the FATAL detail must do, or the
# remediation is unactionable) opens a disclosure path the raw projection never had. Redacting at
# PRINT time, not at projection time: the projection needs the exact bytes for equality.
_repo_boundary_safe_key() {
  local k="${1-}"
  k="$(printf '%s' "$k" | sed -E 's,://[^/@[:space:]]*@,://<redacted>@,g')"
  # PIPED, never `strip_log_injection "$k"`. It is a STDIN FILTER (`tr | sed`), so calling it with
  # an argument gives it no stdin — and every call site here is inside a `while IFS= read` loop, so
  # it inherited the LOOP's herestring and consumed the entire remaining config list. Measured: the
  # first key printed as the whole projection with newlines stripped. That is this branch's own
  # subject — a helper silently eating its caller's stdin — reproduced inside the redactor written
  # to make the output safe.
  if declare -F strip_log_injection >/dev/null 2>&1; then
    printf '%s' "$k" | strip_log_injection
  else
    printf '%s' "${k//[$'\r\n\f\v\e\177']/?}"
  fi
}


# Emits `<dim>\t<status>`, read FROM A SNAPSHOT when one is passed.
#
# The stored form carries a `manifest\t` prefix so that manifest lines and body lines cannot
# collide inside the snapshot: without it `refs\tmeasured` parses as a ref named "measured", which
# produced a phantom DELETED + created FATAL pair on every classify.
#
# Taking the snapshot as an ARGUMENT is not a convenience. Every real caller invokes
# `before="$(_repo_state)"` — a command substitution, i.e. a SUBSHELL — so the global this used to
# read is discarded before the caller can render anything from it, and the rendered claim silently
# degenerated to whichever dimensions happened to survive. That is the same "a subshell ate the
# assignment" defect this branch exists to close, reproduced inside its own fix; it was caught by
# the runner-integration arm and not by reading. The snapshot embeds its own manifest precisely so
# the claim travels with the measurement.
repo_boundary_manifest() { # repo_boundary_manifest [snapshot]
  if [[ $# -gt 0 ]]; then
    printf '%s' "$1" | sed -n 's/^manifest\t//p'
  else
    printf '%s' "$_REPO_BOUNDARY_MANIFEST" | sed -n 's/^manifest\t//p'
  fi
}

# Bash string comparison, never `awk -v`: awk processes escape sequences in a `-v` assignment, so
# `url.C:\repos\x.insteadOf` (a documented Windows shape) compares unequal to ITSELF. Measured —
# that key reported ADDED **and** DELETED on every run with nothing changed between snapshots, a
# permanent false FATAL on the shared config, i.e. on every worktree on the machine.
#
# Returns non-zero when the key is ABSENT, so presence is explicit rather than inferred from an
# empty digest (a distinction that mattered: an empty digest used to mean "absent").
_repo_boundary_lookup() { # _repo_boundary_lookup <key> <lines>   (lines are `key\tvalue`)
  local want="${1-}" line k
  while IFS= read -r line; do
    k="${line%%$'\t'*}"
    if [[ "$k" == "$want" ]]; then printf '%s' "${line#*$'\t'}"; return 0; fi
  done <<<"${2-}"
  return 1
}

_repo_boundary_digest() { # _repo_boundary_digest <value>
  # The status must be sha256sum's, not `cut`'s. The original form ended in `| cut -c1-16`, and a
  # pipeline reports its LAST command's status — so a failing or missing `sha256sum` returned 0
  # with empty output, and the up-front probe that exists to catch exactly that was itself vacuous.
  # (This lib is SOURCED, so it cannot set `pipefail` without imposing it on its caller.)
  local out
  out="$(printf '%s\0%s' "$REPO_BOUNDARY_SALT" "${1-}" | sha256sum)" || return 1
  [[ -n "$out" ]] || return 1
  printf '%s' "${out:0:16}"
}

# --- the four dimensions ---------------------------------------------------------------------

_repo_boundary_dim_head() {
  git rev-parse HEAD 2>/dev/null
}

_repo_boundary_dim_worktree() {
  # Digested rather than printed: a porcelain listing of a dirty tree can be hundreds of lines and
  # the boundary only ever compares it for equality.
  local p
  p="$(git status --porcelain 2>/dev/null)" || return 1
  _repo_boundary_digest "$p"
}

_repo_boundary_dim_config() {
  # `--local` in a worktree reads the SHARED config file — which is the file the 2026-08-20 write
  # landed in, and the reason this dimension exists. `--list -z` is NUL-terminated so a value
  # containing newlines cannot forge an entry boundary.
  #
  # Carve-out is exactly ONE key family: `branch.*.vscode-merge-base`, which the VS Code git
  # extension rewrites as the user navigates and which no escape would produce. It is NOT
  # `branch.*`: `branch.<n>.remote` and `.merge` are written as a side effect of `git push -u` and
  # `git checkout -b --track`, so they are the single config trace a `git -C "" checkout -b`
  # escape leaves behind. Cutting the whole family — individually defensible — composes with the
  # refs REPORT class to make that escape invisible in both dimensions at once.
  # NEVER `out="$(git config --list -z)"`. Command substitution strips NUL bytes — bash even warns
  # — so the `-z` framing is destroyed, every entry collapses into one unsplittable blob, and the
  # dimension reports a constant while going silently blind to exactly the write it exists to
  # catch. Caught by this lib's own test, not by reading.
  #
  # Streamed from a process substitution rather than a tempfile. A tempfile here would need an
  # owning `trap ... EXIT` (ADR-129, enforced by scripts/lint-trap-tempfile-ownership), and this
  # file is SOURCED — registering an EXIT trap would silently replace the caller's, which in
  # test-all.sh is the trap that reports an unfinished boundary. The cure would disable the thing
  # this lib exists to provide.
  #
  # `git config --list` exits 1 when there are no entries at all, which is legitimate rather than a
  # capture failure, so repo liveness is established first and the listing is then read for what it
  # holds.
  local kv key val
  git rev-parse --git-dir >/dev/null 2>&1 || return 1
  # The digest tool is probed ONCE, up front. Without this, a missing `sha256sum` made every value
  # digest the empty string while the manifest still said `measured` — and because classify infers
  # "key absent" from an empty digest, the run reported every key in the shared config as DELETED.
  # A capture failure must degrade the DIMENSION, never manufacture a verdict.
  _repo_boundary_digest probe >/dev/null 2>&1 || return 1
  while IFS= read -r -d '' kv; do
    if [[ "$kv" == *$'\n'* ]]; then
      key="${kv%%$'\n'*}"
      val="${kv#*$'\n'}"
    else
      # A valueless key (`[section]\n\tkey`) is a real, distinguishable state.
      key="$kv"
      val=$'\1valueless'
    fi
    case "$key" in
      # `branch.*.vscode-merge-base`, NOT `*.vscode-merge-base`. The looser pattern dropped any key
      # in any section ending in that suffix, while the comment above and the operator-facing
      # not-inspected list both say `branch.*`. Claim/check drift of the shape this lib polices.
      branch.*.vscode-merge-base) continue ;;
    esac
    # A TAB or CR inside a subsection name — both accepted by git — would break this framing and
    # silently truncate the key, so the emitted remediation would name a key that does not exist.
    # Encoded rather than dropped: the key must stay distinguishable for the equality compare.
    key="${key//$'\t'/%09}"; key="${key//$'\r'/%0D}"
    printf '%s\t%s\n' "$key" "$(_repo_boundary_digest "$val")"
  done < <(git config --local --list -z 2>/dev/null) | LC_ALL=C sort
  # NOTE: the pipeline's status is `sort`'s. That is deliberate here — the repo liveness probe
  # above already established the config file is readable, and `git config --list` exits 1 on a
  # legitimately EMPTY config, which must not read as a capture failure.
}

_repo_boundary_dim_refs() {
  # `--heads --tags` excludes `refs/remotes/**` by construction: a fetch is the only thing that
  # writes it and an escape has no reason to.
  #
  # `git show-ref` exits 1 on NO REFS, which is a legitimate empty result rather than a capture
  # failure. Conflating the two would make ref DELETION — the dimension's most destructive
  # outcome — read as not-measured, i.e. fail open exactly where it must fail closed. So rc=1 with
  # empty stdout is measured-and-empty; any other failure is a capture failure.
  local out rc
  out="$(git show-ref --heads --tags 2>/dev/null)"; rc=$?
  if (( rc != 0 )) && [[ -n "$out" ]]; then return 1; fi
  if (( rc > 1 )); then return 1; fi
  printf '%s' "$out" | LC_ALL=C sort
}

# --- the snapshot ------------------------------------------------------------------------------

_repo_state() {
  local head worktree config refs manifest="" body="" wt_list=""
  # HEAD is the liveness probe for the whole function. If it cannot be read there is no repository
  # to have a boundary around, and the caller must degrade to an honest NOTE.
  head="$(_repo_boundary_dim_head)" || { _REPO_BOUNDARY_MANIFEST=""; return 1; }
  [[ -n "$head" ]] || { _REPO_BOUNDARY_MANIFEST=""; return 1; }
  manifest+=$'manifest\thead\tmeasured\n'
  body+="head"$'\t'"$head"$'\n'

  if worktree="$(_repo_boundary_dim_worktree)"; then
    manifest+=$'manifest\tworktree\tmeasured\n'
    body+="worktree"$'\t'"$worktree"$'\n'
  else
    manifest+=$'manifest\tworktree\tnot-measured\n'
  fi

  if config="$(_repo_boundary_dim_config)"; then
    manifest+=$'manifest\tconfig\tmeasured\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      body+="config"$'\t'"$line"$'\n'
    done <<<"$config"
  else
    manifest+=$'manifest\tconfig\tnot-measured\n'
  fi

  if refs="$(_repo_boundary_dim_refs)"; then
    manifest+=$'manifest\trefs\tmeasured\n'
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      body+="refs"$'\t'"$line"$'\n'
    done <<<"$refs"
  else
    manifest+=$'manifest\trefs\tnot-measured\n'
  fi

  # The set of branches checked out in OTHER worktrees, carried in the snapshot rather than
  # re-derived at classify time. Re-deriving it after the window closes lets an escape running
  # `git -C "" worktree add -b probe` register its own branch and thereby launder itself from
  # FATAL into the softer REPORT class — `worktree add` is in the sibling scanner's own write-verb
  # list, so it is a contemplated shape, not a hypothetical. A harm classification's reference set
  # has to be part of the measurement.
  # `wt` is a MANIFEST dimension, not a bare body family. It is a classification INPUT — it decides
  # FATAL vs REPORT for refs — and a classification input outside the manifest is precisely what
  # this design exists to prevent.
  #
  # The `<none>` sentinel is load-bearing: without it, "measured, and there are no sibling
  # worktrees" is byte-identical to "not carried in this snapshot", and the classifier's fallback
  # then re-derives the set AFTER the window closes. On any single-worktree checkout — i.e. every
  # CI runner — that made the fallback the DEFAULT path, so an escape running
  # `git -C "" worktree add -b probe` registered its own branch and laundered itself from FATAL to
  # REPORT, which changes no exit code. Three reviewers found that independently.
  local wt wt_n=0
  if wt_list="$(_repo_boundary_branches_elsewhere)"; then
    manifest+=$'manifest\twt\tmeasured\n'
    while IFS= read -r wt; do
      [[ -n "$wt" ]] || continue
      body+="wt"$'\t'"$wt"$'\n'
      wt_n=$((wt_n + 1))
    done <<<"$wt_list"
    (( wt_n == 0 )) && body+="wt"$'\t'"<none>"$'\n'
  else
    manifest+=$'manifest\twt\tnot-measured\n'
  fi

  _REPO_BOUNDARY_MANIFEST="$manifest"
  # The manifest is emitted INSIDE the snapshot as well as kept in the global: a before/after pair
  # taken across a lib swap must show the dimension set itself changing, not silently compare a
  # four-dimension reading against a three-dimension one.
  printf '%s' "$manifest"
  printf '%s' "$body"
}

# --- harm classification -------------------------------------------------------------------------

_repo_boundary_default_branch() {
  local d
  d="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)" && { printf '%s' "${d#origin/}"; return 0; }
  printf 'main'
}

# Branches checked out in a worktree OTHER than this one. A measured read of the ref store via
# `git worktree list`, not a concurrency sniff — which is what disqualified the `${CI:-}` tier.
_repo_boundary_branches_elsewhere() {
  local here line path_ branch
  here="$(git rev-parse --show-toplevel 2>/dev/null)" || here=""
  git worktree list --porcelain 2>/dev/null | {
    path_=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*) path_="${line#worktree }" ;;
        "branch "*)
          branch="${line#branch }"
          [[ -n "$here" && "$path_" == "$here" ]] || printf '%s\n' "$branch"
          ;;
      esac
    done
  }
}

# repo_boundary_classify <before> <after>
# Prints zero or more `<SEVERITY>\t<dimension>\t<detail>` lines. Silent when there is no delta.
#
# Three severities, because two were not enough:
#   FATAL        this run changed something it had no business changing.
#   REPORT       a SHARED store changed in a way a sibling worktree routinely produces. Printed,
#                counted, but not a verdict — see below.
#   UNMEASURABLE a dimension was captured at one boundary and not the other, so the delta is
#                meaningless. Neither clean nor dirty: the run is simply not evidence about it.
#
# WHY `config` NEEDS A HARM PARTITION AND NOT JUST `refs`.
#
# `git config --local` in a linked worktree reads the SHARED config file — that is the entire
# point of measuring it, since the 2026-08-20 incident wrote `commit.gpgsign=false` there. But it
# means the dimension is not private to this worktree: `git push -u` and `git checkout -b --track`
# write `branch.<n>.remote` and `branch.<n>.merge` into that same shared file, so ANY of this
# machine's sibling worktrees doing ordinary work during a multi-minute gate run mutates it.
#
# Measured on this repo while writing this: 22 worktrees, and the `branch.*` entry count moved
# 46 -> 48 inside a single session. Before this partition existed, that produced
# `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` — byte-identical to the output for the real
# incident key. That is the cry-wolf failure the refs partition was introduced to prevent,
# re-collapsed on the config axis, and it is also an AP-021 violation of exactly the shape this
# lib exists to fix: the run measured "a shared key changed", never "a suite of THIS run did it",
# and for a shared store it structurally cannot.
#
# So config is classified PER KEY, and the keys are NAMED in the detail. Naming them is not a
# nicety either: the operator-facing next action said "unset the key named above" while no key was
# ever printed, which is the same claim-outruns-content defect one line further down.
repo_boundary_classify() {
  # Herestrings and process substitutions throughout, never tempfiles: a sourced lib cannot own an
  # EXIT trap without clobbering its caller's (ADR-129).
  local before="${1-}" after="${2-}"

  # --- manifest pairing, FIRST ---------------------------------------------------------------
  # A dimension measured at one boundary and not the other cannot be diffed: the body lines are
  # simply absent on one side, so a plain diff reports a delta and would emit a FATAL naming a
  # dimension the INSPECTED list (rendered from the after-manifest) does not even claim to have
  # inspected. That is reachable, not theoretical — `git status --porcelain` refreshes the index
  # and fails under `index.lock` contention, which parallel worktrees produce routinely.
  local bman aman dim bstat astat
  bman="$(repo_boundary_manifest "$before")"
  aman="$(repo_boundary_manifest "$after")"
  local unmeasurable=""
  while IFS=$'\t' read -r dim bstat; do
    [[ -n "$dim" ]] || continue
    astat="$(printf '%s\n' "$aman" | awk -F'\t' -v d="$dim" '$1==d {print $2}')"
    if [[ "$bstat" != "$astat" ]]; then
      unmeasurable="$unmeasurable $dim"
      printf 'UNMEASURABLE\t%s\tcaptured at one boundary (%s) and not the other (%s); this run is not evidence about it\n' \
        "$dim" "${bstat:-absent}" "${astat:-absent}"
    fi
  done <<<"$bman"

  local default_branch elsewhere own_branch own_short
  default_branch="$(_repo_boundary_default_branch)"
  # Branches checked out elsewhere are read from the BEFORE snapshot when it carries them, so a
  # `git -C "" worktree add -b probe` cannot register its own branch mid-run and thereby launder
  # itself into the softer class.
  # No `|| re-derive` fallback. An empty measured set is a legitimate result and must not be
  # confused with an uncarried one — that conflation is what reopened the laundering hole. A
  # snapshot predating the `wt` family (only possible across a lib swap) has no `wt` manifest row,
  # which the pairing check above already reports as UNMEASURABLE.
  elsewhere="$({ grep "^wt"$'\t' <<<"$before" || true; } | sed 's/^wt\t//' | grep -v '^<none>$' || true)"
  own_branch="$(git symbolic-ref --quiet HEAD 2>/dev/null)" || own_branch=""
  own_short="${own_branch#refs/heads/}"

  # --- head / worktree: private to this worktree, so any delta is ours -------------------------
  for dim in head worktree; do
    [[ " $unmeasurable " == *" $dim "* ]] && continue
    if ! diff -q <({ grep "^${dim}"$'\t' <<<"$before" || true; }) \
                 <({ grep "^${dim}"$'\t' <<<"$after"  || true; }) >/dev/null; then
      printf 'FATAL\t%s\tthis dimension changed between the first suite and the end of the run\n' "$dim"
    fi
  done

  # --- config: per key, by harm ----------------------------------------------------------------
  if [[ " $unmeasurable " != *" config "* ]]; then
    local bcfg acfg key bdig adig brname _rwb_present
    bcfg="$({ grep "^config"$'\t' <<<"$before" || true; } | sed 's/^config\t//')"
    acfg="$({ grep "^config"$'\t' <<<"$after"  || true; } | sed 's/^config\t//')"
    # Added or modified.
    while IFS=$'\t' read -r key adig; do
      [[ -n "$key" ]] || continue
      if bdig="$(_repo_boundary_lookup "$key" "$bcfg")"; then
        [[ "$bdig" == "$adig" ]] && continue
        _rwb_present=1
      else
        _rwb_present=0
      fi
      if [[ "$_rwb_present" == 0 ]]; then
        # ADDED. The only benign shape is a tracking-config pair for a branch that is not this
        # worktree's — precisely what `git push -u` / `checkout -b --track` leave behind. Our OWN
        # branch gaining tracking config mid-run stays FATAL: fail closed on the ambiguous case.
        case "$key" in
          branch.*.remote|branch.*.merge)
            brname="${key#branch.}"; brname="${brname%.*}"
            if [[ -n "$own_short" && "$brname" == "$own_short" ]]; then
              printf 'FATAL\tconfig\t%s was ADDED — tracking config for THIS worktree'"'"'s own branch\n' "$(_repo_boundary_safe_key "$key")"
            else
              printf 'REPORT\tconfig\t%s was ADDED — the shape `git push -u` / `checkout -b --track` leaves for branch %s\n' "$(_repo_boundary_safe_key "$key")" "$(_repo_boundary_safe_key "$brname")"
            fi ;;
          *)
            printf 'FATAL\tconfig\t%s was ADDED\n' "$(_repo_boundary_safe_key "$key")" ;;
        esac
      else
        printf 'FATAL\tconfig\t%s CHANGED VALUE\n' "$(_repo_boundary_safe_key "$key")"
      fi
    done <<<"$acfg"
    # Deletions. An earlier revision of this comment said "nothing routine removes a shared config
    # key" — measured FALSE: `worktree-manager.sh` runs `git branch -D`, and `cleanup-merged` runs
    # at EVERY session start across this machine's worktrees, which removes the deleted branch's
    # `branch.<n>.remote` and `.merge` alongside its head. So the DELETE side takes the same harm
    # partition as the ADD side, or a routine session start reds every concurrent gate run.
    while IFS=$'\t' read -r key bdig; do
      [[ -n "$key" ]] || continue
      _repo_boundary_lookup "$key" "$acfg" >/dev/null && continue
      case "$key" in
        branch.*.remote|branch.*.merge)
          brname="${key#branch.}"; brname="${brname%.*}"
          if [[ -n "$own_short" && "$brname" == "$own_short" ]]; then
            printf 'FATAL\tconfig\t%s was DELETED — tracking config for THIS worktree'"'"'s own branch\n' "$(_repo_boundary_safe_key "$key")"
          else
            printf 'REPORT\tconfig\t%s was DELETED — the shape `git branch -d` / cleanup-merged leaves for branch %s\n' "$(_repo_boundary_safe_key "$key")" "$(_repo_boundary_safe_key "$brname")"
          fi ;;
        *)
          printf 'FATAL\tconfig\t%s was DELETED\n' "$(_repo_boundary_safe_key "$key")" ;;
      esac
    done <<<"$bcfg"
  fi

  # --- refs: per ref, by harm -------------------------------------------------------------------
  if [[ " $unmeasurable " != *" refs "* ]]; then
    local brefs arefs ref name bsha asha shared_store=""
    # ATTRIBUTION, not severity, is what the class turns on here. Every ref except our own lives in
    # the SHARED bare repo that all linked worktrees write to, so when sibling worktrees exist a
    # non-own ref delta has no attributable author: `git fetch` in any sibling moves
    # refs/heads/main, `worktree add -b` creates a head, and `worktree-manager.sh cleanup-merged`
    # (which /work Phase 0 runs at the START of every session) deletes one. All routine, none this
    # run's doing. Measured 2026-09-02: one 73-minute `scripts` shard observed SIX sibling ref
    # moves and reddened the gate with all 342 suites passing, while the config dimension
    # independently classified the SAME sibling `git push -u` as REPORT -- the two dimensions
    # disagreed about one event. A gate that cannot pass on the ordinary workflow gets ignored,
    # and it is the operator's machine, not CI, that this boundary exists to protect.
    #
    # The softer class is gated on whether ANY sibling worktree existed, read from the BEFORE
    # snapshot for exactly the anti-laundering reason the `wt` dimension was added: a mid-run
    # `git -C "" worktree add -b probe` cannot retroactively manufacture the siblings that would
    # soften its own class. On a single-worktree checkout -- every CI runner, and every probe
    # fixture in the suite next door -- `elsewhere` is empty, so refs keeps FULL strength exactly
    # where attribution is possible. HEAD, the tree and our own branch stay FATAL unconditionally
    # (private to this worktree); tags too, since sibling traffic does not routinely move them.
    #
    # What this gives up, stated plainly: on a machine with siblings, a suite that moves some OTHER
    # worktree's branch is REPORT rather than FATAL. That is the price of not being able to
    # attribute it, and the delta is still printed, named and counted -- never silence. The
    # incident class this guard was filed for (#7553/#7652: a fixture whose `cd` fails running git
    # in the caller's CWD) lands on HEAD, the tree and our own branch, all of which stay FATAL.
    [[ -n "$elsewhere" ]] && shared_store=1
    brefs="$({ grep "^refs"$'\t' <<<"$before" || true; } | sed 's/^refs\t//')"
    arefs="$({ grep "^refs"$'\t' <<<"$after"  || true; } | sed 's/^refs\t//')"
    if [[ "$brefs" != "$arefs" ]]; then
      # Field-exact throughout. A substring compare on " $name" matches ` refs/heads/foo` inside
      # ` refs/heads/foo/bar`; git's D/F rule makes that pair impossible among heads today, but a
      # prefix match would drop the deletion from the report ENTIRELY -- not soften its class, but
      # lose the line. That fails OPEN in both regimes: silently on a shared store, and on the
      # fail-closed no-sibling path (CI) where a deletion is still FATAL.
      while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        name="${ref#* }"
        if [[ -z "$(printf '%s\n' "$arefs" | awk -v n="$name" '$2==n {print $1}')" ]]; then
          case "$name" in
            refs/tags/*|"$own_branch")
              printf 'FATAL\trefs\t%s was DELETED\n' "$name" ;;
            *)
              if [[ -n "$shared_store" ]]; then
                printf 'REPORT\trefs\t%s was DELETED; sibling worktrees share this ref store (the `cleanup-merged` shape)\n' "$name"
              else
                printf 'FATAL\trefs\t%s was DELETED\n' "$name"
              fi ;;
          esac
        fi
      done <<<"$brefs"
      while IFS= read -r ref; do
        [[ -n "$ref" ]] || continue
        name="${ref#* }"; asha="${ref%% *}"
        bsha="$(printf '%s\n' "$brefs" | awk -v n="$name" '$2==n {print $1}')"
        [[ "$bsha" == "$asha" ]] && continue
        case "$name" in
          refs/tags/*)
            printf 'FATAL\trefs\t%s (tag) was created or moved\n' "$name" ;;
          "$own_branch")
            printf 'FATAL\trefs\t%s is this worktree'"'"'s checked-out branch and it moved\n' "$name" ;;
          "refs/heads/$default_branch")
            if [[ -n "$shared_store" ]]; then
              printf 'REPORT\trefs\t%s is the default branch and it moved (the sibling `git pull` shape)\n' "$name"
            else
              printf 'FATAL\trefs\t%s is the default branch and it moved\n' "$name"
            fi ;;
          *)
            if [[ -z "$shared_store" ]]; then
              # Fail closed: no sibling worktree existed, so this run is the only candidate author.
              printf 'FATAL\trefs\t%s was created or moved\n' "$name"
            elif grep -qxF -- "$name" <<<"$elsewhere"; then
              printf 'REPORT\trefs\t%s is checked out in another worktree; created or moved\n' "$name"
            else
              printf 'REPORT\trefs\t%s was created or moved; sibling worktrees share this ref store\n' "$name"
            fi ;;
        esac
      done <<<"$arefs"
    fi
  fi
}

# --- the rendered claim --------------------------------------------------------------------------

_repo_boundary_dim_prose() {
  case "$1" in
    head)     printf 'HEAD' ;;
    worktree) printf "this worktree's tree and index" ;;
    config)   printf "local (shared) config, except branch.*.vscode-merge-base" ;;
    refs)     printf 'local heads and tags, by harm class' ;;
    *)        printf '%s' "$1" ;;
  esac
}

# The operator-facing "inspected:" list, rendered FROM THE MANIFEST. This is the whole point of the
# manifest: the claim cannot outrun the check, because it is generated by it.
# With ONE snapshot, renders what that snapshot measured. With TWO, renders the INTERSECTION —
# a dimension is only "inspected" for the run as a whole if it was captured at BOTH boundaries.
# Rendering from the after-manifest alone would print a full-width claim for a run whose start
# snapshot was narrower, which is the claim/check drift this lib exists to remove.
repo_boundary_render_inspected() { # repo_boundary_render_inspected [before [after]]
  local dim status other
  while IFS=$'\t' read -r dim status; do
    [[ -n "$dim" ]] || continue
    [[ "$status" == "measured" ]] || continue
    if [[ $# -ge 2 ]]; then
      other="$(repo_boundary_manifest "$2" | awk -F'\t' -v d="$dim" '$1==d {print $2}')"
      [[ "$other" == "measured" ]] || continue
    fi
    printf '          - %s\n' "$(_repo_boundary_dim_prose "$dim")"
  done <<<"$(repo_boundary_manifest "${1-}")"
}

repo_boundary_render_not_inspected() { # repo_boundary_render_not_inspected [before [after]]
  local dim status other
  # MEASURED, so a reader does not go hunting: of the five dimensions, only `worktree` can
  # realistically report not-measured. git parses packed-refs and config eagerly, so every ref-store
  # or config corruption takes `git rev-parse HEAD` down first and the WHOLE snapshot degrades.
  # `git status --porcelain` refreshing the index under `index.lock` contention is the one live
  # per-dimension case.
  #
  # A dimension not measured at EITHER boundary is named HERE rather than silently dropped, so a
  # partial reading is never presented as whole coverage. This is the union of the two
  # not-measured sets, mirroring the intersection the inspected list renders.
  while IFS=$'\t' read -r dim status; do
    [[ -n "$dim" ]] || continue
    other="measured"
    [[ $# -ge 2 ]] && other="$(repo_boundary_manifest "$2" | awk -F'\t' -v d="$dim" '$1==d {print $2}')"
    if [[ "$status" == "not-measured" || "$other" == "not-measured" ]]; then
      printf '          - %s (COULD NOT BE MEASURED on this run)\n' "$(_repo_boundary_dim_prose "$dim")"
    fi
  done <<<"$(repo_boundary_manifest "${1-}")"
  cat <<'EOF'
          - the content of a push to a remote (though `push -u` leaves a local
            branch.*.remote/.merge artifact, which IS inspected)
          - loose or packed objects with no ref change
          - the contents of .git/hooks (so `lefthook install` does not fire here)
          - branch.*.vscode-merge-base
          - config in --worktree scope (.git/worktrees/<n>/config.worktree, under
            extensions.worktreeConfig), --global, and --system. Only --local is read, and on this
            repo that IS the shared file — but a fixture calling `git config --global ...` with no
            -C writes somewhere this boundary never looks
          - remote-tracking refs (refs/remotes/**)
          - reflogs
          - the relative order of a multivalued config key (the projection sorts, so a
            reordering of repeated http.* or remote.*.fetch entries is invisible)
          - files matched by .gitignore — `git status --porcelain` is run WITHOUT --ignored, so a
            fixture overwriting .env, .env.local or .claude/settings.local.json is invisible here
          - the working tree of any OTHER worktree on this machine; only THIS checkout's tree and
            index are read, and the 2026-08-20 escape class can reach a sibling checkout
          - refs outside refs/heads and refs/tags: refs/notes/**, refs/replace/**, refs/stash,
            refs/bisect/** (a `git replace` silently changes what every later `git log` shows)
          - loose or packed objects written with no ref change (hash-object -w, commit-tree, mktree)
          - reflogs — which is also the recovery path the [head] next action prescribes
          - index bits: --skip-worktree, --assume-unchanged, sparse-checkout
          - a HEAD that changed SYMBOLICALLY at a constant sha (`checkout --detach`); the head
            dimension is `rev-parse HEAD`, a sha, so this is invisible AND it empties the
            own-branch comparison that drives two FATAL escalations
          - any A -> B -> A pair inside the window (a `git stash push` followed by `pop`)
          - anything a suite's descendants do AFTER the end snapshot
          - any entry point other than runs of this runner
          - any suite this runner did not start
EOF
}

# Per-dimension next action. The old text offered `git reflog` and `git log origin/main..main` for
# every outcome — HEAD/worktree instructions that say nothing at all about a config flip.
repo_boundary_next_action() {
  case "$1" in
    head)     printf 'git reflog -25   # the commit that moved HEAD is reachable there' ;;
    worktree) printf 'git status && git diff   # UNCOMMITTED work is what is at risk' ;;
    config)   printf 'git config --local --unset <the key named in the [config] line above>   # --local IS the SHARED file every worktree on this machine inherits' ;;
    refs)     printf 'git show-ref --heads --tags   # compare against git reflog <ref>; a DELETED ref is recoverable from the reflog until gc' ;;
    *)        printf 'git status' ;;
  esac
}
