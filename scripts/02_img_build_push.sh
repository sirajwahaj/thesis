#!/bin/bash
# =============================================================================
# Build & Push Thesis Workload Image
#
# Builds the Dagster workload container image using podman (not Docker).
# For local builds, image is stored in podman local registry.
# For remote builds, image is pushed to ghcr.io.
#
# Prerequisites:
#   - podman installed and running
#   - For push: authenticate with ghcr.io (podman login ghcr.io)
#
# Usage:
#   ./02_img_build_push.sh                    # Build v0.1 locally
#   ./02_img_build_push.sh v0.2               # Build v0.2 locally
#   ./02_img_build_push.sh v0.2 1             # Build and push v0.2 to ghcr.io
#   PUSH=1 ./02_img_build_push.sh v0.2        # Alternative: use env var
#
# Examples:
#   bash scripts/02_img_build_push.sh v0.1 0          # Local only
#   bash scripts/02_img_build_push.sh v0.1 1          # Build + push
# =============================================================================

set -euo pipefail

# -------- SCRIPT LOCATION --------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# -------- CONFIGURATION --------
TAG="${1:-v0.1}"
PUSH="${2:-${PUSH:-0}}"  # Allow TAG and PUSH via args or env vars
IMAGE_NAME="ghcr.io/sirajwahaj/thesis-workload"
DOCKERFILE="$REPO_ROOT/src/Containerfile"
BUILD_CONTEXT="$REPO_ROOT/src"

# -------- VALIDATION --------
if [ ! -f "$DOCKERFILE" ]; then
    echo "[FAIL] Dockerfile not found at: $DOCKERFILE"
    echo "   Expected path: src/Containerfile"
    exit 1
fi

if [ ! -d "$BUILD_CONTEXT" ]; then
    echo "[FAIL] Build context not found at: $BUILD_CONTEXT"
    exit 1
fi

# Check if podman is available
if ! command -v podman &> /dev/null; then
    echo "[FAIL] podman is not installed or not in PATH"
    echo "   Install podman: https://podman.io/docs/installation"
    exit 1
fi

# -------- BUILD --------
echo "--------------------------------------------------------------------━━"
echo "🔨 Building: $IMAGE_NAME:$TAG"
echo "--------------------------------------------------------------------━━"
echo "Build context: $BUILD_CONTEXT"
echo "Dockerfile:    $DOCKERFILE"
echo ""

podman build \
    -t "$IMAGE_NAME:$TAG" \
    -f "$DOCKERFILE" \
    "$BUILD_CONTEXT"

BUILD_EXIT=$?

if [ $BUILD_EXIT -eq 0 ]; then
    echo ""
    echo "[OK] Build successful: $IMAGE_NAME:$TAG"
else
    echo ""
    echo "[FAIL] Build failed with exit code $BUILD_EXIT"
    exit $BUILD_EXIT
fi

# -------- PUSH (OPTIONAL) --------
if [ "$PUSH" -eq "1" ]; then
    echo ""
    echo "--------------------------------------------------------------------━━"
    echo " Pushing: $IMAGE_NAME:$TAG"
    echo "--------------------------------------------------------------------━━"
    
    # Verify authentication before pushing
    if ! podman push "$IMAGE_NAME:$TAG" --quiet 2>&1 | grep -q "Pushing image"; then
        # Try to authenticate if push failed
        echo "🔐 Attempting authentication with ghcr.io..."
        echo "   Run: podman login ghcr.io"
        echo "   Then: bash scripts/02_img_build_push.sh $TAG 1"
        exit 1
    fi
    
    echo ""
    echo "[OK] Push successful: $IMAGE_NAME:$TAG"
else
    echo ""
    echo "[INFO]  Local build only (not pushed to registry)"
    echo "   To push later, run: PUSH=1 bash scripts/02_img_build_push.sh $TAG"
    echo "   Or: bash scripts/02_img_build_push.sh $TAG 1"
fi

# -------- SUMMARY --------
echo ""
echo "--------------------------------------------------------------------━━"
echo " Image Summary"
echo "--------------------------------------------------------------------━━"
podman images | grep -E "thesis-workload|REPOSITORY" | head -2
echo ""
echo "Next steps:"
echo "  1. Review image: podman inspect $IMAGE_NAME:$TAG"
echo "  2. Test locally: make validate-build"
echo "  3. Start services: make compose-up"
echo ""