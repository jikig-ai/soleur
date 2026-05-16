# Secret-scan fixtures — `database-url-with-password`

Synthesized fixtures for the `database-url-with-password` rule in `.gitleaks.toml`.
This file lives under `apps/web-platform/test/__synthesized__/` which is in the
rule's per-rule `paths = [...]` allowlist, so every example here is allowlisted
by path. The point of the fixture is to demonstrate the regex semantics on real
inputs so a future widening event can re-run them as a regression check.

Refs #3877 (asterisk-redaction `\*+` widening), #3874 (path-allowlist on
learnings tree).

## Positive — placeholder shapes that the per-rule `regexes` allowlist silences

These shapes match the placeholder-allowlist regex and would be silenced even
outside the path allowlist:

- `postgres://USER:PASSWORD@host.example.com:5432/db`
- `postgres://user:password@host.example.com:5432/db`
- `postgres://postgres:secret@host.example.com:5432/db`
- `postgres://<user>:<password>@host.example.com:5432/db`
- `postgres://user:***@aws-0-eu-west-1.pooler.supabase.com:6543/postgres`
- `postgres://user:**@host.example.com:5432/db`
- `postgresql://postgres:*****************@host.example.com:5432/db`

## Negative — real-shape passwords that still fire (caught by path-allowlist here)

These are NOT silenced by the regex allowlist — they would fire on any path NOT
listed in the per-rule `paths` allowlist. They are silenced HERE only because
the path matches `apps/web-platform/test/__synthesized__/.*`:

- `postgres://user:realpw_AAAA1111@host.example.com:5432/db`
- `postgres://admin:s3cret_pAssw0rd@host.example.com:5432/db`

## How to re-verify

```bash
gitleaks git --no-banner --exit-code 1 --redact -v 2>&1 | tail -40
```

The `database-url-with-password` rule must NOT fire on any line above.
