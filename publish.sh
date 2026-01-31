#!/bin/bash
set -e

# Configuration (override via environment variables)
DOCKER_HUB_ORG="${DOCKER_HUB_ORG:-fourplayers}"
IMAGE_NAME="${IMAGE_NAME:-openclaw}"
DOCKER_HUB_USER="${DOCKER_HUB_USER:?DOCKER_HUB_USER is required}"
DOCKER_HUB_ACCESS_TOKEN="${DOCKER_HUB_ACCESS_TOKEN:?DOCKER_HUB_ACCESS_TOKEN is required}"

# Get current openclaw version from npm
echo "==> Fetching openclaw version from npm..."
OPENCLAW_VERSION=$(npm show openclaw version)
echo "==> OpenClaw version: $OPENCLAW_VERSION"

# Login
echo "$DOCKER_HUB_ACCESS_TOKEN" | docker login -u "$DOCKER_HUB_USER" --password-stdin

# Setup buildx
docker buildx create --name multiarch --driver docker-container --use 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap

# Build and push multi-arch with version tag
echo "==> Building and pushing $DOCKER_HUB_ORG/$IMAGE_NAME:latest and :$OPENCLAW_VERSION"
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --tag "$DOCKER_HUB_ORG/$IMAGE_NAME:latest" \
  --tag "$DOCKER_HUB_ORG/$IMAGE_NAME:$OPENCLAW_VERSION" \
  --push \
  .

echo "Done! Image published to: https://hub.docker.com/r/$DOCKER_HUB_ORG/$IMAGE_NAME"
echo "Tags: latest, $OPENCLAW_VERSION"
