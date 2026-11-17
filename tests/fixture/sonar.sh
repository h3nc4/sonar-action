#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Stands in for a repository's scan script, recording what the action handed it.

set -eu

# A warm cache still holds the marker an earlier run left in it.
cache=""
if [ -d "${SONAR_CACHE:-}" ]; then
  cache=cold
  if [ -f "${SONAR_CACHE}/cache/fixture" ]; then
    cache=warm
  fi
  mkdir -p "${SONAR_CACHE}/cache"
  date >"${SONAR_CACHE}/cache/fixture"
fi

{
  printf 'key=%s\n' "${SONAR_PROJECT_KEY:-}"
  printf 'cache=%s\n' "${cache}"
  printf 'gate=%s\n' "${SONAR_GATE:-}"
  printf 'args=%s\n' "$*"
} | tee "${RUNNER_TEMP:-/tmp}/fixture-scan"
