#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Exercises cache.sh with curl stubbed out, covering each mount it can choose.

set -eu

here="$(dirname "$0")"
root="$(cd "${here}/.." && pwd)"
cache="${root}/cache.sh"

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT INT TERM

failures=0

# Answers with CURL_ANSWER, or fails the way curl does when CURL_ANSWER is empty.
mkdir -p "${work}/bin"
cat >"${work}/bin/curl" <<'STUB'
#!/bin/sh
if [ -z "${CURL_ANSWER:-}" ]; then
  echo "curl: (7) Failed to connect" >&2
  exit 7
fi
printf '%s' "${CURL_ANSWER}"
STUB
chmod +x "${work}/bin/curl"

plan() { # runs cache.sh plan, reporting every output it wrote on one line
  : >"${work}/output"
  env PATH="${work}/bin:${PATH}" GITHUB_OUTPUT="${work}/output" RUNNER_TEMP="${work}" \
    RUNNER_OS=Linux "$@" sh "${cache}" plan >/dev/null
  tr '\n' ' ' <"${work}/output" | sed 's/ $//'
}

ready() { # runs cache.sh ready over $1, reporting what it wrote
  : >"${work}/output"
  env GITHUB_OUTPUT="${work}/output" CACHE_PATH="$1" sh "${cache}" ready >/dev/null
  cat "${work}/output"
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

echo "cache.sh"

dir="${work}/sonar-user-home"

check "a GitHub runner keys a directory on the server version" \
  "mount=${dir} path=${dir} key=sonar-user-home-Linux-26.11.0.134175 prefix=sonar-user-home-Linux-" \
  plan SONAR_HOST_URL=https://sonar.example.com/ CURL_ANSWER=26.11.0.134175

check "a workspace volume gets a volume on the same daemon" \
  "mount=sonar-action-user-home" \
  plan HOST_ROOT=workspace-volume SONAR_HOST_URL=https://sonar.example.com

check "no host url leaves the cache off" \
  "" \
  plan CURL_ANSWER=26.11.0.134175

check "an unreachable server leaves the cache off" \
  "" \
  plan SONAR_HOST_URL=https://sonar.example.com

check "an answer that is no version leaves the cache off" \
  "" \
  plan SONAR_HOST_URL=https://sonar.example.com CURL_ANSWER="<html>error</html>"

mkdir -p "${work}/empty/cache" "${work}/filled/cache"
: >"${work}/filled/cache/plugin.jar"

check "an empty user home is not saved" "" ready "${work}/empty"
check "a filled user home is saved" "ready=true" ready "${work}/filled"

if [ "${failures}" -ne 0 ]; then
  printf '\n%s check(s) failed\n' "${failures}"
  exit 1
fi
printf '\nall checks passed\n'
