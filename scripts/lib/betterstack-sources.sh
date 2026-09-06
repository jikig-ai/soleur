#!/usr/bin/env bash
# (#7855) The identity of the Better Stack sources this repo reads and writes.
#
# WHY THIS FILE EXISTS. One invariant spans two scripts and was, before this file, enforced across
# THREE independent spellings of the same source joined only by prose:
#
#   scripts/followthroughs/git-data-rung2-evidence-capture.sh  reads  t520508_soleur_inngest_vector_prd_3_logs
#   scripts/followthroughs/betterstack-roundtrip-latency-7855.sh reads the same table by literal
#   ...and refuses to WRITE to                                          s2457081.*
#
# Nothing asserted that `2457081`, `t520508_soleur_inngest_vector_prd_3_logs` and
# `s2457081.eu-fsn-3.betterstackdata.com` name one source. Change the capture's control table to a
# different shared source and the probe's refusal no longer follows — the write-manufactures-its-own-
# control hazard returns silently, at the gate that authorises a production host's birth, with every
# test green. The refusal was PARALLEL to the constraint rather than DERIVED from it.
#
# THE INVARIANT, stated once: never write to whatever source the rung-2 capture reads as its control.
# Both sides now derive from the constants below, so the refusal moves when the control moves.
#
# This is a DATA module, deliberately not a behaviour one: it declares identities and defines no
# functions. `scripts/lib/betterstack-absence.sh` owns the classifier and is untouched by #7855
# (its only other production consumer branches on its token as a string with no default arm, so
# widening it would fail open — see the ADR-192 amendment).

# shellcheck disable=SC2034  # every constant below is consumed by a script that SOURCES this file.
[[ -n "${_BS_SOURCES_LIB_LOADED:-}" ]] && return 0
_BS_SOURCES_LIB_LOADED=1

# ── The CONTROL source (2457081) ─────────────────────────────────────────────────────────────
# Shared, multi-tenant, and chatty. The rung-2 capture asks it "is the warehouse storing anything
# at all", which is the right question for an account-wide refusal. Because that question is
# satisfied by ANY row, nothing this repo writes may ever land here.
BS_CONTROL_SOURCE_ID="2457081"
BS_CONTROL_TABLE="t520508_soleur_inngest_vector_prd_3_logs"
BS_CONTROL_TABLE_S3="t520508_soleur_inngest_vector_prd_3_s3"
# The ingest authority for the SAME source. Derived from the id above rather than restated, so a
# source change cannot move the table and leave the write-refusal pointing at the old host.
BS_CONTROL_INGEST_HOST="s${BS_CONTROL_SOURCE_ID}.eu-fsn-3.betterstackdata.com"

# ── The GIT-DATA source (2734275) ────────────────────────────────────────────────────────────
# Single-tenant. The rung-2 rehearsal reads it as its TARGET, and the round-trip probe is the only
# thing in this repo permitted to write to it.
BS_GIT_DATA_SOURCE_ID="2734275"
BS_GIT_DATA_TABLE="t520508_soleur_git_data_prd_logs"
BS_GIT_DATA_TABLE_S3="t520508_soleur_git_data_prd_s3"
BS_GIT_DATA_INGEST_URL="https://s${BS_GIT_DATA_SOURCE_ID}.eu-central-1a.betterstackdata.com/"
