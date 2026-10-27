#!/usr/bin/env bash
#
# Behavioral tests for scan.sh. Run locally or from the self-test workflow.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
scan="$here/scan.sh"
failures=0

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; failures=$((failures + 1)); }

# A clean manifest-only tree passes, even though it contains a Git-driven
# release workflow under .github/ and a *_test.go fixture full of GitOps terms.
if out="$(SCAN_ROOT="$here/testdata/clean" bash "$scan" 2>&1)"; then
  pass "clean tree passes"
else
  fail "clean tree should pass but failed:"$'\n'"$out"
fi

# A synthetic runtime Git/Argo/GitHub dependency and generated Argo Application
# output must fail the scan.
if out="$(SCAN_ROOT="$here/testdata/dirty" bash "$scan" 2>&1)"; then
  fail "dirty tree should fail but passed:"$'\n'"$out"
else
  pass "dirty tree fails"
  for label in \
    "Git library" \
    "GitHub API client" \
    "Git process execution" \
    "Pull request operation" \
    "Argo/Flux API group" \
    "Argo/Flux client" \
    "Argo Application" \
    "Argo AppProject" \
    "Repository URL binding" \
    "Repository branch binding" \
    "Repository revision binding" \
    "Git command"; do
    if grep -qF "[$label]" <<<"$out"; then
      pass "dirty tree reports: $label"
    else
      fail "dirty tree missed concept: $label"
    fi
  done
fi

# Checksums can describe transitive test dependencies, without importing them
# in the generated runtime. The generated source and module declarations still
# carry ownership evidence and must remain visible beside those checksums.
if out="$(SCAN_ROOT="$here/testdata/checksum-metadata" bash "$scan" 2>&1)"; then
  pass "generated Go dependency checksums are metadata"
else
  fail "checksum metadata should pass but failed:"$'\n'"$out"
fi
if out="$(SCAN_ROOT="$here/testdata/generated-client" bash "$scan" 2>&1)"; then
  fail "generated GitHub client source and declaration should fail"
else
  for file in main.go.tmpl go.mod.tmpl; do
    if grep -qF "[GitHub API client] templates/factory/code/$file:" <<<"$out"; then
      pass "generated client remains detected in $file"
    else
      fail "generated client missed in $file:"$'\n'"$out"
    fi
  done
fi

# Canonical Go identifiers must be detected without relying on a YAML copy of
# the same concept elsewhere in the tree.
if out="$(SCAN_ROOT="$here/testdata/runtime-identifiers" bash "$scan" 2>&1)"; then
  fail "runtime ownership identifiers should fail but passed"
else
  for expectation in \
    "[Argo Application] runtime.go:3:" \
    "[Argo AppProject] runtime.go:4:" \
    "[Repository URL binding] runtime.go:7:" \
    "[Repository branch binding] runtime.go:8:" \
    "[Repository revision binding] runtime.go:9:"; do
    if grep -qF "$expectation" <<<"$out"; then
      pass "runtime identifier reports: ${expectation%%] *}]"
    else
      fail "runtime identifier scan missed: $expectation"$'\n'"$out"
    fi
  done
fi

# Reading a released RPC request field named Revision is not ownership: the
# plugin declares neither the type nor a repository binding. The declaration
# form stays a violation, as the runtime-identifiers fixture above asserts.
if out="$(SCAN_ROOT="$here/testdata/contract-field" bash "$scan" 2>&1)"; then
  pass "reading a released contract revision field is not ownership"
else
  fail "contract field read should pass but failed:"$'\n'"$out"
fi

# Prose is not ownership. The English words "branch" and "revision" in a
# comment that explains control flow name no repository — including when the
# comment QUOTES them, which a quoted-key pattern reds unless it requires the
# colon that makes a key a key. A gate that reports either answers about a word
# rather than about ownership. Every binding spelling still fails, below.
if out="$(SCAN_ROOT="$here/testdata/runtime-prose" bash "$scan" 2>&1)"; then
  pass "a comment explaining control flow, quoting either word, is not binding"
