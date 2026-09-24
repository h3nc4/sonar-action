#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Decides which SonarQube project a CI run writes to, then hands the scan to the repository's
# own script. Community Edition analyses one branch per project, so only the default branch
# writes the official project and every other ref scans under a throwaway that is deleted.
#
# Called by the action beside it, which documents every variable read here. Writes project-key
# and throwaway to GITHUB_OUTPUT.

set -eu

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set. This runs under GitHub Actions.}"

cd "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is not set. This runs under GitHub Actions.}"

script="${SCAN_SCRIPT:-./scripts/sonar.sh}"
properties="${PROPERTIES_FILE:-sonar-project.properties}"
default_branch="${DEFAULT_BRANCH:-main}"

# A scan that lives in the dev container is copied out and run here rather than run inside it.
# It only shells out to the scanner image, which the runner does as well as the container would.
if [ -n "${SCAN_IMAGE:-}" ]; then
  copy="${RUNNER_TEMP:-/tmp}/sonar-action-scan"
  if ! docker run --rm --entrypoint cat "${SCAN_IMAGE}" "${script}" >"${copy}"; then
    echo "${script} could not be read out of ${SCAN_IMAGE}." >&2
    exit 1
  fi
  if [ ! -s "${copy}" ]; then
    echo "${script} is empty in ${SCAN_IMAGE}, so there is nothing to run." >&2
    exit 1
  fi
  chmod +x "${copy}"
  script="${copy}"
fi

if [ ! -x "${script}" ]; then
  echo "${script} is not an executable file. The scan itself stays in the repository, so" \
    "point the script input at it, or commit it with the executable bit set." >&2
  exit 1
fi

# The official key names the project the default branch writes, and every throwaway is derived
# from it, so one fact in one file decides all of them.
official="${PROJECT_KEY:-}"
origin="the key input"
if [ -z "${official}" ]; then
  origin="sonar.projectKey in ${properties}"
  if [ ! -f "${properties}" ]; then
    echo "${properties} is not there, so the project key cannot be read. Point" \
      "properties-file at it, or name the key outright with the key input." >&2
    exit 1
  fi
  official="$(
    sed -n 's/^[[:space:]]*sonar\.projectKey[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' \
      "${properties}" | head -n 1
  )"
fi
if [ -z "${official}" ]; then
  echo "${origin} is empty, so there is no project to scan under." >&2
  exit 1
fi

# A key takes letters, digits and _ - . : only, and a ref carries anything a branch name can.
slug() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-'
}

delete=""
case "${EVENT_NAME:-}" in
  pull_request | pull_request_target)
    : "${PR_NUMBER:?PR_NUMBER is empty on a pull request event, which should not happen.}"
    key="${official}-pr-${PR_NUMBER}"
    delete="-d"
    ;;
  *)
    : "${REF_NAME:?REF_NAME is not set, so the branch being scanned is unknown.}"
    if [ "${REF_NAME}" = "${default_branch}" ]; then
      key="${official}"
    else
      key="${official}-ref-$(slug "${REF_NAME}")"
      delete="-d"
    fi
    ;;
esac

throwaway=false
if [ -n "${delete}" ]; then
  throwaway=true
  echo "::notice::scanning as ${key}, a throwaway project deleted once the scan passes"
else
  echo "::notice::scanning as ${key}, the official project for ${default_branch}"
fi

{
  echo "project-key=${key}"
  echo "throwaway=${throwaway}"
} >>"${GITHUB_OUTPUT}"

SONAR_PROJECT_KEY="${key}"
export SONAR_PROJECT_KEY
if [ -n "${GATE:-}" ]; then
  SONAR_GATE="${GATE}"
  export SONAR_GATE
fi

set --
if [ -n "${delete}" ]; then
  set -- -d
fi
exec "${script}" "$@"
