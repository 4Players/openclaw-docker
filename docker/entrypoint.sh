#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "Error on line $LINENO: $BASH_COMMAND" >&2' ERR

# SSH setup (runs as root if enabled)
if [ "${OPENCLAW_SSH_ENABLED:-false}" = "true" ]; then
  if [ "$(id -u)" = "0" ]; then
    /setup-ssh.sh

    # Add sshd to supervisord config
    cat >> /etc/supervisor/conf.d/openclaw.conf <<'EOF'

[program:sshd]
command=/usr/sbin/sshd -D -e
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
EOF
  else
    echo "Warning: SSH enabled but not running as root, skipping SSH setup" >&2
  fi
fi

# Set HOME for node user
export HOME=/home/node
mkdir -p "$HOME/.openclaw"

# Fix ownership on data directory so node user can write
if [ "$(id -u)" = "0" ]; then
  chown -R node:node "$HOME/.openclaw" || {
    echo "Error: Could not set permissions on data directory." >&2
    echo "Run 'sudo chown -R 1000:1000 ./data' on the host." >&2
    exit 1
  }
fi

# Auto-update OpenClaw if enabled
if [ "${OPENCLAW_AUTO_UPDATE:-false}" = "true" ]; then
  echo "==> Auto-updating OpenClaw..."
  # || true: update may exit non-zero when it tries to restart via systemctl,
  # which doesn't exist in the container. The restart is unnecessary since
  # the entrypoint will start the service fresh via exec "$@".
  openclaw update --channel "${OPENCLAW_UPDATE_CHANNEL:-stable}" || true

  # Fix ownership after update (openclaw update runs as root and may recreate files)
  if [ "$(id -u)" = "0" ]; then
    chown -R node:node "$HOME/.openclaw" 2>/dev/null || true
  fi

  # Re-patch config after update, since openclaw update can overwrite it
  if [ -f "$HOME/.openclaw/openclaw.json" ]; then
    echo "==> Re-patching config after update..."
    export CONFIG_FILE="$HOME/.openclaw/openclaw.json"
    export TLS_ENABLED="${OPENCLAW_TLS_ENABLED:-false}"
    if [ -f "/run/secrets/tls_cert" ] && [ -f "/run/secrets/tls_key" ]; then
      export TLS_HAS_CUSTOM="true"
      export TLS_CERT_PATH="/run/secrets/tls_cert"
      export TLS_KEY_PATH="/run/secrets/tls_key"
    elif [ -f "/certs/cert.pem" ] && [ -f "/certs/key.pem" ]; then
      export TLS_HAS_CUSTOM="true"
      export TLS_CERT_PATH="/certs/cert.pem"
      export TLS_KEY_PATH="/certs/key.pem"
    else
      export TLS_HAS_CUSTOM="false"
    fi
    export OPENCLAW_MODEL="${OPENCLAW_MODEL:-}"
    runuser -u node -- node /patch-config.js
    runuser -u node -- openclaw doctor --fix 2>/dev/null || true
  fi

  echo "==> Update complete."
fi

CONFIG_FILE="$HOME/.openclaw/openclaw.json"

# Set defaults
export OPENCLAW_GATEWAY_HOST="${OPENCLAW_GATEWAY_HOST:-localhost}"
export OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
export OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"

# Determine auth mode: password (user-friendly) or token (machine-friendly)
if [ -n "${OPENCLAW_GATEWAY_PASSWORD:-}" ]; then
  GATEWAY_AUTH_MODE="password"
