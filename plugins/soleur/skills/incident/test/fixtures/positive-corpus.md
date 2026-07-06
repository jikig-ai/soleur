# Positive-corpus fixture (synthesized — `cq-test-fixtures-synthesized-only`)

All tokens below are **synthesized from format specs** — no real production credentials.
Each block exists to trigger one regex class in `scripts/redact-sentinel.sh` (plan FR3).

Synthesis rule: use low-entropy padding (repeated alphanumerics, all-zeros) so the
strings match Soleur's redaction regex (`{16,}` minimum) without matching Stripe /
GitHub / Doppler secret-scanner heuristics, which look for high-entropy real-key shapes.
This keeps the fixture safe to commit while still exercising every regex class.

## JWT three-segment

eyJaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaaaaaaaaa.aaaaaaaaaaaaaaaaaa

## Email

synthetic.fixture+test@example-not-real.invalid

## UUID

aaaaaaaa-1111-2222-3333-bbbbbbbbcccc

## Stripe `sk_/pk_/rk_`

sk_test_0000000000000000
pk_live_1111111111111111
rk_test_2222222222222222

## Stripe `whsec_` (webhook signing secret)

whsec_3333333333333333

## Stripe `acct_` (Connect account)

acct_4444444444444444

## Stripe `cus_/pi_/seti_/sub_/in_`

cus_55555555555555
pi_6666666666666666
seti_77777777777777
sub_88888888888888
in_9999999999999999

## IPv4

203.0.113.42

## Env-var-with-value

SUPABASE_SERVICE_ROLE_KEY=zzzzzzzz-zzzz-zzzz-zzzz-placeholder
DOPPLER_TOKEN=dp.placeholder.zzzzzzzzzzzzzzzz
STRIPE_SECRET_KEY=sk_test_aaaaaaaaaaaaaaaa

## GitHub PAT / OAuth / Actions (added 2026-05-14 review)

ghp_PLACEHOLDERaaaaaaaaaaaaaaaaaaaaaaaa
github_pat_PLACEHOLDERaaaaaaaaaaaaaaaaaaaa

## Anthropic key

sk-ant-PLACEHOLDERaaaaaaaaaaaaaaaaaaaaaaaa

## OpenAI key

sk-proj-PLACEHOLDERaaaaaaaaaaaaaaaaaaaaa

## Supabase PAT / project key

sbp_zzzzzzzzzzzzzzzzzzzzzzzzz
sb_secret_zzzzzzzzzzzzzzzzzzzz

## PEM private-key header

-----BEGIN RSA PRIVATE KEY-----

## Doppler token (added #5987 — crown-jewel class)

dp.st.dev.zzzzzzzzzzzzzzzzzzzz

## Slack token (added #5987 — crown-jewel class)

xoxb-zzzzzzzzzzzzzzzzzzzz

## Cloudflare API token (added #6045 item 6 — 40-char, upper+digit anti-SHA predicate)

Ab3K9xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
