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
mock_provider "hcloud" {
  # #6570: hcloud_server.git_data carries a lifecycle.precondition asserting
  # `data.hcloud_server_type.git_data.architecture` matches the arch derived from
  # var.git_data_server_type. `mock_provider` synthesizes a RANDOM STRING for every
  # computed attribute it is not told about, so the precondition compares "amd64"
  # against e.g. "qq64nr49" and fails EVERY run block in this file — a failure that
  # has nothing to do with the var.web_hosts validation under test, and whose error
  # text ("Hetzner reports architecture=qq64nr49") actively misdirects, since no
  # Hetzner call happened at all.
  #
  # Pin it to the value the real catalog returns for the cpx22 default. This is the
  # arch the derivation must agree with, so the override keeps the precondition
  # meaningful here rather than disabling it: flip the default to a `cax*` type and
  # this file goes red, which is the correct signal.
  #
  # (STALE AS OF #7309 — corrected below.) This used to read: "zot-registry.tf reads
  # the same data source but consumes only `.memory`, which a synthesized number
  # satisfies harmlessly — git-data is the first assertion in this root on a mocked
  # STRING attribute, which is why no prior test needed this."
  #
  # #7309 back-filled the ADR-068 D7 wrong-arch precondition onto hcloud_server.registry
  # (it was the only host in this root without one, on the sole pull path). That makes
  # zot-registry.tf the SECOND assertion on a mocked STRING attribute, so it needs the
  # same override for the same reason — and CI proved it by failing with
  # "Hetzner reports architecture=5xqx4f82", the misdirecting text this comment warns
  # about, on the very run that introduced the precondition.
  override_data {
    target = data.hcloud_server_type.git_data
    values = {
      architecture = "x86"
    }
  }

  override_data {
    target = data.hcloud_server_type.registry
    values = {
      architecture = "x86"
    }
  }

  # #12866: bastion.tf carries the same x86 precondition, so it is the THIRD mocked STRING
  # assertion. CI failed on it exactly as #7309 predicts ("Hetzner reports architecture=mg989s7r").
  override_data {
    target = data.hcloud_server_type.bastion
    values = {
      architecture = "x86"
    }
  }
}
mock_provider "random" {}
mock_provider "\u0064oppler" {}  # the doppler provider; \u escape keeps the literal name out of the #9294 trio census read shapes
mock_provider "betteruptime" {}
mock_provider "github" {
  # #8754: web-host-birth-environment.tf adopts the live deployment policy with an
  # unconditional `import` block. That import goes through this MOCKED default provider,
  # and Terraform refuses it ("Invalid import request: Cannot import resources from mock
  # providers", measured on 1.9.8), failing every run block here. The seo_config import
  # below behaves differently only because it names the unmocked `cloudflare.rulesets`
  # alias, which reads the real API. Overriding the import target keeps this file
  # credential-free. Remove with the import (#9060).
  override_resource {
    target = github_repository_environment_deployment_policy.web_platform_infra_apply_main_adopted
  }
}
mock_provider "tls" {}
mock_provider "supabase" {
  # #9168: supabase-project.tf adopts the live prd project with an unconditional
  # `import` block — the same shape as the github adoption above. `mock_provider`
  # does NOT mock `import` blocks, and leaving the provider unmocked would run the
  # import read against the real Management API with the dummy
  # supabase_access_token below, failing every run block on a credential error in
  # a credential-free suite. Overriding the import target keeps the file
  # credential-free. Remove with the import (the #9168 follow-up PR deletes the
  # one-time import block post-apply).
  override_resource {
    target = supabase_project.prd
  }
}

