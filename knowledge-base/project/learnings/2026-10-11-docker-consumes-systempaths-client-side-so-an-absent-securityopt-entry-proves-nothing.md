# Learning: docker never records `systempaths=` in SecurityOpt, so its absence proved nothing

## Problem

#10032 read "no `systempaths=` entry in the `hostsec` row" as evidence that docker's default masked `/proc` was in force, and planned to verify the fix by expecting `systempaths=unconfined` in `HostConfig.SecurityOpt` (the hostsec row, `audit-bwrap-uid.sh` Check 2, a mock `docker inspect`). A plan reviewer ran `docker create --security-opt systempaths=unconfined` locally and inspected it: `SecOpt=["no-new-privileges=true"] Masked=[] RO=[]`. The docker CLI consumes the option client-side and expresses it only as empty `MaskedPaths` and `ReadonlyPaths`. The planned verification could never pass on a correct container, and the original inference was empty.

## Solution

Verify the flag through the field docker actually writes: `HostConfig.MaskedPaths` (empty after, the default list before), exposed as `masked=<n>` on the `host` diag row via `{{len .HostConfig.MaskedPaths}}`. Model the REAL docker behaviour in the mock `docker inspect` instead of the behaviour the plan imagined.

## Key Insight

Before using a field as evidence for or against a flag, run the flag once and read the field. A mock built from the author's model of docker will happily pass a verification that the real tool can never satisfy.

## Session Errors

- The plan's Guard 1 anchor, Phase 7.3 pass criteria and two mock rows all assumed a `SecurityOpt` entry. Prevention: for any "assert flag X appears in inspect field Y" criterion, add a plan-time check that names the command that produced the sample output.
- The parity guard's derivation grep was specified from the three known sites; a plan reviewer measured that the bare profile path also matches `audit-bwrap-uid.sh`, `cat-deploy-state.sh`, `server.tf` and comments. Prevention: run the derivation once at plan time and record the hit count.

## Tags
category: workflow-patterns
module: agent-sandbox, ci-deploy, docker
