# Learning: a text pin over published legal prose counted lines and fragments, and the fix rounds reproduced the gaps they closed

## Problem

PR #12438 (founder-acceptance-record follow-ups: published retention wording, a parked-hold required check, a counts RPC, an Inbox row) went through a 16-seat panel, two fix rounds of 10 seats, and a verification seat. Every round found defects in the previous round's fixes, not in the feature:

- `published-retention.test.ts` was the guard for the published Privacy Policy, GDPR Policy and DPD. Its first version pinned fragments page-wide, exempted history lines by line PREFIX, and counted LINES that carry the retired claim. The verification seat reintroduced the false claim five ways (an extra sentence on the branch-only Amended entry, an overtaken phrase in the same entry, "every event carries" for two clauses the pins never named, a 10-year sentence inside the retention line) and the suite stayed 57/57 green.
- The umbrella lint matched the bare text `continue-on-error:`. YAML also accepts quoted keys, list-item-first keys, flow style, `shell:`, `defaults:`, `BASH_ENV`, a constant verdict argument and an early `exit` before the aggregate tail. The second fix batch parsed the YAML but still skipped workflow-level keys and allowed `env` everywhere.
- A published sentence ("each event carries the name of the text") was the CLO's own ruling and was false for four event kinds. Three seats found it independently; the register addendum written in the same commit listed the fields correctly.
- An "anon-denial probe" meant to compensate for a skipped `verify-migrations` job was a GET that the route's bearer check answers 401 for whatever the grants are. Its replacement (an anon POST to the REST rpc endpoint) omitted `Content-Type` and counted 404 as PASS, so a broken REVOKE still printed PASS.
- `published-retention.test.ts` read outside `apps/web-platform` and was not in `REPO_WIDE_SUITES`; the combined-tree run, not the fix agent, caught it.

## Solution

- Pin the OCCURRENCE count of the retired claim (case-insensitive: the later entry quotes it mid-sentence in lower case), require every carrier to be a history line, and give the branch-only entry its own cap. Pin whole sentences (the retention core, the monitoring sentence) contiguous and verbatim, and forbid any other `<n> years` token on the retention line. Mutation-prove each escape in a sandbox copy with an unmutated control before and after.
- Parse the workflow YAML and allow-list job keys, step keys, top-level keys and env names instead of matching spellings.
- Make a vendor-behaviour claim in a runbook only after reading the vendor's reference. PostgREST maps SQLSTATE 42501 to 403 when a JWT is presented and 401 when none; 42883 (undefined function) is 404 and is inconclusive, never a pass.
- Register any suite that reads outside the app in `REPO_WIDE_SUITES`; register a suite that is both a `run_suite` and a workflow step in `DOUBLE_COVERED_ACK`.

## Key Insight

A pin on published prose is a guard with three axes (population, wording, position) and a first version nearly always covers one. Count occurrences, not lines; pin whole sentences, not fragments; make a prefix exemption a counted population. The same fix round that closes a class tends to reopen it one level up, so the verification seat's brief should be "reintroduce the claim and tell me which pin stays green", run against the fix batch rather than against the original.

## Session Errors

1. **CLO resume rejected by an API safeguard (`reasoning_extraction`)** — Recovery: spawned a fresh CLO agent with a full brief; it succeeded. Prevention: for a legal consult after a safeguard stop, spawn fresh with the reports attached instead of resuming; do not work the ruling myself.
2. **`published-retention.test.ts` was not registered in `REPO_WIDE_SUITES`** (introduced in the first commit of the PR, found only at the combined-tree run) — Recovery: added the entry. Prevention: the fix-agent brief already names this registry; add `git grep -n "readFileSync" <new test>` outside `apps/web-platform` to the self-check of whoever adds a test, and run `repo-wide-containment.test.ts` with every new test file.
3. **First retention pins let five mutations through** — Recovery: whole-sentence and occurrence pins, mutation-proven. Prevention: when writing a text pin, run the five shapes (append a sentence to a history line, change an unpinned clause, add a second period, move text into a history line, quote the claim twice) before reporting it done.
4. **Two pin assertions failed on first run** (line-count 2 vs 3 because of a lower-case quote; a re-pin run from the wrong cwd after `cd apps/web-platform`) — Recovery: case-insensitive count; `cd` back to the worktree root. Prevention: one-off; `cd <worktree>` at the start of every Bash call that uses repo-relative paths.
5. **A vendor-behaviour claim written from memory (PostgREST status for a revoked grant) was wrong in two places** — Recovery: read the PostgREST error reference via context7 and rewrote the PASS set (403 or 401; 404 inconclusive; `Content-Type` header). Prevention: a runbook probe that names an HTTP status needs the reference read in the same session, and its PASS set must exclude any status a broken control could also produce.
6. **The double registration of `ci-parked-hold.test.sh` (`run_suite` plus a workflow step) failed `lint-orphan-test-suites.sh`** — only the guards agent noticed. Recovery: `DOUBLE_COVERED_ACK` entry with the reason. Prevention: the orphan lint is slow (over 120 s); run it by name after adding a workflow step that runs a `.test.sh`.
7. **Playwright browser install timed out twice (plain and host-override) and the nav-states gate died at `browserType.launch`** — Recovery: recorded INFRA-BLOCKED; the containerized CI `e2e` job is the authoritative gate. Prevention: none beyond the existing preflight; do not spend a third attempt.
8. **A leftover seat sandbox without a valid ownership marker** could not be removed by the sandbox tool — Recovery: left in place and reported. Prevention: brief seats to use the allocator, not `mktemp -d`, for mutation copies.
9. **The stop hook rejected two closing messages that named a next action** — Recovery: ended with a `Paused:` sentence naming the external wait. Prevention: when waiting on background agents, say so as the last sentence from the first draft.
10. **Round-to-round rulings contradicted each other on whether new public markers may carry an issue number** — Recovery: the fix-round CLO ruling settled it (drop `per #12011` from new markers; pre-existing ones stay byte-identical). Prevention: put "no issue numbers in new public annotations" into the standing ruling file, not into one round's reasoning.

## Tags
category: test-failures
module: legal-acceptance, ci-guards, review
