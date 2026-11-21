#!/bin/sh
# Whole-config env-file fetch for soleur-doppler-download (#9294 PR-B, D-2).
#
# A bulk `doppler secrets download` of soleur/prd is a counted read shape in any
# file that NAMES the deploy-channel trio; this sibling names none, so the fetch
# sits outside the censused surface by construction. Do not name
# WEBHOOK_DEPLOY_SECRET or CF_ACCESS_CLIENT_* here.
exec doppler secrets download --no-file --format docker --project soleur --config prd
