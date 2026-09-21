#!/bin/sh
# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Stands in for a repository's scan script, recording what the action handed it.

set -eu

{
  printf 'key=%s\n' "${SONAR_PROJECT_KEY:-}"
  printf 'gate=%s\n' "${SONAR_GATE:-}"
  printf 'args=%s\n' "$*"
} | tee "${RUNNER_TEMP:-/tmp}/fixture-scan"
