# Learning: a ruling applied wider than its consumers, and a test that could not isolate the clause it named

## Problem

PR #11622 (closes #11569, #11572) added an owner-draft UPDATE policy plus a column-narrowed grant on `public.messages`, and a batch of mutation-harness and card-copy fixes. A 14-seat review and a targeted fix round found about 91 items, none P1 in the original diff. The one P1 was introduced by a fix.

Four lessons:

1. **A ruling's wording is a hypothesis about consumers, not a spec.** A CTO ruling said to refresh the Today list "after a Discard, Dismiss or Send 200". Implemented literally inside the shared send hook, the refresh also fired for the GitHub and kb-drift cards, which deliberately stay mounted after Send to show the run panel (Stop, Undo, cost). The send route archives the draft and the list returns only `status = draft`, so the panel unmounted one round trip after the click. Two review seats found it independently; the ruled-on diff and every unit test were green, because the tests mocked the mutator and never rendered those cards after Send.
2. **`mutate(key)` revalidates; it does not drop.** The comments claimed the cached list was "dropped". Dropping an item needs `mutate(key, (items) => items?.filter(...), { revalidate: true })`. Passing explicit `undefined` data is not equivalent: the 3-argument form sets the data.
3. **A defense-in-depth policy clause cannot always be isolated by behaviour.** The `is_workspace_member` conjunct in the UPDATE policy is shadowed by the workspace-wide SELECT policy (an UPDATE's WHERE and RETURNING read through SELECT policies), so a removed member is denied with or without the conjunct. A behavioural "removed member" test passes either way. The conjunct is pinned by text (one per clause, no OR in any case), and the test says what it proves.
4. **A mock that ignores its filters certifies the absence of the filters.** The discard-route test's approval lookup returned the configured row whatever it was asked, so dropping `message_id` or `user_id` from the lookup stayed green. The fixture must behave like the table: return the row only for the message and user it belongs to.

## Solution

- Narrowed the refresh to the card that unmounts itself (Stripe's `onAcknowledgedArchive`), restored the shared hook byte-for-byte, and added `useRefreshToday(id)` doing an optimistic filter plus revalidate.
- Gave the Discard route an approval lookup (409 only while the message is still a draft, otherwise the zero-row 403), and a post-archive recheck that reports Sentry op `discard-send-race` so the accepted race has a detector.
- Pinned the lookup by message and user in the mock, the policy clauses by captured text, and each card's refresh behaviour by a per-card test (Stripe drops, GitHub and kb-drift do not touch the list).
- Recorded rulings D20–D30 in the PR's decision file; two CTO rulings were corrected by later evidence (D21's "Send resolves that state" premise, D22's Send arm).

## Key Insight

When a ruling or plan says "do X after every Y", enumerate the consumers of Y before putting X in the shared path, and write the test for the consumer that must NOT do X. The cheapest check is one question per card or caller: "does this one unmount, or stay?" A test for what must not happen is the only thing that catches an over-broad application.

## Session Errors

1. **Plan-phase (forwarded):** a `gh issue create` was denied by a hook until the body file was written in a separate step, and duplicate Monitor watchers added noise. Recovery: write the body first, then file; stop extra watchers. **Prevention:** already in the work skill (heredoc body in the same call as a hook-gated filing).
2. **`run-migrations.sh` refused to apply the unmerged migration to dev** ("NOT on origin/main"). Recovery: rolled-back dry run, then an in-transaction GREEN rehearsal of the tenant test; CI applies it on push. **Prevention:** none needed; the guard is correct. Note that the first push freezes the migration bytes, so get the SQL and its header right before pushing.
3. **`/tmp` was swept mid-session**, deleting my scratch log directory and turning every re-verification into a false red (`No such file or directory`). Recovery: moved logs to a `mktemp -d -p /var/tmp` directory. **Prevention:** the skill text already says long-lived logs go in `/var/tmp` or the worktree; the `mktemp -d -t soleur-run.$$.X` default lands in `/tmp`, so use `-p /var/tmp` for anything a later call reads.
4. **A "removed member" tenant test that could not isolate the conjunct it named** (lesson 3). Recovery: kept it as a behaviour row with an honest comment and pinned the text. **Prevention:** before writing a deny test for one clause, name a second layer that would also deny and say so in the test.
5. **Refreshed the Today list on every Send 200** (lesson 1). Recovery: narrowed to the Stripe card, restored the hook. **Prevention:** per-consumer test for what must not happen; read the ruling's consumers, not its wording.
6. **Comments said the SWR copy is "dropped"** (lesson 2). Recovery: real optimistic filter plus corrected comments. **Prevention:** falsify every causal sentence a comment adds with the library source or a probe.
7. **A test named "recheck failing" injected no error**, and a stale `nextResponse` leaked between card tests. Recovery: added a recheck-only error option and set the response explicitly. **Prevention:** after writing a test, flip its subject and confirm it reds; set module-level fixtures per test.
8. **`BASELINE_DECLARED_PROBES` went red in CI** because the plan's observability block declares `credentials_required`. Recovery: 88 to 89 with the required PLACEMENT/TRUTH/NO-SUBSTITUTE note. **Prevention:** already in `plan-sharp-edges.md`; the miss was mine, since no file-scoped selection reaches the ratchet. Run the plugin discoverability suite whenever a plan declares `credentials_required`.
9. **The local affected gate queued behind a sibling's run and expired unrun** (`budget-deferred`, rc 6). Recovery: targeted suites as the substitute, CI as the authority, stated honestly. **Prevention:** none; the contention banner was readable and correct.
10. **`pgrep -f` was blocked** by the self-match hook. Recovery: used the rc file and monitor. **Prevention:** already hook-enforced.
11. **Review findings on migration 181's comments could not be applied** because the file is byte-frozen once dev has it. Recovery: moved the corrections to the ADR bullet and the decision file. **Prevention:** proofread comment-level wording (sources of claims such as "174 snapshot of Supabase defaults") before the first push of a migration.
12. **The planner's `decision-challenges.md` failed the ruling gate** (bad ruling shape, a non-vocabulary operator category). Recovery: reworded to `Ruled by CTO agent, <date>: <decision> - <rationale>` and `operator (production-mutating)`. **Prevention:** run `technical-ruling-gate.sh --branch` at the end of the plan phase.

## Tags
category: workflow-patterns
module: dashboard-today-card, supabase-rls, mutation-harness
