#!/usr/bin/env node
import { spawn } from "child_process";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const packageRoot = join(__dirname, "..");

const args = process.argv.slice(2);
const command = args[0] || "install";

if (command === "install" || command === "setup") {
  const installer = join(packageRoot, "scripts", "install.js");
  const child = spawn("bun", [installer, ...args.slice(1)], { stdio: "inherit" });
  child.on("close", (code) => process.exit(code));
} else if (command === "--help" || command === "-h") {
  console.log("Soleur OpenCode Plugin CLI");
  console.log("");
  console.log("Commands:");
  console.log("  install    Install and configure the Soleur plugin for OpenCode");
  console.log("  help       Show this help message");
} else {
  console.log(`Unknown command: ${command}`);
  console.log("Run 'soleur-opencode help' for usage");
  process.exit(1);
}
