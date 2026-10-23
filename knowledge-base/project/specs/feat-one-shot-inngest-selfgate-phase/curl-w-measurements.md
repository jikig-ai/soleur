# Measured: what curl prints for each phase of the Inngest self-gate (issue #10934)

Measured on 2026-10-23, locally, against real servers on 127.0.0.1 (a python `ssl` listener, and a real `stunnel` 5.72 with the production
conf shape from `cloud-init-inngest.yml`: `accept` to `connect 127.0.0.1:8288`, `sslVersionMin = TLSv1.2`, the production `ciphers`). Nothing
production was read or written. The command is the self-gate's exact curl line with a longer `-w`:

```
timeout 20 curl --disable --noproxy '*' -s -o /dev/null \
  -w '%{http_code}|%{time_connect}|%{time_appconnect}|%{ssl_verify_result}|%{num_connects}|%{errormsg}' \
  --connect-timeout 5 --max-time 10 --cacert <pinned cert> https://127.0.0.1:<port>/health
```

Three curl builds: **7.81.0** (the Ubuntu 22.04 package, the oldest userland a web host could plausibly run), **8.5.0** (the Ubuntu 24.04 package;
`server.tf` provisions `ubuntu-24.04`, and the CI runner is the same userland) and **8.23.0** (the dev host). The host's real curl version has
NOT been read (no production reads); the repo facts say 8.5.0. `errormsg` is printed here for the measurement only: it is free text and is never
an event field.

## The fields the event will use are identical on all three builds

`http_code`, `time_connect`, `time_appconnect`, `ssl_verify_result` exist since curl 7.19. `%{errormsg}` and `%{exitcode}` need 7.75, so
they are not used. An unknown `-w` variable prints nothing, exits 0 and warns on stderr (`curl: unknown --write-out variable: 'x'`; measured on 7.81
and 8.5.0), so a misspelled variable is silent: the test stub must refuse any variable it does not model. `-w` output has no trailing newline
(`od -c`, 8.23). Every time printed here uses `.` as the decimal separator; whether a locale could change that was not established (a
`LC_ALL=de_DE.UTF-8` run was not confirmed to have the locale installed), so the parser accepts either `.` or `,`. `timeout` killing curl
(rc 124) prints nothing (7.81 and 8.5.0).

## Measured table (curl 8.5.0 unless stated; columns are rc, http_code, time_connect, time_appconnect, ssl_verify_result, num_connects)

