# Learning: pen-cli migration — a prose claim about the engine was false, and each fix wave contradicted the last

## Problem

PR #11225 (migrate the headless Pencil adapter to `@pen.dev/cli` 0.3.13, plus the stale-file save guard for #11168) took
three review/fix rounds. Three things recurred:

1. A steering sentence ("a relative `Export` path lands in a scratch directory that is deleted on exit") was written from
   the adapter's design, copied into the adapter, `SKILL.md`, `ux-design-lead.md` and three tests, and pinned by tests that
   asserted the sentence itself. The live probe, once a case existed for it, showed the opposite: a relative directory is
   resolved against the document's directory and lands next to the `.pen`. Every test was green while the claim was false.
2. Each fix wave introduced a contradiction that only the next panel found: "re-run the pre-edit hash after every recovery
   reload" vs "skip the replay when the edit is already on disk" (the gate then fails "file unchanged"); and a failed write
   that changed the file got the generic stale-flavoured refusal text, which tells the agent to reopen and replay and so
   discards the only copy of the edit.
3. The live probe ran against an engine installed from an older lockfile (undici 8.10.2, no lock stamp) while the committed
   lockfile pinned 8.12.2, and it is load-sensitive (load average ~30 on 16 cores: three of five runs failed on the 30 s open
   timeout and a scrubber leak check).

## Solution

- Add a probe case for every behavioural sentence the prose promises (recipe forms, Export path resolution, visitor scope),
  and correct the prose to what the engine does. `Get(id, visitor)` visits the node and all descendants, frame first.
- When a recovery rule changes a baseline (a hash, a count), write down which branch keeps the old baseline and which
  re-takes it, and pin both branches with a gate-test row.
- Give every distinct arming cause its own refusal text. A shared generic text silently inherits the wrong recovery.
- Re-install the engine from the committed lockfile (`check_deps.sh --auto`) before the final probe run, and read the
  transcript's recorded dependency versions against the lockfile.

## Key Insight

A test that pins a sentence proves the sentence is stable, not that it is true. The only instrument that can refute a prose
claim about a third-party engine is a probe case that measures the engine. And a fix wave is a new change: the verification
pass over it found four P2s that the panel that triggered the wave could not have seen, because the wave wrote them.

## Session Errors

- **Worktree removed twice mid-run (lease expired after ~11 h of agent time, then a sibling session's cleanup reaped it)** —
  Recovery: `git worktree prune` + `git worktree add`, branch intact on origin — Prevention: take the lease for the whole
  expected agent runtime up front (1440 min for a multi-round pipeline).
- **Scoped-gate reds from repo-global ratchets (bare agent name in prose, KB read under a directory operand, anti-vacuity
  floor not in the `-lt`/`[FATAL]` shape)** — Recovery: reworded/rewrote and raised the floor in the same edit — Prevention:
  already in `work` ("a file-selected suite set cannot see a repo-global ratchet"); run `guard-vacuity-floor`,
  `test-affected-kb-consumers` and `harness-parity-tree` for any change that adds a test or prose.
- **Security seat silent ~10 h; idle turns while waiting on agents** — Recovery: respawned, then stopped the duplicate;
  did independent work while agents ran — Prevention: set a deadline when spawning a seat and do independent work in the gap.
- **A false prose claim about engine behaviour shipped through plan, work and two review rounds** — Recovery: probe case,
  corrected the sentence in 6 files + 3 pinning tests — Prevention: for every causal sentence about an external engine,
  name the probe case that falsifies it before the sentence lands (existing compound rule; applied here only at round 3).
- **Fix waves introduced contradictions found by the next panel (PRE_SHA re-run; failed-write refusal text)** — Recovery:
  a third targeted wave plus a gate-test row per branch — Prevention: a fix that changes a recovery sequence is graded
  against every other sentence that mentions the sequence, in the same wave.
- **Probe ran on a non-lockfile-faithful engine and failed intermittently under load** — Recovery: `--auto` reinstall,
  re-probe, committed the passing run — Prevention: compare the transcript's recorded versions with the lockfile before
  committing it; do not run the probe while the machine is saturated.
- **`pgrep -f` hook block; `ux-design-lead.md` merge conflict with main; hung `cursor --install-extension` process** —
  Recovery: `pgrep -x`; kept our gate text and added main's untracked-path sentence; left the foreign process alone —
  Prevention: none beyond the existing hook (one-offs).

## Tags
category: workflow-issues
module: pencil-setup
