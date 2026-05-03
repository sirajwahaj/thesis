#!/bin/bash
set -euo pipefail

# Build script for thesis PDF

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "==== Building Thesis PDF ===="
echo "Copying latest results and compiling LaTeX..."

# Run Makefile PDF target
make -C "$REPO_ROOT" pdf

echo "==== Done! PDF is at docs/thesis.pdf ===="