| Phase the gate reached | Scenario | rc | http | t_connect | t_appconnect | verify | nconn | Same on 7.81 / 8.23? |
|---|---|---|---|---|---|---|---|---|
| connect | nothing listening / listener (stunnel) stopped | 7 | 000 | 0.000000 | 0.000000 | 0 | 0 | yes / yes |
| connect | SYN dropped by a firewall (iptables DROP on lo) | 28 (5 s) | 000 | 0.000000 | 0.000000 | 0 | 0 | not run / not run |
| handshake | TCP accepted then closed, no TLS | 35 | 000 | 0.000198 | 0.000000 | 1 | 1 | rc 35 / rc 35 |
| handshake | TCP accepted then RST | 35 | 000 | 0.000140 | 0.000000 | 1 | 1 | rc 35 / rc 35 |
| handshake | plaintext HTTP on the TLS port | 35 | 000 | 0.000134 | 0.000000 | 1 | 1 | rc 35 / rc 35 |
| handshake | TCP accepted, no ServerHello (SSL connection timeout) | 28 (5 s) | 000 | 0.000201 | 0.000000 | 1 | 1 | rc 28 / rc 28 |
| ca_file | `--cacert` file empty (the placeholder) or garbage | 77 | 000 | 0.000452 | 0.000000 | 1 | 1 | 77 / 77; a MISSING file is rc 77 on 7.81 and 8.5.0 but rc 2 with EMPTY `-w` output on 8.23 |
| verify | served certificate is not the pinned one | 60 | 000 | 0.000119 | 0.000000 | 18 | 1 | verify 18 on all three |
| verify | served certificate expired | 60 | 000 | 0.000203 | 0.000000 | 10 | 1 | verify 10 on all three |
| verify | certificate has no matching IP SAN | 60 | 000 | 0.000462 | 0.000000 | **1** | 1 | verify 1 on all three (1 is curl's default "unset") |
| request | TLS completed, server reads the request then RST | 56 | 000 | 0.000107 | 0.005781 | 0 | 1 | 56 / 56 |
| request | TLS completed, clean `close_notify`, no HTTP bytes | 52 | 000 | 0.000125 | 0.008238 | 0 | 1 | 52 / 52 |
| request | TLS completed, TCP closed with no `close_notify` | 52 | 000 | 0.000119 | 0.005153 | 0 | 1 | **7.81: rc 56, 8.23: rc 56** |
| request | TLS completed, non-HTTP bytes back | 1 | 000 | 0.000114 | 0.006970 | 0 | 1 | 1 / 1 |
| request | TLS completed, then silence until `--max-time` | 28 (10 s) | 000 | 0.000155 | 0.004901 | 0 | 1 | 28 / 28 |
| request | **real stunnel, upstream 127.0.0.1:8288 refused** (the incident signature) | **56** | 000 | 0.000138 | 0.004360 | 0 | 1 | measured on 8.5.0 only |
| request | real stunnel, upstream accepts then closes, or RSTs | 52 | 000 | 0.000128 | 0.004774 | 0 | 1 | 8.5.0 only |
| request | real stunnel, upstream silent until `--max-time` | 28 (10 s) | 000 | 0.000184 | 0.007224 | 0 | 1 | 8.5.0 only |
| request | TLS completed, `200` header then the body closes short (truncated, `Content-Length: 100`, 2 bytes sent) | **18** | **200** | 0.000329 | 0.012484 | 0 | 1 | 8.5.0 only (added in the deepen pass); a code of 200 with a non-zero rc is NOT `status` |
| status | TLS completed, `502` header then the body closes short | 18 | 502 | 0.000110 | 0.007349 | 0 | 1 | 8.5.0 only (deepen pass); a non-200 status was received, so it stays `status` |
| status | TLS completed and verified, HTTP 502 (also real stunnel with a 502 upstream) | 0 | 502 | 0.000235 | 0.010363 | 0 | 1 | yes / yes |
| pass | TLS completed and verified, HTTP 200 (also real stunnel with a 200 upstream) | 0 | 200 | 0.000503 | 0.009276 | 0 | 1 | yes / yes |

## What the measurements settle

1. **rc alone cannot name the phase; the times can.** rc 56 appears only after TLS completed (`time_appconnect > 0`) in every row above, and rc 28
   appears in all three phases. `time_connect == 0` is "no TCP connection", `time_appconnect == 0` with `time_connect > 0` is "TCP up, TLS not
   complete", `time_appconnect > 0` with `http_code == 000` is "TLS complete, no HTTP status".
2. **The rc differs between curl builds for the same wire event** (TCP close without `close_notify`: 52 on 8.5.0, 56 on 7.81 and 8.23; a missing
   CA file: 77 or 2). The phase must therefore be derived from the times, with the rc used only for the two codes that name a stage by themselves
   (60 = verification, 77 = CA file).
3. **`ssl_verify_result` is not a stage indicator.** It reads 1 for a hostname mismatch, for a CA-file error, for every handshake failure and for
   a refused TLS record; it reads 0 for a connect failure and for every completed handshake. It is meaningful only with rc 60 (18 pinned certificate
   not the served one, 10 expired).
4. **The production incident (rc=56 http=000) matches only one row family**: TLS completed and verified, then the terminator reset the connection.
   With real stunnel that is the upstream `127.0.0.1:8288` refusing the connection. The certificate, the pinned CA and the listener are not the
   cause for that signature. This is a measured match, not proof of the 2026-10-23 cause (the terminator's journald is not shipped, #10880).
5. **Empty `-w` output happens**: rc 124 (the `timeout 20` wrapper fired) and, on curl 8.23, a missing `--cacert` file (rc 2). Parsing must treat
   an empty or malformed line as `phase=unknown`, never as an error.

## Added during implementation (2026-10-23, curl 8.23.0 on the dev host only)

- A served self-signed certificate that is NOT the pinned one and ALSO has no matching IP SAN printed `000 0.000109 0.000000 1` with rc 60: the name check is reported before the untrusted chain, so `ssl_verify_result` reads 1, not 18. The same certificate pair with a matching `IP:127.0.0.1` SAN printed `000 0.000159 0.000000 18`, rc 60. The 18 row of the table above therefore needs a served certificate that carries the matching address (the real-curl differential row H6 `mismatch` serves one: `loopalt`). Not run on 7.81 or 8.5.0 in this form.
- A served leaf issued by a CA that is not pinned (matching IP SAN) printed `000 0.000145 0.000000 20`, rc 60.
- `curl --cacert /nonexistent/ca.pem` printed a usage error (`option --cacert: is badly used here`), no `-w` output and exited 2.

## Corrections and additions (2026-10-23, review round 1; the text above is left as written)

- **#10880 is not the journald issue.** Wherever this file says the terminator's journald is not shipped "(#10880)", the issue number is wrong: #10880 is "resolve Inngest vector carrier drift against pinned image tag", a `vector.toml` carrier-drift CI guard. The measured fact is that the terminator's own journald is not shipped to Better Stack today: `soleur-inngest-tls.service` runs stunnel with `foreground = yes` and `syslog = no` (`cloud-init-inngest.yml`) and sets no priority, so its output takes systemd's default priority 6, and `vector.toml` Source 1 admits only `inngest-server.service` (any priority) or priority 3-4 from other units; no `vector.toml` entry names the terminator. No issue tracks shipping it.
- **rc 2 is a MISSING CA file.** An EMPTY or garbage `--cacert` file prints rc 77 (curl 8.23.0, re-run on a live TLS listener in review); only a missing file prints rc 2 and no `-w` output on 8.23. In production the candidate is created by `mktemp`, so rc 2 is not reachable through an empty placeholder.
- **The truncated-200 `rc 18` is curl 8.5.0 only.** On curl 8.23.0 a `200` header followed by a TCP close without `close_notify` printed `200 0.000147 0.003847 0` with rc 56 (measured 2026-10-23 on the dev host), and a `200` header followed by a stalled body printed `200 0.000150 0.005328 0` with rc 28 after `--max-time`; both read `http=200 phase=request`. The table above and the profile table in `test-fixtures/curl-w-profiles.sh` (the `req_partial` and `status_partial` rows, whose header sentence lists all three builds) therefore hold rc 18 for 8.5.0 only, as the "Same on 7.81 / 8.23?" column says for each row; read that column, not the fixture header, for build coverage.
- **Four curl 8.23.0 measurements, not three,** are in "Added during implementation": the no-IP-SAN certificate (reads 1), the matching-SAN certificate (reads 18), the non-pinned CA leaf (reads 20) and the missing `--cacert` file (exit 2).
- **No handshake time on rc 60 and rc 77.** Every rc 60 row (verify 18, 10, 1 in the table; 1, 18 and 20 in the 8.23 section) and the rc 77 row printed `time_appconnect` 0.000000, so `phase=verify` and `phase=ca_file` lines read `tcp=<attempts> tls=0`, the same counts as a steady `handshake`.
- **The resolver suite's H6 ran against REAL curl 8.5.0.** On 2026-10-23 the resolver suite ran in an `ubuntu:24.04` container (curl 8.5.0 with OpenSSL 3.0.13, bash 5.2.21): H6 passed 6 of 6 (closed port, accept and close, the pinned-certificate mismatch, TLS then a clean close, 200, 502), including the mismatch row, where a different self-signed certificate carrying the matching loopback IP printed `verify=18` (`/var/tmp/soleur-selfgate/c2-resolver.log`, `252 passed, 0 failed`). The earlier note that the mismatch row was "not run on 7.81 or 8.5.0 in this form" is superseded for 8.5.0 (7.81 still unrun). The rc 58, 83 and 51 codes were never measured; the classifier files them under `handshake` when the connect time is non-zero.
