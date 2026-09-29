#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/defaults"

export HOME="$test_home"
export PATH="$mock_bin:$ROOT/bin:$PATH"

# 1. Verify omarchy agent help includes the new subcommands
agent_help=$("$ROOT/bin/omarchy" agent --help)
echo "$agent_help" | grep -Fq "omarchy agent sessions" || fail "omarchy agent --help includes sessions"
echo "$agent_help" | grep -Fq "omarchy agent issues" || fail "omarchy agent --help includes issues"
echo "$agent_help" | grep -Fq "omarchy agent prs" || fail "omarchy agent --help includes prs"
pass "omarchy agent --help advertises sessions, issues, and prs"

# 2. Verify --help on individual commands
sessions_help=$("$ROOT/bin/omarchy-agent-sessions" --help)
echo "$sessions_help" | grep -Fq "omarchy agent sessions" || fail "sessions --help displays usage"
issues_help=$("$ROOT/bin/omarchy-agent-issues" --help)
echo "$issues_help" | grep -Fq "omarchy agent issues" || fail "issues --help displays usage"
prs_help=$("$ROOT/bin/omarchy-agent-prs" --help)
echo "$prs_help" | grep -Fq "omarchy agent prs" || fail "prs --help displays usage"
pass "sessions, issues, and prs provide standard --help"

# 3. Missing dependency checks
cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
[[ $1 == "${OMARCHY_TEST_MISSING:-}" ]]
SH
chmod +x "$mock_bin/omarchy-cmd-missing"

export OMARCHY_TEST_MISSING=fzf
if "$ROOT/bin/omarchy-agent-sessions" >/dev/null 2>"$test_tmp/fzf-err"; then
  fail "sessions fails when fzf is missing"
fi
grep -Fq "fzf is required" "$test_tmp/fzf-err" || fail "sessions warns when fzf is missing"

if "$ROOT/bin/omarchy-agent-issues" >/dev/null 2>"$test_tmp/fzf-err2"; then
  fail "issues fails when fzf is missing"
fi
grep -Fq "fzf is required" "$test_tmp/fzf-err2" || fail "issues warns when fzf is missing"

if "$ROOT/bin/omarchy-agent-prs" >/dev/null 2>"$test_tmp/fzf-err3"; then
  fail "prs fails when fzf is missing"
fi
grep -Fq "fzf is required" "$test_tmp/fzf-err3" || fail "prs warns when fzf is missing"

export OMARCHY_TEST_MISSING=gh
if "$ROOT/bin/omarchy-agent-issues" >/dev/null 2>"$test_tmp/gh-err"; then
  fail "issues fails when gh is missing"
fi
grep -Fq "GitHub CLI (gh) is required" "$test_tmp/gh-err" || fail "issues warns when gh is missing"

if "$ROOT/bin/omarchy-agent-prs" >/dev/null 2>"$test_tmp/gh-err2"; then
  fail "prs fails when gh is missing"
fi
grep -Fq "GitHub CLI (gh) is required" "$test_tmp/gh-err2" || fail "prs warns when gh is missing"
pass "sessions, issues, and prs handle missing dependencies gracefully"

# 4. Sessions empty state
unset OMARCHY_TEST_MISSING
cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin/omarchy-cmd-missing"

# Mock default agent to agy
printf '%s\n' agy >"$test_home/.config/omarchy/defaults/agent"
empty_output=$("$ROOT/bin/omarchy-agent-sessions" 2>&1 || true)
echo "$empty_output" | grep -Eq "No (Antigravity session history|previous Antigravity sessions)" ||
  fail "sessions reports empty Antigravity history"
pass "sessions reports when no previous sessions exist"

# 5. Issues dispatch to agent prompt
cat >"$mock_bin/gh" <<'SH'
#!/bin/bash
if [[ $1 == "issue" && $2 == "list" ]]; then
  printf '42\tFix memory leak in parser\topen\n'
elif [[ $1 == "pr" && $2 == "list" ]]; then
  printf '108\tAdd dark mode theme support\topen\n'
fi
SH

cat >"$mock_bin/fzf" <<'SH'
#!/bin/bash
# Mock fzf selecting the first line
head -n 1
SH

cat >"$mock_bin/omarchy-agent-prompt" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_PROMPT_LOG"
SH

chmod +x "$mock_bin/gh" "$mock_bin/fzf" "$mock_bin/omarchy-agent-prompt"

prompt_log="$test_tmp/prompt_log"
export OMARCHY_TEST_PROMPT_LOG="$prompt_log"

# Run issues and auto-confirm 'y'
printf 'y\n' | "$ROOT/bin/omarchy-agent-issues" --inline >/dev/null
mapfile -d '' -t prompt_args <"$prompt_log"
[[ ${prompt_args[0]} == "--inline" ]] || fail "issues forwards --inline"
echo "${prompt_args[1]}" | grep -Fq "Work on GitHub Issue #42" || fail "issues dispatches correct prompt"
pass "issues selects and launches agent prompt"

# Run prs and auto-confirm 'y'
: >"$prompt_log"
printf 'y\n' | "$ROOT/bin/omarchy-agent-prs" --inline >/dev/null
mapfile -d '' -t prompt_args <"$prompt_log"
[[ ${prompt_args[0]} == "--inline" ]] || fail "prs forwards --inline"
echo "${prompt_args[1]}" | grep -Fq "Review GitHub Pull Request #108" || fail "prs dispatches correct prompt"
pass "prs selects and launches agent prompt"
