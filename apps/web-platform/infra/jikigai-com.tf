# jikigai.com Cloudflare resources (LinkedIn Page verification, #4046; legal-track
# privacy-policy redirect, #4051).
#
# Scope: narrow. This file manages (a) the LinkedIn Page Verifications TXT
# record (#4046), and (b) a single Cloudflare ruleset redirect from
# jikigai.com/legal/privacy-policy → soleur.ai/pages/legal/privacy-policy.html
# (#4051; canonical-domain alignment for the LinkedIn appeal flow so the
# Developer app 229658411 privacy-policy URL points at jikigai.com — the
# K-bis-named controller's domain — rather than soleur.ai). Pre-existing
# jikigai.com DNS (MX/SPF/DKIM for ops@jikigai.com, etc.) remains
# dashboard-managed and will be imported in follow-up #4052.
#
# Provider: aliased `cloudflare.jikigai_com` backed by a narrow
# `cf_api_token_jikigai_com`. This isolates blast radius from the soleur.ai
# providers. **Operator action required at #4051 apply time:** expand the
# `cf_api_token_jikigai_com` API token scope from `Zone:DNS:Edit on jikigai.com`
# (the #4046 minimum) to `Zone:DNS:Edit + Zone:Ruleset:Edit on jikigai.com`
# (the #4051 minimum). Re-paste into Doppler `prd` under the same secret name.
#
# Apply caveat (#4046): Phase 5.2 of the runbook applies the TXT record via
# `terraform apply -target=cloudflare_record.linkedin_verification`. After the
# targeted apply, run an untargeted `terraform plan` in the same session and
# confirm `No changes` on soleur.ai resources (per AC24 / terraform-architect P1-4).
#
# Apply caveat (#4051): the ruleset applies via
# `terraform apply -target=cloudflare_ruleset.jikigai_com_redirects` and
# follows with an untargeted `terraform plan` confirming zero soleur.ai drift
# (mirror of the verification-TXT pattern from #4046; AC-Infra-3 of the #4051 plan).

provider "cloudflare" {
  # Blank line between alias and api_token keeps `terraform fmt` from
  # column-aligning the `=` signs, which would break plan AC8b's literal
  # `grep -q 'alias = "jikigai_com"'` check (single-space form, #4046).
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

# jikigai.com → soleur.ai privacy-policy redirect (#4051).
#
# Narrow scope: a single 301 redirect from jikigai.com/legal/privacy-policy to
# soleur.ai/pages/legal/privacy-policy.html. The canonical privacy policy
# remains hosted on soleur.ai (single source of truth: docs/legal/privacy-policy.md);
# this rule exists only to align the LinkedIn Developer app 229658411
# privacy-policy URL with the K-bis-named controller's domain (Jikigai SARL ↔
# jikigai.com) per the LinkedIn appeal-flow reviewer's documented expectation.
#
# Expression intentionally pinned to one exact path — no broader catch-all that
# might shadow future jikigai.com sub-paths or interfere with the email infra
# (MX/SPF/DKIM) that remains dashboard-managed pending #4052.
resource "cloudflare_ruleset" "jikigai_com_redirects" {
  provider    = cloudflare.jikigai_com
  zone_id     = var.cf_zone_id_jikigai_com
  name        = "jikigai-com-static-redirects"
  description = "Static redirects for jikigai.com. Added in #4051 (LinkedIn appeal privacy-policy URL alignment)."
  kind        = "zone"
  phase       = "http_request_dynamic_redirect"

  rules {
    expression  = "http.host eq \"jikigai.com\" and http.request.uri.path eq \"/legal/privacy-policy\""
    action      = "redirect"
    description = "Privacy policy → soleur.ai canonical URL for LinkedIn appeal alignment (#4051)."

    action_parameters {
      from_value {
        status_code = 301
        target_url {
          value = "https://soleur.ai/pages/legal/privacy-policy.html"
        }
        preserve_query_string = false
      }
    }
  }
}
