// ReDoS harness for PR #9570 fix-round — exact regexes from safe-bash.ts.
// Usage: node redos-bench.mjs <case> <m>   (m = token repeat count)
// Prints match result + elapsed ms. Bounded by outer `timeout`.
const PATH_TOKEN = String.raw`[\w./~+:=@-]+`;

// NEW (fix commit 0ab886b6ad)
const FORCE = String.raw`(?:--list|--show-current|--all|--remotes|--contains|--no-contains|--merged|--no-merged|--points-at|-[arv]*[ar][arv]*)`;
const FLAG = String.raw`(?:${FORCE}|-[v]+|--verbose|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;
const ARM1 = new RegExp(String.raw`^git\s+branch(?:\s+${FLAG})*\s*$`);
const ARM2 = new RegExp(String.raw`^git\s+branch(?=\s+(?:${FLAG}\s+)*?${FORCE}(?=\s|$))\s+${FLAG}(?:\s+(?:${FLAG}|(?!-)${PATH_TOKEN}))*\s*$`);

// OLD (pre-fix, 92bba346af)
const OFLAG = String.raw`(?:--list|--show-current|--all|--remotes|--verbose|-[arv]+|--contains|--merged|--no-merged|--points-at|--sort=${PATH_TOKEN}|--format=${PATH_TOKEN}|--abbrev(?:=\d+)?|--column|--no-column|--color(?:=${PATH_TOKEN})?|--no-color|--ignore-case)`;
const OARM1 = new RegExp(String.raw`^git\s+branch(?:\s+${OFLAG})*\s*$`);
const OARM2 = new RegExp(String.raw`^git\s+branch\s+${OFLAG}(?:\s+(?:${OFLAG}|(?!-)${PATH_TOKEN}))*\s*$`);

const [which, mStr] = process.argv.slice(2);
const m = parseInt(mStr, 10);
let input, re;
switch (which) {
  // Arm1: flag run of multi-parse `-ar` tokens, then a guaranteed-fail char.
  case "arm1-ar":   input = "git branch " + "-ar ".repeat(m) + "?"; re = ARM1; break;
  case "arm1-arar": input = "git branch " + "-arar ".repeat(m) + "?"; re = ARM1; break;
  case "arm1-ra":   input = "git branch " + "-ra ".repeat(m) + "?"; re = ARM1; break;
  // Arm1 with a write flag tail (fails FLAG and (?!-)TOKEN).
  case "arm1-ar-d": input = "git branch " + "-ar ".repeat(m) + "-d"; re = ARM1; break;
  // Arm2-only: `--list x` makes Arm1 fail fast on `x`, lookahead hits --list
  // at position 0, then the body's `-ar` run + failing tail.
  case "arm2-ar":   input = "git branch --list x " + "-ar ".repeat(m) + "?"; re = ARM2; break;
  case "arm2-arar": input = "git branch --list x " + "-arar ".repeat(m) + "?"; re = ARM2; break;
  // Single-parse controls (should stay linear).
  case "arm1-v":    input = "git branch " + "-v ".repeat(m) + "?"; re = ARM1; break;
  case "arm1-v-foo":input = "git branch " + "-v ".repeat(m) + "foo"; re = ARM1; break; // Arm1 fails, Arm2 lookahead fails
  case "arm2-v":    input = "git branch --list x " + "-v ".repeat(m) + "?"; re = ARM2; break;
  // Lookahead-failure path: all modifiers, no force flag, trailing positional.
  case "la-fail":   input = "git branch " + "-v ".repeat(m) + "foo"; re = ARM2; break;
  // Old arms on the same -ar attack (pre-fix baseline).
  case "old1-ar":   input = "git branch " + "-ar ".repeat(m) + "?"; re = OARM1; break;
  case "old2-ar":   input = "git branch --list x " + "-ar ".repeat(m) + "?"; re = OARM2; break;
  // Full-pattern sweep: every pattern tried (mimics SAFE_BASH_PATTERNS loop).
  case "isafe-ar":  input = "git branch " + "-ar ".repeat(m) + "?"; re = null; break;
  default: throw new Error("unknown case " + which);
}

const t0 = performance.now();
let r;
if (which === "isafe-ar") {
  r = ARM1.test(input) || ARM2.test(input);
} else {
  r = re.test(input);
}
const ms = performance.now() - t0;
console.log(`${which} m=${m} len=${input.length} match=${r} ${ms.toFixed(1)}ms`);
