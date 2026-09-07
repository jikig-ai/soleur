#!/usr/bin/env bash
set -uo pipefail
MY_API_TOKEN=$(cat /dev/null)
printf 'len=%s\n' "${#MY_API_TOKEN}"
