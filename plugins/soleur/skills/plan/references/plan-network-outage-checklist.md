# Network-Outage Hypothesis Checklist

Trigger: feature description or existing plan Overview matches any of
`SSH`, `connection reset`, `kex`, `firewall`, `unreachable`, `timeout`,
`502`, `503`, `504`, `handshake`, `EHOSTUNREACH`, `ECONNRESET` (case
insensitive).

When triggered, the plan's `## Hypotheses` section MUST include a
verification entry for each of the four layers below BEFORE any
service-layer hypothesis (sshd config drift, fail2ban, app crash, etc.).

## Why this exists

Issue #2654 generated a plan with three sshd-layer hypotheses because
the firewall was "known to allow 82.67.29.121". The actual outage was
firewall-layer (admin-IP drift) -- issue #2681. Cost: one misdirected
PR (#2655), a correct-but-non-causal fix, and a second incident day
spent rediagnosing.

The class recurs: institutional learning
`2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` documents the
same L3-vs-L7 inversion in a CI-runner context. Codifying an L3->L7
discipline in the plan skill makes this hard to get wrong.

## Checklist (L3 to L7)

For each layer, the plan MUST answer "verified / not verified" with a
specific command or artifact. "Obvious" is not a verification.

### L3 -- Firewall allow-list

Has `hcloud firewall describe <server>` (or equivalent vendor CLI) been
run against the affected host, and has the result been diffed against
the current client/operator egress IP (`curl -s https://ifconfig.me/ip`)?

- Verification artifact: the diff output pasted into the plan's Research
  Reconciliation or Hypotheses section.
- Failure mode when skipped: admin-IP drift mistaken for sshd/fail2ban
  issue. See issue #2681, runbook
  `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`.

### L3 -- DNS / routing

Has `dig <hostname>` resolved to the expected IP, and has `traceroute`
or `mtr` from the client network confirmed the route reaches the host's
announced prefix?

- Verification artifact: the resolved IP + the last non-dropped hop.
- Failure mode when skipped: DNS cache poisoning, ISP-level routing
  misdirection, anycast edge node outages mistaken for app-layer issues.

### L7 -- TLS / proxy layer (HTTPS only)

If the symptom is on an HTTPS path, has `curl -Iv https://<host>/<path>`
confirmed the certificate chain, SNI, and any intermediary (Cloudflare,
CDN) is serving the expected host?

- Verification artifact: the `curl -Iv` headers (`Server`, `CF-Ray`,
  `X-Cache`, etc.) pasted into the plan.
- Failure mode when skipped: CDN/edge misconfiguration, expired certs,
  SNI mismatch mistaken for origin app failure.

### L7 -- Application layer (service-specific)

Has `journalctl -u <service>` (or the service's equivalent log stream)
been inspected on the host for an entry matching the incident window
AND the client IP?

- Verification artifact: a journal line matching the client IP and
  timestamp, OR an explicit note that "no journal entry exists" (which
  is itself strong evidence the packet never reached the service).
- Failure mode when skipped: drawing conclusions about service-layer
  behavior without confirming the service ever saw the packet.

## Ordering discipline

Layers MUST be verified in order (L3 -> L7). A layer above that drops
packets is invisible to layers below. Starting at L7 (the service) and
working up produces phantom hypotheses.

**Absence of a lower-layer signal is itself a signal.** If L7
`journalctl` shows no entry for the client IP, the packet never reached
the service -- confirm L3 before drafting any L7 hypothesis.

## Plan output shape

The `## Hypotheses` section of a triggered plan must list unverified
layers FIRST, in L3->L7 order, before any service-specific hypothesis.

Example (well-formed):

```markdown
## Hypotheses

1. **L3 firewall allowlist drift.** `var.admin_ips` has one `/32`
   entry; operator egress may have rotated. Verification: run
   `hcloud firewall describe <server>` and diff against current
   `curl -s https://ifconfig.me/ip`. [verified: diff shown]
2. **L3 DNS/routing.** `dig soleur.ai` returns expected IP. [verified]
3. **L7 sshd config drift.** `sshd -T` output matches committed config.
   [verified via journal entries showing sshd accepting the handshake]
```

Example (malformed -- what #2654 produced):

```markdown
## Hypotheses

1. **fail2ban permanent ban.** [unverified: firewall not checked]
2. **sshd drift.** [unverified: journalctl not inspected]
3. **sshguard conflict.** [unverified: hcloud firewall not inspected]
```

## Opt-out

A plan MAY explicitly opt out of a layer check with a one-line
justification citing a verification artifact (e.g., "L3 DNS verified
stable -- same host was reachable 5 minutes prior with same client
network, traceroute captured"). "Obvious", "unlikely", or "already
ruled out" without an artifact is not a valid opt-out.

## References

- Runbook: `knowledge-base/engineering/ops/runbooks/admin-ip-drift.md`
- Issue: #2681 (the incident that surfaced this gap)
- Prior-art incident: issue #2654, PR #2655
- Institutional learning:
  `knowledge-base/project/learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md`
- AGENTS.md: `hr-ssh-diagnosis-verify-firewall`
