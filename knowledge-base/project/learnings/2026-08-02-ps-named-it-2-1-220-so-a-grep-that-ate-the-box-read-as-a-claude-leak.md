# Learning: `ps` named it "2.1.220", so a grep that ate the box read as a Claude Code leak

## Problem

On 2026-08-01 a parallel session ran a one-line regex search against a **single
21 kB markdown file**. It reached **9.5 GB RSS in 171 s at 99% CPU and was still
climbing**, driving a 31 GB box to 691 MB free with swap at 88.5%. The operator's
terminal crashed, killing six sessions at once.

This had happened before, more than once, and had never been root-caused. The
reason is the single most useful thing in this file:

**The process is invisible as a cause.** Claude Code's shell snapshot installs a
bash **function** named `grep` that transparently re-execs the `claude` binary
with `argv[0]=ugrep`. So `ps` renders the runaway as `COMMAND 2.1.220` — the
claude *version directory* — never as `grep` and never as `ugrep`. Every prior
occurrence therefore read as "Claude Code is leaking memory," which is a
believable-and-wrong story that survives casual inspection. Nobody looks for a
regex engine when the process table says the agent is at fault.

Verify the shim before theorising about any grep-shaped resource anomaly:

```
$ type -t grep       # -> function   (NOT file)
$ declare -f grep    # -> re-execs "${CLAUDE_CODE_EXECPATH}" with argv[0]=ugrep
```

## Both prescribed mechanisms were wrong, and measurement said so

The fix was specified before it was measured. **Both halves of the specification
were refuted by hard-capped probes** (`ulimit -v` + `timeout` on every run; the
reproducer was never once run uncapped).

### 1. The trigger is not what it looks like

The prescribed detector was "bounded repeat `{n,m}` **AND** alternation `|`".
That is wrong **on both sides**:

| Pattern | Alternation? | Result |
|---|---|---|
| `.{0,80}cannot[^.]{0,120}` | **no** | blowup — killed at cap |
| `.{0,8}(NEVER\|MUST NOT)` | **yes** | 8.8 MB / 0.1 s |

Alternation is nearly irrelevant. Had the prescribed heuristic shipped, it would
have blocked the cheap case and allowed the one that froze the desktop — a guard
that is worse than nothing, because it *reads* as protection.

### …and the replacement cost model was ALSO wrong (caught at review)

The plan replaced that heuristic with "two or more BOUNDED repeats, cost =
∏(upper+1), deny at ≥ 500". **That model is wrong in both directions**, which is
the more interesting finding, because it was itself derived from measurement and
therefore felt settled.

**Width of the repeated class is the discriminator — not the bound product.**
Re-measured 2026-08-02, hard-capped (`ulimit -v 2000000` + `timeout`), against a
31 kB fixture:

| Pattern | ∏(upper+1) | Peak RSS | Plan's verdict |
|---|---|---|---|
| `[0-9]{0,80}x[0-9]{0,120}` | 9801 | **7.5 MB** | deny ❌ |
| `[0-9a-f]{8}-…-[0-9a-f]{12}` (UUID) | 14625 | **7.5 MB** | deny ❌ |
| `[0-9]{4}-[0-9]{2}-[0-9]{2}T…` (ISO ts) | 1215 | **7.5 MB** | deny ❌ |
| `^\+(<{7}\|={7}\|>{7})` | 512 | **7.4 MB** | deny ❌ |
| `.{0,16}q[^.]{0,16}` | 289 | **BLOWUP** | allow ❌ |
| `.{0,20}(a\|b\|c\|d\|e\|f)[^.]{0,20}` | 441 | **BLOWUP** | allow ❌ |

A **narrow** class (`[0-9]`, `[0-9a-f]`, a literal) stays cheap even at a product
of 9801, because DFA state count scales with the SIZE of the repeated set. Only
`.` and a negated class `[^…]` are wide enough to explode. The wide-class ladder,
one literal between two repeats:

| ∏(upper+1) | 25 | 49 | 81 | 121 | 169 | 289 |
|---|---|---|---|---|---|---|
| Peak RSS | 7.7 MB | 8.3 MB | 12 MB | 30 MB | 103 MB | **BLOWUP** |

Note the 441 row of the comparison table above: **the plan's own "highest
observed-safe product 441 (44 MB)" datapoint does not reproduce** — that exact
pattern blows up. So the planned
threshold of 500 sat *above* the real danger point (~150), and would have shipped
a guard that misses genuine blowups while denying **22 benign call sites in this
repo** — including the conflict-marker regex inside `guardrails.sh` itself.

A **single** bounded repeat is always cheap, however large: `.{0,10000}cannot` =
60 MB / 0.6 s. GNU grep runs the reproducer in 7 MB / 0.1 s.

The shipped model: count only bounded repeats over a WIDE atom (`.`, `[^…]`, or a
group close, counted conservatively); fewer than two → allow; else deny at
∏(upper+1) ≥ **150**.

### 2. `ulimit -v` is categorically incompatible with this toolchain

