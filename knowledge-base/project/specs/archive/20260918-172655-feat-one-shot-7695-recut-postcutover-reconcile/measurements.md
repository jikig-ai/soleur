# Live measurements — 2026-09-18 (/work Phase 0.1, #7695)

Taken 2026-09-18T14:56:25Z from the worktree, no SSH. Each block names the read that produced it.

## 1. Better Stack probe row — `doppler run -p soleur -c prd_terraform -- scripts/inngest-host-state.sh`

```
dedicated inngest host — newest probe row
  observed_at    2026-09-18 14:54:01  [2m old]   (rows in window: 2)
  instance_id    hetzner-166317708
  boot_id        ef763c72-74bb-44ff-aa74-c19dc25ca13c
  probe_schema   8
  server_active  active        http_code=200
  registry_fns   70
  redis_active   active        redis_keys=1261 expires=1250
  data_mount     /dev/sdb  devid=scsi-0HC_Volume_106261946  bytes=46548668
  cutover_flag   done        flush_latched=true
  VERDICT        SERVING   SERVING=yes

recent refusals / failures: NONE in the window (the scan ran and matched nothing).
RC=0
```

## 1b. Raw row — `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 3h --grep SOLEUR_INNGEST_SERVER_PROBE` (newest dedicated row, fields only)

```
SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active vector_active=active redis_active=active uptime_s=93969 boot_id=ef763c72-74bb-44ff-aa74-c19dc25ca13c image_ref=10.0.1.30:5000\/jikig-ai\/soleur-inngest-bootstrap:v1.1.35@sha256:c8e27c71bb3f4b79379bb0929e89acef1b4bf18b80b41e14496dd96c726ed0cd instance_id=hetzner-166317708 cli_version=1.19.4-2c8385ba8 cutover_flag=done probe_schema=8 host_role=dedicated flush_latched=true redis_keys=1261 redis_expires=1250 redis_key_patterns=?estate?:key:*=719,?queue?:queue:*=253,?cs?:a:*=20,?queue?:partition:*=2,?queue?:accounts:*=2,?connect?:gateways:*=1 data_mount_src=\/dev\/sdb data_bytes=46548668 data_mount_base=sdb data_mount_devid=scsi-0HC_Volume_106261946 registry_fns=70
```

## 2. Doppler flags — `doppler secrets get INNGEST_CUTOVER_FLIP INNGEST_DIAGNOSTIC_BOOT -p soleur-inngest -c prd --plain`

```
INNGEST_CUTOVER_FLIP=done
INNGEST_DIAGNOSTIC_BOOT=0
```

## 3. Hetzner — `GET /v1/volumes/106261946` and `GET /v1/servers?name=soleur-inngest` (token: Doppler `prd_terraform` `HCLOUD_TOKEN`; jq projection, fields only)

```json
{
  "id": 106261946,
  "name": "soleur-inngest-redis-store",
  "size": 10,
  "format": "ext4",
  "status": "available",
  "server": 166317708,
  "created": "2026-07-07T23:51:07Z",
  "linux_device": "/dev/disk/by-id/scsi-0HC_Volume_106261946"
}
[
  {
    "id": 166317708,
    "name": "soleur-inngest",
    "status": "running",
    "server_type": "cpx22",
    "created": "2026-09-17T12:47:37Z",
    "private_ip": "10.0.1.40",
    "volumes": [
      106261946
    ]
  }
]
```

## 4. #7674 step-4 probe — `doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/inngest-host-not-serving-7674.sh`

```
PASS: soleur-inngest-prd served within 24h — 24 SOLEUR_INNGEST_SERVER_PROBE row(s) carrying ALL THREE
      server_active=active, http_code=200 and a NON-ZERO registry_fns. #7674 step 4 met.
RC=0
```

## STOP-set check (plan Phase 0.1)

| Condition | Measured | OK |
|---|---|---|
| `cutover_flag == done` | done | yes |
| `redis_keys > 0` | 1261 (plan time: 1081 — grew, still populated) | yes |
| volume id == 106261946 | 106261946, attached to server 166317708 | yes |
| `probe_schema == 8` | 8 | yes |
| `data_mount_devid == scsi-0HC_Volume_106261946` | scsi-0HC_Volume_106261946 | yes |
| `registry_fns` present, non-zero | 70 | yes |
| #7674 probe rc == 0 | rc=0 | yes |

Delta vs plan time (2026-09-18 ~14:00Z): `redis_keys` 1081 → 1261, `data_bytes` 38671222 → 46548668, `uptime_s` 90359 → 93969. Same boot_id `ef763c72`, same host `166317708`, same volume. No premise moved.

## 5. Dedicated-host instance history since Merge B — `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 15d --grep SOLEUR_INNGEST_SERVER_PROBE --limit 2000`, grouped by `instance_id` (first/last `dt`)

```
hetzner-162809678  126 rows  first=2026-09-03 15:47  last=2026-09-08 19:06   (pre-schema host; created 2026-08-20)
hetzner-165279348    8 rows  first=2026-09-09 08:41  last=2026-09-09 14:43
hetzner-165327294    4 rows  first=2026-09-09 15:17  last=2026-09-09 17:18
hetzner-165340214    4 rows  first=2026-09-09 17:33  last=2026-09-09 19:34
hetzner-165351540    4 rows  first=2026-09-09 19:53  last=2026-09-09 21:53
hetzner-165360464   22 rows  first=2026-09-09 22:08  last=2026-09-10 20:11   (probe_schema=7)
hetzner-165451537  160 rows  first=2026-09-10 21:00  last=2026-09-17 11:10   (probe_schema=8; the 2026-09-15 cutover host — op=arm run 34948112813)
hetzner-166305436    3 rows  first=2026-09-17 11:38  last=2026-09-17 12:38   (inherited-done incident, first replace)
hetzner-166317708   28 rows  first=2026-09-17 12:49  last=2026-09-18 14:54   (current; op=resume recovery)
```

**Correction to the plan (2026-09-18 plan text said "the third host since 2026-09-04, across two more
replaces").** Measured: the current host is the NINTH dedicated host since Merge B (2026-09-04) —
eight replaces: five on 2026-09-09 (probe_schema 4→7 iterations + the user_data cap recreate), one on
2026-09-10 (probe_schema=8), two on 2026-09-17 (inherited-done incident). None was the recut Dispatch
A/C sequence. The durable latch was written on host `165451537` (2026-09-15 arm) and survived both
2026-09-17 replaces. The runbook callout and the addenda use these measured figures, not the plan's.
