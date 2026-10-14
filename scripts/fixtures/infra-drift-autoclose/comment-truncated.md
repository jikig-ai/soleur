Drift still present as of 2000-01-02 00:00 UTC ([run](https://example.invalid/runs/2)).

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

  # terraform_data.example_a must be replaced
-/+ resource "terraform_data" "example_a" {
      ~ id          = "9999999" -> (known after apply)
        triggers_replace = {
            "files" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

</details>

## Next Steps

1. Review the plan output above
2. Close this issue when resolved
