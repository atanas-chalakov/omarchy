#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Test 1: Empty environment with no history
result=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$TEST_HOME/.gemini/antigravity-cli" "$ROOT/bin/omarchy-agent-usage-agy")

[[ $(jq -r '.id' <<<"$result") == "agy" ]] ||
  fail "Antigravity collector reports id agy" "$result"
pass "Antigravity collector reports id agy"

[[ $(jq -r '.name' <<<"$result") == "Antigravity" ]] ||
  fail "Antigravity collector reports name Antigravity" "$result"
pass "Antigravity collector reports name Antigravity"

[[ $(jq -r '.totalPrompts' <<<"$result") == "0" ]] ||
  fail "Antigravity collector handles empty state" "$result"
pass "Antigravity collector handles empty state"

# Test 2: History with today's prompts and conversations
data_dir="$TEST_HOME/.gemini/antigravity-cli"
mkdir -p "$data_dir/conversations"

now_ms=$(date +%s%3N)
cat >"$data_dir/history.jsonl" <<EOF
{"display":"hello world","timestamp":$now_ms,"workspace":"/home/user","conversationId":"test-conv-1"}
{"display":"second prompt","timestamp":$now_ms,"workspace":"/home/user","conversationId":"test-conv-1"}
EOF

touch "$data_dir/conversations/test-conv-1.db"

result=$(HOME="$TEST_HOME" ANTIGRAVITY_DATA_DIR="$data_dir" "$ROOT/bin/omarchy-agent-usage-agy")

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "Antigravity collector marks ready when prompts exist" "$result"
pass "Antigravity collector marks ready when prompts exist"

[[ $(jq -r '.totalPrompts' <<<"$result") == "2" ]] ||
  fail "Antigravity collector counts total prompts" "$result"
pass "Antigravity collector counts total prompts"

[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Antigravity collector counts today prompts" "$result"
pass "Antigravity collector counts today prompts"

[[ $(jq -r '.totalSessions' <<<"$result") == "1" ]] ||
  fail "Antigravity collector counts total sessions" "$result"
pass "Antigravity collector counts total sessions"

[[ $(jq -r '.recentDays[-1].messageCount' <<<"$result") == "2" ]] ||
  fail "Antigravity collector populates recentDays" "$result"
pass "Antigravity collector populates recentDays"

[[ $(jq -r '.limits | length' <<<"$result") -ge 1 ]] ||
  fail "Antigravity collector populates limits" "$result"
pass "Antigravity collector populates limits"

[[ $(jq -r '.tierLabel' <<<"$result") == "Gemini 3.8 Flash" ]] ||
  fail "Antigravity collector reports tierLabel" "$result"
pass "Antigravity collector reports tierLabel"
