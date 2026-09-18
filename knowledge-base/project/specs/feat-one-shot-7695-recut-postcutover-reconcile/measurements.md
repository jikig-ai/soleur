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
SOLEUR_INNGEST_SERVER_PROBE http_code=200 server_active=active vector_active=active redis_active=active uptime_s=93969 boot_id=ef763c72-74bb-44ff-aa74-c19dc25ca13c image_ref=10.0.1.30:5000\/jikig-ai\/soleur-inngest-bootstrap:v1.1.35@sha256:c8e27c71bb3f4b79379bb0929e89acef1b4bf18b80b41e14496dd96c726ed0cd instance_id=hetzner-166317708 cli_version=1.19.4-2c8385ba8 cutover_flag=done probe_schema=8 host_role=dedicated flush_latched=true redis_keys=1261 redis_expires=1250 redis_key_patterns=?estate?:key:*=719,?queue?:queue:*=253,?cs?:a:*=20,?queue?:partition:*=2,?queue?:accounts:*=2,?connect?:gateways:*=1 data_mount_src=\/dev\/sdb data_bytes=46548668 data_mount_base=sdb data_mount_devid=scsi-0HC_Volume_106261946 registry_fns=70\",\"pii_scrub_applied\":\"+string\",\"shipper\":\"vector\",\"source_kind\":\"journald\",\"source_type\":\"journald\",\"timestamp\":\"2026-09-18T14:53:59.974705Z\"}"}
```

## 2. Doppler flags — `doppler secrets get INNGEST_CUTOVER_FLIP INNGEST_DIAGNOSTIC_BOOT -p soleur-inngest -c prd --plain`

```
INNGEST_CUTOVER_FLIP=done
INNGEST_DIAGNOSTIC_BOOT=0
```

## 3. Hetzner — `GET /v1/volumes/106261946` and `GET /v1/servers?name=soleur-inngest` (token: Doppler `prd_terraform` `HCLOUD_TOKEN`)

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