The prescribed backstop was `ulimit -v ~4 GB`. Measured: **vitest dies instantly
at every cap tested — 6, 8, 12, 16, 24 and even 32 GB — at only 97 MB of actual
RSS**, with `WebAssembly.instantiate(): Out of memory`. Uncapped it passes (12702
tests, 898 MB peak).

V8/WASM *reserves* enormous virtual address space; `ulimit -v` counts
**reservations, not usage**. A 32 GB cap on a 31 GB box still fails. The quantity
that actually exhausts a machine is RSS, so the backstop must be a cgroup v2
`memory.max`, which limits RSS.

## What shipped: nothing. PR #7151 was closed unmerged.

That is the finding, not a footnote. Two guards were built, fully tested
(74/74 and 26/26), mutation-tested twice (10/10 and 7/7 killed), shellcheck
clean, and green on a 243/243 full suite. An 8-agent review then established
that **neither one worked**.

### The cost model was refuted three times, each time by measurement

Each model was *derived from measurement* and therefore felt settled. Each was
measured against fixtures its own author chose.

| # | Model | Refuted by |
|---|---|---|
| 1 | bounded repeat **AND** alternation | A no-alternation pattern blows up; a bounded-repeat-plus-alternation pattern costs 8.8 MB. Wrong on both sides. |
| 2 | ∏(upper+1) ≥ 500 over any bounded repeat | Denies UUIDs, ISO timestamps, SHA-256 pairs and the conflict-marker regex *inside `guardrails.sh` itself* (~7 MB each); allows a genuine blowup at product 289 — including the plan's own "highest observed-safe 441" datapoint, which does not reproduce. |
| 3 | ∏(upper+1) ≥ 150 over a **wide** atom (`.`, `[^…]`) | Positive classes of any width blow up when the literal between them is reachable. |

**The third refutation is the one that ends the approach.** Same pattern, same
bound product; the only variable is whether the literal occurs in the subject:

| Pattern | Literal in corpus? | Peak RSS |
|---|---|---|
| `[0-9]{0,80}x[0-9]{0,120}` | no | 7.3 MB |
| `[0-9]{0,80}5[0-9]{0,120}` | **yes** | **1.67 GB — killed** |
| `[a-z]{0,80}q[a-z]{0,120}` | yes | **killed** |
| `[[:print:]]{0,80}q[[:print:]]{0,120}` | yes | **killed** |
| `.{0,80}Z[^.]{0,120}` (wide, literal absent) | no | **killed** |

The first row was fixture **G21 — the evidence for "narrow classes are cheap."**
It measured 7.5 MB only because `x` never appears in the subject, so ugrep
prefilters on the literal and never builds the DFA. Every "cheap" datapoint in
the calibration ladder shares that confound.

Real cost is a function of **class size × bound magnitude × literal
reachability against the specific input**. A static regex-shape heuristic in a
PreToolUse hook cannot see the third factor at all, because the input is a file
it has not read. That is not a threshold to retune; it is a missing variable.

### Transferable lesson

**A calibration ladder is only as good as the axis you forgot to vary.** All
three models were built by sweeping *one* axis (alternation, then bound product,
then class width) while holding the corpus fixed. The corpus was the variable
that mattered. Before trusting any measured threshold, ask: *what did I hold
constant across every datapoint, and would varying it change the verdict?*

## The guard also leaked, in ways the tests could not see

Independent of the model, review found seven forms that reach the shim and are
**not** gated — `X=$(grep …)`, backtick substitution, `(grep …)` subshell,
`G=grep; $G …`, `P='…'; grep "$P"`, `eval "grep …"`, and `grep -f patternfile`.
Command substitution is the common one: `count=$(grep -c …)` is a first-class
agent idiom, and the 2026-08-01 incident is described as exactly "a one-liner".

