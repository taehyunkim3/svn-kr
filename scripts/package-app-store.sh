#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
DISTRIBUTION=app-store exec "$ROOT/scripts/package-app.sh"
