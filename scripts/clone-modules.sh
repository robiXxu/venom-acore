#!/usr/bin/env bash
set -euo pipefail

MODULES_FILE="${1:-modules.lock}"
MODULES_DIR="${2:-/src/modules}"

mkdir -p "$MODULES_DIR"

while IFS='|' read -r name repo ref; do
  [[ -z "${name}" ]] && continue
  [[ "${name}" =~ ^# ]] && continue

  echo "Installing module: ${name}"
  rm -rf "${MODULES_DIR:?}/${name}"

  git clone --depth=1 "$repo" "$MODULES_DIR/$name"

  pushd "$MODULES_DIR/$name" >/dev/null
    git fetch --depth=1 origin "$ref" || true
    git checkout "$ref"
  popd >/dev/null
done < "$MODULES_FILE"
