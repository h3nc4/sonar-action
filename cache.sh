#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Keeps the scanner's user home between runs, so its JRE and plugins download once per server
# version. The action beside it calls plan before the scan and ready after it.

set -eu

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set. This runs under GitHub Actions.}"

plan() {
  # HOST_ROOT is set where docker cannot see the job's filesystem, as on Forgejo. A volume on
  # that daemon stays after the job ends, so it keeps the cache without any upload.
  if [ -n "${HOST_ROOT:-}" ]; then
    echo "mount=${CACHE_VOLUME:-sonar-action-user-home}" >>"${GITHUB_OUTPUT}"
    return 0
  fi

  host="${SONAR_HOST_URL:-}"
  if [ -z "${host}" ]; then
    echo "::notice::host-url is empty, so the scanner cache has no server version to key on"
    return 0
  fi
  if ! version="$(curl -fsS --max-time 15 "${host%/}/api/server/version")"; then
    echo "::warning::could not read the server version, so the scan runs without its cache"
    return 0
  fi
  case "${version}" in
    "" | *[!0-9A-Za-z.-]*)
      echo "::warning::the server answered ${version} for its version, so the cache is off"
      return 0
      ;;
    *) ;;
  esac

  dir="${RUNNER_TEMP:?RUNNER_TEMP is not set. This runs under GitHub Actions.}/sonar-user-home"
  mkdir -p "${dir}"
  prefix="sonar-user-home-${RUNNER_OS:-Linux}-"
  {
    echo "mount=${dir}"
    echo "path=${dir}"
    echo "key=${prefix}${version}"
    echo "prefix=${prefix}"
  } >>"${GITHUB_OUTPUT}"
}

# A scan script that ignores SONAR_CACHE leaves the directory empty. Saving that under the
# version key would hold the key until the next upgrade, so only a filled one is saved.
ready() {
  first="$(find "${CACHE_PATH:?CACHE_PATH is not set.}" -type f -print -quit)"
  if [ -n "${first}" ]; then
    echo "ready=true" >>"${GITHUB_OUTPUT}"
  else
    echo "::notice::the scan wrote nothing to its user home, so there is no cache to save"
  fi
}

case "${1:-}" in
  plan) plan ;;
  ready) ready ;;
  *)
    echo "usage: $0 plan|ready" >&2
    exit 2
    ;;
esac
