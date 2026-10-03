## Drift Detected

**Stack:** `web-platform`
**Detected:** 2000-01-01 00:00 UTC
**Workflow:** [Run #1](https://example.invalid/runs/1)

Terraform `plan -detailed-exitcode` returned exit code 2, indicating infrastructure has drifted from the Terraform state.

<details><summary>Plan output</summary>

```
Warning: Ignoring Doppler secrets already defined in the environment due to --preserve-env flag
terraform_data.example_a: Refreshing state... [id=1111111]
hcloud_server.web["web-1"]: Refreshing state... [id=2222222]
hcloud_firewall_attachment.example: Refreshing state... [id=3333333]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  ~ update in-place
-/+ destroy and then create replacement

Terraform will perform the following actions:

  # hcloud_server.web["web-2"] must be replaced
-/+ resource "hcloud_server" "web" {
      ~ id          = "4444444" -> (known after apply)
        name        = "example-web-2"
    }

  # hcloud_server.git_data must be replaced
-/+ resource "hcloud_server" "git_data" {
      ~ id          = "5555555" -> (known after apply)
        name        = "example-git-data"
    }

Plan: 2 to add, 0 to change, 2 to destroy.

Changes to Outputs:
  ~ example_output = "a" -> (known after apply)

Warning: Argument is deprecated

  with example_resource.this,
  on example.tf line 1, in resource "example_resource" "this":
   1: resource "example_resource" "this" {

This argument is deprecated.

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```

</details>

## Next Steps

1. Review the plan output above
2. Close this issue when resolved
