#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/fixture/workflows"
cp "$ROOT_DIR/workflows/standard.yaml" "$tmp_dir/fixture/workflows/standard.yaml"

cat >"$tmp_dir/fixture/prd.json" <<'EOF'
{
  "projectName": "Fixture",
  "branchName": "main",
  "userStories": [
    {
      "id": "US-001",
      "title": "T",
      "description": "D",
      "workflow": "standard",
      "dependencies": [],
      "passes": false
    }
  ]
}
EOF

"$ROOT_DIR/lib/prd-validator.sh" "$tmp_dir/fixture/prd.json" >/dev/null
echo "PASS"