else
  GATEWAY_AUTH_MODE="token"
  # Auto-generate gateway token if not provided
  if [ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    OPENCLAW_GATEWAY_TOKEN="$(
      openssl rand -hex 32 2>/dev/null \
        || python3 -c 'import secrets; print(secrets.token_hex(32))' 2>/dev/null \
        || python  -c 'import secrets; print(secrets.token_hex(32))' 2>/dev/null \
        || (head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')
    )"
    export OPENCLAW_GATEWAY_TOKEN
  fi
fi

# TLS configuration - check multiple locations
# Priority: 1. Docker secrets, 2. Mounted certs, 3. Auto-generate (if enabled)
TLS_CERT_PATH=""
TLS_KEY_PATH=""
HAS_CUSTOM_CERTS="false"

# Check Docker secrets first
if [ -f "/run/secrets/tls_cert" ] && [ -f "/run/secrets/tls_key" ]; then
  TLS_CERT_PATH="/run/secrets/tls_cert"
  TLS_KEY_PATH="/run/secrets/tls_key"
  HAS_CUSTOM_CERTS="true"
  echo "==> Found TLS certificates (Docker secrets)"
# Check mounted certs
elif [ -f "/certs/cert.pem" ] && [ -f "/certs/key.pem" ]; then
  TLS_CERT_PATH="/certs/cert.pem"
  TLS_KEY_PATH="/certs/key.pem"
  HAS_CUSTOM_CERTS="true"
  echo "==> Found TLS certificates (mounted)"
fi

# Run onboard if not configured and not skipped
if [ ! -f "$CONFIG_FILE" ] && [ "${OPENCLAW_SKIP_ONBOARD:-false}" != "true" ]; then
  echo "==> Running auto-setup..."

  # Build args as an array (prevents word-splitting/injection)
  ONBOARD_ARGS=(
    --non-interactive --accept-risk
    --gateway-port "$OPENCLAW_GATEWAY_PORT"
    --gateway-bind "$OPENCLAW_GATEWAY_BIND"
    --no-install-daemon
    --skip-health
  )

  # Gateway auth mode
  if [ "$GATEWAY_AUTH_MODE" = "password" ]; then
    ONBOARD_ARGS+=(--gateway-auth password --gateway-password "${OPENCLAW_GATEWAY_PASSWORD}")
  else
    ONBOARD_ARGS+=(--gateway-auth token --gateway-token "${OPENCLAW_GATEWAY_TOKEN}")
  fi

  # Auth choice based on available API keys
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    ONBOARD_ARGS+=(--auth-choice apiKey --anthropic-api-key "${ANTHROPIC_API_KEY}")
  elif [ -n "${OPENAI_API_KEY:-}" ]; then
    ONBOARD_ARGS+=(--auth-choice openai-api-key --openai-api-key "${OPENAI_API_KEY}")
    # Default to OpenAI model when using OpenAI API key
    export OPENCLAW_MODEL="${OPENCLAW_MODEL:-openai/gpt-5-nano}"
  else
    ONBOARD_ARGS+=(--auth-choice "${OPENCLAW_AUTH_CHOICE:-skip}")
  fi

  # Run onboard as node user so files are created with correct ownership
  runuser -u node -- openclaw onboard "${ONBOARD_ARGS[@]}"

  # Post-setup configuration
  if [ -f "$CONFIG_FILE" ]; then
    echo "==> Configuring gateway..."

    # Pass config via env to avoid issues with node stdin args
    export CONFIG_FILE
    export TLS_ENABLED="${OPENCLAW_TLS_ENABLED:-false}"
    export TLS_HAS_CUSTOM="$HAS_CUSTOM_CERTS"
    export TLS_CERT_PATH TLS_KEY_PATH

    export OPENCLAW_MODEL="${OPENCLAW_MODEL:-}"
    runuser -u node -- node /patch-config.js

    # Migrate any remaining legacy config keys
    runuser -u node -- openclaw doctor --fix 2>/dev/null || true

    if [ "$HAS_CUSTOM_CERTS" = "true" ]; then
      echo "==> TLS enabled with custom certificates"
    elif [ "${OPENCLAW_TLS_ENABLED:-false}" = "true" ]; then
      echo "==> TLS enabled with auto-generated certificate"
    fi
  fi

  # Print access info
  if [ "$HAS_CUSTOM_CERTS" = "true" ] || [ "${OPENCLAW_TLS_ENABLED:-false}" = "true" ]; then
    SCHEME="https"
  else
    SCHEME="http"
  fi

  if [ "$GATEWAY_AUTH_MODE" = "password" ]; then
    echo "==> Setup complete. Access: $SCHEME://$OPENCLAW_GATEWAY_HOST:$OPENCLAW_GATEWAY_PORT (password: ${OPENCLAW_GATEWAY_PASSWORD})"
  else
    echo "==> Setup complete. Access: $SCHEME://$OPENCLAW_GATEWAY_HOST:$OPENCLAW_GATEWAY_PORT/?token=${OPENCLAW_GATEWAY_TOKEN}"
  fi
fi

exec "$@"