# Dummy values for the module's required (no-default) variables — terraform test
# requires every required variable be set before it evaluates var.web_hosts's
# validation, even though validation fails before any provider/resource planning.
# None of these are used by the validation under test; they only satisfy the
# required-variable check. web_hosts is overridden per run block below.
variables {
  admin_ips = ["203.0.113.1"]

  # mock_provider does not mock `import` blocks: Terraform performs the import read against
  # the REAL provider even under `terraform test`, so the #12931 import blocks
  # (cf-account-migration-imports.tf) are switched off here. Production keeps the default.
  cf_migration_imports_enabled = false
  # Pinned to the legacy account by variables.tf (CTO ruling D8): any other value fails every run.
  cf_r2_account_id      = "4d5ba6f096b2686fbdd404167dd4e125"
  betterstack_api_token = "dummy"
  # Length-bearing, not "dummy": modules/git-data-userdata/variables.tf validates this is a
  # real ingest token, because an empty or stub value renders `BETTERSTACK_LOGS_TOKEN=` and
  # darkens eight of the nine git-data boot stages on a HASH-VALID boot (#7460).
  betterstack_logs_token = "stub-NOT-A-REAL-TOKEN-000000000000"
  # (#7772) git-data's own source token. Same length-bearing rationale as the shared sibling
  # directly above — it feeds the SAME module validation. It needs a value here for a reason
  # `terraform validate` cannot surface: a run block resolves EVERY root variable before it
  # evaluates anything, so a new no-default variable fails all three run blocks with
  # "No value for required variable" while validate stays green. Measured on this branch.
  git_data_betterstack_logs_token = "stub-NOT-A-REAL-GIT-DATA-TOKEN-000"
  cf_access_client_id             = "0123456789012345678901234567890123456789.access"
  cf_access_client_secret         = "0123456789012345678901234567890123456789012345678901234567890123"
  cf_account_id                   = "0123456789abcdef0123456789abcdef"
  cf_api_token                    = "0123456789012345678901234567890123456789"
  cf_api_token_bot_management     = "0123456789012345678901234567890123456789"
  cf_api_token_dns_edit           = "0123456789012345678901234567890123456789"
  cf_api_token_r2                 = "0123456789012345678901234567890123456789"
  cf_api_token_pages              = "0123456789012345678901234567890123456789"
  cf_api_token_rulesets           = "0123456789012345678901234567890123456789"
  cf_api_token_zone_settings      = "0123456789012345678901234567890123456789"
  cf_notification_email           = "ops@example.com"
  cf_zone_id                      = "0123456789abcdef0123456789abcdef"
  doppler_token                   = "dp.st.prd.testdummy" # #7095: must satisfy the shape precondition
  doppler_token_tf                = "dummy"
  github_app_id                   = "12345"
  github_app_private_key          = "dummy"
  hcloud_token                    = "dummy"
  kb_drift_operator_founder_id    = "00000000-0000-0000-0000-000000000000"
  resend_api_key                  = "dummy"
  resend_receiving_api_key        = "dummy"
  supabase_access_token           = "dummy"
  anthropic_api_key_ci            = "sk-ant-test-ci-dummy" # #8505: must satisfy the sk-ant- validation
  webhook_deploy_secret           = "dummy"
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

# #8505: the CI key's shape is validated before any resource is planned.
run "reject_non_sk_ant_ci_key" {
  command = plan
  variables {
    anthropic_api_key_ci = "not-an-anthropic-key"
  }
  expect_failures = [var.anthropic_api_key_ci]
}

# #12931 / ADR-329 Guard 4: the OLD zone and account ids are refused before any refresh.
run "reject_old_zone_id" {
  command = plan
  variables {
    cf_zone_id = "5af02a2f394e9ba6e0ea23c381a26b67"
  }
  expect_failures = [var.cf_zone_id]
}

# Upper case fails the 32-lowercase-hex shape check, so an upper-case paste of the old id is still refused.
run "reject_old_zone_id_upper_case" {
  command = plan
  variables {
    cf_zone_id = "5AF02A2F394E9BA6E0EA23C381A26B67"
  }
  expect_failures = [var.cf_zone_id]
}

run "reject_old_account_id" {
  command = plan
  variables {
    cf_account_id = "4d5ba6f096b2686fbdd404167dd4e125"
  }
  expect_failures = [var.cf_account_id]
}

run "reject_short_r2_account_id" {
  command = plan
  variables {
    cf_r2_account_id = "4d5ba6f096b2686fbdd404167dd4e12"
  }
  expect_failures = [var.cf_r2_account_id]
}

run "reject_empty_r2_account_id" {
  command = plan
  variables {
    cf_r2_account_id = ""
  }
  expect_failures = [var.cf_r2_account_id]
}

# A padded or otherwise malformed id is refused as malformed before any provider call
# (#12931 review, security P3: Guard 4 is only as strong as this check).
run "reject_padded_zone_id" {
  command = plan
  variables {
    cf_zone_id = " 0123456789abcdef0123456789abcdef"
  }
  expect_failures = [var.cf_zone_id]
}

run "reject_padded_account_id" {
  command = plan
  variables {
    cf_account_id = "0123456789abcdef0123456789abcdef "
  }
  expect_failures = [var.cf_account_id]
}

# CTO ruling D8: R2 stays on the legacy account. The Soleur account id (or any other) is refused.
run "reject_new_account_as_r2_account" {
  command = plan
  variables {
    cf_r2_account_id = "66d4f93f7397f196544e9fe84c3557c2"
  }
  expect_failures = [var.cf_r2_account_id]
}

# CTO ruling D9: the plan-tier gates are locked off. A Doppler TF_VAR cannot turn one on; a
# reviewed PR deletes the validation. One run block per gate.
run "reject_load_balancing_enabled" {
  command = plan
  variables {
    cf_load_balancing_enabled = true
  }
  expect_failures = [var.cf_load_balancing_enabled]
}

run "reject_zone_plan_pro" {
  command = plan
  variables {
    cf_zone_plan_pro = true
  }
  expect_failures = [var.cf_zone_plan_pro]
}

run "reject_zone_dnssec_enabled" {
  command = plan
  variables {
    cf_zone_dnssec_enabled = true
  }
  expect_failures = [var.cf_zone_dnssec_enabled]
}

run "reject_migration_import_app" {
  command = plan
  variables {
    cf_migration_import_app = true
  }
  expect_failures = [var.cf_migration_import_app]
}
