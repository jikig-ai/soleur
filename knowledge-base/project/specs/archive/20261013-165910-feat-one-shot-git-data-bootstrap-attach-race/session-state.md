# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-13-fix-git-data-bootstrap-volume-attach-race-plan.md
- Status: complete
- cto_spawns=1

### Errors
None. Two decision-challenges rows were rewritten to pass the technical-ruling gate (a category name and a ruling shape).

### Decisions
- One shared wait helper at the plaintext link (bound a literal 300 s, 30 passes of `sleep 10`) plus the first-boot LUKS wait in the cloud-init heredoc (300 counted passes, one settle after the loop). The env seam, the section-1 LUKS wait and the in-loop settles were deleted in the review round (see Review Phase).
- Boot budget fits with no workflow change (apply blocks on the attachments; post-attach tail at most about 56 s measured).
- Rehearsal harness gets staggered rehearsal-only attach delays so the paid rehearsal exercises both waits.
- Rung-2 evidence goes stale on the edit: a fresh rehearsal run and an evidence-only PR are needed, each dispatch needing the operator's go-ahead naming the command.
- Recovery needs a new server; order is fix PR, rehearsal, evidence PR, then rotate (or a plain replace first if #10207 merged as drafted).

### Components Invoked
soleur:plan, soleur:deepen-plan, soleur:engineering:cto, code-simplicity-reviewer, architecture-strategist

## Review Phase
- 10-seat panel at PANEL_SHA 43a0b34e1f plus a simplicity pass; one more CTO ruling (four forks, recorded in `decision-challenges.md`).
- Fixed inline: the loopback suite lacked the helper (HIGH, CI-gated); counted time was about half of real time; the FATAL did not name the measured state; a post-loop settle before `luksFormat`; probe timeouts; crash-credited-as-kill mutation rows; heredoc loop pins; ledger labels and wrong issue refs.
- CTO ruled: delete the section-1 LUKS wait, the `GIT_DATA_ATTACH_WAIT_S` seam and the in-loop settles; prune the test matrix. Implemented.
- Not run here: the loopback suite (needs sudo; CI runs it), the paid rehearsal and every dispatch.
