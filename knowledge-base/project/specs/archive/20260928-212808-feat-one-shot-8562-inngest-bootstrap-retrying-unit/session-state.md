# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- First plan Write blocked by the IaC write-guard (prose mentioned systemd); terraform-architect reviewed the routing (units via cloud-init write_files) before the ack was added.
- Provenance line numbers first pinned to f1f2336156 but measured on merge-base 7bc9bde2db; corrected.
- BASELINE_DECLARED_PROBES ratchet red on the branch until work task 1.1 bumps it 34 -> 35.

### Decisions
- One PR, delivered dark, no split. Squash commit must carry `[skip-web-platform-apply]` on its own line so apply-web-platform-infra.yml's apply job skips; no hcloud_server target is in the push-apply set regardless. hcloud_server.inngest ignores only ssh_keys, so the re-rendered user_data lands only through the dispatch-gated inngest-host-replace.yml workflow and its op=resume leg (follow-through with an enrolled probe; PR body says `Ref #8562`, not Closes). The standard web-v* release of unchanged app code is the one unavoidable effect (same as #9134, #9071).
- Design: zot login + isolation check + pull -> bootstrap -> health move from runcmd into a script run by soleur-inngest-provision.service (unbounded retry every 120 s, empty latch file after success, no [Install], boot timer re-enters on reboot); runcmd enables the timer and starts the service non-blocking. No .tf, image carrier, sentry/** or workflow edits.
- Deepen: pause cutover-flip and LUKS-cutover timers before each bootstrap run; /mnt/data mount check withdrawn; follow-through probe anchors on cloud-init instance id; long children run `& wait`; xtrace refusal, per-attempt /tmp cleanup, Guard 8, Downtime & Cutover section, TimeoutStartSec derived (~45 min). 8 guards, 59 rows.
- #6985 not folded in (different host/file); EnvironmentFile= plus Guards 4 and 7 prevent recreating its token-loss class here. Forced-race rehearsal -> follow-up issue (needs a throwaway host); offline systemd-255-as-PID-1 container rehearsal (Tier B) in-PR.
- Follow-ups at ship: Sentry alert for non-pull provision failures; op=resume bootstrap-done check; SOLEUR-DEBT note on #6780.
- Post-planning collision re-probe: no PR linked to #8562; open PR #8945 touches cloud-init-inngest.yml but only the nftables comment (bot fix) — not a collision, possible textual conflict.

### Components Invoked
- soleur:plan, soleur:deepen-plan, plus the research/review agents and lints listed in the planning subagent's summary.
