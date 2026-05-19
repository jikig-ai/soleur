# jikigai.com Cloudflare resources (LinkedIn Page verification, #4046).
#
# Scope: narrow. This file manages only the LinkedIn Page Verifications TXT
# record. Pre-existing jikigai.com DNS (MX/SPF/DKIM for ops@jikigai.com, etc.)
# remains dashboard-managed and will be imported in follow-up #4052.
#
# Provider: aliased `cloudflare.jikigai_com` backed by a narrow
# `cf_api_token_jikigai_com` (Zone:DNS:Edit on jikigai.com only). This isolates
# blast radius from the soleur.ai providers.
#
# Apply caveat: Phase 5.2 of the runbook applies via
# `terraform apply -target=cloudflare_record.linkedin_verification`. After the
# targeted apply, run an untargeted `terraform plan` in the same session and
# confirm `No changes` on soleur.ai resources (per AC24 / terraform-architect P1-4).

provider "cloudflare" {
  alias = "jikigai_com"

  api_token = var.cf_api_token_jikigai_com
}

# LinkedIn Page domain verification. The exact `name` (subdomain prefix) is
# provided by LinkedIn at Page Verifications time and stored in Doppler as
# TF_VAR_linkedin_page_verification_txt. LinkedIn currently uses
# `_linkedin-challenge.<sub>.<domain>` style hosts; the value is supplied as
# `<host>=<token>` and split here at apply time.
#
# No drift-suppression block (terraform-architect P1-3): LinkedIn
# verification tokens are stable post-verification, and absorbing dashboard-side
# drift would mask any operator-side change to the record.
resource "cloudflare_record" "linkedin_verification" {
  provider = cloudflare.jikigai_com
  zone_id  = var.cf_zone_id_jikigai_com
  name     = "_linkedin-challenge"
  content  = var.linkedin_page_verification_txt
  type     = "TXT"
  ttl      = 300
  comment  = "managed_by:terraform; purpose:linkedin-page-verification; issue:#4046"
}
