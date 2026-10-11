#!/usr/bin/env bash
# Shared helpers for the acceptance checks in scripts/verify/ (constitution XI).
# Usage in a check script:
#   source "$(dirname "$0")/lib.sh"
#   check "description" command args...
#   summary
set -euo pipefail

export AWS_REGION="${AWS_REGION:-us-east-2}"
export AWS_DEFAULT_REGION="$AWS_REGION"
export CLUSTER_NAME="${CLUSTER_NAME:-data-platform-dev}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Secrets are required as variables by the bootstrap root module, also on plan (D-011).
if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

# The AWS CLI on Windows ends text output with CRLF; strip the CR so comparisons work in Git Bash.
aws() {
  command aws "$@" | tr -d '\r'
}

_passed=0
_failed=0

require_tools() {
  local tool
  for tool in "$@"; do
    if ! type -P "$tool" >/dev/null 2>&1; then
      echo "Missing tool: $tool" >&2
      exit 2
    fi
  done
}

# check "description" command args...: runs the command and records PASS or FAIL.
check() {
  local description="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "PASS  $description"
    _passed=$((_passed + 1))
  else
    echo "FAIL  $description"
    _failed=$((_failed + 1))
  fi
}

# summary: prints the totals and exits non-zero if any check failed.
summary() {
  echo "----"
  echo "Passed: $_passed  Failed: $_failed"
  if [ "$_failed" -gt 0 ]; then
    exit 1
  fi
}
