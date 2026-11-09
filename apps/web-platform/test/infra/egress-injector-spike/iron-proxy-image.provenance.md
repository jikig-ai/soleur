# iron-proxy image provenance (egress injector spike, #12517)

Test-path only. No production config references this image.

## Pin

| Field | Value | Label |
|---|---|---|
| Image | `docker.io/ironsh/iron-proxy@sha256:727da0cc35a6d73ed2913a38d56c4b9b4476c075149492e4fbf75552e83361ff` | measured (`docker image inspect`, RepoDigests) |
| Tag at retrieval | `0.56.0` (published only on Docker Hub as `ironsh/iron-proxy`; `ghcr.io/ironsh/iron-proxy` returns not found) | measured |
| Image created | 2026-11-04T21:39:34Z, `linux/amd64` | measured |
| `--version` | `0.56.0` | measured |
| Source | `github.com/paradigmxyz/iron-proxy` (Go module path `github.com/ironsh/iron-proxy`), tag `v0.56.0` = commit `3d96ce8dd2ca093051b75ccb0c9e5e1db52d1c04` | measured (`git clone --branch v0.56.0`) |
| Licence | Apache-2.0 | measured (GitHub API) |
| Release cadence | v0.54.0 2026-10-21, v0.55.0 2026-11-02, v0.56.0 2026-11-04 | measured (GitHub API) |
| Release build | goreleaser `dockers_v2`, `Dockerfile.release` = `alpine:latest` + the release binary (base not digest-pinned upstream) | read from file |
| gRPC client | `grpc-go/1.83.0` (user-agent the hook receives) | measured |
| Hook proto | `proto/transform/v1/transform.proto` at the commit above | read from file |
| Retrieved | 2026-11-09 | measured |

Contributor count, bus-factor review and mirroring into our registry are preconditions for #11637's production adoption, not spike criteria.

## Tracer (Phase 0.5) answers

Run 2026-11-09 on a workstation (docker 29.9.2), `env -i`, throwaway `HOME`, `GIT_CONFIG_GLOBAL=/dev/null`, all containers on one `docker network create --internal` network with no route out. Stub destination (`github.com`, `api.github.com`, `other.example`) on a test root; a Node CONNECT proxy requiring `Proxy-Authorization: Basic workspace:<token>` stands in for the forwarder; a logging gRPC hook on a `unix:` socket; the decoy credential reaches iron-proxy as a `type: file` secret source. Clients are hand-written CONNECT + TLS + HTTP/1.1 so headers and framing are exact.

