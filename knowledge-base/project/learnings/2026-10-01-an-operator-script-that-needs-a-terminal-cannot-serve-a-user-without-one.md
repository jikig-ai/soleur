# Learning: a gate that needs a terminal cannot serve a user who has none, so the approval moves to the channel the human already has

## Problem

The generated operator scripts (`soleur:operator-bootstrap`, the shared library
`plugins/soleur/scripts/lib/operator-script.sh`) refused to run without a TTY: every production write
needed a typed `yes`, and with no terminal the script exited 64 with
`SOLEUR_BOOTSTRAP_INPUT_REQUIRED ... tty=0`. That was a deliberate, reviewed decision (ADR-228 and ADR-249:
a typed yes at a terminal is the one acknowledgement an agent cannot supply by setting a variable). It was
also wrong by the product's own direction. Soleur serves non-technical founders and a web app where nobody
has a terminal, so "open a terminal and type yes" is not an instruction a founder can follow, and the agent,
which the product exists to put to work, was locked out of its own post-merge steps. The open #9321
bootstrap carried that contract: the agent could not run any stage that wrote, and the ship message handed
the founder a terminal task.

## What generalises

1. **A control is only as usable as the surface it assumes.** The typed-yes gate assumed a human at a
   terminal. When the product's users have no terminal, the control has to live in a channel they already
   use (the harness approval prompt on the exact command the agent is about to run), not in a channel the
   product tells them they never need.
2. **Move the acknowledgement; do not drop it.** The tempting fix is a flag, an environment variable or a
   run-all mode that lets the agent proceed. That is exactly the "prior approval extending to a new command"
   that `hr-menu-option-ack-not-prod-write-auth` forbids. The design that keeps the human gate: a plugin
   PreToolUse hook mints a one-time receipt bound to the digest of the exact command when the human approves
   it, rewrites the command to carry the receipt's nonce, and the script consumes the receipt before its first
   write. The nonce is a lookup key into a record the hook wrote, so a value the agent sets is never an
   approval.
3. **State the threat model in the words of what it resists.** A same-OS-user file is writable by the agent.
   The honest claim is "resists an instruction-following agent", not "unforgeable"; a hijacked agent that
   forges a record through an obfuscated path is out of scope and is closed only by credential custody (a
   principal the agent cannot write as). Writing the word "unforgeable" anywhere would have been the defect.
4. **Staging is the enabler.** A script an agent can run is one it can run one stage at a time, with a plan
   (names and booleans, never values) printed before any write, a digest of that plan, and idempotent stages
   whose already-satisfied state needs no approval at all. "Run all stages after one typed yes" was never a
   shape an agent-run, human-approved flow could keep.

## Planning and implementation traps (each cost a review round on paper before it cost one in code)

- **A hook that executes the script it fingerprints is code execution outside the sandbox.** The header
  marker is agent-writable; running `--list` from the hook to read the stage table would hand the agent
  exactly that. The hook reads the `# SOLEUR-STAGE` lines statically with grep, and a suite row plants a
  canary in a v2-headed script and asserts the hook never runs it.
- **A fail-closed hook needs a prefilter or it bricks every call.** Failing closed when `jq` is missing is
  right for a candidate command and catastrophic for every other Bash call on a founder machine. Candidates
  are decided by a fixed-string check that needs no `jq`; only a candidate fails closed. The path tools are
  the exception (their arm is evaluated on a canonicalized path, so it needs `jq`), and without `jq` they
  are a no-op rather than a deny.
- **Moving ordering from one run to separately addressable stages means re-proving preconditions inside the
  later stage.** The old single run could trust that stage 3 had run before stage 4. Now `mint-and-store-token`
  re-proves the live App and the copied values in its own plan, refuses with `PRECONDITION_FAILED` and prints
  no digest when it cannot, and `READY` is derived from vendor state, never from the sequence of stages run.
- **A function-name census treats every `read` in the library as a prompt.** The new library functions parse
  files; they use `grep`/`cut`/`awk` instead of `while read`, and the one TTY branch of the stage gate calls
  the existing typed-yes helper rather than owning a `read`. The census stayed a real guard instead of being
  loosened to admit the new code.
- **A library copied into a sandbox must be one file.** The first draft put the receipt algorithm in a
  sibling file; every harness that copies the library alone then lost it. One file is also what the library
  header already promised, and the hook sources the same file so mint and verify cannot drift.
- **A snapshot of a directory listing matches by prefix.** The "consumed before the first write" row greps the
  receipt directory at the first mutating call; `<hash>.consumed` shares its prefix with `<hash>`, so the row
  needs an exact-line match (`grep -x`) or it reports a consumed record as live.
- **Prove the mutation landed.** Two of the thirteen receipt-gate mutation rows first "survived" or failed
  to apply because the perl pattern did not match the edited text; every row now proves the edit landed (md5
  against the pristine copy and `bash -n`) before it is asked to redden a guard, and the one equivalent mutant
  (dropping only the nonce format check) is recorded as equivalent instead of being left to look like a gap.

## What review of the first implementation found (a gate that trusts inputs in the agent's own domain fails open)

