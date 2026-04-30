#!/bin/bash
set -euo pipefail

# Build script for thesis PDF

echo "==== Building Thesis PDF ===="
echo "Copying latest results and compiling LaTeX..."

# Run Makefile PDF target
make -C ../.. pdf

echo "==== Done! PDF is at docs/thesis.pdf ===="