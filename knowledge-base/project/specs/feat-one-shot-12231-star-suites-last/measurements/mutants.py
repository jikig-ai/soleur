# Guard 1 mutant builder (one edit to a copy of scripts/test-all.sh per mutant, run through TESTALL_TARGET_OVERRIDE).
# Built against the runner of commit e2f2b4c552 (the measured tree). The park test and the star predicate changed afterwards
# (lane_tokens_has_star, _pj_star), so the PARK strings below no longer match later trees; results: mutant-results.txt.
# Later additions, built the same way by hand: T1 (park predicate matches spaces only), MF (release needs a prior submit),
# MB (release only in the reap path), H5 (tl_check `>=` always true) - all red against the 84-assertion suite.
import hashlib, os, subprocess, sys

REPO = "/data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-12231-star-suites-last"
SRC = open(f"{REPO}/scripts/test-all.sh").read()
OUT = "/var/tmp/soleur-12231/mut"
os.makedirs(OUT, exist_ok=True)

PARK = '''    if [[ " $tok " == *" * "* ]]; then
      rest+=("$idx"); continue   # parked until the drain (see the comment above)
    fi
'''
OLD_STAR = '''    if [[ " $tok " == *" * "* ]]; then
      (( _pj_live_n == 0 && any_q == 0 )) || ok=0
    else
      lane_tokens_conflict "$tok" "$live_tok" && ok=0
      if (( ok == 1 && any_q == 1 )) && lane_tokens_conflict "$tok" "$skip_tok"; then ok=0; fi
    fi
'''
CHECKS = '''    lane_tokens_conflict "$tok" "$live_tok" && ok=0
    if (( ok == 1 && any_q == 1 )) && lane_tokens_conflict "$tok" "$skip_tok"; then ok=0; fi
'''
REL = '''  if (( _pj_draining == 1 && _pj_live_n == 0 && ${#rest[@]} > 0 )); then
    _pj_launch "${rest[0]}"
    rest=("${rest[@]:1}")
  fi
'''
PASS_START = '''  for idx in "${_pj_queue[@]}"; do
    if (( _pj_live_n >= _pj_jobs )); then rest+=("$idx"); continue; fi
'''


def r(s, old, new):
    assert s.count(old) == 1, (old[:60], s.count(old))
    return s.replace(old, new)


def m1a(s):  # revert the park: old star handling
    return r(s, PARK + CHECKS, OLD_STAR)


def m1b(s):  # park, but add the star to skip_tok
    return r(s, 'rest+=("$idx"); continue   # parked', 'rest+=("$idx"); skip_tok+=" $tok"; continue   # parked')


def m1c(s):  # park, add to skip_tok AND set any_q
    return r(s, 'rest+=("$idx"); continue   # parked', 'rest+=("$idx"); skip_tok+=" $tok"; any_q=1; continue   # parked')


def m2(s):  # release without the draining flag
    return r(s, '(( _pj_draining == 1 && _pj_live_n == 0 && ${#rest[@]} > 0 ))', '(( _pj_live_n == 0 && ${#rest[@]} > 0 ))')


def m3a(s):  # release without the empty-pool check
    return r(s, '(( _pj_draining == 1 && _pj_live_n == 0 && ${#rest[@]} > 0 ))', '(( _pj_draining == 1 && ${#rest[@]} > 0 && _pj_live_n < _pj_jobs ))')


def m3b(s):  # launch all of rest
    return r(s, REL, '''  if (( _pj_draining == 1 && _pj_live_n == 0 && ${#rest[@]} > 0 )); then
    local _r
    for _r in "${rest[@]}"; do _pj_launch "$_r"; done
    rest=()
  fi
''')


def m3c(s):  # release the last, not the first
    return r(s, REL, '''  if (( _pj_draining == 1 && _pj_live_n == 0 && ${#rest[@]} > 0 )); then
    _pj_launch "${rest[-1]}"
    unset 'rest[-1]'
  fi
''')


def m3d(s):  # do not drop the released index
    return r(s, '    _pj_launch "${rest[0]}"\n    rest=("${rest[@]:1}")\n', '    _pj_launch "${rest[0]}"\n')


def m4(s):  # reorder: release from the queue BEFORE the pass; drop the post-loop step
    s = r(s, REL, '')
    return r(s, PASS_START, '''  if (( _pj_draining == 1 && _pj_live_n == 0 )); then
    local -a _q2=(); local _done=0
    for idx in "${_pj_queue[@]}"; do
      if (( _done == 0 )) && [[ " ${_pj_tok[idx]} " == *" * "* ]]; then _pj_launch "$idx"; _done=1; else _q2+=("$idx"); fi
    done
    if ((${#_q2[@]})); then _pj_queue=("${_q2[@]}"); else _pj_queue=(); fi
    (( _pj_live_n == 0 )) || { live_tok=" *"; }
  fi
''' + PASS_START)


def m5(s):  # the FIFO branch no longer taken: the knob is ignored
    return r(s, 'if (( _pj_fifo == 1 )); then\n    while', 'if (( _pj_fifo == 1 && 0 )); then\n    while')


def m6(s):  # raise the draining flag at the first submit instead of the drain
    s = r(s, '  _pj_draining=1   # from here', '  : # from here')
    return r(s, '_pj_submit() {  # _pj_submit <label> <argv...> — the run_suite dispatch under parallel mode.\n', '_pj_submit() {  # _pj_submit <label> <argv...> — the run_suite dispatch under parallel mode.\n  _pj_draining=1\n')


def m7(s):  # equality with a lone star instead of the word-bounded match
    return r(s, 'if [[ " $tok " == *" * "* ]]; then\n      rest+=("$idx"); continue', 'if [[ "$tok" == "*" ]]; then\n      rest+=("$idx"); continue')


def m8(s):  # release only in the normal reap path, not in _pj_fill
    s = r(s, REL, '')
    return r(s, '  _pj_fmt_done "$j"\n  _pj_fill\n  return 0\n}', '''  _pj_fmt_done "$j"
  _pj_fill
  if (( _pj_draining == 1 && _pj_live_n == 0 && ${#_pj_queue[@]} > 0 )); then
    local _h="${_pj_queue[0]}"; _pj_queue=("${_pj_queue[@]:1}"); _pj_launch "$_h"
  fi
  return 0
}''')


MUTANTS = {"M1a": m1a, "M1b": m1b, "M1c": m1c, "M2": m2, "M3a": m3a, "M3b": m3b, "M3c": m3c, "M3d": m3d,
           "M4": m4, "M5": m5, "M6": m6, "M7": m7, "M8": m8}

want = sys.argv[1:] or list(MUTANTS)
for name in want:
    mutated = MUTANTS[name](SRC)
    assert hashlib.md5(mutated.encode()).hexdigest() != hashlib.md5(SRC.encode()).hexdigest(), name + " did not land"
    path = f"{OUT}/{name}.sh"
    open(path, "w").write(mutated)
    open(path + ".md5", "w").write(hashlib.md5(mutated.encode()).hexdigest() + "\n")
    print("built", name)