Eleven review seats converged on one structural cause: the receipt was only as strong as "the agent's only
route to a satisfied gate is the hook", and four routes stayed open because the gate (or its guards) trusted
something the agent controls.

- **A second approval source kept "for the human" is a second approval source for the agent.** The gate kept
  a typed `yes` at `[[ -t 0 && -t 1 ]]` as a fallback. `script(1)` or a python `pty` gives any Bash call a
  pseudo-terminal, so the agent typed its own `yes`; the suite even owned the primitive (its decline-path
  guard drives the old ack through `script -qec`). The terminal is evidence of a person only OUTSIDE an agent
  harness, so the source is now refused when the harness variables are set, and a row drives the pty both
  ways (with the variable, refused; without, accepted, as the control that proves the pty mechanism works).
- **A "human-set" environment marker is agent-writable if the harness reads settings.** The headless resume
  marker looked unreachable ("the agent cannot alter the harness's own environment") until a probe showed a
  settings `env` block, written by an ordinary Bash call, reaches the hook of the next process. Measure what
  the channel really carries before trusting it; the marker was removed and resume is interactive.
- **Bind the approval to the bytes that run, not only the command that names them.** The digest covered the
  script path, stage and argv, so an agent could edit `apply_*` after the plan and run the approved command.
  The script's content hash is now in both the receipt binding and the plan digest, and every variable field
  is length-prefixed so a newline in an argument cannot read as the next argument.
- **Take the secret out of the environment at the first line you control, not at the gate.** The nonce was
  unset at the gate, but the plan phase had already run vendor reads with it exported. The library now moves
  it into a plain shell variable the moment it is sourced; a suite that only snapshots the FIRST MUTATING call
  cannot see this, so the stub records the nonce on EVERY call.
- **A guard assembled from the self-declared shape proves the properties of the world it defines.** The
  stub classified a call as mutating by a list of verbs (so `gh api -X DELETE`, `curl -XPOST` and
  `secrets delete` passed as reads), drove the apply with no bypass variable set (so a gate wrapped in
  `if [[ "${FORCE:-}" != 1 ]]` was invisible), drove only the stages the table listed, and discovered
  scripts by extension and line. Each is now the other way round: default-deny classification, every
  approve/force/skip-shaped name set to 1, undeclared stage names probed, discovery by `git grep` of the
  header with no directory exclusions.
- **A fake that cannot reject proves nothing.** The stubbed GitHub answered 200 to any request, so six
  mutations of the JWT (wrong algorithm, issuer, lifetime, scheme, key) stayed green. The stub now validates
  the token the way GitHub would and derives the signature from the key bytes it was handed.
- **Text the person reads at the prompt comes from the file being approved.** The first line of the prompt is
  the agent's `description` and the impact sentence is the script's own words; both are now replaced or
  framed ("the script describes this as ..., not verified by Soleur"), stripped of control characters and
  capped.

## Session Errors

Triage (item | recurring? | disposition):

- Editing a test file in place while a background batch was about to run it (bash reads a script incrementally, so the run died with a syntax error at a shifted line) | recurring | one-off fix applied (re-ran; `sed -i` replaces the inode and is safe, an in-place Python rewrite is not). **Prevention:** never edit a suite that a background run has queued; run the batch only after the edits settle, or copy the suite first.
- A Python heredoc containing the literal text of a vendor write command was blocked by the secrets-delete/set redirect hook, so the edit did not apply | one-off | edited with the Edit tool instead. **Prevention:** put command-shaped fixture text through Edit, not a shell heredoc.
- `PIPESTATUS` read inside `$(...)` returns nothing (new pty helper in Guard 11) | recurring (second time in this PR) | read it in the calling shell and capture output through a file. **Prevention:** the pty helper comment now says so.
- Mutation regex written against the previous text of the file (the content line was not last; a `\n` inside a perl pattern for a backslash-newline) | recurring | every mutation row proves it landed (md5 + bash -n), which is what caught both. **Prevention:** keep that row.
- The rule-body lint (`--check --base`) was not run before the first push, so two edited hr- rules had no ack and stale hashes | recurring | fix-now-inline (acks and `--write` hashes added). **Prevention:** run `lint-rule-bodies.py --check --base origin/main` whenever AGENTS.rules.md changes.
- The matcher edit in hooks.json left `devin-dispositions.tsv` stale | one-off, caught by the devin-matcher-parity suite. **Prevention:** grep the matcher string repo-wide when changing it.
- `scripts/test-all.sh --affected` refused as a full gate while sibling sessions ran | one-off | CI is the gate.

## Where it lives

ADR-264 (supersedes in part ADR-228 points 2-4 and ADR-249 step 1 points 2 and 4, for generated scripts only;
amends ADR-162 for the second named rewriter). Guards: `plugins/soleur/test/operator-agent-runnable.test.sh`
(a generated script that cannot run without a TTY fails CI, with the pre-ADR-264 template as a must-RED row),
`operator-script.test.sh` Guard 11 (the receipt gate and the known-answer digest vectors),
`operator-stage-approval-hook.test.sh`, and `operator-9321-stages.test.sh`. The terminal handoff remains, with
its reason, for the flag scripts whose audit row accepts only a typed-yes acknowledgement (tracked follow-up).
