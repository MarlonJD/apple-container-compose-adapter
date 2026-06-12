#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright (C) 2026 Burak Karahan

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

entitlements="signing/container-compose-adapter.entitlements"
binary="${1:-}"

if [[ -z "$binary" ]]; then
  if [[ -x ".build/arm64-apple-macosx/debug/container-compose-adapter" ]]; then
    binary=".build/arm64-apple-macosx/debug/container-compose-adapter"
  elif [[ -x ".build/debug/container-compose-adapter" ]]; then
    binary=".build/debug/container-compose-adapter"
  else
    echo "No debug container-compose-adapter executable found. Run swift build first." >&2
    exit 2
  fi
fi

if [[ ! -f "$entitlements" ]]; then
  echo "Missing entitlements file: $entitlements" >&2
  exit 2
fi

if [[ ! -x "$binary" ]]; then
  echo "Debug executable is missing or not executable: $binary" >&2
  exit 2
fi

codesign --force --sign - --entitlements "$entitlements" "$binary"
codesign -d --entitlements :- "$binary"
