---
category: integration-issues
module: sentry-iac
problem_type: integration_issue
symptom: "A vendor endpoint returns 410, a re-probe minutes later returns 200, and the incident is closed as transient"
issues: [7590, 6636, 7634]
date: 2026-08-19
---

# A vendor brownout is not a flake, and the header said so all along

## Problem

On 2026-07-17 the Sentry Terraform root failed with `410 This API no longer
exists` on the legacy issue-alert read endpoint. The session re-probed, got a
clean plan, and wrote the conclusion into `versions.tf`:

> the 410 was transient — beta2 plans clean again now, so a terraform plan
> cannot observe it

That reading is what a **brownout** produces, and it is not distinguishable
from a flake by the evidence that session gathered. Sentry deprecated the
alert-rule API family on **2026-05-14** and serves it on a recurring schedule:
410 for a window, 200 the rest of the time. A follow-up probe minutes later
returns 200 whether the endpoint was restored or merely outside its next
window. Both readings fit; the session picked the reassuring one, and the audit
gate then presented as an intermittent red for months.

## The measurement

This is the part worth keeping. Inside a **single session** on 2026-08-19,
against the same prod org with the same token and no change on our side:

| Time (UTC) | `GET /api/0/projects/{org}/{proj}/rules/` |
|---|---|
| ~20:5x | **410** |
| 21:23:42 | **200** |
| 21:23:43 | **200** |
| 21:23:45 | **200** |

The 410 response carried the discriminator the whole time:

```
x-sentry-deprecation-date: 2026-05-14T00:00:00+00:00
x-sentry-replacement-endpoint: /api/0/organizations/jikigai-eu/workflows/
```

Nothing read those headers. They are also served **on successful responses**,
which is the important half: a 200 carrying `x-sentry-deprecation-date` is a
durable, always-available signal, whereas the 410 is only visible if you happen
to probe inside the window.

Two consequences that were not obvious before measuring:

- **The replacement is per-endpoint, not per-family.** `projects/{org}/{proj}/rules/`
  maps to `organizations/{org}/workflows/`; `organizations/{org}/alert-rules/`
  maps to `organizations/{org}/detectors/`. A brief that assumed one replacement
  for both would have mis-mapped metric alerts onto the issue-alert replacement.
  Take the mapping from `x-sentry-replacement-endpoint` per endpoint, never by
  analogy.
- **A retry cannot be the fix.** A retry long enough to swallow a brownout 410
  necessarily also masks a post-sunset 410 — the permanent case the gate exists
  to catch. Status-aware classification plus a header tripwire is the only
  shape that separates them.

## Solution

1. When a vendor 4xx/5xx "clears on re-run", capture the response **headers**
   before concluding transience — `curl -D -` or `-D <file>`, not just the body.
   Deprecation, sunset and replacement headers are standard-ish and free.
2. Treat a deprecation header on a **200** as the actionable signal. Wire a
   tripwire that warns on the first successful response carrying one, rather
   than waiting for the failure window to recur.
3. Never retry a `410`. `410`/`404`/`401`/`403` are permanent; retrying a 410
   converts a sunset into a flake, which is precisely the ambiguity that cost
   this repo an investigation.
4. Correct the record by **appending**, not editing. `versions.tf`'s dated
   measurement is left verbatim with a supersession note beneath it — the
   re-probe genuinely did come back clean, and deleting that would destroy the
   evidence that makes the misreading legible.

## Key insight

**One follow-up probe cannot distinguish "restored" from "outside the next
window", and the reassuring reading is the one that gets written down.** The
discriminator is not more probes — it is the response headers, which were
present on the very first failure and on every success since.

## Session Errors

- **I asserted a diagnostic gap I had already measured away.** I wrote that a
  brownout gives the operator "a bare `curl: (22)` and none of the new
  diagnostics" and sized ~25 lines of header-surfacing plumbing around that
  claim. My own probe, earlier in the same session, had printed
  `curl: (22) The requested URL returned error: 410` — `curl -S` prints the
  status. `code-simplicity-reviewer` caught it and the plumbing was dropped.
  **Prevention:** before writing a sentence about what a failure mode *does not*
  show the operator, scroll up to the run where you produced that failure mode
  and read what it actually printed.

- **I ran a linter without its baseline flag and briefly believed the output.**
  `python3 scripts/lint-shell-capture-exit.py` reported `207 NEW findings across
  64 files`. The canonical invocation is in `scripts/test-all.sh` and passes
  `--baseline scripts/lint-shell-capture-exit.baseline.txt`, which reports
  `0 new, 207 baselined`. **Prevention:** for any repo linter, read its
  registration site (`test-all.sh`, the workflow that runs it) for the exact
  invocation before interpreting its output — a bare run of a baselined linter
  reports the whole backlog as new.

## Related

- `knowledge-base/engineering/architecture/decisions/ADR-031-sentry-as-iac.md`
  §Amendment 2026-08-19 (#7590) — the endpoint mapping and header provenance.
- #7634 — the two scripts still on the deprecated **write** path; blocked on the
  replacement's payload shape, not on typing.
- #4781 — open recurrence guard whose target field moved with this migration.
