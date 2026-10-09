#!/usr/bin/env bash
# tenant-isolation-inner-probe.sh — the SHARED realized-isolation assertion
# set for #5863 (arm F mountns-only outer wrap). This file runs INSIDE the
# wrap. Every caller passes it as stdin to `bash -s` so the script text
# travels on the pipe, not the filesystem (nothing under /app/scripts is
# bound inside the wrap). Callers — the founder check
# (knowledge-base/project/specs/feat-5863-tenant-fs-isolation/tenant-isolation-probe.sh),
# the deploy canary arm (sandbox-canary.mjs --replay-outer), and the test
# suite — share THIS body so no independently drifting copy can stay green
# while the deployed mount table regresses.
#
# Positional args (inside the wrap):
#   $1 = workspaces-parent dir (e.g. <root>/workspaces)
#   $2 = the session's own workspace path
#   $3 = a sibling workspace path that exists on the HOST but must be
#        absent inside the wrap
#
# Dual vantage per the plan Guard 1 / AC1:
#   (a) Bash-tier: mount table + ls/stat under the parent — what the Bash
#       tool sees through the inner sandbox.
#   (b) File-tool-tier equivalent: a plain read of a sibling file must fail
#       with ENOENT ("No such file or directory"), not EACCES — the file
#       tools run in the wrapped CLI process, whose fs view is exactly this
#       mount namespace. Absence is the claim; a permission error would mean
#       the path is still reachable (different, weaker posture).
#
# `/proc` is intentionally NOT asserted scoped — arm F passes the shared
# container procfs through (#9723 residual). Only fs surfaces are checked.
#
# Prints `isolation_ok` and exits 0 on success; prints `isolation_fail` plus
# a FAIL line per violated assertion and exits 1 otherwise. The positive
# signal is floored: a harness that ran nothing (empty mounts, no checks)
# cannot produce `isolation_ok` — the own-workspace assertions below are
# the anti-vacuity guard (plan mutation row 4).

set -u
PARENT="${1:?usage: tenant-isolation-inner-probe.sh <parent> <own-ws> <sibling-ws>}"
OWN="${2:?}"
SIBLING="${3:?}"

fail=0
bad() { printf 'FAIL: %s\n' "$1"; fail=1; }

# --- vantage (a): own workspace must be present AND usable ----------------
# Anti-vacuity floor: if the wrap never built (or this probe ran unwrapped
# on the host), the own-ws assertions still pin that we are looking at the
# intended mount table.
[ -d "$OWN" ] || bad "own workspace $OWN is not a directory inside the wrap"
[ -r "$OWN" ] || bad "own workspace $OWN is not readable inside the wrap"

# --- vantage (a): sibling absent from stat/ls ----------------------------
if [ -e "$SIBLING" ]; then
  bad "sibling $SIBLING exists inside the wrap (stat succeeded)"
fi
if [ -d "$PARENT" ]; then
  # The workspaces parent is bound only via per-workspace binds; if it
  # resolves at all inside the wrap it must contain nothing but the own
  # workspace entry.
  _seen_own=0
  for _e in "$PARENT"/*; do
    [ -e "$_e" ] || continue
    if [ "$_e" = "$OWN" ]; then _seen_own=1; else bad "unexpected entry under workspaces parent: $_e"; fi
  done
  [ "$_seen_own" -eq 1 ] || printf 'note: parent %s visible but own workspace not listed under it\n' "$PARENT"
fi

# --- vantage (a): mount table carries no sibling-bearing entry ------------
if grep -qF -- "$SIBLING" /proc/self/mounts 2>/dev/null; then
  bad "sibling path $SIBLING appears in /proc/self/mounts"
fi

# --- vantage (b): file-tool-equivalent read → ENOENT, not EACCES ----------
_sib_marker="$SIBLING/marker.txt"
if [ -e "$_sib_marker" ]; then
  bad "sibling file $_sib_marker exists inside the wrap"
fi
_read_err="$(cat "$_sib_marker" 2>&1 >/dev/null)"
_read_rc=$?
if [ "$_read_rc" -eq 0 ]; then
  bad "sibling file $_sib_marker is READABLE inside the wrap"
elif ! grep -qi 'no such file' <<<"$_read_err"; then
  bad "sibling read failed with a NON-absence error: $_read_err"
fi

# --- posture assertions (F2/F3, security-seat) ----------------------------
# Shared /proc is the wrap's documented residual (#9723) — it is ALSO a
# mount-namespace oracle: /proc/<pid>/{root,cwd,ns} reach a same-uid
# process's mount table when ptrace_scope=0. The residual only stays
# acceptable while yama restricts ptrace; assert it here so a sysctl drift
# pages instead of silently voiding the wrap.
_ps="$(cat /proc/sys/kernel/yama/ptrace_scope 2>/dev/null || echo 'unreadable')"
if [ "$_ps" = "0" ]; then
  bad "kernel.yama.ptrace_scope=0 — shared /proc exposes sibling mount namespaces (#9723 residual voided)"
elif [ "$_ps" = "unreadable" ]; then
  printf 'note: ptrace_scope unreadable inside the wrap\n'
fi
# --cap-drop ALL must clear the BOUNDING set under the privileged arm too:
# if bit 21 (cap_sys_admin) survives in CapBnd, the file-cap'd bwrap inside
# the ro-bound /usr can re-elevate to SYS_ADMIN+SETUID+SETGID.
_capbnd="$(awk '/^CapBnd:/ {print $2}' /proc/self/status 2>/dev/null)"
if [ -n "$_capbnd" ]; then
  _bit21=$(( (0x$_capbnd >> 21) & 1 ))
  [ "$_bit21" -eq 0 ] || bad "CapBnd still carries cap_sys_admin (0x$_capbnd) — file-cap'd bwrap inside the wrap can re-elevate"
fi

# --- elevation metadata (NOT part of ok/fail) -----------------------------
# A file-cap'd /usr/bin/bwrap creates no userns: the child inherits the
# container's own uid_map (full-map `0 0 4294967295`). The implicit-userns
# fallback produces a narrow map — the arm Phase 0 measured fatal to the
# inner sandbox. The deploy canary treats `elevation=userns` as
# sandbox_broken; the founder check tolerates it (its explicit
# --unshare-user arm is the documented local fallback).
_elev="userns"
if awk '$1 == "0" && $3 == "4294967295" { found=1; exit } END { if (!found) exit 1 }' /proc/self/uid_map 2>/dev/null; then
  _elev="privileged"
fi
printf 'elevation=%s\n' "$_elev"

if [ "$fail" -eq 0 ]; then
  printf 'isolation_ok\n'
else
  printf 'isolation_fail\n'
fi
exit "$fail"
