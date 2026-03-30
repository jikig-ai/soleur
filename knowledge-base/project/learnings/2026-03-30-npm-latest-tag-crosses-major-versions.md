# Learning: npm @latest tag crosses major version boundaries during dependency upgrades

## Problem

When triaging Dependabot security alerts, `npm install next@latest` pulled Next.js 16.x instead of the intended 15.x upgrade. The same happened with `npm install eslint-config-next@latest`. The `@latest` npm dist-tag always resolves to the highest published version regardless of the currently installed major version, silently crossing major version boundaries. This required rolling back and reinstalling with the correct major version tag.

## Solution

When upgrading a dependency within a major version range, always pin the major version in the install command:

1. **Use `npm install <pkg>@<major>`** (e.g., `next@15`, `eslint-config-next@15`) to stay within the current major
2. **Never use `@latest`** for in-place upgrades -- it resolves to the newest version globally, not the newest within your range
3. **After installing, verify** the resolved version in `package.json` before committing -- catch cross-major jumps immediately

For Dependabot alerts specifically, the triage workflow was:

1. **Runtime deps first** -- upgrade packages that ship to production
2. **Dev-only deps second** -- upgrade build/test tooling
3. **Dismiss with justification** -- alerts on transitive dev-only deps where the vulnerable path is unreachable
4. **Align peer deps** -- after upgrading a framework, align its ecosystem packages to the same version

## Session Errors

1. **`npm install next@latest` pulled Next.js 16.x instead of 15.x** -- Recovery: reinstalled with `npm install next@15`. Prevention: always use `@<major>` tag for upgrades within a major version.
2. **`npm install eslint-config-next@latest` pulled 16.x** -- Recovery: reinstalled with `eslint-config-next@15`. Prevention: same rule as above.
3. **Pillow QA scenario could not run locally** -- PEP 668 system Python restriction prevented `pip install` without a venv. Accepted upgrade based on changelog review. Prevention: use a virtualenv for Python dependency verification.

## Key Insight

`npm install <pkg>@latest` is not "upgrade to the latest compatible version" -- it is "install whatever `npm view <pkg> dist-tags.latest` returns." For major-version-aware upgrades, always specify the major: `<pkg>@15`, `<pkg>@3`, etc.

## Tags

category: dependency-management
module: apps/web-platform
