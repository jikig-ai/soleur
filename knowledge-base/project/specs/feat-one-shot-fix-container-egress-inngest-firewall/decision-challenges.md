# Decision Challenges — feat-one-shot-fix-container-egress-inngest-firewall

Persisted at deepen-plan (headless). `ship` renders these into the PR body and files an
`action-required` issue so the operator sees the correction.

## Challenge 1 — the task's delivery-path premise was factually wrong (corrected)

**Class:** upstream technical-fact correction (verified against the repo at deepen-plan).

**What the task/pipeline stated:** "`cron-egress-nftables.sh` is NOT in the merge-triggered
auto-apply `-target` set, so merging does not push it to running hosts — it lands when web-2/web-1
are recreated. Merging does not fire `apply-web-platform-infra.yml` (cron-egress-nftables.sh is
not a `.tf` file)."

**What is actually true (evidence):**
- `apply-web-platform-infra.yml:69-70` triggers on the **path-glob** `apps/web-platform/infra/**`,
  NOT `*.tf`. All three edited files match → **merging fires the workflow.**
- `terraform_data.cron_egress_firewall` **is** in the merge-triggered `-target` set
  (`apply-web-platform-infra.yml:593`) and folds `cron-egress-nftables.sh` into its `config_hash`
  (`server.tf:1074-1088`).
- Editing the loader changes the hash → the resource **replaces** → its `remote-exec`
  re-provisions **web-1** (`server.tf` `host = hcloud_server.web["web-1"]`) and restarts the live
  `cron-egress-firewall.service` (`cron-egress-postapply-assert.sh:48`), installing
  `10.0.1.40:8288` into the **live** nft ruleset on web-1 on merge.
- The plan's own test asserts the target is present: `cron-egress-firewall.test.sh:138`.

**Operator-visible impact:** merging this PR is **not** a no-op on running hosts — it restarts
the production egress firewall on **web-1** and makes the new rule live there immediately. This
is **zero-downtime and safe** (the loader is gap-free: it resolves allowlist sets before flushing
and `die`s before flush if resolve fails, leaving existing rules intact; and the rule is inert
until `INNGEST_BASE_URL` repoint #6348). **web-2** gets the rule only on its next recreate. The
code change is unchanged; only the delivery narrative was corrected.

**Disposition:** plan corrected in place (Downtime & Cutover, Infrastructure (IaC), Delivery
Context, Research Reconciliation, AC8/AC9). No scope change. Surfaced here so the operator is
aware the merge touches the live web-1 firewall.
