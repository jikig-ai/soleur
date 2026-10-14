# Decision challenges: argv-bearer sweep S5 (#9597)

Persisted by the headless plan run (ADR-084). Each entry states the default the plan took and the alternative, so `ship` can render them into the PR body and file the action-required issue.

## 2026-10-11 DC-1: the registry rows convert in S5 and the merge delivers by an automatic host replace

- **Operator direction:** "S5 must take the remaining 4 files / 11 sites to the final target." and the tracker's S5 line: `cloud-init-registry.yml` (4 sites, inline form; the plan must show no host replacement).
- **Measured:** editing a code line of `cloud-init-registry.yml` changes the rendered user_data of `hcloud_server.registry` (no `ignore_changes`), and `registry-host-replace-dispatch.yml` fires on the merge and dispatches the replace after a read-only preflight, with no reviewer gate. "No host replacement" cannot hold.
- **Default taken:** convert the rows, keep them in one commit, stop for explicit approval before the merge, do not arm auto-merge until approved.
- **Alternative:** drop that commit; the four registry rows stay in baseline E under a new tracker that owns a maintenance-window delivery; `Closes #9597` still holds because every remaining row is owned by tracked work.
- **Cost of the default:** one pull-path outage window fired by a merge. **Cost of the alternative:** the Logs ingest token stays on argv on the registry host until that tracker lands.

## 2026-10-11 DC-2: the two cla-evidence rows stay under #9756

- **Operator direction:** "S5 must take the remaining 4 files / 11 sites to the final target."
- **Default taken:** the two rows (R2 SigV4 `--user` pair, legal-evidence upload path with its own suites) stay baselined with an owner comment naming #9756, which is the tracker's own close condition.
- **Alternative:** fold both into S5 so baseline E is empty, at the cost of a legal-record change in a last-and-alone production slice.

## 2026-10-11 DC-3: split the registry file into its own PR (DHH, plan review)

- **Operator direction:** "Do ONE slice per PR: S5 only, and stop there." and the tracker's definition of S5 as one last-and-alone PR carrying the only `Closes`.
- **Default taken:** one PR, with everything registry-specific in the last commit (C3) so it can be dropped or split off without rework.
- **Alternative:** ship the workflow conversion and the baseline now (S5a), and the registry file as its own PR (S5b) with its own approval, so the host replace is never a side effect of a security sweep merge. Cost: two PRs for one slice and a window where baseline E holds a registry row with only a tracker line as owner.

## 2026-10-11 DC-4: no new follow-through script for S5's first runs (DHH, CTO, simplicity at plan review)

- **Operator direction:** "Measure what you can without SSH, and report plainly what you could not."
- **Default taken:** read the evidence that is certain to occur in Phase 5 (the merge's own dispatched `registry_host_replace` run, the new host's rows, the release arm), and record the three dispatch-only jobs as a comment on #9905, whose probe scans apply-workflow run logs. No new probe, suite or tracker.
- **Alternative:** a new probe and tracker modelled on the S4 one for every converted site, at the cost of a script, a suite, a `secrets=` wiring and a wait budget that the dispatch-only jobs may never satisfy.
