---
title: "Run-log evidence preservation record for #11294 (Terraform random_id values printed in public Actions logs)"
status: record
date: 2026-10-31
updated: 2026-11-01
related: [11294, 10205]
related_prs: [11551, 11674]
---

# Run-log evidence preservation record (#11294)

## What this file is

Terraform printed `random_*` id key values into public GitHub Actions run logs (incident #11294;
redaction merged in #11551 and #11674). Before the affected runs are deleted, this file records what
was measured and what was removed, so the deletion leaves a count-level evidence trail. It carries
**counts, run ids, metadata and hashes only**. No log text and no value is reproduced here, and none
was read into this record.

## Census (measured 2026-10-29, scanned live from the run logs)

- Runs scanned: **1,433**, across **17 workflows**.
- Runs with at least one value-shaped line: **686** (**680 production**, **6 rehearsal** from `inngest-provision-rehearsal`).
- Value-shaped lines in those runs: **6,383** in total (counts only).
- Runs with no readable log (`NOLOG`): **16**. Those are the 16 unreadable logs listed under Known gaps.

Value-shaped hits by workflow:

| Workflow | Runs with a hit | Runs scanned |
|---|---|---|
| `apply-web-platform-infra` | 503 | 769 |
| `scheduled-terraform-drift` | 89 | 211 |
| `apply-deploy-pipeline-fix` | 88 | 101 |
| `inngest-provision-rehearsal` | 6 | 9 |

Value-shaped hits by job (a run can hit in more than one job, so job-rows sum to 692 for 686 runs):

| Job | Job-rows with a hit |
|---|---|
| `apply` | 570 |
| `drift-check (apps/web-platform/infra)` | 89 |
| `web_host_replace` | 13 |
| `rehearse` | 6 |
| `teardown` | 6 |
| `inngest_host` | 3 |
| `inngest_backstop_retire` | 3 |
| `vector_redeliver` | 2 |

Census file: `census-11294.tsv` (1448 data rows, columns `run_id, workflow, created_at, job, id_lines,
random_addr_lines, secret_shaped_random_id_lines`). It is kept in the operator's scratch area and is
not committed, because it is a per-run map of where values were printed.

- sha256 (full): `6ba16467a5aa4ff432b306b91c7e5cee2cdcabaf1c78c61832eb4c7108e39744`

## Deleted on 2026-10-31

- **565 production** runs and **2 rehearsal** runs were deleted (567 in total), each live-checked as
  a completed run of `jikig-ai/soleur` immediately before deletion.
- **2 multi-attempt runs** (list C) were scanned and found **clean**, so they were not deleted and are
  not held.
- No comment, issue body, issue or PR was edited or removed on that date.

## Held: 119 runs, deleted on 2026-11-01 after this file merged

The remaining runs with value-shaped lines (115 production, 4 rehearsal = 119) were **held on
2026-10-31, not deleted**, because each is cited by a run id in a committed document or an open issue
and deleting the run would break the citation. This file merged first (PR #11721); all 119 were then
**deleted on 2026-11-01** (119 of 119 deleted, 0 skipped, each confirmed absent afterwards). The table
is their preserved metadata, and the citations stay resolvable as ids with this file as the record.
Citation basis: 112 cited by bare run id, 7 by run URL. "Citing location" is the first two files on
`origin/main` that name the run id (counted by file), measured 2026-10-31.

| Run id | Workflow | Conclusion | Head sha | Created at (UTC) | Citing location |
|---|---|---|---|---|---|
| 30623984560 | Apply web-platform infra | success | `d8e8e2f63796e59cf8e5b6faf9cabb14e7edc07f` | 2026-07-31T10:33:57Z | `inngest-host-no-cloud-firewall-8754-postmort`, `2026-09-25-8754-inngest-cloud-firewall-deter` (+2 more files) |
| 30649821431 | Apply web-platform infra | success | `2cd251885c7c2b499fbfe6f3eb6748fb76640fba` | 2026-07-31T17:05:54Z | `20261013-051752-2026-08-01-fix-web1-credenti` |
| 30650564509 | Apply deploy-pipeline-fix | failure | `3faa95fa89dad71683530456739071a522d6a715` | 2026-07-31T17:17:11Z | `action.yml`, `ADR-154-repair-the-credential-channel-not-th` (+5 more files) |
| 30653453432 | Terraform Drift Detection | failure | `3faa95fa89dad71683530456739071a522d6a715` | 2026-07-31T18:00:42Z | `scheduled-terraform-drift.yml`, `ADR-154-repair-the-credential-channel-not-th` (+3 more files) |
| 30686984837 | Terraform Drift Detection | failure | `3faa95fa89dad71683530456739071a522d6a715` | 2026-08-01T06:02:50Z | `scheduled-terraform-drift.yml`, `ADR-154-repair-the-credential-channel-not-th` (+3 more files) |
| 30688451196 | Apply web-platform infra | failure | `1e1634289dd1b8ca9adb65c1ed39621b56a9c36f` | 2026-08-01T06:48:27Z | `20261013-051752-2026-08-01-fix-web1-credenti` |
| 30735099570 | Terraform Drift Detection | success | `2579d2d7031a2701e3dba1c84653dd4ba0f363f4` | 2026-08-02T06:00:06Z | `spec` |
| 30811367645 | Apply deploy-pipeline-fix | failure | `701e76e6bfce84ceed91096a58d88df7da5b6932` | 2026-08-03T11:54:20Z | `infra-config-gate.test.sh`, `20261013-051752-2026-08-03-fix-infra-config-` |
| 31049971942 | Apply deploy-pipeline-fix | success | `43ccb4f14b28e347ed7a63229dde966958eb8a7c` | 2026-08-05T21:45:08Z | `20260820-143437-2026-08-12-fix-apply-verify-` |
| 31081679510 | Apply deploy-pipeline-fix | success | `9f1849d0495e7fbb39b9ad39c7e52ab6a0d4b51e` | 2026-08-06T07:38:07Z | `20260820-143437-2026-08-12-fix-apply-verify-` |
| 31636951749 | Apply deploy-pipeline-fix | failure | `0d644396066262b32884a2faec10e317857bea5e` | 2026-08-12T20:18:13Z | `apply-deploy-pipeline-fix.yml`, `infra-config-gate.sh` (+6 more files) |
| 31696609210 | Apply web-platform infra | failure | `19bbdb7689a8ae736ca996e612e797618509f042` | 2026-08-13T11:41:20Z | `web-platform-infra-apply-bridgeless-target-p`, `20260814-010601-2026-08-13-infra-vector-rede` |
| 31708799547 | Apply web-platform infra | failure | `c723e45192f7a2490c13a138582da7c4d6402973` | 2026-08-13T14:10:55Z | `20260814-010601-2026-08-13-infra-vector-rede` |
| 31714143720 | Apply deploy-pipeline-fix | success | `fe29d479b08fbd20a2bd49bbfe4779de12979acf` | 2026-08-13T15:12:19Z | `infra-config-verify.sh`, `ADR-189-the-infra-config-gate-may-write-prod` (+5 more files) |
| 31751479550 | Apply web-platform infra | failure | `5c85b1c3e9099aa78120b0df1cef6615126e5f36` | 2026-08-13T22:49:07Z | `20260817-013738-2026-08-16-fix-pushpath-brid` |
| 31950518641 | Apply web-platform infra | success | `72c79002c66804b766938539df5d999797a7ca42` | 2026-08-16T13:41:07Z | `20260817-013738-2026-08-16-fix-pushpath-brid` |
| 31952153708 | Apply web-platform infra | failure | `f78468e539e06b184407292954db00dbabdaf8ae` | 2026-08-16T14:15:00Z | `20260817-013738-2026-08-16-fix-pushpath-brid` |
| 31974987253 | Apply web-platform infra | failure | `0b4a446fce796a8554d69447b5915fd52a0bdd71` | 2026-08-16T21:57:21Z | `20261013-051752-2026-08-20-fix-apply-infra-f` |
| 31976455160 | Apply web-platform infra | failure | `173f7889b0eccf3a7093276cd66840e33bf4bc2b` | 2026-08-16T22:28:56Z | `web-platform-infra-apply-bridgeless-target-p`, `20261013-051752-2026-08-20-fix-apply-infra-f` (+1 more files) |
| 32279292256 | Apply web-platform infra | success | `b70f4928b39132f507ccf86c763be432bb2b1049` | 2026-08-19T17:01:57Z | `vector.toml`, `vector-redeliver` |
| 32283291074 | Apply web-platform infra | success | `45ea9f7e924c904a9ebb589598d86aa405601e5e` | 2026-08-19T17:43:55Z | `measurements` |
| 32288987090 | Apply web-platform infra | success | `76607d89cd4f2a0e532786f3b6f2322a824bccc4` | 2026-08-19T18:43:52Z | `measurements` |
| 32293304282 | Apply web-platform infra | success | `2d3bb0e51eac855eccbd6c1df982c1d71a015c52` | 2026-08-19T19:29:25Z | `vector-redeliver`, `20261001-161547-2026-10-01-fix-retier-apply-` (+1 more files) |
| 32318240780 | Apply web-platform infra | success | `5116247a4eb0c50eb863d743c6652c56273cf5f3` | 2026-08-20T00:41:20Z | `measurements` |
| 32356859661 | Apply web-platform infra | success | `5de88f2d8719394011e076a6610494ffde9bd49d` | 2026-08-20T10:01:36Z | `ADR-117-executable-heartbeat-arming`, `20261013-051752-2026-08-20-fix-apply-infra-f` (+1 more files) |
| 32360734255 | Apply web-platform infra | success | `5d88013849a3520f2a4707080441395f61639400` | 2026-08-20T10:48:38Z | `arm-heartbeats.sh`, `ADR-117-executable-heartbeat-arming` (+1 more files) |
| 34330222965 | Apply web-platform infra | success | `5c8f42a3cc175eda0fd83ef16fc537ccb88b598e` | 2026-09-09T08:38:26Z | `inngest-host-no-cloud-firewall-8754-postmort`, `2026-09-25-8754-inngest-cloud-firewall-deter` (+1 more files) |
| 34532702614 | Apply web-platform infra | success | `6921bd9a2bfd0f0cf8854ebb5edefde52e397c70` | 2026-09-10T21:32:01Z | `20260911-184315-2026-09-11-fix-resend-five-i` |
| 34662519329 | Apply web-platform infra | success | `3aa72044a951770e4b060148fa548d13430371ab` | 2026-09-12T00:42:21Z | `20260913-190954-2026-09-12-feat-betterstack-` |
| 34679740292 | Apply web-platform infra | success | `4c43c4eae3eb996e186920c2d3d02f838d05320a` | 2026-09-12T07:03:45Z | `20260913-190954-2026-09-12-feat-betterstack-` |
| 34838319053 | Apply web-platform infra | success | `463f56e0a7cf03f8ebd7b3c174fcac88e20add79` | 2026-09-14T11:27:42Z | `20260914-191548-2026-09-14-chore-git-data-po` |
| 34862300918 | Apply deploy-pipeline-fix | success | `a14992a79ac0d32b66705449aaf583751be95f36` | 2026-09-14T15:27:46Z | `20260914-223454-2026-09-14-fix-inngest-cutov` |
| 35431644262 | Apply web-platform infra | success | `58275d1ac332067394de4da2e12b785938372164` | 2026-09-19T08:18:24Z | `ADR-231-workflow-files-are-byte-budgeted-and`, `20260919-215833-2026-09-19-fix-ci-workflow-f` (+1 more files) |
| 35605929787 | Apply web-platform infra | success | `b53173a04e813ca11bb47b14ea4e89e129343064` | 2026-09-21T13:29:19Z | `ADR-142-inngest-redis-aof-zero-data-loss-luk`, `ADR-218-native-better-stack-logs-alerts-are-` (+5 more files) |
| 35824770896 | Terraform Drift Detection | success | `d1fe38939d0840b945c384c7380f818f5b68a32e` | 2026-09-23T06:00:18Z | `20261013-051752-2026-09-24-chore-sentry-root` |
| 35899473356 | Terraform Drift Detection | success | `b91dcf219b06612c4a1d2030349027231af763d5` | 2026-09-23T18:00:19Z | `20261013-051752-2026-09-24-chore-sentry-root` |
| 35912244388 | Apply web-platform infra | failure | `c7edc2c76fa30c96d6b8eaf568abfc5bdf69a563` | 2026-09-23T19:52:50Z | `ADR-096-migrate-container-registry-ghcr-to-s`, `web-fresh-boot-dark-tokenless-zot-read-postm` (+3 more files) |
| 35912754656 | Apply web-platform infra | failure | `2d974f8eef6f1fdbf750d4dd1b5f04a7baf7934d` | 2026-09-23T19:57:36Z | `infra-credential-tiers-8209`, `2026-09-24-a-line-scanner-is-not-a-lexer-and` (+1 more files) |
| 35921899265 | Apply web-platform infra | failure | `79e84ea1a064e74a253c7650dbcb4d082c66a85d` | 2026-09-23T21:21:14Z | `infra-credential-tiers-8209`, `2026-09-24-a-line-scanner-is-not-a-lexer-and` (+1 more files) |
| 35927849285 | Apply web-platform infra | failure | `afaec5d6e53f6f32fb1a87c4cd6d191c43a82baa` | 2026-09-23T22:21:08Z | `infra-credential-tiers-8209`, `2026-09-24-a-line-scanner-is-not-a-lexer-and` (+1 more files) |
| 35951193547 | Apply web-platform infra | failure | `81abd1bb30b471a42a8f2aa9843ee67385f43e86` | 2026-09-24T03:22:44Z | `infra-credential-tiers-8209`, `2026-09-24-a-line-scanner-is-not-a-lexer-and` (+1 more files) |
| 35951886838 | Apply web-platform infra | success | `81abd1bb30b471a42a8f2aa9843ee67385f43e86` | 2026-09-24T03:32:41Z | `ADR-096-migrate-container-registry-ghcr-to-s`, `zot-registry-revert` (+2 more files) |
| 35963237090 | Apply web-platform infra | success | `ca83c8edf02552803c0f298dddc8be7b5a00c3d0` | 2026-09-24T06:10:30Z | `infra-credential-tiers-8209`, `2026-09-24-a-line-scanner-is-not-a-lexer-and` (+2 more files) |
| 35976102312 | Apply web-platform infra | success | `c30991f602c9f98b8009853c48dc88c162851619` | 2026-09-24T08:35:09Z | `20261013-051752-2026-09-25-fix-web-platform-` |
| 35991817062 | Apply web-platform infra | failure | `5e4bd3744886ad68044da3ad586bd36af1f4c1a0` | 2026-09-24T11:14:00Z | `ADR-119-luks-at-rest-for-the-live-workspaces` |
| 36005279546 | Apply web-platform infra | success | `6f5b97523b3dfea798916c582ee3cc1a7e8450fa` | 2026-09-24T13:23:04Z | `web-probe-read-token.tf`, `ADR-119-luks-at-rest-for-the-live-workspaces` (+6 more files) |
| 36008843465 | Apply web-platform infra | success | `f4dfb8e1a77ce4e967c4a31acb877f38f14fac72` | 2026-09-24T13:53:42Z | `20261013-051752-2026-09-25-fix-web-platform-` |
| 36015201873 | Apply web-platform infra | success | `2426534dc6dff160bfac8152550d6ad9186ac664` | 2026-09-24T14:46:14Z | `20260925-115424-2026-09-24-fix-pin-redeploy-` |
| 36037220805 | Apply web-platform infra | success | `396ea62aa4da114a08112ffccb093e6fd5326148` | 2026-09-24T17:51:35Z | `20261013-051752-2026-09-25-fix-web-platform-` |
| 36063185028 | Apply web-platform infra | success | `96a87c89caeb02a533268226d2cc6adf90ba5dbc` | 2026-09-24T21:42:44Z | `2026-09-24-a-second-apply-workflow-could-per` |
| 36077212409 | Apply web-platform infra | success | `309ff2a3165d3fa127f83139ae39087fd4681454` | 2026-09-25T00:22:09Z | `20260925-144815-2026-09-25-security-rotate-g`, `20261013-051752-2026-09-25-fix-web-platform-` |
| 36079251562 | Apply web-platform infra | success | `cd105f170531850236897c2d00caea808e289817` | 2026-09-25T00:48:48Z | `20260925-144815-2026-09-25-security-rotate-g` |
| 36092626570 | Apply web-platform infra | success | `09c7cc31cdde3df8e5ec2bd49e3196397179cb09` | 2026-09-25T04:00:05Z | `20260925-144815-2026-09-25-security-rotate-g`, `20261013-051752-2026-09-25-fix-web-platform-` |
| 36117021829 | Apply web-platform infra | success | `51a5541a1a730d51b51436d9100657ed55d94dfd` | 2026-09-25T09:11:12Z | `2026-09-24-a-second-apply-workflow-could-per`, `20261013-051752-2026-09-25-fix-web-platform-` |
| 36142758324 | Apply web-platform infra | success | `6d08cca86d67dcd0d2fea26de3b0f77ec1b6a253` | 2026-09-25T13:43:19Z | `2026-09-25-doppler-token-rotation-with-a-sec` |
| 36150370048 | Apply web-platform infra | failure | `793391e7fbb853bfbbc4c5bcae8d4af356c05de2` | 2026-09-25T14:52:13Z | `20261013-051752-2026-09-28-feat-git-data-del` |
| 36186259051 | Apply web-platform infra | failure | `f5adf210ef61695b20620e7d644a68133ccae638` | 2026-09-25T20:31:14Z | `20261013-051752-2026-09-28-feat-git-data-del` |
| 36249105103 | Apply web-platform infra | failure | `0224ac6b8ee843da75b19dc1abc60a3548130281` | 2026-09-26T14:36:56Z | `20261013-051752-2026-09-28-feat-git-data-del` |
| 36314758055 | Apply web-platform infra | success | `cdbf358001dcffb7dd94e8643ab1628bc2dba695` | 2026-09-27T11:08:13Z | `20261013-051752-2026-09-27-fix-luks-monitor-` |
| 36315721116 | Apply web-platform infra | success | `707c7d072d1c82dc15fa5b71e2e7def84a111075` | 2026-09-27T11:26:09Z | `20261013-051752-2026-09-27-fix-luks-monitor-` |
| 36331513256 | Apply web-platform infra | success | `e980b9bfc87cf32b2ba7a367cbb8dd2141c55403` | 2026-09-27T15:58:50Z | `20260927-194534-2026-09-27-chore-retire-ghcr` |
| 36340195638 | Apply web-platform infra | success | `bf30947f14153dc92ce01f1de3b2f869d1342dec` | 2026-09-27T18:19:06Z | `ADR-119-luks-at-rest-for-the-live-workspaces`, `web1-reboot-unlock-near-miss-postmortem` (+2 more files) |
| 36425473000 | Apply web-platform infra | success | `ff019afe7136bed34bbd632ac11f5ae4090ba437` | 2026-09-28T12:59:47Z | `ADR-119-luks-at-rest-for-the-live-workspaces`, `20260929-031924-2026-09-28-fix-web1-reboot-u` (+1 more files) |
| 36633715088 | Apply web-platform infra | success | `e43a52463c71f721f6a573feee2c408d3d8c3673` | 2026-09-29T21:30:23Z | `cost-model`, `expenses` |
| 36646627695 | Apply web-platform infra | success | `bef6dd5a077decfd9b4e1bc68800568e1c042289` | 2026-09-29T23:42:34Z | `2026-10-19-web2-plugin-mount-fchmodat2-postm`, `20261019-190112-2026-10-19-fix-web2-plugin-m` |
| 36652454766 | Apply deploy-pipeline-fix | success | `aa7a20a70be1c8b0e281d05c00af4f20553b8b20` | 2026-09-30T00:53:14Z | `20261013-051752-2026-09-30-infra-deny-ghcr-o` |
| 36743565651 | Apply web-platform infra | success | `f27ca5444cbe06124882cdadc89aca7e2be770c3` | 2026-09-30T16:21:13Z | `2026-10-19-web2-plugin-mount-fchmodat2-postm`, `20261019-190112-2026-10-19-fix-web2-plugin-m` |
| 36922225571 | Apply deploy-pipeline-fix | success | `4a1230f2447cd41b21f17c62818bdb2c9ff62563` | 2026-10-01T20:31:40Z | `20261013-062704-2026-10-03-chore-8609-r3-del` |
| 37185772362 | Apply deploy-pipeline-fix | success | `907b0a50791751f03f7a827c0f4dc0b75496acca` | 2026-10-04T07:26:12Z | `ADR-263-guest-side-fresh-boot-luks-for-web-h`, `article-30-register` (+3 more files) |
| 37209725107 | Apply web-platform infra | success | `9e6412fb34fbf9a692327491f1b1c08aeeb26238` | 2026-10-04T14:33:54Z | `ADR-218-native-better-stack-logs-alerts-are-`, `ADR-263-guest-side-fresh-boot-luks-for-web-h` (+10 more files) |
| 37279684488 | Apply web-platform infra | failure | `482d889cb2c453695390a7a74f1447163c2a41c3` | 2026-10-05T07:47:03Z | `20261005-112710-2026-10-05-fix-stock-preflig` |
| 37280063535 | Apply web-platform infra | failure | `482d889cb2c453695390a7a74f1447163c2a41c3` | 2026-10-05T07:51:08Z | `20261005-112710-2026-10-05-fix-stock-preflig` |
| 37310111213 | Apply web-platform infra | success | `0b35762459f004b8cca2c853cabb1a99bd765611` | 2026-10-05T12:31:22Z | `ADR-263-guest-side-fresh-boot-luks-for-web-h`, `article-30-register` (+2 more files) |
| 37519267492 | Apply web-platform infra | success | `2efc8025ffa9feb4f19f5d00da48a1a64b09e081` | 2026-10-06T19:28:46Z | `20261030-120202-2026-10-30-fix-web-first-dep` |
| 37587956580 | Apply web-platform infra | success | `e4cd9bd48cdf529f8ef50fee6f917df32bd076f6` | 2026-10-07T07:32:30Z | `session-state` |
| 37678331159 | Apply web-platform infra | success | `411f034290ccc7a4e728ed36e7a8ad1a97c03569` | 2026-10-07T19:56:57Z | `20261008-215644-2026-10-08-fix-argv-bearer-s`, `20261013-062704-2026-10-08-chore-zot-adr096-` (+1 more files) |
| 37829680169 | Apply web-platform infra | success | `3ed3e4e6da7c4e55e40daa687d604034df544ffe` | 2026-10-08T19:08:22Z | `20261013-062704-2026-10-08-chore-retire-inng` |
| 37928426862 | Apply deploy-pipeline-fix | success | `5e755483731bf4b4eec9e00b2e31e34abf3fe7ce` | 2026-10-09T12:11:34Z | `20261009-195834-2026-10-09-fix-deploy-canary`, `20261009-195834-decision-challenges` |
| 37950928039 | Apply web-platform infra | success | `32b2fe2abb6cb57b2badf0faf8efca0ac51990c0` | 2026-10-09T15:19:57Z | `ADR-100-inngest-dedicated-single-host-single`, `ADR-142-inngest-redis-aof-zero-data-loss-luk` (+5 more files) |
| 37955244979 | Apply web-platform infra | success | `32b2fe2abb6cb57b2badf0faf8efca0ac51990c0` | 2026-10-09T15:54:55Z | `ADR-100-inngest-dedicated-single-host-single`, `ADR-142-inngest-redis-aof-zero-data-loss-luk` (+6 more files) |
| 37958051426 | Apply web-platform infra | success | `32b2fe2abb6cb57b2badf0faf8efca0ac51990c0` | 2026-10-09T16:17:35Z | `ADR-100-inngest-dedicated-single-host-single`, `ADR-142-inngest-redis-aof-zero-data-loss-luk` (+7 more files) |
| 37976212395 | Apply deploy-pipeline-fix | success | `79482dab59b64076d39dc87f141ea6c1cc054bb3` | 2026-10-09T18:51:43Z | `20261010-222353-2026-10-09-docs-deploy-statu`, `20261010-223151-2026-10-09-fix-argv-bearer-s` (+7 more files) |
| 38021561267 | inngest provision rehearsal | failure | `653b5d0f6a94597cd4affeedfa81247ae764c220` | 2026-10-10T03:43:25Z | `dispatch-only-infra-workflow-dry-run-does-no` |
| 38025838564 | inngest provision rehearsal | failure | `7f3f87dd062f81b2584695df1af4b647c04e9f5d` | 2026-10-10T04:57:14Z | `dispatch-only-infra-workflow-dry-run-does-no` |
| 38031062344 | inngest provision rehearsal | failure | `85aed833a702a0b42245abfbc0cf81f182e958a9` | 2026-10-10T06:28:40Z | `2026-10-11-a-unit-file-content-pin-must-mode`, `dispatch-only-infra-workflow-dry-run-does-no` (+4 more files) |
| 38036022367 | inngest provision rehearsal | success | `9e0978e59178d5bfd4757fdd02c63134c9f6b273` | 2026-10-10T07:54:11Z | `20261013-062704-2026-10-10-chore-inngest-luk` |
| 38097457915 | Apply web-platform infra | failure | `e35d0d75c9ae3842282dc8e45531526d9afb4073` | 2026-10-11T00:09:18Z | `20261011-120807-2026-10-11-chore-zot-consume` |
| 38105510474 | Apply web-platform infra | failure | `21331e94e352fd95502751ee0d91658fed0e0b84` | 2026-10-11T02:32:53Z | `20261011-164009-2026-10-11-fix-argv-bearer-s` |
| 38106710993 | Apply web-platform infra | failure | `db6631ddb731553207dd93228232e53295cf60e7` | 2026-10-11T02:55:23Z | `20261011-120807-2026-10-11-chore-zot-consume`, `20261011-164009-2026-10-11-fix-argv-bearer-s` |
| 38128304531 | Apply web-platform infra | failure | `31ada28352b05733d409aebc24276647462f4904` | 2026-10-11T09:25:15Z | `20261011-164009-2026-10-11-fix-argv-bearer-s` |
| 38139392390 | Apply web-platform infra | failure | `67cb281e4f866f51398422ec41dba591edc58081` | 2026-10-11T12:28:34Z | `ADR-282-sole-copy-luks-volume-protection-set`, `article-30-register` (+4 more files) |
| 38150427433 | Apply web-platform infra | success | `76da243c20fa936acd3cac1a7b467cbb242a075e` | 2026-10-11T15:14:11Z | `20261012-000417-2026-10-11-chore-zot-consume` |
| 38151596067 | Apply web-platform infra | success | `ec33ca285bbc1130c29515debbf63e6f0dc7621a` | 2026-10-11T15:31:00Z | `20261012-000417-2026-10-11-chore-zot-consume`, `flip-preconditions-report` |
| 38151764939 | Apply web-platform infra | success | `47c38a19da2e12262f7fb9d861cd7aac6e05f3c2` | 2026-10-11T15:33:23Z | `20261012-000417-2026-10-11-chore-zot-consume` |
| 38172628025 | Apply web-platform infra | success | `e5ee9d577f2ea64580c17c314d0153bfe427d1de` | 2026-10-11T20:32:19Z | `20261012-133610-2026-10-12-chore-web2-luks-r` |
| 38204104938 | Apply web-platform infra | failure | `0aae3f8680348e25e6794384286a28a3e597d0c8` | 2026-10-12T04:31:01Z | `20261012-133610-2026-10-12-chore-web2-luks-r` |
| 38228632851 | Apply web-platform infra | failure | `67ebbbeb4e46c04280125cc0d3d94358daecbe91` | 2026-10-12T09:14:51Z | `egress-gateway-bootstrap.sh`, `20261012-184317-2026-10-12-fix-egress-gw-tcp` |
| 38229123048 | Apply web-platform infra | failure | `0dc19ef389e9a8f064fa5837bfecc911cc7c941c` | 2026-10-12T09:19:15Z | `egress-gateway-bootstrap.sh`, `2026-10-12-egress-gateway-single-shot-tcp-pr` (+2 more files) |
| 38280522229 | Apply web-platform infra | success | `84a7953ea58c30737dc8aca73b483094bbbfe8ea` | 2026-10-12T16:53:26Z | `2026-10-13-a-classifier-that-reads-absent-as` |
| 38296039170 | Apply web-platform infra | success | `41b8801ad8e8e19ec41cbb79c98e9a77f06620d9` | 2026-10-12T19:12:00Z | `flip-preconditions-report` |
| 38303163269 | Apply web-platform infra | success | `64046de07615501b3c5ede72f72028336dc6e7c7` | 2026-10-12T20:16:46Z | `20261018-175601-2026-10-18-fix-heartbeat-url`, `closeout-evidence` (+1 more files) |
| 38653889114 | Apply web-platform infra | success | `944372f0d5054cc86a5ae1b75fc3af951c6f9195` | 2026-10-14T23:24:33Z | `ADR-282-sole-copy-luks-volume-protection-set`, `20261015-101343-2026-10-15-chore-flip-adr-28` |
| 38717225114 | Apply web-platform infra | success | `8c8401e6fa687485aa4421166ce0e4c47abe03b8` | 2026-10-15T10:01:09Z | `20261019-163644-2026-10-15-feat-g1-webhook-t` |
| 38718988284 | Apply web-platform infra | success | `8c8401e6fa687485aa4421166ce0e4c47abe03b8` | 2026-10-15T10:15:39Z | `20261019-163644-2026-10-15-feat-g1-webhook-t` |
| 38720185519 | Apply web-platform infra | success | `8c8401e6fa687485aa4421166ce0e4c47abe03b8` | 2026-10-15T10:25:41Z | `20261019-163644-2026-10-15-feat-g1-webhook-t` |
| 38781655048 | Apply web-platform infra | success | `a54c4e315b0aca603cfc6fbb5bdbbc57cad855f2` | 2026-10-15T17:57:43Z | `2026-08-counsel-review-7440` |
| 38791101231 | Apply web-platform infra | success | `1c0cf63dd3c68286a4e6ec4660910e3199213022` | 2026-10-15T19:06:00Z | `closeout-evidence` |
| 39351965961 | Apply web-platform infra | success | `1f9eebcd8a99540c496cc4a7e096813f04aee99e` | 2026-10-20T01:10:43Z | `20261020-063243-2026-10-20-fix-nic-guard-url` |
| 39364009152 | Apply web-platform infra | success | `57dda4c245caafc30ad8b890a71a31145606b721` | 2026-10-20T03:23:10Z | `20261020-170333-2026-10-20-fix-apply-web-pla` |
| 39948259622 | Apply deploy-pipeline-fix | success | `99936ce183a086f446091e2888a0eff5a7e42bd1` | 2026-10-23T11:44:55Z | issues #10136, #9905 (body/comments) |
| 40159796783 | Apply web-platform infra | success | `3946ba7ec5a25540c018e2e8a401efbf9ffc91af` | 2026-10-25T03:52:15Z | `decision-challenges` |
| 40262107186 | Apply web-platform infra | success | `81192540bfd0811856003a731d36274e9818d03c` | 2026-10-26T03:02:56Z | `20261026-103434-2026-10-26-chore-trim-innges` |
| 40486279399 | Apply web-platform infra | success | `2e9874cdf65e9ca5fd086f3728fd0c2105d0cae5` | 2026-10-27T10:09:17Z | `20261027-201109-2026-10-27-docs-delegated-ac` |
| 40573930081 | Apply web-platform infra | failure | `bb1432b6f7a939d38fd8a9113a4483398e6930d6` | 2026-10-27T19:58:54Z | `20261028-095914-2026-10-27-fix-egress-probe-` |
| 40678688421 | Apply web-platform infra | failure | `7d83c90210d7055cae612899b5aa535d6fd31d85` | 2026-10-28T11:16:40Z | `session-state` |
| 40698576985 | Apply web-platform infra | failure | `cd503b827fa7780f8f6112368d1093b74b65d5db` | 2026-10-28T13:40:19Z | `session-state` |
| 40720815376 | Apply web-platform infra | success | `b55fc70d3d4effbe44a1e8c1fd71d47b06c7597b` | 2026-10-28T15:55:17Z | `20261028-210048-2026-10-28-infra-web2-ssh-pr`, `20261030-120202-2026-10-30-fix-web-first-dep` |
| 40744937376 | Apply web-platform infra | failure | `744396abbbe1f788d049297b4b5efc575693a008` | 2026-10-28T18:25:12Z | `betterstack-logs-alerts.tf`, `ADR-282-sole-copy-luks-volume-protection-set` (+9 more files) |
| 40782617701 | Apply web-platform infra | success | `04cad4e8e0f2f80e90dc1ec218b3044cd4d68b25` | 2026-10-28T22:47:21Z | `betterstack-logs-alerts.tf`, `ADR-282-sole-copy-luks-volume-protection-set` (+4 more files) |

Workflow totals in the held set: Apply web-platform infra 97, Apply deploy-pipeline-fix 13, Terraform Drift Detection 5, inngest provision rehearsal 4.
Conclusions: success 81, failure 38.

## Comments and issue bodies, cleaned on 2026-11-01

Run on 2026-11-01 under the owner's per-command go for each of the two execute commands. Counts only;
no value was printed or read into this record.

- **PR bot comments: 498 deleted.** Deleting a comment removes its edit history too.
- **Issue bodies: 74 edited in place** (all verified), value-shaped lines replaced by a redaction marker.
- **Issue bot comments: 234 edited in place** (232 verified by the script, 2 flagged
  `verify-mismatch`; a separate rescan of both found no value-shaped line). 218 of the 732 bot
  comments sat under `infra-drift` issues and 16 on #10835; they were redacted rather than deleted
  because the drift workflows read the newest bot "Plan output" comment on those issues.
- **Rescan after the edits:** 0 value-shaped lines in the 74 bodies and 0 in the 234 comments.
- **Drift classifier:** the script's live old-versus-redacted verdict check was skipped (its worktree
  path was gone). The earlier dry run compared verdicts on all 73 `infra-drift` issues and found them
  identical. The next scheduled drift run on those issues is the live test.
- **Other surfaces scanned, nothing found:** PR review comments (393 scanned, 0 hits), review
  summaries (0 hits). No commit comments or discussions exist.
- **Ledgers (not committed, kept in the operator's scratch area):**
  `delete-bot-comments.EXECUTE.20261101T081522Z.ledger.tsv`, sha256
  `700e72fdcbbb53017a82f3f0f1259ae2c7f092e577bc437edf41f086c7539e1c`;
  `redact-issue-bodies.EXECUTE.20261101T084610Z.ledger.tsv`, sha256
  `5ff90a80fd9e15a04cdbe61ce03780bd9593cb0a531e93e7b5534c9062a535a0`.

### Residual exposure after the cleanup

- **Edit history of the 74 bodies and 234 comments stays readable.** GitHub keeps earlier revisions of
  an edited body or comment visible to any reader of a public repository. Editing in place did not
  remove them. Only deleting the comment does, and that was not possible for these without breaking
  the drift workflows.
- **The exposed keys are not rotated.** Anyone who read a run log, comment or earlier revision before
  the deletion or redaction may hold the values. The records above cannot show who did. Rotation is
  tracked on the incident (#11294, #11711) and is an owner-run act.
- Whether this residual changes the notifiability assessment is the CLO's call
  (see `2026-10-29-clo-determination-11294-random-id-log-exposure-art-4-12.md`); this record only states it.

## Known gaps

This record does not claim the exposure is fully enumerated. Not counted or not reachable:

- **Commit comments** and **discussions** do not exist in the repository. The **edit history** of
  issue and PR bodies and comments was not part of the census and, for the 74 bodies and 234 comments
  edited in place, still survives (see Residual exposure above).
- The run **artifact list** endpoint returned HTTP 500 during the census, so artifacts were not
  scanned.
- The **oldest runs have expired** logs (GitHub retention), so their logs were not readable and
  cannot be shown clean or dirty.
- **16 runs had unreadable logs** (`NOLOG`). Their status is unknown, not clean.
- 175 runs had zero jobs (`NOJOBS`): no log exists by construction, so they are neither exposure nor
  clean-by-reading. 337 rows are whole-run (`(all jobs)`) scans with no value-shaped line.
- The value-shaped test is a line-shape match on `random_*` id output. A value in another shape would
  not be counted.

## Related

- Incident: #11294. Redaction: #11551, #11674. Parent: #10205.
