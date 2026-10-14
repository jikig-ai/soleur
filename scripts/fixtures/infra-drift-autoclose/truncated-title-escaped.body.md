## Drift Detected

**Stack:** `web-platform`
**Detected:** 2000-01-01 00:00 UTC
**Workflow:** [Run #1](https://example.invalid/runs/1)

Terraform `plan -detailed-exitcode` returned exit code 2, indicating infrastructure has drifted from the Terraform state.

&lt;details&gt;&lt;summary&gt;Plan output (truncated)&lt;/summary&gt;

```
  # hcloud_firewall_attachment.example will be updated in-place
  ~ resource "hcloud_firewall_attachment" "example" {
        id           = "3333333"
      ~ server_ids   = [
          + 6666666,
        ]
    }

  # terraform_data.deploy_pipeline_fix must be replaced
-/+ resource "terraform_data" "deploy_pipeline_fix" {
      ~ id = "7777777" -> (known after apply)
    }

  # hcloud_server_network.example must be replaced
-/+ resource "hcloud_server_network" "example" {
      ~ id = "8888888" -> (known after apply)
    }

Plan: 2 to add, 1 to change, 2 to destroy.

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

&lt;/details&gt;
