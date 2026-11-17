#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Exercises scan.sh against a throwaway workspace, covering every project it can choose and
# proving what reaches the repository's scan script. Needs nothing but a shell.

set -eu

here="$(dirname "$0")"
root="$(cd "${here}/.." && pwd)"
scan="${root}/scan.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT INT TERM

failures=0

# The stand-in for a repository's scan script, reporting what it was handed.
cat >"${work}/sonar.sh" <<'STUB'
#!/bin/sh
printf 'key=%s gate=%s host=%s args=%s\n' \
  "${SONAR_PROJECT_KEY:-}" "${SONAR_GATE:-}" "${SONAR_HOST_URL:-}" "$*"
STUB
chmod +x "${work}/sonar.sh"

# Fails with FLAKY_MESSAGE on its first FLAKY_FAILS calls, then passes, counting every call.
cat >"${work}/flaky.sh" <<'STUB'
#!/bin/sh
calls=$(($(cat "${FLAKY_CALLS}" 2>/dev/null || echo 0) + 1))
echo "${calls}" >"${FLAKY_CALLS}"
if [ "${calls}" -le "${FLAKY_FAILS}" ]; then
  echo "${FLAKY_MESSAGE}" >&2
  exit 1
fi
echo "passed"
STUB
chmod +x "${work}/flaky.sh"

printf 'sonar.projectKey=fixture\nsonar.projectName=Fixture\n' \
  >"${work}/sonar-project.properties"

run() { # runs scan.sh in the workspace, reporting what the scan script was handed
  env GITHUB_WORKSPACE="${work}" GITHUB_OUTPUT="${work}/output" \
    SCAN_SCRIPT=./sonar.sh "$@" sh "${scan}" 2>/dev/null | tail -n 1
}

check() { # $1=label $2=expected, rest: command producing the actual value
  label="$1"
  expected="$2"
  shift 2
  if actual="$("$@")"; then
    if [ "${expected}" = "${actual}" ]; then
      printf '  ok    %s\n' "${label}"
      return 0
    fi
    printf '  FAIL  %s\n          expected %s\n          got      %s\n' \
      "${label}" "${expected}" "${actual}"
  else
    printf '  ERROR %s\n          command exited %s\n' "${label}" "$?"
  fi
  failures=$((failures + 1))
}

fails() { # $1=label, rest: command expected to exit non-zero
  label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  FAIL  %s\n          expected a non-zero exit\n' "${label}"
    failures=$((failures + 1))
  else
    printf '  ok    %s\n' "${label}"
  fi
}

key_written() { # runs scan.sh, then reports the project-key it wrote to GITHUB_OUTPUT
  : >"${work}/output"
  run "$@" >/dev/null
  sed -n 's/^project-key=//p' "${work}/output"
}

echo "scan.sh"

check "the default branch writes the official project" \
  "key=fixture gate= host= args=" \
  run EVENT_NAME=push REF_NAME=main DEFAULT_BRANCH=main

check "a pull request gets a throwaway it deletes" \
  "key=fixture-pr-42 gate= host= args=-d" \
  run EVENT_NAME=pull_request PR_NUMBER=42 REF_NAME=feature DEFAULT_BRANCH=main

check "pull_request_target is a pull request too" \
  "key=fixture-pr-7 gate= host= args=-d" \
  run EVENT_NAME=pull_request_target PR_NUMBER=7 REF_NAME=feature DEFAULT_BRANCH=main

check "any other ref gets a throwaway named after it" \
  "key=fixture-ref-release-1.2 gate= host= args=-d" \
  run EVENT_NAME=push REF_NAME=release/1.2 DEFAULT_BRANCH=main

check "a nightly on the default branch still writes the official project" \
  "key=fixture gate= host= args=" \
  run EVENT_NAME=schedule REF_NAME=main DEFAULT_BRANCH=main

check "a default branch that is not main is honoured" \
  "key=fixture gate= host= args=" \
  run EVENT_NAME=push REF_NAME=trunk DEFAULT_BRANCH=trunk