else
  fail "prose comment should pass but failed:"$'\n'"$out"
fi

# Every spelling that BINDS a branch or revision stays a violation: a manifest
# key, a list entry, a field declaration, a struct tag, a selector assignment
# (`cfg.Branch = "main"`), a setter call (`cfg.SetBranch(...)`), a
# struct-literal field (`Source{Branch: ...}`) and a bare assignment. Catching
# only the last of those — the one nobody writes in Go — would leave the guard
# green on every real binding.
if out="$(SCAN_ROOT="$here/testdata/token-declaration-forms" bash "$scan" 2>&1)"; then
  fail "token declaration forms should fail but passed:"$'\n'"$out"
else
  for expectation in \
    "[Repository branch binding] runtime.go:4:" \
    "[Repository branch binding] runtime.go:12:" \
    "[Repository branch binding] runtime.go:14:" \
    "[Repository branch binding] runtime.go:15:" \
    "[Repository branch binding] runtime.go:16:" \
    "[Repository branch binding] source.yaml:3:" \
    "[Repository branch binding] source.yaml:6:" \
    "[Repository revision binding] runtime.go:5:" \
    "[Repository revision binding] runtime.go:13:" \
    "[Repository revision binding] runtime.go:15:" \
    "[Repository revision binding] source.yaml:4:"; do
    if grep -qF "$expectation" <<<"$out"; then
      pass "token declaration reported: $expectation"
    else
      fail "token declaration scan missed: $expectation"$'\n'"$out"
    fi
  done
fi

# Go declarations are bindings even with var/const prefixes or inline fields.
# Prose and contract reads above must remain clean under the same matcher.
if out="$(SCAN_ROOT="$here/testdata/go-declarations" bash "$scan" 2>&1)"; then
  fail "Go binding declarations should fail but passed"
else
  for expectation in \
    "[Repository branch binding] source.go:4:" \
    "[Repository revision binding] source.go:5:" \
    "[Repository branch binding] source.go:9:" \
    "[Repository revision binding] source.go:10:" \
    "[Repository branch binding] source.go:13:" \
    "[Repository revision binding] source.go:13:"; do
    if grep -qF "$expectation" <<<"$out"; then
      pass "Go declaration reported: $expectation"
    else
      fail "Go declaration missed: $expectation"$'\n'"$out"
    fi
  done
fi

# Excluded paths must not be the reason a dirty tree fails: prove the release
# workflow's git@github.com and the fixture's argoproj.io are never reported
# for the clean tree.
out="$(SCAN_ROOT="$here/testdata/clean" bash "$scan" 2>&1 || true)"
if grep -q "FORBIDDEN" <<<"$out"; then
  fail "clean tree reported a violation from an excluded path:"$'\n'"$out"
else
  pass "excluded release automation and test fixtures are not scanned"
fi

# Fixture exclusions leave runtime violations visible.
if out="$(SCAN_ROOT="$here/testdata/dirty" EXTRA_EXCLUDE_PATHS=$'pkg/runtime/fixture_test.go\ntemplates/fixtures/*' bash "$scan" 2>&1)"; then
  fail "fixture exclusions must not hide runtime violations:"$'\n'"$out"
else
  pass "fixture exclusions leave runtime violations visible"
fi

# Runtime and generated-output exclusions are invalid.
if out="$(SCAN_ROOT="$here/testdata/dirty" EXTRA_EXCLUDE_PATHS=$'pkg/*\ntemplates/*' bash "$scan" 2>&1)"; then
  fail "runtime exclusions should be rejected but passed:"$'\n'"$out"
elif grep -qF "only release automation and test-fixture paths may be excluded" <<<"$out"; then
  pass "runtime exclusions are rejected"
else
  fail "runtime exclusion failed without the expected diagnostic:"$'\n'"$out"
fi

echo ""
if [ "$failures" -gt 0 ]; then
  echo "scan_test: $failures assertion(s) failed."
  exit 1
fi
echo "scan_test: all assertions passed."
