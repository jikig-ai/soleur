# Mandatory advisory disclaimer (CLO Decision 1)

This text is appended verbatim by `run-scan.sh` to every scanner output. It is
the SINGLE point of insertion (per plan Sharp Edge #9). Per-script outputs do
NOT include the disclaimer; the aggregator does.

```
---
Advisory static analysis only. LOW-RISK does not constitute a security audit,
certification, or warranty of safety. The skill executes in your environment
under your account; you remain responsible for review.

Scanner version: <version>  Rule pack: <sha-prefix>  Scanned: <ISO-8601>
```

The token `<version>` is replaced with the value of `scanner_version` from the
manifest. `<sha-prefix>` is the first 12 hex chars of the rule-pack manifest
SHA. `<ISO-8601>` is the scan timestamp in `date -u +"%Y-%m-%dT%H:%M:%SZ"`.

The disclaimer is required regardless of verdict — including LOW-RISK — so
that downstream consumers cannot infer "no warning" as a positive certification.