Arming compared the token to the literal string `grep`; `xargs -n1` yields
`$(grep`, `` `grep ``, `(grep`, none of which match. The header comment asserted
that exact-token arming "is what makes every non-shim form safe" — a confident
claim about a predicate (*does this word resolve to the bash function*) that the
code did not implement (*is this word spelled `grep`*).

Also measured false negatives inside the model: `{n,}` over a wide class blows
up (`.{16,}q[^.]{16,}` → 1.07 GB) but was discarded as "unbounded, ignore", and
its fixture used a narrow pattern so it pinned the wrong contract; and
`\\.{0,16}q[^.]{0,16}` → 1.19 GB, allowed, because the "not preceded by a
backslash" test misfires on an escaped backslash.

## Guard 2 never executed once

`memory-cap.sh` was committed `100644`. `settings.json` invokes the path
directly, so every SessionStart died at `exec` with `EXIT=126`. Both sibling
SessionStart hooks are `100755`.

**Nothing could catch it.** The suite runs `bash "$HOOK"`, which ignores the mode
bit; so does `scripts/test-all.sh`. The live verification of AC7a — a real cgroup
created, `memory.max` read back at 12 GiB — was reached through `bash
memory-cap.sh`, a path production never uses. 26 green assertions, a 7/7 mutation
battery, a live kernel readback and 243/243 CI all sat on top of a hook that
could not run.

**Verify through the invocation production uses, not one that merely reaches the
same code.** The repo already had this gate for `scripts/followthroughs/*.sh`
(`followthrough-exec-bit.test.sh`, which deliberately asserts the *index* mode
via `git ls-files -s`); its glob does not reach `.claude/hooks/`.

And when it did run, the design was wrong in four independent ways:

- **It escaped the terminal's kill switch.** The cgroup was created as a
  *sibling* of the terminal's systemd scope, so `claude` was no longer a scope
  member and closing the terminal would not reap it. "Never modify the terminal's
  own scope" is what caused this; the side effect was never checked.
- **The cap sat above the harm point.** The desktop froze at 9.5 GB; the cap was
  12 GB. It would not have fired before the freeze it was built to prevent.
  Sizing was measured against *honest* workloads (4.9× `tsc`) and never against
  the *harm* threshold.
- **No aggregate bound.** Per-pid keying means N sessions × 12 GB on a 31 GB box.
  Two honest 11 GB sessions pass both guards and reproduce the freeze.
- **Swap was never capped.** `memory.swap.max` defaults to `max`, so a capped
  runaway still drives the 2 GB swapfile to exhaustion — and "swap at 88.5%" is
  the *observed symptom* of the original incident.

The sanctioned API existed and was missed: systemd adopts a live PID into a scope
via `StartTransientUnit` with `PIDs=`, verified working on this box with no sudo.
With `--slice=soleur-agents.slice` it also supplies the aggregate bound. The
"move a live process vs. launch into a capped scope" framing was a false
dichotomy. Related: the documented `systemctl daemon-reload` GC caveat **does not
reproduce** on systemd 259 — a load-bearing comment describing a risk that isn't
real while omitting the one that is.

## A confirmed RCE in the hook layer (pre-existing, 10 files)

`guardrails.sh` and nine siblings parse hook input as:

```sh
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "") …"')"
```

`jq @sh` shell-quotes each **array element as a separate word**, so a non-string
`.tool_input.command` makes `eval` read word 1 as an assignment and words 2+ as a
command:

```
input : {"tool_input":{"command":["x","touch","/tmp/…/PWNED"]}}
jq    : COMMAND='x' 'touch' '/tmp/…/PWNED' TOOL_NAME='Bash' FILE_PATH=''
result: marker file created — the hook executed it
```

Confirmed by execution, before the permission prompt, with full operator
privileges. Pre-existing on `main`; filed separately. Fix: force a scalar in jq
(`| if type=="string" then . else tojson end`) or drop `eval` for `mapfile -d ''`.

Note the fail-open half is *correct* — a PreToolUse hook that denies every
command on a jq hiccup bricks the session. The defect is that the disarm is
**silent**: malformed JSON yields empty stdout, exit 0, no incident. That is
precisely why the plan's own broken discoverability probe (a `printf` emitting
invalid JSON) was indistinguishable from a working guard, and could never have
returned a deny for *any* rule.

## Sharp edges worth keeping

- **Never re-run the reproducer uncapped.** Every probe here ran under
  `ulimit -v 2000000` + `timeout`.
- **Verifying that a memory cap kills does not require allocating the cap.** The
  kill mechanism was proven in a separate **256 MB** cgroup (`oom_kill 1`, exit
  137) — same kernel path, bounded blast radius. Testing a 12 GB cap by
  allocating 12 GB risks reproducing the incident.
- **A probe returning the same result on every arm — including a known-positive
  control — is an un-run instrument, not a clean result.** The first cost probe
  reported empty for the control; only after the control provably fired (rc=124
  timeout, rc=139 at 1.69 GB) were the other rows worth reading.
- Moving a process into a new cgroup does **not** migrate its existing charge:
  `memory.current` reads 0 after the move and grows with new allocations.
- **`\grep` is not an escape hatch** — backslash suppresses *alias* expansion,
  not *function* lookup. The real bypasses are `command grep` and a
  path-qualified grep. Note GNU `xargs` already strips a leading backslash
  outside quotes, so tokenization delivered this behaviour, not the guard's own
  normalization.
- The shim is **not** `export -f`'d: `bash -c 'grep --version'` gets GNU grep
  3.12. So the dangerous call can only originate in a top-level Bash-tool command
  string — which is exactly what a PreToolUse hook sees. The 54 hook scripts that
  call `grep` are structurally out of scope. This is the strongest argument for
  the lexical layer, and it points at the design that should have been chosen:
  PreToolUse supports `updatedInput`, so rewriting `grep` → `command grep`
  sidesteps classification entirely — no cost model, no false positives, no false
  negatives. The caveat is that the shim injects
  `-G --ignore-files --hidden -I --exclude-dir=.git`, so recursive invocations
  need a carve-out.

## Residual

Under a cap the blowup dies by **SIGSEGV after ~45 s at 2.7 GB** (measured at a
3 GB cap) — ugrep does not handle allocation failure gracefully. A memory cap
bounds the damage; it does not prevent ~45 s of 100% CPU.

**The operator's exposure is unchanged as of this writing.** The diagnosis is
solid and the mechanism is understood; no guard is in place. Follow-ups carry the
two candidate designs.