check "the gate and the host url reach the script" \
  "key=fixture gate=h3nc4-no-coverage host=https://sonar.example.com args=" \
  run EVENT_NAME=push REF_NAME=main DEFAULT_BRANCH=main \
  GATE=h3nc4-no-coverage SONAR_HOST_URL=https://sonar.example.com

check "the key input overrides the properties file" \
  "key=other-pr-3 gate= host= args=-d" \
  run EVENT_NAME=pull_request PR_NUMBER=3 REF_NAME=f DEFAULT_BRANCH=main PROJECT_KEY=other

check "the chosen project is reported as an output" \
  "fixture-pr-42" \
  key_written EVENT_NAME=pull_request PR_NUMBER=42 REF_NAME=f DEFAULT_BRANCH=main

fails "a missing scan script is refused" \
  env GITHUB_WORKSPACE="${work}" GITHUB_OUTPUT="${work}/output" SCAN_SCRIPT=./absent.sh \
  EVENT_NAME=push REF_NAME=main sh "${scan}"

fails "a properties file without a key is refused" \
  env GITHUB_WORKSPACE="${work}" GITHUB_OUTPUT="${work}/output" SCAN_SCRIPT=./sonar.sh \
  PROPERTIES_FILE=./sonar.sh EVENT_NAME=push REF_NAME=main sh "${scan}"

flaky() { # $1=failures before a pass, $2=message, rest: env, reports exit status and calls
  fails_first="$1"
  message="$2"
  shift 2
  rm -f "${work}/calls"
  status=0
  env GITHUB_WORKSPACE="${work}" GITHUB_OUTPUT="${work}/output" SCAN_SCRIPT=./flaky.sh \
    EVENT_NAME=push REF_NAME=main RETRY_DELAY=0 FLAKY_CALLS="${work}/calls" \
    FLAKY_FAILS="${fails_first}" FLAKY_MESSAGE="${message}" "$@" sh "${scan}" \
    >/dev/null 2>&1 || status=$?
  calls="$(cat "${work}/calls")"
  printf 'status=%s calls=%s\n' "${status}" "${calls}"
}

check "a 502 from the server is retried" \
  "status=0 calls=2" \
  flaky 1 "ERROR Failed to query server version: GET https://sonar.example.com/api/server/version failed with HTTP 502 Bad Gateway"

check "a 520 on the settings call is retried" \
  "status=0 calls=2" \
  flaky 1 "Caused by: java.lang.IllegalStateException: Failed to load global settings: HTTP code 520: error code: 520"

check "a connection the server reset is retried" \
  "status=0 calls=2" \
  flaky 1 "Caused by: java.net.SocketException: Connection reset"

check "a connection the server closed is retried" \
  "status=0 calls=2" \
  flaky 1 "java.lang.IllegalStateException: Call to URL [https://sonar.example.com/api/v2/analysis/jres/x] failed: closed"

check "retries are bounded" \
  "status=1 calls=3" \
  flaky 5 "failed with HTTP 503 Service Unavailable"

check "the retries input sets the bound" \
  "status=1 calls=1" \
  flaky 5 "failed with HTTP 503 Service Unavailable" RETRIES=0

check "a failed quality gate is final" \
  "status=1 calls=1" \
  flaky 1 "ERROR QUALITY GATE STATUS: FAILED - View details on https://sonar.example.com"

check "a refused token is final" \
  "status=1 calls=1" \
  flaky 1 "ERROR Error during SonarScanner CLI execution: HTTP 401 Unauthorized"

check "a broken scan script is final" \
  "status=1 calls=1" \
  flaky 1 "SONAR_TOKEN is not set."

fails "a retries input that is not a number is refused" \
  env GITHUB_WORKSPACE="${work}" GITHUB_OUTPUT="${work}/output" SCAN_SCRIPT=./sonar.sh \
  EVENT_NAME=push REF_NAME=main RETRIES=two sh "${scan}"

if [ "${failures}" -ne 0 ]; then
  printf '\n%s check(s) failed\n' "${failures}"
  exit 1
fi
printf '\nall checks passed\n'
