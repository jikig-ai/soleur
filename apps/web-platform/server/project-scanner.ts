import fs from "fs";
import path from "path";

export interface ProjectHealthSnapshot {
  scannedAt: string;
  category: "strong" | "developing" | "gaps-found";
  signals: {
    detected: { id: string; label: string }[];
    missing: { id: string; label: string }[];
  };
  recommendations: string[];
  kbExists: boolean;
}

interface SignalDefinition {
  id: string;
  label: string;
  paths: string[];
  recommendation: string;
}

const SIGNAL_DEFINITIONS: SignalDefinition[] = [
  {
    id: "package-manager",
    label: "Package manager",
    paths: [
      "package.json",
      "Gemfile",
      "requirements.txt",
      "go.mod",
      "Cargo.toml",
      "pyproject.toml",
      "pom.xml",
    ],
    recommendation:
      "Add a package manifest to declare dependencies and enable reproducible builds.",
  },
  {
    id: "tests",
    label: "Test suite",
    paths: ["test", "tests", "spec", "__tests__"],
    recommendation:
      "Add tests to catch regressions before they ship. The team can scaffold a test directory to get started.",
  },
  {
    id: "ci",
    label: "CI/CD",
    paths: [
      ".github/workflows",
      ".gitlab-ci.yml",
      "Jenkinsfile",
      ".circleci",
    ],
    recommendation:
      "Set up CI/CD to automate testing. GitHub Actions workflows can run on every push.",
  },
  {
    id: "linting",
    label: "Linting",
    paths: [
      ".eslintrc.json",
      ".eslintrc.js",
      ".eslintrc.yml",
      ".eslintrc",
      ".prettierrc",
      ".prettierrc.json",
      ".prettierrc.js",
      "biome.json",
      ".rubocop.yml",
      ".golangci.yml",
    ],
    recommendation:
      "Add a linter to enforce consistent code style across the project.",
  },
  {
    id: "readme",
    label: "README",
    paths: ["README.md", "README.rst", "README.txt", "README"],
    recommendation:
      "Create a README.md to document the project's purpose, setup instructions, and usage.",
  },
  {
    id: "claude-md",
    label: "CLAUDE.md",
    paths: ["CLAUDE.md"],
    recommendation:
      "Add a CLAUDE.md to give AI assistants context about project conventions and patterns.",
  },
  {
    id: "docs",
    label: "Documentation",
    paths: ["docs", "documentation"],
    recommendation:
      "Create a docs directory to house technical documentation, API references, and guides.",
  },
  {
    id: "kb",
    label: "Knowledge Base",
    paths: ["knowledge-base"],
    recommendation:
      "The Knowledge Base will be populated by the deep analysis running now.",
  },
];

function detectSignal(
  workspacePath: string,
  signal: SignalDefinition,
): boolean {
  return signal.paths.some((p) => fs.existsSync(path.join(workspacePath, p)));
}

function categorize(
  detectedCount: number,
): ProjectHealthSnapshot["category"] {
  if (detectedCount >= 6) return "strong";
  if (detectedCount >= 3) return "developing";
  return "gaps-found";
}

export function scanProjectHealth(workspacePath: string): ProjectHealthSnapshot {
  const detected: { id: string; label: string }[] = [];
  const missing: { id: string; label: string }[] = [];
  const missingRecommendations: string[] = [];

  for (const signal of SIGNAL_DEFINITIONS) {
    if (detectSignal(workspacePath, signal)) {
      detected.push({ id: signal.id, label: signal.label });
    } else {
      missing.push({ id: signal.id, label: signal.label });
      missingRecommendations.push(signal.recommendation);
    }
  }

  const recommendations = missingRecommendations.slice(0, 3);

  const kbExists = fs.existsSync(path.join(workspacePath, "knowledge-base"));

  return {
    scannedAt: new Date().toISOString(),
    category: categorize(detected.length),
    signals: { detected, missing },
    recommendations,
    kbExists,
  };
}
