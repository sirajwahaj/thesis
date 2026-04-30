#!/bin/bash
# =============================================================================
# Build & Push Thesis Workload Image
#
# Builds the Dagster workload container image using Docker.
# For local builds, image is stored in the local Docker registry.
# For remote builds, image is pushed to ghcr.io.
#
# Prerequisites:
#   - docker installed and running
#   - For push: authenticate with ghcr.io (docker login ghcr.io)
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
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

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

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "[FAIL] docker is not installed or not in PATH"
    echo "   Install Docker Desktop: https://docs.docker.com/get-docker/"
    exit 1
fi

# Verify Docker daemon is running
if ! docker info &>/dev/null; then
    echo "[FAIL] Docker daemon is not running"
    echo "   Start Docker Desktop or run: sudo systemctl start docker"
    exit 1
fi

# -------- BUILD --------
echo "--------------------------------------------------------------------━━"
echo "🔨 Building: $IMAGE_NAME:$TAG"
echo "--------------------------------------------------------------------━━"
echo "Build context: $BUILD_CONTEXT"
echo "Dockerfile:    $DOCKERFILE"
echo ""

# -------- PUSH (OPTIONAL) --------
# When PUSH=1, build and push in one step with --push (avoids loading into local store
# then re-pushing — more efficient and works with all BuildKit drivers).
# When PUSH=0, use --load to ensure the image lands in the local Docker store.

# Check GHCR authentication before build when pushing
if [ "$PUSH" -eq "1" ]; then
    if [[ -n "${GHCR_TOKEN:-}" ]]; then
        GHCR_USER_VAR="${GHCR_USER:-sirajwahaj}"
        echo "Logging into ghcr.io as $GHCR_USER_VAR..."
        echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER_VAR" --password-stdin
    fi

    echo ""
    echo "--------------------------------------------------------------------━━"
    echo " Building + Pushing: $IMAGE_NAME:$TAG"
    echo "--------------------------------------------------------------------━━"

    docker buildx build \
        --push \
        -t "$IMAGE_NAME:$TAG" \
        -f "$DOCKERFILE" \
        "$BUILD_CONTEXT"

    BUILD_EXIT=$?
    if [ $BUILD_EXIT -eq 0 ]; then
        echo ""
        echo "[OK] Build + push successful: $IMAGE_NAME:$TAG"
    else
        echo ""
        echo "[FAIL] Build+push failed with exit code $BUILD_EXIT"
        exit $BUILD_EXIT
    fi
else
    docker buildx build \
        --load \
        -t "$IMAGE_NAME:$TAG" \
        -f "$DOCKERFILE" \
        "$BUILD_CONTEXT"

    BUILD_EXIT=$?
    if [ $BUILD_EXIT -eq 0 ]; then
        echo ""
        echo "[OK] Build successful (local): $IMAGE_NAME:$TAG"
    else
        echo ""
        echo "[FAIL] Build failed with exit code $BUILD_EXIT"
        exit $BUILD_EXIT
    fi

    echo ""
    echo "[INFO]  Local build only (not pushed to registry)"
    echo "   To push later: bash scripts/bash/02_img_build_push.sh $TAG 1"
fi

# -------- SUMMARY --------
echo ""
echo "--------------------------------------------------------------------━━"
echo " Done: $IMAGE_NAME:$TAG"
echo "--------------------------------------------------------------------━━"
echo ""
