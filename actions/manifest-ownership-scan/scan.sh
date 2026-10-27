#!/usr/bin/env bash
#
# Scan a Codefly plugin working tree for delivery/ownership concepts that must
# never appear in a manifest-only Kubernetes plugin. A conforming plugin is a
# deterministic manifest producer: it must not know about Git, GitHub, pull
# requests, Argo CD / Flux, or repository/revision binding.
#
# Exclusions are path-based only. Release automation and test fixtures are
# allowed to reference Git; runtime source and generated plugin-owned output get
# no exceptions.
#
# Environment:
#   SCAN_ROOT             directory to scan (default: .)
#   EXTRA_EXCLUDE_PATHS   newline-separated glob patterns to exclude, in
#                         addition to the built-in defaults
#
# Exit status: 0 when clean, 1 when any forbidden concept is found.

set -euo pipefail

SCAN_ROOT="${SCAN_ROOT:-.}"

# Path globs excluded from the scan. `*` spans '/'. Release automation and test
# fixtures necessarily name concepts that runtime code may not own.
DEFAULT_EXCLUDES='.git
.git/*
*/.git/*
.github/*
*/.github/*
.coderabbit.yaml
scripts/publish/*
*/scripts/publish/*
scripts/release/*
*/scripts/release/*
release/*
*/release/*
*_test.*
*.test.*
*.spec.*
test_*.*
testdata/*
*/testdata/*
fixtures/*
*/fixtures/*
tests/*
*/tests/*
Tests/*
*/Tests/*
__tests__/*
*/__tests__/*'

# Forbidden concepts as "label::regex" pairs. Matching is case-insensitive;
# token boundaries keep ordinary identifiers such as ApplicationController
# from looking like ownership.
PATTERNS=(
  'Argo/Flux API group::argoproj\.io|fluxcd\.io'
  'Argo/Flux client::github\.com/argoproj/argo-cd|github\.com/fluxcd/|argocd[-_/]?client|flux[-_/]?client'
  "Argo Application::kind[\"']?[[:space:]]*:[[:space:]]*[\"']?Application([\"']|[^[:alnum:]_]|$)|(type|class|struct|interface)[[:space:]]+Application([^[:alnum:]_]|$)"
  "Argo AppProject::kind[\"']?[[:space:]]*:[[:space:]]*[\"']?AppProject([\"']|[^[:alnum:]_]|$)|(type|class|struct|interface)[[:space:]]+AppProject([^[:alnum:]_]|$)"
  'Repository URL binding::(^|[^[:alnum:]_])(repoURL|repositoryURL|repository_url|repository-url)([^[:alnum:]_]|$)'
  # A bare token is ownership where the syntax BINDS it: a manifest key or list
  # entry, an assignment (`cfg.Branch = ...`), a field declaration, a struct tag,
  # a struct-literal field, a setter call. Matching the word anywhere made an
  # English comment read as repository binding — a finding about a word rather
  # than about ownership — while matching only a line-start identifier would let
  # `cfg.Branch = branchFromManifest()` sail through the guard that exists to
  # catch it. A plain READ (`req.Revision == ""`) stays allowed: reading a
  # released contract field owns neither the type nor a binding. The explicit
  # spellings and refs/heads/ stay matched wherever they appear.
  "Repository branch binding::(^|[^[:alnum:]_])(repoBranch|repositoryBranch|repository_branch|repository-branch|gitBranch|git_branch|git-branch)([^[:alnum:]_]|$)|refs/heads/|^[[:space:]]*(-[[:space:]]*)?[\"']?branch[\"']?[[:space:]]*(:|=[^=])|^[[:space:]]*branch[[:space:]]+[^[:space:]]|(^|[{;])[[:space:]]*(var|const)[[:space:]]+branch[[:space:]]+[^[:space:]]|^[[:space:]]*type[[:space:]]+[[:alnum:]_]+[[:space:]]+struct[[:space:]]*[{]([^}]*;)?[[:space:]]*branch[[:space:]]+[^[:space:]]|[\"']branch[\"'][[:space:]]*:|:[\"']branch[\"']|[.>]branch[[:space:]]*=[^=]|[{,][[:space:]]*branch[[:space:]]*:|(set|with)_?branch[[:space:]]*\\("
  # Same rule as Branch above, including var/const and inline fields,
  # while preserving the allowed selector read.
  "Repository revision binding::(^|[^[:alnum:]_])(targetRevision|repoRevision|repositoryRevision|repository_revision|repository-revision|gitRevision|git_revision|git-revision)([^[:alnum:]_]|$)|^[[:space:]]*(-[[:space:]]*)?[\"']?revision[\"']?[[:space:]]*(:|=[^=])|^[[:space:]]*revision[[:space:]]+[^[:space:]]|(^|[{;])[[:space:]]*(var|const)[[:space:]]+revision[[:space:]]+[^[:space:]]|^[[:space:]]*type[[:space:]]+[[:alnum:]_]+[[:space:]]+struct[[:space:]]*[{]([^}]*;)?[[:space:]]*revision[[:space:]]+[^[:space:]]|[\"']revision[\"'][[:space:]]*:|:[\"']revision[\"']|[.>]revision[[:space:]]*=[^=]|[{,][[:space:]]*revision[[:space:]]*:|(set|with)_?revision[[:space:]]*\\("
  'Git library::github\.com/(go-git/go-git|libgit2/git2go|src-d/go-git)/|org\.eclipse\.jgit|git2::Repository|simple-git|isomorphic-git|nodegit|GitPython|dulwich'
  'GitHub API client::github\.com/google/go-github/|github\.com/shurcooL/githubv4|github\.NewClient|@octokit/|PyGithub|githubkit|octocrab'
  'Pull request operation::PullRequest|pull_request|pull-request|pulls\.(Create|Edit|List|Merge)'
  "Git process execution::Command(Context)?\\([^)]*[\"']git[\"']|Command::new\\([\"']git[\"']\\)"
  'Git command::(^|[;&|()[:space:]])git[[:space:]]+(clone|init|fetch|pull|push|commit|checkout|switch|branch|tag|remote|merge|rebase|reset|rev-parse|ls-remote|worktree|archive)([;&|()[:space:]]|$)'
  "Git command::[\"']git[\"'][,[:space:]]+[\"'](clone|init|fetch|pull|push|commit|checkout|switch|branch|tag|remote|merge|rebase|reset|rev-parse|ls-remote|worktree|archive)[\"']"
)

validate_extra_excludes() {
  local pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    case "$pattern" in
      *..*)
        echo "manifest-ownership-scan: invalid exclusion '$pattern': parent traversal is not allowed." >&2
        return 2
        ;;
      .github | .github/* | */.github/* | .coderabbit.yaml | scripts/publish/* | */scripts/publish/* | \
        scripts/release/* | */scripts/release/* | release/* | */release/* | \
        *_test.* | *.test.* | *.spec.* | test_*.* | \
        testdata/* | */testdata/* | fixtures/* | */fixtures/* | tests/* | */tests/* | \
        Tests/* | */Tests/* | __tests__/* | */__tests__/*)
        ;;
      *)
        echo "manifest-ownership-scan: invalid exclusion '$pattern': only release automation and test-fixture paths may be excluded." >&2
        return 2
        ;;
    esac
  done <<<"${EXTRA_EXCLUDE_PATHS:-}"
}

matches_any_exclude() {
  local path="$1" pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # shellcheck disable=SC2254 # intentional glob match, not literal
    case "$path" in
      $pattern) return 0 ;;
    esac
  done <<EOF
$DEFAULT_EXCLUDES
${EXTRA_EXCLUDE_PATHS:-}
EOF
  return 1
}

is_scannable() {
  case "$1" in
    # Like plain go.sum (not a source extension below), a generated checksum
    # lock records dependency bytes, not runtime imports or ownership.
    go.sum.tmpl | */go.sum.tmpl | *.md.tmpl)
      return 1
      ;;
    *.go | *.rs | *.py | *.rb | *.java | *.kt | *.kts | *.swift | *.c | *.cc | *.cpp | *.h | *.hpp | \
      *.js | *.jsx | *.ts | *.tsx | *.sh | *.bash | *.yaml | *.yml | *.json | *.jsonnet | *.tmpl | \
      *.gotmpl | *.tpl | Dockerfile | */Dockerfile)
      return 0
      ;;
  esac
  return 1
}

validate_extra_excludes
cd "$SCAN_ROOT"

# Collect scannable files, sorted for deterministic reporting.
files=()
while IFS= read -r -d '' file; do
  rel="${file#./}"
  matches_any_exclude "$rel" && continue
  is_scannable "$rel" || continue
  files+=("$rel")
done < <(find . -type f -print0 | sort -z)

violations=0
for pair in "${PATTERNS[@]}"; do
  label="${pair%%::*}"
  regex="${pair#*::}"
  [ "${#files[@]}" -eq 0 ] && break
  # grep across the file list; -I skips binaries, -H/-n give file:line context.
  if hits="$(grep -EnIHi "$regex" -- "${files[@]}")"; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      echo "FORBIDDEN [$label] $line"
      violations=$((violations + 1))
    done <<<"$hits"
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "manifest-ownership-scan: grep failed while checking $label." >&2
      exit "$status"
    fi
  fi
done

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "manifest-ownership-scan: FAILED — $violations forbidden reference(s) in runtime/generated output."
  echo "A manifest-only plugin must not own Git/GitHub/Argo/repository responsibilities."
  exit 1
fi

echo "manifest-ownership-scan: clean — no forbidden ownership concepts found in ${SCAN_ROOT}."
