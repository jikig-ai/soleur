# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-12-fix-argv-bearer-sweep-held-back-sites-htpasswd-and-inspect-evidence-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking (see plan Session Summary: three gh issue create calls refused by the filing hook until body files were written first).

### Decisions
- Registry host replace (C6): operator ruled 2026-10-12 "Separate PR after this one". This PR EXCLUDES the cloud-init-registry.yml htpasswd conversion (B1/B2) and its suites/battery rows/ADR text; follow-up PR right after. Apply-workflow htpasswd line (C2) stays in.
- C1 (inngest-bootstrap.sh): peel if PR 10073 has not merged when implementation reaches that commit; otherwise keep.
- C3-C5: plan defaults kept.
- Merge needs explicit operator approval (web-platform release, push apply re-delivering probes to web-1, possible inngest tag mint). Never dispatch a production apply.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan

## Work Phase (2026-10-12)
- C1 outcome: the inngest-bootstrap.sh heartbeat commit was PEELED from this PR and kept on the local side branch keep/9757-inngest-heartbeat-argv (sha b48247d559). Reason (measured by slice 4): editing inngest-bootstrap.sh makes cloud-init-inngest-bootstrap.test.sh GuardA red by design until the minted tag and pin bump merge, so the commit cannot be green inside this PR. It ships as its own PR; #9757 item 2 stays partly open (Ref, not Closes).
- C6 outcome: registry template (B1, B2) excluded per the operator ruling; the S6 htpasswd row carries the two registry files as a residual allowlist that the follow-up PR deletes.
- Slice commits so far: inspect-evidence xtrace refusal; linkedin write-env + canonical HMAC docs; held-back HMAC arms + census + leads (a)(b)(g); workflow htpasswd + S6 + htpasswd-stdin suite; heartbeat URLs for web-git-data-probe and luks-monitor.
- Slice 4 deviation to record in the ADR addendum: the heartbeat curls use --disable --noproxy '*' (lint Rule D forces it) instead of the plan's -q-only; the plan's text saying otherwise is superseded.
