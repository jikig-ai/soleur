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

Note the last row: **the plan's own "highest observed-safe product 441 (44 MB)"
datapoint does not reproduce** — that exact pattern blows up. So the planned
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

## `\grep` is not an escape hatch

Backslash suppresses **alias** expansion, not **function** lookup. Verified:
`\foo` still runs the function `foo`. So `\grep` is fully shimmed and must stay
gated. The real bypasses are `command grep` and a path-qualified `/usr/bin/grep`
(both reach GNU grep 3.12).

## What shipped

- **Guard 1 (the real fix)** — `guardrails:block-catastrophic-grep-repeat` in
  `.claude/hooks/guardrails.sh`. Denies pre-flight at cost ≥ 500, where cost is
  ∏(upper+1). Calibration: highest observed-safe product 441 (44 MB), lowest
  clearly-bad 961 (672 MB). Common multi-bound patterns stay well clear — an
  IPv4 regex (four `[0-9]{1,3}`) costs 256.
- **Guard 2 (backstop)** — `.claude/hooks/memory-cap.sh`, a fail-soft cgroup v2
  `memory.max=12 GB` on the agent process tree.

Two implementation traps, both load-bearing:

- **Scan `$COMMAND`, not `$SCAN`.** `strip_command_bodies` blanks quoted bodies,
  and a grep pattern is *always* inside quotes. A `$SCAN`-based guard sees
  nothing and silently never fires — it would have tested green in principle and
  protected nothing. Assert the deny path, not just the allow path.
- **Tokenize with `xargs -n1`.** This removes the entire false-positive class:
  in `git commit -m "... grep -noE '.{0,80}(a|b)' ..."` the whole message is one
  token whose command word is `git`, so no `grep` token exists to trigger on.

## The mutation battery earned its keep

The 16 fixtures went 16/16 green on the first run. A 9-mutation battery then
found **three assertions that could not fail**:

- The `\{`→`{` normalization was dead — the extraction regex already matched
  `{0,80}` *inside* `\{0,80}`, so only the `\}`→`}` half did any work.
- `\grep` normalization was dead — GNU xargs already strips a leading backslash
  outside quotes.
- The `*/grep` bypass entry was unreachable — arming requires the *exact* token
  `grep`, so a path-qualified grep never armed the guard in the first place.

All three were removed rather than kept. Dead code in a guard is worse than
absent code: it advertises a protection the guard does not actually provide, and
the next reader budgets no further thought for that case. Re-run: 8/8 killed.

The two survivors were only distinguishable from real coverage by *measuring*
what the tokenizer does, not by reading the code:

```
$ printf '%s\n' 'X -n ".\{0,80\}b\{0,120\}" f' | xargs -n1
.\{0,80\}b\{0,120\}      # backslashes PRESERVED inside double quotes
$ printf '%s\n' '\X -n "a" f' | xargs -n1
X                        # backslash STRIPPED outside quotes
```

## Sharp edges

- **Never "verify" this by re-running the reproducer uncapped.** It will take the
  machine down again. Every probe here ran under `ulimit -v` + `timeout`.
- Verifying that a memory cap **kills** something does not require allocating the
  cap. AC7c was proven in a separate **256 MB** cgroup (`oom_kill 1`, exit 137) —
  same kernel mechanism, bounded blast radius. Testing a 12 GB cap by allocating
  12 GB would risk reproducing the incident.
- Moving a process into a new cgroup does **not** migrate its existing charge:
  `memory.current` reads 0 immediately after the move and grows with new
  allocations. That is fine here (a runaway allocates fresh) but it means the cap
  bounds *subsequent* allocation, not total footprint.
- The cgroup lives under a systemd slice that is not `Delegate=`, so a
  `systemctl daemon-reload` may garbage-collect it and the cap lapses silently.
  It fails toward "no cap", never toward "blocked session", and the next
  SessionStart restores it.

## Residual

Under a cap the blowup dies by **SIGSEGV after ~45 s at 2.7 GB** (measured at a
3 GB cap) — ugrep does not handle allocation failure gracefully. Guard 2 bounds
the damage; it does not prevent ~45 s of 100% CPU. **Guard 1 is the real fix.**
