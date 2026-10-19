#!/usr/bin/env bash
# Shared `gh` stub for the standing-delegation suites that need the verifier's reads (today: the Technical-Ruling Gate suite,
# which wraps it). Test fixture, not production code. The verifier suite and the hold-evaluator suite keep their own inline
# copies on purpose: each pins its own exact argv.
# Answers ONLY these argv shapes (every other argv is refused with exit 64 after logging STUB-MISS), all reads:
#   repo view --json nameWithOwner --jq .nameWithOwner
#   api repos/<o>/<r>/issues/comments/<id> | collaborators/<login>/permission | issues/<n>
# State comes from files in $STUB_DIR (comment-<id>.json, perm-<login>.json, issue-<n>.json, repo.txt); a mode-<what> file
# (mode-repo, mode-comment-<id>, mode-perm, mode-issue) holds `404` or `net` to simulate a failure.
d="${STUB_DIR:?}"
echo "$*" >> "$d/calls.log"
miss() { echo "STUB-MISS $*" >> "$d/calls.log"; echo "gh stub: unsupported argv: $*" >&2; exit 64; }
fail_mode() {
  case "$(cat "$d/$1" 2>/dev/null)" in
    404) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
    net) echo "error connecting to api.github.com" >&2; exit 1 ;;
  esac
}
if [ "$*" = "repo view --json nameWithOwner --jq .nameWithOwner" ]; then fail_mode mode-repo; cat "$d/repo.txt"; exit 0; fi
[ "$#" -eq 2 ] && [ "$1" = api ] || miss "$@"
p="$2"
case "$p" in
  repos/*/*/issues/comments/*)
    id="${p##*/}"; fail_mode "mode-comment-$id"
    [ -f "$d/comment-$id.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/comment-$id.json" ;;
  repos/*/*/collaborators/*/permission)
    l="${p%/permission}"; l="${l##*/}"; fail_mode mode-perm
    [ -f "$d/perm-$l.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/perm-$l.json" ;;
  repos/*/*/issues/*)
    n="${p##*/}"; fail_mode mode-issue
    [ -f "$d/issue-$n.json" ] || { echo "gh: Not Found (HTTP 404)" >&2; exit 1; }; cat "$d/issue-$n.json" ;;
  *) miss "$@" ;;
esac
