# Learning: a log-scraping probe matched the script it echoed, and the inline copies dropped a trim the library had

## Problem

Slice S4 of the argv-credential sweep (tracker #9597) moved production credentials off curl/openssl/git argv onto stdin config, through the shared library (ADR-280) or an inline wrapper where a job is checkout-free by design. A 12-seat panel, a 7-seat targeted fix round and a verification pass found one P1 and about twenty P2, almost all in the verification and operations code the slice added rather than in the conversions. Three classes recur and generalize.

1. **A probe that greps run logs for a marker matches the marker text echoed inside the step's `run:` source.** GitHub prints each step's script into the job log, and the inline wrappers contain `echo "SOLEUR_CREDENTIAL_REFUSED script=... reason=token_shape"` (11 times in `web-platform-release.yml` alone). The follow-through probe's unanchored regex counted those lines on every healthy run, so the merge's own release run would have read as "a stored credential was refused" and the probe could never pass. No suite drove the probe, and S3's probe had not hit this because the library, not the workflow source, printed the marker.
2. **An inline copy of a library guard silently loses the library's pre-processing.** `bc_ok` trims trailing whitespace before judging a credential; the inline `_bearer_ok` copies (byte-pinned by a parity audit) judge the raw value. GitHub secrets cannot be read back, so a stored trailing newline, which the old argv form tolerated, would have turned the merge's own deploy red and dropped the failure email. The first fix trimmed trailing whitespace in the runner's locale; review then found the old argv form also tolerated a leading blank and that a locale-class trim diverges from the library's C-locale judgement.
3. **A fix's own prose and guards overclaim.** The first review-fix trigger messages said "nothing was deployed" for any exit code (only the wrapper's rc 2 proves nothing was sent; a timeout can follow an accepted POST), and the attempted correction added an `rc == 2` branch that contradicted the plan's own rule that no site branches on rc 2 (curl uses 2 too) and needed a battery exemption, which was then reverted for one message that carries both cases.

## Solution

- Anchor a log probe on the EMITTED line: a timestamp-prefixed, end-anchored regex (`<ISO-8601Z> SOLEUR_CREDENTIAL_REFUSED script=<name> reason=<word>$`). The echoed source lines are indented or colour-escaped, so they cannot match. Measure the real log-line shape (`<job>\t<step>\t<BOM?><timestamp> <text>`) on a recent run and put a log fixture that contains the echoed source into the probe's suite so the regression row can go red.
- Make "exercised" mean the converted step concluded `success` in the run's jobs JSON, not that the run concluded `success` (a skipped or no-op step makes a green run). Bound the probe's API calls and total budget against the shared sweeper job.
- Where an inline copy must stay byte-pinned, put the missing pre-processing at the call site (an ASCII-only trim of both ends for the credentials the library trims, never the HMAC key) and PIN IT: derive the population of steps that define the inline guard and declare the secret from the YAML, and require the trim before the definition.
- For failure messages on a call whose failure can follow a sent request, print one honest message for every exit code (what the marker means if present; otherwise "the request may have reached the host, check status before re-running") and keep the exit code; do not branch on an ambiguous exit code.
- Add an executed row for every new alert arm (the `credential_refused` output mapped to the existing `ungraded` class had only a reference-count pin: deleting it, comparing a different literal or moving it behind the empty-frame arm all stayed green).

## Key Insight

The verification layer of a conversion PR is where its defects live: a probe, a guard exemption, a message, an allow-list. Each reads as bookkeeping while it is written, so it is the least-audited surface, and its failure mode is silence (a probe that cannot pass, a guard that cannot fail, a message that names an unmeasured cause). Before shipping any probe or guard added alongside a conversion, drive it against a REAL artifact of the thing it reads (a real log, a real jobs JSON) and against the shape the conversion itself produces.

## Session Errors

1. **Plan subagent returned no Session Summary** — Recovery: the plan with Acceptance Criteria and Research Insights was on disk; wrote session-state.md from it — Prevention: one-shot's partial-artifact recovery already covers this; no change.
2. **`pgrep -f` denied by the self-match hook** — Recovery: re-ran without it — Prevention: already hook-enforced (pkill-self-match-guard); use `pgrep <name>` or a captured PID.
3. **Sent a measurement-amendment message to the wrong agent id** — Recovery: re-sent to the right one — Prevention: record the id-to-job mapping when spawning several agents in one message.
4. **A wave-1 agent added a second `: > "$STATUS_RESPONSE"` site and reddened the fixture-relative ratchet** — Recovery: moved the pre-guard's action behind the loop's existing truncation site — Prevention: when a ratchet counts sites, brief the agent with the ratchet's name; fix the code, never the baseline.
5. **decision-challenges.md still named the sparse-checkout default after plan D4 flipped to inline** — Recovery: rewrote item 3 — Prevention: re-read every artifact that restates a decision whenever the plan's decision changes.
6. **Lint suite's ceiling "raise" mutation went vacuous after the baseline shrink** — Recovery: raise to ceiling+1 instead of count+1 — Prevention: a mutation row that changes a value by a fixed delta must be re-derived whenever the data it mutates changes; the gate run caught it.
7. **First probe false-FAILed on echoed `run:` source (P1)** — Recovery: anchored on the emitted line, added a suite with a real-shaped log fixture — Prevention: route to the follow-through convention (below); drive every new probe against a real log before filing its tracker.
8. **Inline copies lost the library's trim; first trim was trailing-only and locale-dependent** — Recovery: ASCII-only both-ends trim loop at the call sites plus a derived population row — Prevention: when a guard is copied inline, diff its pre-processing against the library's and pin the difference.
9. **Trigger messages overclaimed; rc==2 branch contradicted plan D5** — Recovery: one message for every exit code, exemption removed — Prevention: never branch on an exit code a second tool also uses; state only what the marker proves.
10. **Manifest regeneration swept six unrelated suites' rows into the diff** — Recovery: restored both manifests and added only this PR's rows — Prevention: use the incremental regeneration as a diff to read, not a write.
11. **Foreground gate batch exceeded the 600 s limit** — Recovery: let it move to the background and read its output file — Prevention: split long suites across calls.

## Tags
category: workflow-issues
module: argv-credential-sweep
