# Learning: a merge that edits the registry's cloud-init auto-replaces the registry host, and the plan and its reviews checked only the apply workflow

## Problem

PR #12379 (#12007, periodic `SOLEUR_HOST_KERNEL` marker) edited `apps/web-platform/infra/cloud-init-registry.yml` to add the collector and a once-per-6h call. The plan, the CTO rulings and the first architecture seat all stated that a merge installs nothing on a running host and cannot replace the registry or inngest host, because neither appears in a per-merge `-target` list of `apply-web-platform-infra.yml`.

That claim was true of ONE workflow. A second workflow, `registry-host-replace-dispatch.yml`, fires on a push to main touching `cloud-init-registry.yml`, `zot-registry.tf` or `variables.tf`; when the offline-rendered registry `user_data` differs from the merge base it emits `deliver=true` and runs `apply_target=registry-host-replace` with no reviewer gate and no confirm token (ADR-190: "the merge IS the intent to deliver"). Merging the PR would have replaced the production registry host, the sole image pull path, with no rollback if the create failed after the destroy. The operator's standing constraint for the run was no production-mutating step without an explicit per-command go-ahead. It was found only at the fix-round code-quality seat, after three full review rounds, by a seat that read the registry dispatcher's `on.push.paths`.

## Solution

- CTO ruling: remove the registry delivery from the PR (revert `cloud-init-registry.yml` to the merge base), keep the collector's `--role registry` support, the helper and feeder registry decode, and the paused `host-kernel-registry` heartbeat. Ship the registry emitter in a separate, owner-approved PR tracked in #12386. Registry kernel evidence stays honestly `unknown` until then.
- Guard 3 marks registry as an `exempt` class keyed to #12386 and a ratchet (`STALE-REGISTRY-EXEMPTION`) goes red if the collector appears in `cloud-init-registry.yml` while the exemption stands, so the follow-up must flip it on purpose.
- Verified the dispatcher's own gate would now emit `deliver=false`: `git diff <merge-base> -- cloud-init-registry.yml zot-registry.tf variables.tf registry-userdata-budget.sh` is empty and the offline render is byte-identical to the merge base.

## Key Insight

"A merge does not apply X" is a universal claim over EVERY workflow whose `on.push.paths` matches a changed file, not over the one workflow the author was reading. For any diff touching `apps/*/infra/**`, enumerate the workflows by their trigger (`grep -l` the changed basenames across `.github/workflows/*.yml`, read each `on:` block) and state what each does on merge, before any sentence says a merge is inert. An ADR that says "the merge IS the intent to deliver" for a path is a hold-breaker for any run that must not mutate production.

## Session Errors

1. **Merge-time claim checked against one workflow** — the plan, rulings and the first architecture seat said a merge replaces nothing; the registry dispatcher contradicts it. Recovery: code-quality fix-round seat found it; CTO ruled Option A. **Prevention:** the plan skill's Sharp Edges now requires enumerating every workflow whose `push.paths` matches the changed files before a plan states what a merge does.
2. **Heredoc-opener literal inside a test's own sed pattern** — a Guard 3 pattern containing the text `<<'HKMSCRIPTEOF'` in `host-state.test.sh` made `guard-vacuity-floor.test.sh` treat the rest of the file as a heredoc and score the suite non-floor-bearing. Recovery: wrote the pattern as `<<.HKMSCRIPTEOF`. **Prevention:** never spell a heredoc opener as a literal in a test file; the vacuity guard reads it as one.
3. **Census anchored on a token a later batch removed** — Guard 3 grepped `host_kernel_marker_gz_b64`; the inline-collector change deleted the variable and the combined verification caught it. Recovery: re-anchored on the `- path:` entry. **Prevention:** after a fix batch that deletes a token, run the combined suite list before commit (done) — one-off.
4. **Row-shape failures in `decision-challenges.md`** — `technical-ruling-gate.sh` rejected rows lacking `Ruled by CTO agent, <date>:` and a non-closed operator category. Recovery: rewrote rows. **Prevention:** run the gate right after the plan subagent returns (done).
5. **Disk quota exhausted on the Claude temp volume** — `/tmp` tmpfs filled (review sandboxes and logs), every tool call failed with EDQUOT until the operator freed space. **Prevention:** keep review scratch under `/var/tmp` and remove sandboxes with `scripts/soleur-sandbox.sh rm` as each seat returns.
6. **A blocked `git stash list`** — a probe I appended tripped the stash hook; the hook did its job. One-off.
7. **A seat returned nothing and wrote no file** — the structural-enumeration seat ended after "make no further tool calls"; resumed once and delivered. **Prevention:** put "final message IS the deliverable; also write the report file" in the SPAWN prompt (done for later seats).
8. **Stop-hook rejections of forward-looking closings** — three turns ended naming an action instead of a labelled Paused/Blocked sentence. Recovery: used `Paused:`. One-off.

## Tags
category: integration-issues
module: infra/registry-delivery
