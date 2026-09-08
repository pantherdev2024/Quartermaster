#!/bin/bash
# Every test here runs against temporary directories and stubbed commands, and
# none of them touch the machine's real theme, bar or configuration.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"$ROOT/manifest-test.sh"
"$ROOT/qml-test.sh"
"$ROOT/barlayout-test.sh"
"$ROOT/loadouts-test.sh"
"$ROOT/agent-set-test.sh"
"$ROOT/scan-test.sh"
"$ROOT/deploy-test.sh"
