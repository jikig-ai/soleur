#!/usr/bin/env bash
set -uo pipefail
TOK="$(doppler secrets get SOME_TOKEN -p soleur -c prd --plain)"
printf 'len=%s\n' "${#TOK}"
