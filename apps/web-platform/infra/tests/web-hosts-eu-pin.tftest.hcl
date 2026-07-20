# EU-residency pin (CLO T-1, GA-blocking) — variable-validation negative tests for
# var.web_hosts (variables.tf, #5274 Phase 3 / ADR-068). Runs credential-free:
# variable validation is evaluated before any provider/resource planning, so
# `command = plan` with `expect_failures = [var.web_hosts]` catches the rejection
# without a Hetzner token or the R2 backend.
#
# Run: terraform -chdir=apps/web-platform/infra test -filter=tests/web-hosts-eu-pin.tftest.hcl
# (after `terraform init -backend=false`). Registered in infra-validation.yml.

# Mock every provider so `command = plan` does not validate real credentials — the
# variable validation under test (var.web_hosts EU pin) fires regardless of the
# provider layer, and mocking keeps the test credential-free for CI.
mock_provider "cloudflare" {}
mock_provider "hcloud" {}
mock_provider "random" {}
mock_provider "doppler" {}
mock_provider "betteruptime" {}
mock_provider "github" {}
mock_provider "tls" {}

# Dummy values for the module's required (no-default) variables — terraform test
# requires every required variable be set before it evaluates var.web_hosts's
# validation, even though validation fails before any provider/resource planning.
# None of these are used by the validation under test; they only satisfy the
# required-variable check. web_hosts is overridden per run block below.
variables {
  admin_ips = ["203.0.113.1"]

  # Opt this credential-free test OUT of the seo_config_settings entrypoint
  # adoption. `mock_provider` does NOT mock `import` blocks — Terraform performs
  # the import read against the REAL provider even under `terraform test`, so
  # leaving this at its production default (`true`) fails the whole file with
  # `error reading ruleset ID ... Authentication error (10000)` before any
  # var.web_hosts validation runs. That is a credential error in a job whose
  # entire premise is running without credentials.
  #
  # The default stays `true` so production adopts rather than clobbers; only
  # this test opts out. seo-config-rules.tf explains what the adoption is for,
  # and test/seo-config-rules.test.ts pins that the default is `true` — because
  # flipping it to `false` silently restores the whole-list clobber (#6767).
  adopt_seo_config_entrypoint  = false
  betterstack_api_token        = "dummy"
  betterstack_logs_token       = "dummy"
  cf_access_client_id          = "0123456789012345678901234567890123456789.access"
  cf_access_client_secret      = "0123456789012345678901234567890123456789012345678901234567890123"
  cf_account_id                = "0123456789abcdef0123456789abcdef"
  cf_api_token                 = "0123456789012345678901234567890123456789"
  cf_api_token_bot_management  = "0123456789012345678901234567890123456789"
  cf_api_token_dns_edit        = "0123456789012345678901234567890123456789"
  cf_api_token_r2              = "0123456789012345678901234567890123456789"
  cf_api_token_rulesets        = "0123456789012345678901234567890123456789"
  cf_api_token_zone_settings   = "0123456789012345678901234567890123456789"
  cf_notification_email        = "ops@example.com"
  cf_zone_id                   = "0123456789abcdef0123456789abcdef"
  doppler_token                = "dummy"
  doppler_token_tf             = "dummy"
  github_app_id                = "12345"
  github_app_private_key       = "dummy"
  ghcr_read_user               = "dummy"
  ghcr_read_token              = "dummy"
  hcloud_token                 = "dummy"
  kb_drift_operator_founder_id = "00000000-0000-0000-0000-000000000000"
  resend_api_key               = "dummy"
  resend_receiving_api_key     = "dummy"
  supabase_access_token        = "dummy"
  webhook_deploy_secret        = "dummy"
  # command=plan evaluates file(var.ssh_key_path) (hcloud_ssh_key.default). The
  # default ~/.ssh/id_ed25519.pub does not exist in CI, so point at a committed
  # fixture (content is irrelevant — the hcloud provider is mocked). Path is
  # CWD-relative (terraform test runs from the infra dir in CI + locally).
  ssh_key_path = "tests/dummy-id_ed25519.pub"
}

# A non-EU location (ash = US) MUST be rejected (GDPR residency).
run "reject_non_eu_location" {
  command = plan
  variables {
    web_hosts = {
      "web-1" = { location = "ash", private_ip = "10.0.1.10" }
    }
  }
  expect_failures = [var.web_hosts]
}

# A private_ip outside the 10.0.1.0/24 subnet MUST be rejected.
run "reject_non_subnet_ip" {
  command = plan
  variables {
    web_hosts = {
      "web-1" = { location = "hel1", private_ip = "192.168.0.5" }
    }
  }
  expect_failures = [var.web_hosts]
}

# A second non-EU host among otherwise-EU hosts MUST still be rejected
# (alltrue over values — a single bad host fails the whole set).
run "reject_mixed_eu_and_non_eu" {
  command = plan
  variables {
    web_hosts = {
      "web-1" = { location = "hel1", private_ip = "10.0.1.10" }
      "web-2" = { location = "hil", private_ip = "10.0.1.11" }
    }
  }
  expect_failures = [var.web_hosts]
}
