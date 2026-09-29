#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command jq
require_command python3
require_command sqlite3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# Test 1: Empty environment with no history
result=$(HOME="$TEST_HOME" COPILOT_HOME="$TEST_HOME/.copilot" "$ROOT/bin/omarchy-agent-usage-copilot")

[[ $(jq -r '.id' <<<"$result") == "copilot" ]] ||
  fail "Copilot collector reports id copilot" "$result"
pass "Copilot collector reports id copilot"

[[ $(jq -r '.name' <<<"$result") == "GitHub Copilot" ]] ||
  fail "Copilot collector reports name GitHub Copilot" "$result"
pass "Copilot collector reports name GitHub Copilot"

[[ $(jq -r '.totalPrompts' <<<"$result") == "0" ]] ||
  fail "Copilot collector handles empty state" "$result"
pass "Copilot collector handles empty state"

# Test 2: History with today's prompts and sessions
data_dir="$TEST_HOME/.copilot"
mkdir -p "$data_dir"

sqlite3 "$data_dir/session-store.db" <<EOF
CREATE TABLE sessions (id TEXT PRIMARY KEY, cwd TEXT, repository TEXT, host_type TEXT, branch TEXT, summary TEXT, created_at TEXT, updated_at TEXT);
CREATE TABLE turns (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, turn_index INTEGER, user_message TEXT, assistant_response TEXT, timestamp TEXT);
CREATE TABLE assistant_usage_events (id INTEGER PRIMARY KEY AUTOINCREMENT, session_id TEXT, turn_index INTEGER, agent_id TEXT, parent_tool_call_id TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER, cache_read_tokens INTEGER, cache_write_tokens INTEGER, reasoning_tokens INTEGER, total_nano_aiu INTEGER, request_multiplier REAL, duration_ms INTEGER, time_to_first_token_ms INTEGER, output_ttft_ms REAL, inter_token_latency_ms INTEGER, initiator TEXT, api_endpoint TEXT, reasoning_effort TEXT, finish_reason TEXT, content_filter_triggered INTEGER, token_details_json TEXT, created_at TEXT, copilot_usage_model TEXT);

INSERT INTO sessions VALUES ('s1', '/home/user/work', 'user/repo', 'github', 'main', 'Test feature', datetime('now'), datetime('now'));
INSERT INTO turns VALUES (1, 's1', 0, 'Hello world', 'Hi', datetime('now'));
INSERT INTO turns VALUES (2, 's1', 1, 'Second prompt', 'Sure', datetime('now'));
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, created_at)
  VALUES ('s1', 'gpt-5-mini', 100, 50, 0, 0, datetime('now'));
EOF

result=$(HOME="$TEST_HOME" COPILOT_HOME="$data_dir" "$ROOT/bin/omarchy-agent-usage-copilot")

[[ $(jq -r '.ready' <<<"$result") == "true" ]] ||
  fail "Copilot collector marks ready when prompts exist" "$result"
pass "Copilot collector marks ready when prompts exist"

[[ $(jq -r '.totalPrompts' <<<"$result") == "2" ]] ||
  fail "Copilot collector counts total prompts" "$result"
pass "Copilot collector counts total prompts"

[[ $(jq -r '.todayPrompts' <<<"$result") == "2" ]] ||
  fail "Copilot collector counts today prompts" "$result"
pass "Copilot collector counts today prompts"

[[ $(jq -r '.totalSessions' <<<"$result") == "1" ]] ||
  fail "Copilot collector counts total sessions" "$result"
pass "Copilot collector counts total sessions"

[[ $(jq -r '.recentDays[-1].messageCount' <<<"$result") == "150" ]] ||
  fail "Copilot collector populates recentDays with token count" "$result"
pass "Copilot collector populates recentDays with token count"

[[ $(jq -r '.limits | length' <<<"$result") -eq 0 ]] ||
  fail "Copilot collector reports empty limits without quota data" "$result"
pass "Copilot collector reports empty limits without quota data"

[[ $(jq -r '.tierLabel' <<<"$result") == "GitHub Copilot" ]] ||
  fail "Copilot collector reports tierLabel" "$result"
pass "Copilot collector reports tierLabel"

[[ $(jq -r '.modelUsage["gpt-5-mini"].inputTokens' <<<"$result") == "100" ]] ||
  fail "Copilot collector reports model input tokens" "$result"
pass "Copilot collector reports model input tokens"

# Test 3: Prompt caching subtracts from inputTokens to avoid double-counting
sqlite3 "$data_dir/session-store.db" <<EOF
INSERT INTO assistant_usage_events (session_id, model, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, created_at)
  VALUES ('s1', 'claude-sonnet-4.6', 10000, 500, 9000, 0, datetime('now'));
EOF

result=$(HOME="$TEST_HOME" COPILOT_HOME="$data_dir" "$ROOT/bin/omarchy-agent-usage-copilot")
model_total=$(jq -r '.modelUsage["claude-sonnet-4.6"] | .inputTokens + .outputTokens + .cacheReadInputTokens + .cacheCreationInputTokens' <<<"$result")
[[ $(jq -r '.modelUsage["claude-sonnet-4.6"].inputTokens' <<<"$result") == "1000" ]] ||
  fail "Copilot collector subtracts cache read tokens from input tokens" "$result"
[[ $model_total == "10500" ]] ||
  fail "Copilot collector model row total matches input plus output tokens" "$model_total"
pass "Copilot collector accounts for cache tokens without double counting"

# Test 4: Timezone conversion matches local date across different UTC offsets
if (( 10#$(date -u +%H) >= 10 )); then zone=Etc/GMT-14; else zone=Etc/GMT+12; fi
tz_result=$(TZ=$zone HOME="$TEST_HOME" COPILOT_HOME="$data_dir" "$ROOT/bin/omarchy-agent-usage-copilot")
[[ $(jq -r '.todayPrompts' <<<"$tz_result") == "2" ]] ||
  fail "Copilot collector uses local date in sqlite date comparisons" "$tz_result"
pass "Copilot collector handles timezones consistently"
