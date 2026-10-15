#!/usr/bin/env bash
# Shared `gh` stub for the standing-delegation suites (verifier, gate, hook). Test fixture, not production code.
# Answers ONLY these argv shapes (every other argv is refused with exit 64 after logging STUB-MISS), all reads:
#   repo view --json nameWithOwner --jq .nameWithOwner
#   api repos/<o>/<r>/issues/comments/<id> | collaborators/<login>/permission | issues/<n>
#   pr view <n> --json state,mergeCommit,baseRefName
#   run list --workflow <wf> --status <s> --limit 5 --json databaseId
#   run list --workflow <wf> --commit <sha> --limit 5 --json status,conclusion
# State comes from files in $STUB_DIR (comment-<id>.json, perm-<login>.json, issue-<n>.json, repo.txt, pr-<n>.json,
# runs-<wf>-<status>.json, green-<wf>-<sha>.json); mode-<what> files hold `404` or `net` to simulate a failure.
#!/usr/bin/env bash
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
if [ "${1:-} ${2:-}" = "pr view" ]; then
  [ "$#" -eq 5 ] && [ "$4" = "--json" ] && [ "$5" = "state,mergeCommit,baseRefName" ] || miss "$@"
  fail_mode mode-pr; [ -f "$d/pr-$3.json" ] || { echo "no pull request found" >&2; exit 1; }; cat "$d/pr-$3.json"; exit 0
fi
if [ "${1:-} ${2:-}" = "run list" ]; then
  if [ "$#" -eq 10 ] && [ "$3" = "--workflow" ] && [ "$5" = "--status" ] && [ "$7" = "--limit" ] && [ "$8" = "5" ] && [ "$9" = "--json" ] && [ "${10}" = "databaseId" ]; then
    fail_mode mode-run; f="$d/runs-$4-$6.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi; exit 0
  fi
  if [ "$#" -eq 10 ] && [ "$3" = "--workflow" ] && [ "$5" = "--commit" ] && [ "$7" = "--limit" ] && [ "$8" = "5" ] && [ "$9" = "--json" ] && [ "${10}" = "status,conclusion" ]; then
    fail_mode mode-run; f="$d/green-$4-$6.json"; if [ -f "$f" ]; then cat "$f"; else echo '[]'; fi; exit 0
  fi
  miss "$@"
fi
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
