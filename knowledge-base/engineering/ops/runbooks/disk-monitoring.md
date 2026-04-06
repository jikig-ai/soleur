# Disk Space Monitoring Runbook

**Issue:** #1409
**Servers:** web-platform CX33

## Alert Types

| Level | Threshold | Email Subject | Cooldown |
|-------|-----------|---------------|----------|
| WARNING | >= 80% | `[WARNING] Disk usage at X% on <hostname>` | 1 hour |
| CRITICAL | >= 95% | `[CRITICAL] Disk usage at X% on <hostname>` | 1 hour |

Alerts are sent to `ops@jikigai.com` via the Resend email API.

## Alert Received -- Immediate Response

1. SSH into the server: `ssh root@<server-ip>`
2. Check current disk usage: `df -h /`
3. Identify largest consumers: `du -sh /* 2>/dev/null | sort -rh | head -10`

## Common Causes and Fixes

### Docker images (most common)

```bash
docker image prune -af
```

The weekly cron and per-deploy pruning should prevent accumulation, but edge cases (failed deploys, manual pulls) can leave orphaned images.

### Systemd journal logs

```bash
journalctl --vacuum-size=100M
```

### Apt cache

```bash
apt clean
```

### Temp files older than 7 days

```bash
find /tmp -type f -mtime +7 -delete
```

### Docker volumes (unused)

```bash
docker volume prune -f
```

## Adjusting Thresholds

Edit `/usr/local/bin/disk-monitor.sh` on the server:

```bash
readonly WARN_THRESHOLD=80   # Change warning threshold
readonly CRIT_THRESHOLD=95   # Change critical threshold
readonly COOLDOWN_SECONDS=3600  # Change cooldown period
```

For persistent changes across reprovisioning, update `apps/web-platform/infra/disk-monitor.sh` in the repo and run `terraform apply`.

## Testing the Alert Manually

```bash
bash /usr/local/bin/disk-monitor.sh
```

This only fires an alert if disk usage is actually above the threshold. To force-test the Resend email API:

```bash
curl -s -X POST "https://api.resend.com/emails" \
  -H "Authorization: Bearer $(grep RESEND_API_KEY /etc/default/disk-monitor | cut -d= -f2-)" \
  -H "Content-Type: application/json" \
  -d '{"from":"Soleur Ops <noreply@send.soleur.ai>","to":["ops@jikigai.com"],"subject":"[TEST] Disk monitoring test","text":"Manual test"}'
```

## Silencing Alerts Temporarily

```bash
systemctl stop disk-monitor.timer
```

Re-enable when done:

```bash
systemctl start disk-monitor.timer
```

## Verifying the Timer

```bash
systemctl is-active disk-monitor.timer     # Should print "active"
systemctl list-timers disk-monitor.timer    # Shows next/last run times
journalctl -u disk-monitor.service --since "10 min ago" --no-pager
```
