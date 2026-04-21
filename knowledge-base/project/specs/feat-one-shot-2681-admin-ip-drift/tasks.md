---
feature: feat-one-shot-2681-admin-ip-drift
plan: knowledge-base/project/plans/2026-04-19-ops-admin-ip-drift-prevention-plan.md
issue: 2681
---

# Tasks: admin-IP drift prevention

Derived from the plan; organized by implementation order (runbook/learning first,
then skill scaffolding, then skill write path, then plan-gate, then AGENTS.md,
then deferral issues).

## 1. Setup

1.1. Read the plan end-to-end; confirm plan's `## Open Code-Review Overlap`
     grep returns no matches (or record disposition).
1.2. Verify CLI prerequisites are on PATH: `command -v hcloud doppler curl jq`.
1.3. Confirm `doppler secrets get ADMIN_IPS -p soleur -c prd_terraform
     --plain` works (auth check, not a write).

## 2. Runbook and learning entry

2.1. Create `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
     matching the `ssh-fail2ban-unban.md` template (YAML frontmatter, Symptom,
     Diagnostic Decision Tree, Recovery Automated/Manual, Prevention).
2.2. Cross-reference `ssh-fail2ban-unban.md` from the new runbook AND add a
     pointer from `ssh-fail2ban-unban.md` to the new runbook (bidirectional
     index so an incident responder finds the right one by symptom).
2.3. Create `knowledge-base/project/learnings/bug-fixes/<topic>.md` (date
     picked at write-time per AGENTS.md sharp edge "do not prescribe exact
     learning filenames with dates in tasks.md"). Topic:
     `admin-ip-drift-misdiagnosed-as-fail2ban`. Include: what happened, why
     it happened, what we changed, how to prevent.
2.4. `npx markdownlint-cli2 --fix` on the two new `.md` files (targeted
     paths only, per `cq-markdownlint-fix-target-specific-paths`).

## 3. Skill scaffolding (`admin-ip-refresh`)

3.1. Create directory `plugins/soleur/skills/admin-ip-refresh/` and nested
     `references/`.
3.2. Create `SKILL.md` with YAML frontmatter (`name: admin-ip-refresh`,
     `description:` third-person under ~30 words, no example blocks). Body:
     intro, sharp edges, 8-step procedure summary, link to
     `[procedure](./references/admin-ip-refresh-procedure.md)`.
3.3. Create `references/admin-ip-refresh-procedure.md` with the detailed
     procedure (detect → read → diff → warn → ack → write → apply-emit →
     verify).
3.4. Add `--dry-run` flag semantics to the procedure (steps 1-4 only, no
     writes).
3.5. Run `bun test plugins/soleur/test/components.test.ts` to confirm skill
     description token budget is preserved.
3.6. `npx markdownlint-cli2 --fix` on the two new skill `.md` files.

## 4. Skill write path

4.1. Implement the Doppler read step (step 2) with JSON list parse and
     missing-secret abort.
4.2. Implement the diff step (step 3) with "no drift" and "drift" branches.
4.3. Implement the list-length warnings (step 4): P1 on length 1
     (`understood` ack), P2 on length > 10 (continue).
4.4. Implement the operator ack prompt (step 5) with explicit show-the-
     command-then-wait semantics. NO `--yes`, NO `--force`, NO auto-approve.
4.5. Implement the Doppler write (step 6) via `doppler secrets set ADMIN_IPS
     -p soleur -c prd_terraform` from stdin JSON list. Verify by re-reading.
4.6. Implement the `terraform apply` emission (step 7) -- print the exact
     nested-Doppler form from `apps/web-platform/infra/variables.tf:1-13`.
     Do NOT execute.
4.7. Implement the verify step (step 8, `--verify` flag): re-run steps 1-3
     only.

## 5. Plan-skill integration

5.1. Create `plugins/soleur/skills/plan/references/plan-network-outage-checklist.md`
     (checklist body from the plan's Phase 3 specification).
5.2. Edit `plugins/soleur/skills/plan/SKILL.md` -- add Phase 1.4 that reads
     the checklist when the feature description matches the network-outage
     regex; require the checklist's output in `## Hypotheses`.
5.3. Edit `plugins/soleur/skills/deepen-plan/SKILL.md` -- add parallel
     "Network-Outage Deep-Dive" step when applicable.
5.4. `npx markdownlint-cli2 --fix` on changed plan/deepen-plan `.md` files.

## 6. AGENTS.md rule

6.1. Edit `plugins/soleur/AGENTS.md` -- add new Hard Rule
     `hr-ssh-diagnosis-verify-firewall` under `## Hard Rules`. Rule body under
     600 bytes; `**Why:**` one sentence pointing to #2681.
6.2. Run the compound step 8 budget check (bytes, rule count).
6.3. Grep repo for any other references that would need the new rule id
     (`.claude/hooks/`, tests, docs/workflows) -- none expected for a new
     rule, but verify per AGENTS.md sharp edge.

## 7. Testing

7.1. Manual test (operator): run `/soleur:admin-ip-refresh --dry-run`
     against prod Doppler and firewall. Expect "No drift" output.
7.2. Manual test (contrived): inject a bogus CIDR into Doppler (ack-gated),
     run the skill, confirm it detects drift AND stops at the operator ack
     gate. Revert the bogus CIDR.
7.3. Manual test: craft a plan-input markdown containing "SSH kex reset" in
     the Overview; run `/soleur:plan` against it; confirm `## Hypotheses`
     section includes an L3 firewall-allowlist entry.

## 8. Ship prep

8.1. Multi-agent plan review (DHH, Kieran, Code simplicity) -- applied in
     Phase 1 of this pipeline before the plan was committed.
8.2. File deferral issues for:
     (a) Cloudflare Access for SSH migration
     (b) Auto-prune `ADMIN_IPS` entries older than 90 days
     (c) Scheduled ADMIN_IPS-vs-firewall drift check
     Each issue must include re-evaluation criteria and milestone "Post-MVP /
     Later" (per `cq-gh-issue-create-milestone-takes-title`, use title).
8.3. PR body includes `## Changelog` section; apply `semver:minor` label
     (new skill). Use `Closes #2681` in PR body, not title.
8.4. Post-merge: re-run `/soleur:admin-ip-refresh --dry-run` against prod
     to verify the production deployment works.

## Dependencies

- Task 4.x depends on 3.x (skill scaffold before write path).
- Task 5.2/5.3 depend on 5.1 (checklist file before skill references).
- Task 6.1 depends on 2.x (rule `**Why:**` points to the learning file --
  file must exist first OR rule points to the issue number).
- Task 8.4 depends on merge (post-merge verification).
