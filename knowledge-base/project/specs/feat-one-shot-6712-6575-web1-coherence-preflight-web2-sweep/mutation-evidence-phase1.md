# Phase 1 mutation evidence — build-integrity assertions

Target: `plugins/soleur/test/cloud-init-user-data-size.test.ts`,
inside `describe("Dockerfile <-> server.tf baked-set parity (AC2)")`.

Runner: `bun test` (the file imports `bun:test`; `scripts/test-all.sh:287` invokes this
suite as `run_suite "plugins/soleur" bun test plugins/soleur/`). **Not** vitest — the
task brief offered vitest as the likely runner; that was incorrect for this file.

All commands below run from the worktree root:
`/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-6712-6575-web1-coherence-preflight-web2-sweep`

---

## Why a mutation proof is required

A negative assertion over a regex that never matches passes vacuously forever. Each of the
three additions below is a negative assertion (`expect(...).toEqual([])` or a
"comment does not change the set" invariant), so the only proof they can ever go red is an
actual mutation that turns them red. Each mutation was applied, observed RED, and reverted.

---

## Baseline (unmutated tree) — GREEN

```
$ bun test plugins/soleur/test/cloud-init-user-data-size.test.ts
bun test v1.3.11 (af24e281)

 30 pass
 0 fail
 79 expect() calls
Ran 30 tests across 1 file. [262.00ms]
```

27 tests before this phase, 30 after (+3).

---

## Mutation 1 — duplicate entry (proves Assertion B)

Assertion under test: `host_script_files contains no duplicate entries`.

**Mutation applied:**

```bash
perl -0pi -e 's{^(    "vector\.toml",\n)}{$1    "vector.toml",\n}m' \
  apps/web-platform/infra/server.tf
```

Result — `server.tf:64-65` both read `"vector.toml",`.

**RED output:**

```
609 |   test("host_script_files contains no duplicate entries", () => {
610 |     const tf = serverTfBakedSet();
611 |     const duplicates = [...new Set(tf.filter((f, i) => tf.indexOf(f) !== i))];
612 |     expect(duplicates).toEqual([]);
                             ^
error: expect(received).toEqual(expected)

- []
+ [
+   "vector.toml",
+ ]

- Expected  - 1

(fail) Dockerfile <-> server.tf baked-set parity (AC2) > host_script_files contains no duplicate entries

 27 pass
 3 fail
 76 expect() calls
Ran 30 tests across 1 file. [347.00ms]
```

The assertion names the offending filename. (The other 2 failures are the pre-existing
list-parity and count-of-30 tests, which a duplicate also legitimately breaks — Assertion B
is the one that diagnoses *why*.)

**Reverted** from a pre-mutation backup; `git diff --stat apps/web-platform/infra/server.tf`
returned empty.

---

## Mutation 2 — content-mutating RUN after the COPY (proves Assertion A)

Assertion under test:
`no RUN after the host-scripts COPY mutates the baked directory's content`.

**Mutation applied:**

```bash
perl -0pi -e 's{^(RUN chown -R 1001:1001 /opt/soleur\n)}{$1RUN echo tampered > /opt/soleur/host-scripts/x\n}m' \
  apps/web-platform/Dockerfile
```

Result — `Dockerfile:210` inserts `RUN echo tampered > /opt/soleur/host-scripts/x`
immediately after the allow-listed `chown`.

**RED output:**

```
593 |     // metadata and NOTHING ELSE: file CONTENT is byte-identical before and after, so the
594 |     // sha256-over-contents that both sides compute is unaffected. Anything else reaching
595 |     // this path — `sed -i`, a `>` or `>>` redirect, `install`, `cp`, `truncate`, `chmod`
596 |     // combined with a rewrite — alters content and MUST fail here.
597 |     const OWNERSHIP_ONLY = /^RUN chown -R 1001:1001 \/opt\/soleur$/;
598 |     expect(touching.filter((r) => !OWNERSHIP_ONLY.test(r))).toEqual([]);
                                                                  ^
error: expect(received).toEqual(expected)

- []
+ [
+   "RUN echo tampered > /opt/soleur/host-scripts/x",
+ ]

- Expected  - 1
+ Received  + 3

(fail) Dockerfile <-> server.tf baked-set parity (AC2) > no RUN after the host-scripts COPY mutates the baked directory's content

 29 pass
 1 fail
 78 expect() calls
Ran 30 tests across 1 file. [172.00ms]
```

