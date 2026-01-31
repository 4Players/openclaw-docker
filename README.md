# OpenClaw All-in-One Docker 🦞

A ready-to-deploy Docker image for [OpenClaw](https://github.com/openclaw/openclaw), the powerful open-source AI assistant that brings Claude and GPT to your favorite messaging apps. Built for [ODIN Fleet](https://odin.4players.io/fleet/) and any Docker-compatible platform.

**Features:**
- Zero-config startup — auto-configures on first run
- HTTPS support with auto-generated or custom certificates
- Supports Anthropic and OpenAI APIs
- Connect WhatsApp, Telegram, Discord, Slack, and more
- Persistent storage for seamless container restarts

## Quick Start

```bash
# 1. Configure
cp .env.example .env
# Edit .env: set your API key and gateway auth (password or token)

# 2. Build & start
docker compose up -d --build

# 3. Access Control UI
# With password: https://localhost:18789 (enter password when prompted)
# With token: https://localhost:18789/?token=YOUR_TOKEN
```

## Data Persistence

OpenClaw stores all configuration and state in `/home/node/.openclaw` inside the container. **This directory must be mounted as a volume to prevent data loss** when the container is recreated.

```yaml
volumes:
  - ./data:/home/node/.openclaw
```

This folder contains:
- `openclaw.json` — main configuration (gateway settings, API keys, TLS config)
- Channel credentials (WhatsApp sessions, bot tokens, etc.)
- Auto-generated TLS certificates (if enabled)

## Environment Variables

| Variable                       | Purpose                          | Default        |
| ------------------------------ | -------------------------------- | -------------- |
| `OPENCLAW_GATEWAY_HOST`        | Gateway public IP/FQDN           | `localhost`    |
| `OPENCLAW_GATEWAY_PORT`        | Gateway port                     | `18789`        |
| `OPENCLAW_GATEWAY_PASSWORD`    | Gateway password (user-friendly) | -              |
| `OPENCLAW_GATEWAY_TOKEN`       | Gateway token (machine-friendly) | Auto-generated |
| `ANTHROPIC_API_KEY`            | Anthropic API key                | -              |
| `OPENAI_API_KEY`               | OpenAI API key                   | -              |
| `OPENCLAW_AUTH_CHOICE`         | Auth provider if no API key      | `skip`         |
| `OPENCLAW_TLS_ENABLED`         | Enable HTTPS                     | `false`        |
| `OPENCLAW_SKIP_ONBOARD`        | Skip auto-setup (for OAuth)      | `false`        |
| `OPENCLAW_MODEL`               | AI model to use                  | Auto-detected  |
| `OPENCLAW_SSH_ENABLED`         | Enable SSH server                | `false`        |
| `OPENCLAW_SSH_PORT`            | SSH server port                  | `22`           |
| `OPENCLAW_SSH_AUTHORIZED_KEYS` | SSH public keys (one per line)   | -              |

> **Auth modes:** Set `OPENCLAW_GATEWAY_PASSWORD` for password auth, or `OPENCLAW_GATEWAY_TOKEN` for token auth. If neither is set, a token is auto-generated and printed in the logs.

## TLS / HTTPS

Set `OPENCLAW_TLS_ENABLED=true` to enable HTTPS with an auto-generated self-signed certificate.

**Custom certificates (mounted):**

```yaml
volumes:
  - ./certs/cert.pem:/certs/cert.pem:ro
  - ./certs/key.pem:/certs/key.pem:ro
```

**Docker Secrets:**

```yaml
secrets:
  - tls_cert
  - tls_key
```

**Disable TLS:**

```yaml
environment:
  - OPENCLAW_TLS_ENABLED=false
```

## SSH Access

Enable SSH for remote access and debugging. Uses public key authentication only (no passwords).

```yaml
environment:
  - OPENCLAW_SSH_ENABLED=true
  - OPENCLAW_SSH_AUTHORIZED_KEYS=ssh-ed25519 AAAA... user@host
ports:
  - "2222:22"
```

**Multiple keys (via environment):**

```yaml
environment:
  - OPENCLAW_SSH_ENABLED=true
  - |
    OPENCLAW_SSH_AUTHORIZED_KEYS=
    ssh-ed25519 AAAA... user1@host
    ssh-rsa AAAA... user2@host
```

**Via mounted file:**

```yaml
volumes:
  - ./authorized_keys:/ssh/authorized_keys:ro
```

**Via Docker secret:**

```yaml
secrets:
  - ssh_authorized_keys
```

Then connect: `ssh -p 2222 node@<host>`

## OAuth (Claude.ai / Codex)

```bash
# 1. Interactive setup
docker compose run --rm openclaw openclaw onboard

# 2. Set OPENCLAW_SKIP_ONBOARD=true in .env

# 3. Start
docker compose up -d
```

## Adding Channels

```bash
# WhatsApp (shows QR code)
docker compose exec -it openclaw openclaw channels login --channel whatsapp

# Telegram
docker compose exec openclaw openclaw channels add --channel telegram --token <BOT_TOKEN>

# Discord
docker compose exec openclaw openclaw channels add --channel discord --token <BOT_TOKEN>

# Slack
docker compose exec openclaw openclaw channels add --channel slack --bot-token <xoxb-...> --app-token <xapp-...>
```

## CLI

```bash
docker compose exec openclaw openclaw health
docker compose exec openclaw openclaw channels list
docker compose exec openclaw openclaw <command>
```

## Updating

```bash
docker compose pull
docker compose up -d
```

Or rebuild from source:

```bash
docker compose build --no-cache
docker compose up -d
```

## Troubleshooting

```bash
docker compose logs -f                 # View logs
rm -rf ./data && docker compose up -d  # Reset and re-run setup
```
