# Learning: my mutation battery inferred the verdict from the input under test, and reported 11/11 while the thesis was unpinned

## Problem

`scripts/check-cloudflare-token-drift.sh` graded Cloudflare Access service tokens LIVE only on HTTP 200. `ssh.<base>`'s tunnel ingress is `ssh://…:22`, so PR #7127 concluded 200 was unreachable there and mapped **5xx → LIVE** for non-HTTP origins. It shipped with 21/21 green, a mutation battery, and shellcheck clean, and was merged.

The premise was never measured. Measured 2026-08-01 against `registry.soleur.ai` with a **live** credential:

```
admitted   -> HTTP/2 200, zero-byte body, NO cf-access-*   (Cloudflare edge answered)
rejected   -> HTTP/2 403, ~39 kB,  cf-access-aud + -domain  (Access denial page)
```

`tunnel.tf` records `ssh://` and `tcp://` as the **same raw-TCP service type**, so an admitted `ssh.` probe returns 200 too. #7127's `5xx` arm could therefore never fire and 200 fell to its catch-all: it traded *DEAD-forever* for **UNVERIFIABLE-forever**. Its suite could not see this because `curl` was stubbed and there was **no case for 200 on the new arm** — the single most likely real code.

## Solution

Grade on Cloudflare Access's own denial stamp, not the status code. The status is a property of the **origin**; the question is about the **gate**. A no-credential CONTROL probe establishes that a gate exists and what its refusal looks like; the credentialed probe is LIVE only if the stamp is **gone** *and* the request succeeded (2xx). Differential, correct for any origin protocol, and still correct if the Access application is deleted — so the `http`/`opaque` taxonomy was removed rather than corrected.

## Key Insight

**Any stub default derived from a value the case also sets converts an observation into a tautology.**

My `curl` stub defaulted the Access stamp from the status code (`403 → stamped`). Six cases therefore produced **identical verdicts under a stamp rule and under a status rule** — they looked like the new arm's core and discriminated nothing. Battery 1 reported **11/11 caught**. After removing the inference, battery 2 caught **14/14**, including two mutants that reverted the PR's entire thesis at full green:

- inserting `elif [[ "$PROBE_CODE" == 200 ]]; then LIVE` ahead of the stamp test — restoring the exact instrument the change existed to remove;
- dropping the credential from the memo cache key — which under a credential-aware fixture turns `live: 1 dead: 1` into `live: 2 dead: 0`, a clean bill of health on the incident the script exists to catch.

Corollaries, each measured this session:

- **The refusal set cannot be enumerated when the refusing layer's status is operator-configurable.** My *first* redesign made LIVE the catch-all `else` narrowed only to 401/403 — the same absence-based error I had just criticised, one notch narrower. A rate-limit 429, a challenge 503, an identity-policy 302 and a tunnel 530 all graded **LIVE at rc=0**, on the only verdict that emails nobody. Assert the positive shape you measured; give the destructive verdict (DEAD) the symmetric guard.
- **Fixture cardinality has a second axis.** The suite had solved multi-*config* and repeated the mistake for multi-*credential*: every fixture wrote identical bytes to every config, so the motivating incident ("5 of 7 configs stale after a dashboard roll") was structurally inexpressible.
- **A memoisation cache called as `state=$(f …)` does not exist.** Command substitution runs the body in a subshell, so every `CACHE[k]=…` write is discarded — measured 3 curl calls for 3 configs holding one identical pair. With no cache, one transient blip grades the **same bytes** live in some configs and dead in another, and the DEAD remedy overwrites the ROOT config all of them inherit. The suite's own harness comment documented this exact trap for its own helper and never applied it to the SUT.
- **A negative grep must be anchored on a token that survives line-wrapping.** An assertion greping `add a hostname mapping` matched nothing on *any* output, because the report wraps that phrase across two `echo` lines. It passed for the wrong reason until a mutation forced the footer to print unconditionally and the suite stayed green.
- **`grep -c` PRINTS 0 and EXITS 1.** So `count=$(grep -c … || printf '0')` returns `"00"` and every `== "0"` comparison fails — the identical print-and-fail concatenation this suite pins in the SUT for curl's `-w` output, reproduced in the helper written to measure it. Use `|| true`.
- **Verify a defensive guard before claiming it defends something.** I added a per-probe truncation with a comment asserting it stopped a stale stamp being read as the next probe's refusal. Measured: curl opens the `-D` dump in truncating mode unconditionally (a DNS failure left a planted `cf-access-aud` file at **0 bytes**), and the `000` arm short-circuits ahead of the stamp read anyway. Removing it leaves the suite green — an equivalent mutant. Keeping it with an honest comment beats keeping it with a false one.

## Session Errors

- **Ran the test suite against a stray copy in the bare repo root.** The shell CWD was silently reset to the bare root mid-session, and `bash scripts/…test.sh` then executed a *different* file from the one being edited (26/26 and a full mutation battery were measured against it). — **Recovery:** pinned every invocation to the worktree with an explicit absolute path, re-ran, re-derived. — **Prevention:** the bare-repo CWD guard in `go.md` covers *edits*; extend the same suspicion to *test runs* — a suite that passes after an edit that should have reddened it is the tell.
- **A pre-commit hook blocked a commit on a correct feature branch.** The hook reads the shell's persistent CWD, which was the bare root (`main`). — **Recovery:** a standalone `cd` into the worktree before committing. — **Prevention:** make the `cd` its own Bash call; `cd X && git commit` does not move the CWD the hook inspects.
- **`git stash list` in a compound command tripped `hr-never-git-stash-in-worktrees`** and blocked the whole command. — **Recovery:** removed the line (it was redundant). — **Prevention:** the guard matches the verb anywhere in the command; read-only `stash` subcommands are not exempt.
- **`sleep 150` chained before a poll, then `run_in_background` polling** — blocked by the sleep gate and then by `hr-monitor-not-run-in-background-for-polling`. — **Recovery:** Monitor tool with an until-loop. — **Prevention:** for any CI/PR wait, reach for Monitor first.
- **Shipped `PROBES_MADE` write-only** in the first commit — assigned three times, read nowhere, with a load-bearing-sounding comment. — **Recovery:** surfaced it in the report line and in `--json`. — **Prevention:** `grep` for a non-assignment consumer of every new field before committing.
- **PR #7127 was marked ready and merged to `main` by a concurrent session while this review was running**, and `cleanup-merged` then deleted the review worktree mid-session. Seven P1s arrived after the merge instead of before it. — **Recovery:** the branch was already pushed, so nothing was lost; the fix became a follow-up PR off main. — **Prevention:** operator decision — if autonomous sessions can merge, the review-evidence gate does not currently prevent merging a PR that has a review in flight.

## Tags

category: test-failures
module: scripts/check-cloudflare-token-drift.sh
pr: 7134
ref: 7127
