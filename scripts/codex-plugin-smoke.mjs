import { execFileSync, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { existsSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const repoRoot = fileURLToPath(new URL("../", import.meta.url));
const commonDir = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd: repoRoot, encoding: "utf8" }).trim();
const sharedRoot = dirname(commonDir);
const trustForDiscovery = `projects.${JSON.stringify(sharedRoot)}.trust_level="trusted"`;
const child = spawn("codex", ["-c", trustForDiscovery, "app-server"], { cwd: repoRoot, stdio: ["pipe", "pipe", "inherit"] });
const pending = new Map();
let requestId = 0;
const timeout = setTimeout(() => {
  process.exitCode = 1;
  console.error("Codex discovery timed out after 45 seconds.");
  child.kill();
}, 45000);

function request(method, params) {
  return new Promise((resolve, reject) => {
    const id = ++requestId;
    pending.set(id, { resolve, reject });
    child.stdin.write(JSON.stringify({ id, method, params }) + "\n");
  });
}

createInterface({ input: child.stdout }).on("line", (line) => {
  const message = JSON.parse(line);
  const waiter = pending.get(message.id);
  if (!waiter) return;
  pending.delete(message.id);
  if (message.error) waiter.reject(new Error(JSON.stringify(message.error)));
  else waiter.resolve(message.result);
});

child.on("error", (error) => {
  for (const waiter of pending.values()) waiter.reject(error);
});
child.on("exit", (code) => {
  for (const waiter of pending.values()) waiter.reject(new Error("Codex exited: " + code));
  pending.clear();
});

try {
  await request("initialize", { clientInfo: { name: "soleur-smoke", version: "1.0.0" }, capabilities: { experimentalApi: true } });
  child.stdin.write(JSON.stringify({ method: "initialized" }) + "\n");
  const result = await request("skills/list", { cwds: [repoRoot], forceReload: true });
  const entry = result.data[0];
  const skills = entry.skills.filter((skill) => skill.pluginId === "soleur@soleur");
  const expected = readdirSync(new URL("../plugins/soleur/skills/", import.meta.url), { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && existsSync(new URL("../plugins/soleur/skills/" + entry.name + "/SKILL.md", import.meta.url))).map((entry) => entry.name);
  expected.push("go", "help", "sync");
  const missing = expected.filter((name) => !skills.some((skill) => skill.name === "soleur:" + name && skill.enabled));
  const errors = entry.errors.filter((error) => JSON.stringify(error).includes("soleur"));
  if (missing.length || errors.length) {
    throw new Error(JSON.stringify({ missing, errors, discovered: entry.skills.filter((skill) => skill.path.includes("/soleur/")).map(({name, pluginId, enabled}) => ({name, pluginId, enabled})).slice(0, 8) }));
  }
  console.log(JSON.stringify({ plugin: "soleur@soleur", discoveredSkills: skills.length, expectedSkills: expected.length }));
  const hooks = await request("hooks/list", { cwds: [repoRoot] });
  const pluginHooks = hooks.data[0].hooks.filter((hook) => hook.pluginId === "soleur@soleur");
  const projectHooks = hooks.data[0].hooks.filter((hook) => hook.sourcePath === join(sharedRoot, ".codex/config.toml"));
  if (!pluginHooks.some((hook) => hook.command.includes("/hooks/codex-session-start.sh"))) {
    throw new Error("Codex did not discover Soleur's session bootstrap hook.");
  }
  console.log(JSON.stringify({
    pluginHooks: pluginHooks.length,
    projectHooks: projectHooks.length,
    hooksRequiringTrust: pluginHooks.filter((hook) => hook.trustStatus === "untrusted").length,
    hookErrors: hooks.data[0].errors.length,
  }));
  if (hooks.data[0].errors.length) throw new Error("Codex reported hook loading errors.");
  if (projectHooks.length !== 2) throw new Error("Repository hooks are not loaded. Run bash scripts/setup-codex.sh; linked worktrees use the shared repository root's hook configuration.");
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  clearTimeout(timeout);
  child.kill();
}
