import { readdirSync, statSync } from "fs";
import { join } from "path";
import { sessions } from "./ws-handler";

const WORKSPACES_ROOT = process.env.WORKSPACES_ROOT || "/workspaces";

export function getActiveSessionCount(): number {
  try {
    return sessions.size;
  } catch {
    return 0;
  }
}

export function getActiveWorkspaceCount(): number {
  try {
    return readdirSync(WORKSPACES_ROOT)
      .filter((name) => !name.startsWith(".orphaned-"))
      .filter((name) => {
        try {
          return statSync(join(WORKSPACES_ROOT, name)).isDirectory();
        } catch {
          return false;
        }
      }).length;
  } catch {
    return 0;
  }
}
