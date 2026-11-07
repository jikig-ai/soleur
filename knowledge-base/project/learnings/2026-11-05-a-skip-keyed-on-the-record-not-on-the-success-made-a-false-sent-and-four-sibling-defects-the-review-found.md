# Learning: a skip keyed on the record, not on the success, made a false "sent" (PR-C of #12011)

## Problem

PR #12148 (the web card and email-code check for a founder's legal acceptance) went through an
eleven-seat review and two targeted fix rounds. No P1 was raised. The P2s fell into five shapes, and
the second round introduced one of them.

1. **A skip keyed on the wrong proof.** Round 1 made the send step skip the email when the database
   reported `reused: true` for the intent. But the intent is opened BEFORE the email is sent. After a
   failed send (auth 5xx, a 429, a 422 other than the masked one) the intent stays live, so the retry
   was told "sent" and no mail went out. Five seats found it independently. The fix that closed the
   double-mail also created a state in which the screen says "a code is on its way" and none is.
2. **One limit, two units.** The note cap was moved to code points on the client and left at UTF-16
   units on the server. 600 emoji passed the card's counter and got a 400 from the route, shown as
   "Nothing was recorded" on every retry.
3. **A status map wider than the producer.** Every non-2xx reply read as "Nothing was recorded". A
   500 can follow a committed row (a `bad_payload` after the write, a timeout after commit, a gateway
   502 or 504), so the screen could say nothing was recorded about a legal record that exists.
4. **A flag described as narrower than it is.** The routes read `approval-queue` with
   `workspaceId: null`, which keys on role only. The ADR and the card prose called it per-user. It is
   effectively global.
5. **Rate-limit side effects of a retry fix.** Making the next send after a failure a resend opened a
   new intent each time, so three quick clicks after an auth 429 spent the 3-per-15-minutes budget. The
   start-step button needed the same cooldown as the resend button, and a 403 reverify had to clear it.

## Solution

- Key a "skip because it was already done" branch on proof that the earlier ACTION succeeded, not on
  the existence of the record the action was meant to produce. Here: remember a failed send per user
  and key for the intent window (server), and have the client send `resend: true` after any failed or
  rate-limited send. A successful send clears the memory.
- Count the limit once with one function and call it in every layer. The server now uses
  `codePointLength`, the same function the card uses, against the same constant.
- Restrict the "nothing was recorded" statuses to the ones our own routes emit before a write
  (400, 401, 403 not reverify, 404, 413, 415). Everything else, including 408, 409, 429, 5xx, a
  network error, a timeout and an unreadable 2xx body, reads "reload to check".
- Write what the code does into the ADR: the flag is global, enabling it enables the approval gate for
  every workspace, and the only thing keeping the card dark for others is that no real text is
  committed.
- When a fix turns a failure into a retry, count the worst case against the server's budget (fail,
  resend, resend) and make the first-step control respect the same cooldown.

## Key Insight

A fix commit is the least audited surface in the diff, and the defect it adds is usually in the branch
it creates: a new "skip" is a new state, and its proof must be the success of the thing skipped.
Independent seats converging on one finding (five on the false "sent") is the signal that the fix, not
the original code, is where to look. Mutation runs by the test-design seat were what showed which
guards had no test that went red.

## Session Errors

- **The reused-intent skip produced a false "sent" after a failed send** (introduced in fix round 1)
  - Recovery: server `SendFailureMemory` plus a client `lastSendFailed` ref, and a test for each.
  - **Prevention:** in a plan or review, for every branch that skips work because a record exists,
    write down what proves the work happened and test the failed-work-then-retry sequence.
- **The note cap disagreed across layers** — Recovery: server counts code points.
  **Prevention:** when a limit is moved or re-counted, grep every consumer of the constant and add a
  cross-layer test with a multi-unit character.
- **"Nothing was recorded" was shown after a 5xx** — Recovery: narrow `rejected` to the statuses our
  routes emit. **Prevention:** a client map from status to "not written" must be checked against what
  the route can return AFTER a commit.
- **The flag was described as per-user** — Recovery: ADR text corrected. **Prevention:** read the key a
  flag lookup actually uses before writing "per user" or "per workspace".
- **A review seat ran `pkill -x python3`** and may have killed another seat's job. The guard hook blocks
  `pkill -f` only. **Prevention:** brief every seat to kill by PID, and name `pkill -x` as banned too.
- **One agent re-delivered the same report seven times** until `TaskStop`. **Prevention:** stop an agent
  whose report has been delivered once and that keeps notifying.
- **Carry-over (earlier segments):** a Playwright browser install hung for 2h40m (killed by PID, the
  nav-states gate recorded INFRA-BLOCKED); a gate script was called at the wrong path
  (`apps/web-platform/scripts/constraint-gates.sh`); the first three server tests did not run RED first.
  **Prevention:** bound installs with a timeout; resolve gate scripts with `ls` before calling.
- **Status counting error in my own narration** (said 10 of 11 seats were in when 9 were) and one
  stop-hook rejection for a first-person promise at the end of a turn. **Prevention:** count returned
  seats from the notification list, not from memory; end a waiting turn with a `Paused:` sentence.

## Tags

category: logic-errors
module: web-platform/legal-acceptance
