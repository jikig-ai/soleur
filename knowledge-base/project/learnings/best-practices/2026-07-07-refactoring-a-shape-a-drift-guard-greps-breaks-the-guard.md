# Learning: refactoring a shell shape that a literal-match drift-guard greps for breaks the guard — re-anchor on the invariant

## Problem

The zot registry migration (#6122, PR #6120) refactored several shell constructs in
`ci-deploy.sh`, `cloud-init.yml`, and `server.tf`. Each refactor changed the *textual shape*
of a line that an existing `.test.sh` drift-guard greps for by literal, so the guard went red
(or would have false-passed) even though the invariant it protects still held. This session
hit the class **six times**:

1. **FD-200 guard** (`ci-deploy.test.sh`): grepped `docker pull "$IMAGE:$TAG" 200>&-`; the pull
   was wrapped in `pull_image_with_fallback` with braced `${IMAGE}:${TAG}` → literal miss.
2. **login-precedes-pull** (`cloud-init-ghcr-seed-login.test.sh`): grepped
   `until docker pull "$IMAGE_REF"`; the seed pull became `until docker pull "$REF"`.
3. **cosign non-invocation** (`soleur-host-bootstrap-observability.test.sh` AC1): bare
   `grep -qE 'cosign' cloud-init.yml` matched a NEW *comment* ("cosign digest-pinning is the
   integrity guard") — a comment-prose false-positive, not an invocation.
4. **inngest pin** (`cloud-init-inngest-bootstrap.test.sh`): grepped the pin on the
   `docker pull ghcr.io/…:vX.Y.Z` line; the pin moved to an `IREF=ghcr.io/…:vX.Y.Z`
   assignment (+ a `ZIREF=` sibling), and the pin-ref COUNT dropped 3 → 2.
5. **egress-probe ordering** (`cron-egress-enforce-probe.test.sh`): grepped the terminal
   `docker run` image arg as a bare `${image_name}` line; it became
   `"$(cat /run/soleur-image-ref … || echo '${image_name}')"`.
6. **self-inflicted** (my OWN new `registry-insecure-config.test.sh`): a `grep -F 'systemctl
   reload docker'` matched an explanatory comment containing `` `systemctl reload docker` `` in
   backticks, before the real `"systemctl reload docker"` array element — the same
   comment-prose trap as #3, authored fresh.

## Solution

When a refactor changes the shape a drift-guard greps, update the guard to assert the
**INVARIANT**, not the old literal, and anchor on a token the comment prose cannot carry:

- FD-200 → assert *no* real `docker pull` command line lacks `200>&-` (grep command lines only:
  `^[[:space:]]*(if (! )?)?docker pull `), instead of one literal ref shape.
- login-precedes-pull → grep the new `until docker pull "$REF"` form (invariant: a login
  precedes the seed pull, unchanged).
- cosign → `grep -E cosign | grep -qvE '^[[:space:]]*#'` — a cosign *invocation* is a
  non-comment line; documentation mentioning cosign is not.
- inngest pin → anchor on the `IREF=` assignment (new canonical pin home) + assert the pin-ref
  count is the new value (2), with the comment updated to explain why.
- egress ordering → anchor on the run-arg's unique shape (a line *starting* with the quoted
  `"$(cat /run/soleur-image-ref`, which the `docker pull`/`docker create` sites don't).
- self-trip → anchor on the double-quoted inline-array form `"systemctl reload docker"`, which
  a backtick comment can't match.

## Key Insight

A literal-match drift-guard couples to the *syntax* of the code, not its *invariant* — so any
refactor that preserves the invariant while changing the syntax reddens (or, worse for a
`grep`-for-presence guard, silently false-passes on comment prose). Two anchoring rules make
guards refactor-durable:

1. **Anchor on the invariant, not the literal.** "Every pull closes FD-200", "a login precedes
   the pull", "no cosign *invocation* on the fresh-boot path" survive a wrapper/rename;
   `docker pull "$IMAGE:$TAG" 200>&-` does not.
2. **Anchor on a token the comment prose cannot carry.** A body-grep sees comments too. Match
   the quoted-command / array-element form (`"systemctl reload docker"`), the `var=` assignment,
   or a `^[[:space:]]*` command-line anchor — never a bare literal that also appears in an
   explanatory comment or a backtick citation.

Mutation-test the corollary: after re-anchoring, mentally (or actually) mutate out the guarded
construct and confirm the guard goes red. Extends
[[2026-06-03-drift-guard-assertion-false-passes-on-comment-prose]] (guards false-pass on
comment prose) and the family of `2026-06-02-drift-guard-bare-path-grep-vacuous` learnings —
the new angle here is that *your own refactor* is the most common trigger, and it will hit
multiple sibling guards at once (grep `git grep -l '<old-literal>' apps/**/*.test.sh` after any
shell-shape change to find them all up front).

## Session Errors

1. **Six drift-guard literal-match failures** (enumerated above) — Recovery: re-anchored each on
   the invariant. Prevention: this learning; after changing a shell construct, `git grep -l
   '<old-literal>'` the `.test.sh` set to find every coupled guard before running the suite.
2. **Self-inflicted comment-prose trap** in a freshly-authored guard — Recovery: anchored on the
   quoted form. Prevention: never `grep -F` a bare command string that the same file documents in
   a comment; a doc comment with the command in backticks WILL match.
3. **Bash CWD drift** — a `cd <subdir>` and a relative-path background test resolved against the
   wrong directory. Recovery: absolute paths. Prevention: covered by existing absolute-path
   learnings; use worktree-absolute paths in every Bash call.
4. **Background `exit 0` masking** — a `<cmd>; echo EXIT=$?` bg task reported exit 0 regardless.
   Recovery: grepped the runner's own `Results:` summary. Prevention: covered by
   `2026-05-18-test-all-tail-masking`.
5. **4 ADR cross-link slugs guessed wrong** — Recovery: `ls ADR-NNN*` for real filenames + sed.
   Prevention: covered by `hr-when-a-plan-specifies-relative-paths` (verify each path exists).

## Tags
category: best-practices
module: infra-tests, drift-guards