Exactly one failure — the assertion is specific, not collateral — and the diagnostic prints
the offending instruction verbatim.

**Reverted** from a pre-mutation backup; `git diff --stat apps/web-platform/Dockerfile`
returned empty.

---

## Mutation 3 — remove the comment strip (proves the 1.2 parser hardening)

Assertion under test:
`a quoted filename inside a comment does not enter the parsed set`.

Phase 1.2's hardening is itself a negative claim, so it needs the same treatment: without a
mutation, a fixture that passes proves nothing about whether the strip is load-bearing.

**Mutation applied** — deleted the comment-strip line from `parseHostScriptFiles`:

```diff
     const body = (defMatch?.[1] ?? "")
       .split("\n")
-      .filter((line) => !/^\s*#/.test(line))
       .join("\n");
```

**RED output:**

```
627 |     # the bootstrap also installs "phantom.toml" to /etc/soleur — prose, not an entry
628 |     "beta.conf",
629 |   ]
630 | }`;
631 |     expect(parseHostScriptFiles(clean)).toEqual(["alpha.sh", "beta.conf"]);
632 |     expect(parseHostScriptFiles(commented)).toEqual(parseHostScriptFiles(clean));
                                                  ^
error: expect(received).toEqual(expected)

@@ -3,3 +3,3 @@
    "beta.conf",
+   "phantom.toml",
  ]

- Expected  - 0
+ Received  + 1

(fail) ... > a quoted filename inside a comment does not enter the parsed set

 29 pass
 1 fail
 78 expect() calls
Ran 30 tests across 1 file. [142.00ms]
```

The phantom entry appears in the parsed set exactly as predicted. **Reverted.**

---

## Final state (all mutations reverted) — GREEN

```
$ git status --short
 M plugins/soleur/test/cloud-init-user-data-size.test.ts

$ bun test plugins/soleur/test/cloud-init-user-data-size.test.ts
bun test v1.3.11 (af24e281)

 30 pass
 0 fail
 79 expect() calls
Ran 30 tests across 1 file. [152.00ms]
```

`server.tf` and `Dockerfile` are byte-clean; no mutation was committed.

---

## Anti-vacuity design notes

- **Assertion A anchors on `^RUN\s`** — a Dockerfile instruction keyword at line start.
  Whole-line `#` comments are stripped from the region *before* the anchor is applied, and
  `\`-continuations are folded first, so a mutation hidden on a continuation line is still
  seen as part of its logical instruction. A prose mention of the word "RUN" cannot satisfy
  this anchor.
- **Assertion A carries two live floors** beyond the negative claim: `runs.length > 0` (if
  the parser ever yields zero instructions the filter is trivially satisfied), and
  "the allow-listed chown is present exactly once" (if the chown is renamed or removed, the
  exemption stops silently covering nothing and must be re-justified).
- **The allow-list is ownership-only by construction.** `chown -R 1001:1001 /opt/soleur`
  rewrites owner uid/gid in layer metadata and nothing else; file CONTENT is byte-identical
  across it, so `local.host_scripts_content_hash` (sha256 over contents) is unaffected. The
  regex is fully anchored (`^...$`) against the exact form, so `chown` combined with any
  other operation does not match.
- **Assertion B preserves duplicates deliberately.** `parseHostScriptFiles` maps-then-sorts
  rather than de-duplicating into a `Set`, precisely so a duplicate survives to be detected.
  A future refactor to `new Set(...)` inside the parser would make Assertion B vacuous — a
  note in the parser records this.
- **The fixture exercises the real parser.** `parseHostScriptFiles` is parameterized on
  source text and `serverTfBakedSet()` delegates to it, so the comment fixture tests the
  same code path `server.tf` goes through. A fixture against a reimplementation would have
  proven nothing.

---

## Out-of-scope observation (not caused by Phase 1)

`bun test plugins/soleur/` reports **13 failures** in `terraform-target-parity.test.ts` and
`stock-preflight-coverage.test.ts`. These are **not** related to Phase 1 — that file is
untouched here, and the Phase 1 target file passes 30/30 in isolation.

Their cause is Phase 2's sweep landing in this shared worktree concurrently (both the
`warm_standby` and `web_2_recreate` job definitions are now absent from
`.github/workflows/apply-web-platform-infra.yml`, while those two test files still assert
their target sets). Repairing them is Phase 3.2's scope per the plan.
