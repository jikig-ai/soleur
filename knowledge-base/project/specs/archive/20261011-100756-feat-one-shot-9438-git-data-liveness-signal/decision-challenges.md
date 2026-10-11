# Decision challenges - feat-one-shot-9438-git-data-liveness-signal

Persisted by the headless plan run (ADR-084). Each entry is a decision the plan took that the owner may overturn. The plan's default
is stated first. `ship` renders this file into the PR body and files the `action-required` issue.

## 2026-10-10 plan run

### DC-1 (Taste) When #9438 closes

- **Plan default:** `Refs #9438` on the payload PR and on the evidence-only PR; `Closes #9438` on the dependent record PR that lands
  after the owner's replace and the measured first beat.
- **Alternative:** put `Closes #9438` in the evidence-only PR body (the only other defensible carrier; Guard 4 restricts the PR to one
  file but not its body).
- **Why the default:** closing earlier asserts an acceptance nobody observed; the registry heartbeat sat inert for nine days after it
  shipped unarmed (#6537).

### DC-2 (Taste) Bundle scope for #8093

- **Plan default:** bundle only the two comment-only pre-receive fixes into the payload PR; hold out the `AuthorizedKeysFile` move
  (moves a literal five birth-gate arms key on; its own note calls it its own hash-bound change) and the `gc_timer` paging policy
  (the owner's policy call).
- **Alternative:** bundle `AuthorizedKeysFile` too, accepting a larger birth-gate edit in the PR that gates the cutover. The CTO review
  noted the pre-cutover replace is a planned second replace anyway, so "replace once" is not a reason to bundle it.

### DC-3 (Taste) `push` on the new monitor

- **Plan default:** create with `push = false`, like `git_data_prd`; no later flip (eng panel: the flip is unrelated to the ask and contradicts "no per-monitor push").
- **Alternative (COO recommendation):** flip `push = true` in the dependent record PR as a measured change per ADR-260. The eng panel
  (DHH, code-simplicity) judged the flip unrelated to the ask and contradicting "no per-monitor push"; email plus the account-level
  Slack integration already satisfy the alert-route property.

### DC-4 (Taste) Alert-route delivery evidence

- **Plan default:** the dependent record PR cites one Better Stack incident delivered to the Slack channel since ADR-260, read-only.
- **Alternative:** drop it (it tests ADR-260, not this change) or require a throwaway-monitor absence test (a vendor-side production
  write). CPO asked for a proof; simplicity asked to cut it.

### DC-5 (User-Challenge, default stands) Check set

- **Brief and issue text:** "a dead sshd, a full disk or a failed unit". The eng panel (DHH) suggested cutting `ssh`, `store_not_mapper`,
  `root_full` and `unit_failed`.
- **Plan default (mostly kept):** the ssh check stays but reads the loopback banner (the web probe's TCP connect does not prove sshd
  works under `ssh.socket` activation, and a unit-state check would false-fail an idle host); `store_not_mapper` stays (the ADR-239
  "never serve a plaintext device" invariant); `unit_failed` stays (named in the issue). `root_full` was changed to report-only
  (`root_pct` on events, no gating) because its threshold is an unmeasured guess in a hash-bound payload.

### DC-6 (Taste) Soak length

- **Plan default:** at least four consecutive `state=ok` summary events spanning at least 30 minutes, and no other state after the
  first, on the replaced host before arming; the owner may lengthen it.
- **Trade-off:** a longer soak widens the replace-to-flip interval that ADR-220 D6 wants short.

### DC-7 (Taste) Where the arming modes live

- **Plan default:** `--status` and `--arm-one` ship in a small second PR (1b) that lands before the owner's replace.
- **Alternative:** fold them into the payload PR (simplicity and DHH would instead drop `--status` or both and call the existing
  `arm_one` from the runbook). The cost of folding in is a larger diff; the cost of dropping is an untested ad-hoc arm.
