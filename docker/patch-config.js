#!/usr/bin/env node
const fs = require('fs');

const file = process.env.CONFIG_FILE;
const config = JSON.parse(fs.readFileSync(file, 'utf8'));

config.gateway ??= {};
config.gateway.controlUi ??= {};
config.gateway.controlUi.dangerouslyDisableDeviceAuth = true;

// Set model if specified
if (process.env.OPENCLAW_MODEL) {
  config.agent ??= {};
  config.agent.model = process.env.OPENCLAW_MODEL;
}

const hasCustom = process.env.TLS_HAS_CUSTOM === 'true';
const enabled = hasCustom || process.env.TLS_ENABLED === 'true';

config.gateway.tls = hasCustom
  ? {
      enabled: true,
      autoGenerate: false,
      certPath: process.env.TLS_CERT_PATH,
      keyPath: process.env.TLS_KEY_PATH,
    }
  : enabled
    ? { enabled: true, autoGenerate: true }
    : { enabled: false };

fs.writeFileSync(file, JSON.stringify(config, null, 2));