| # | Question | Answer | Evidence |
|---|---|---|---|
| 1 | Upstream chaining with proxy authorization | **Yes** | `proxy.upstream_proxy.https_proxy: http://workspace:<token>@upstream:3128`; the upstream received `CONNECT github.com:443` with `Proxy-Authorization` user `workspace` and no `Authorization` header. iron-proxy pools upstream tunnels (3 upstream CONNECTs for 7 client requests). |
| 2 | Selective termination (non-inject host tunneled, not terminated) | **No** | In `tls.mode: mitm` every TLS tunnel is terminated: `other.example` was served a session-CA leaf (`issuer=tracer-session-ca`, `subject=other.example`), which the name-constrained CA makes invalid (`authorized=false`). Source: `internal/proxy/tunnel.go` `serveTunnelWithReader` MITMs on any `0x16` first byte; the only bypass is DNS-mode `dns.passthrough`, which an explicit `HTTPS_PROXY` client never uses. |
| 3 | Hook body access, gzip and chunked `POST git-receive-pack`; REJECT body shown to the client | **Yes** | gzip: the hook receives the body still gzip-encoded (`1f8b…`) with `Content-Encoding: gzip`, so the parser must gunzip. Chunked: the hook receives the de-chunked body (140 bytes, no `Transfer-Encoding` header), so the parser need not de-chunk. A REJECT with status 403 and a body reached the client verbatim, and the stub recorded no request. |
| 4 | Test upstream root without disabling verification | **Yes** | `SSL_CERT_FILE=<test root>` on the iron-proxy process. Control: with the system bundle instead, the request fails 502 `x509: certificate signed by unknown authority`. |
| 5 | Whole-`Authorization` replacement in configuration only | **Yes** | `secrets` `inject` mode (`headers.Set` deletes every case variant then sets one). No client header: the stub received exactly one injected `Authorization`. Three client copies (`Authorization`, `authorization`, `AUTHORIZATION`): the stub received exactly one, the injected value. The hook (ordered before `secrets`) saw the client's three values, not the real one. |
| 6 | Dead or frozen hook fails closed; bound | **Fails closed; no bound for a frozen hook** | Hook socket gone: 502 in under 1 ms, nothing reaches the stub. Hook alive but not answering: iron-proxy waited until the hook process was killed (25.4 s in this run) and then returned 502; it applies no deadline of its own (`internal/transform/grpc/grpc.go` passes the request context unchanged). Nothing reached the stub in either case. |
| 7 | Per-session `Proxy-Authorization` on CONNECT | **Yes, through the hook only** | iron-proxy has no native inbound proxy authentication. It runs the transform pipeline on a synthetic CONNECT that carries the client's `Proxy-Authorization`; the hook returned 407 for a missing or wrong value and CONTINUE for the right one, and iron-proxy strips the header before the upstream. The check covers only hosts the gRPC transform's `rules` match: a CONNECT to `other.example` was tunneled with no proxy authorization at all. |
| 8 | gRPC over `unix:` with per-call metadata | **`unix:` yes; per-call metadata no** | `target: unix:///…/hook.sock` works. The hook receives only `user-agent` as metadata; there is no configuration for per-call metadata. Configuration alternative, measured: `grpc.tls` with a per-session client certificate over the same `unix:` socket. The hook saw the client certificate CN (`sessA`) on every call, and an injector presenting a certificate from another root was refused (the request failed closed, 403). |
| 2b | `allowlist` transform for the inject hosts refuses a CONNECT straight to a non-inject host | **Yes** | With `allowlist.domains` set to the inject hosts, a CONNECT to `other.example` sent directly to iron-proxy got 403 (`allowlist:reject` in the audit line) and the upstream recorded no CONNECT for it. |
| 7b | gRPC transform with no `rules` sends every CONNECT to the hook | **Yes** | With `rules` omitted, the hook received the CONNECT for `other.example` and returned 407 without the credential; with the credential the CONNECT passed the hook and the allowlist then refused it (403). |
| 9b | `http_listen`, `https_listen` and the metrics listener unreachable once bound to loopback | **Yes, after rebinding all three** | With `http_listen: 127.0.0.1:8081`, `https_listen: 127.0.0.1:8443` and `metrics.listen: 127.0.0.1:9090`, a second container on the same network got `ECONNREFUSED` on 8081, 8443, 80, 443 and 9090, and reached `tunnel_listen` (8080). The metrics listener defaults to `:9090` on all interfaces (`internal/config/config.go` `applyDefaults`) and was reachable before it was rebound. The management listener starts only when `management.listen` is set. |
| — | Sandbox-to-injector binding mechanism | **Not measured here** | Needs the SDK/SRT sandbox on the production run tuple; criterion 5 probes it. |

Configuration hazard found on the way: `proxy.http_listen` is the DNS-redirect plain-HTTP listener. A CONNECT sent there is forwarded to the upstream proxy as a request, and the `secrets` transform injects the real credential onto it, so the forwarder received `Authorization: Basic x-access-token:<decoy>`. Explicit-proxy clients must use `proxy.tunnel_listen`, and `http_listen` must be bound where no sandbox can reach it.

Items 2 and 8 were "no" answers, so per CTO ruling F-b the run stopped and went to the CTO (2026-11-10, rulings R24–R27 in `knowledge-base/project/specs/feat-agent-runtime-sandbox-eval/decision-challenges.md`): a per-session CONNECT router in front of iron-proxy replaces selective termination (R24), a per-session client certificate on the hook channel replaces the nonce (R25), authentication runs at both layers with every listener but `tunnel_listen` on loopback (R26), and a frozen-hook arm joins criterion 8 (R27). The three add-on checks the CTO required before Phase 1 (2b, 7b, 9b) are all "yes".
