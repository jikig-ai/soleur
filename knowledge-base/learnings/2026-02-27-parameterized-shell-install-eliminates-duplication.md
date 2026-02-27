# Learning: Parameterized shell install function eliminates tool-specific duplication

## Problem

When adding auto-install support for multiple CLI tools (ffmpeg, rclone) in a dependency checker script, the initial implementation created separate `install_ffmpeg()` and `install_rclone()` functions. Both had identical structure (~85% overlap): OS detection switch, sudo check, package manager invocation, error messaging. Only the tool name and fallback URL differed.

Three independent code reviewers (security, quality, simplicity) all converged on the same finding: the duplication was the primary code smell.

## Solution

Consolidate into a single parameterized `install_tool()` function that takes the tool name as an argument and passes it directly to `apt-get install -y "$tool"` or `brew install "$tool"`. Extract post-install verification into `verify_install()`.

Before (two functions, 42 lines):
```bash
install_ffmpeg() {
  case "$OS" in
    debian) sudo apt-get install -y ffmpeg ;;
    macos)  brew install ffmpeg ;;
    *)      echo "Manual install: https://ffmpeg.org/download.html" ;;
  esac
}
install_rclone() {
  case "$OS" in
    debian) sudo apt-get install -y rclone ;;
    macos)  brew install rclone ;;
    *)      echo "Manual install: https://rclone.org/install/" ;;
  esac
}
```

After (one function, 16 lines):
```bash
install_tool() {
  local tool="$1"
  case "$OS" in
    debian) sudo apt-get install -y "$tool" ;;
    macos)  brew install "$tool" ;;
    *)      echo "Unsupported OS. Install $tool manually." ;;
  esac
}
```

The refactor reduced the script from 120 to 103 lines and eliminated the function pointer indirection (`$install_fn`) that the security reviewer flagged.

## Key Insight

When multiple shell install functions differ only in the package name, parameterize the name instead of duplicating the function. Package managers (`apt-get`, `brew`) already accept the tool name as an argument — the function structure maps 1:1 to the parameter. The test for this: if a new tool needs the same install path, does it require a new function (bad) or a new call site (good)?

## Tags
category: code-quality
module: feature-video
