---
module: Agent workflow / secret handling
date: 2026-08-04
problem_type: security_issue
component: development_workflow
symptoms:
  - "A masked Doppler secret printed in full to the session transcript despite a sed redaction in the same pipeline"
  - "The redaction pattern matched the provider NAME (betteruptime) while the live URL used a different host (uptime.betterstack.com)"
  - "No error, no non-zero exit — sed passed the line through unchanged and the command reported success"
root_cause: incorrect_assumption
resolution_type: workflow_fix
severity: high
issues: ['#6808']
---

# A redaction that does not match is indistinguishable from one that worked

## What happened

While applying the #6808 heartbeat limb, a verification step read the freshly-created Doppler secret
and piped it through a redaction before echoing it:

```bash
echo "$V" | sed -E 's#(https://[a-z.]*betteruptime[^/]*/api/v[0-9]+/heartbeat/).*#\1<REDACTED>#'
```

The Terraform provider is `betterstackhq/better-uptime` and the resource is `betteruptime_heartbeat`,
so `betteruptime` looked like the right anchor. The **live URL** is
`https://uptime.betterstack.com/api/v1/heartbeat/<token>`. The pattern did not match, `sed` emitted
the line unchanged, and the bearer token went into the transcript at full strength.

Nothing failed. `sed` exits 0 on a non-matching substitution — that is its contract, not a bug — so
the guard's failure mode is silence, and silence reads exactly like success.

## Why this one mattered

The leaked value was a Better Stack heartbeat push URL. Its only capability is *marking the probe
alive*. That is precisely the signal #6808 exists to make trustworthy: anyone holding it can forge
liveness for the LUKS at-rest probe, making a dead probe indistinguishable from a healthy one — the
exact defect the issue was opened to remove, reintroduced through its own verification step.

## The fix that generalises

**Never print a secret and rely on a pattern to scrub it.** A redaction regex is a guess about a
value's shape, evaluated against a value you have not seen. Assert on a *derived* property instead —
one that cannot carry the secret no matter what shape it has:

```bash
# existence + shape, no value
V=$(doppler secrets get NAME --plain -c cfg -p proj) && echo "PRESENT len=${#V}"

# equality between two secrets, without printing either
[ "$(printf %s "$A" | sha256sum)" = "$(printf %s "$B" | sha256sum)" ] && echo MATCH
```

That second form is what proved the rotated Doppler secret equalled the live heartbeat URL — the
same verification the redaction was reaching for, with no path by which the value can escape.

If a value genuinely must be displayed, redact by **construction** (print a known-safe substring you
built, e.g. `${V:0:8}…`) rather than by **subtraction** (matching and removing the dangerous part).
Construction fails closed; subtraction fails open.

## Recovery, for the shape of it

Rotation was cheap only because it happened before anything consumed the value:
`terraform apply -replace=` on **both** the heartbeat and the `doppler_secret`. The second `-replace`
is load-bearing — that resource carries `lifecycle { ignore_changes = [value] }`, so replacing the
heartbeat alone would have left Doppler pointing at a destroyed endpoint. `ignore_changes` suppresses
*updates*, not *creates*, which is why a replace still writes the new value.

Confirmed dead rather than assumed dead: the old heartbeat URL returned **HTTP 404**.

## Related

- `hr-never-paste-secrets-via-bang-prefix` — same class (secrets entering the transcript), different
  mechanism. That rule covers operator-pasted values; this covers agent-printed ones.
- [[2026-02-10-api-key-leaked-in-git-history-cleanup]] — the durable-storage version of this.
