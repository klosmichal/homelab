# Architectural decisions

## Home Assistant

**Home Assistant Container** was selected because running Home Assistant Supervised alongside custom containers and a custom host layout is officially problematic and often results in unsupported or unhealthy states.[web:18][web:26]

## Bitwarden

**Vaultwarden** was selected because the official self-hosted Bitwarden stack requires more containers and more resources, while Vaultwarden is lighter and remains compatible with Bitwarden clients.[web:7][web:10]

## Remote access

**Tailscale** was selected as the default remote access path because it provides private access to services without public exposure and allows access policies between devices.[web:27]

Optional **Cloudflare Tunnel for Vaultwarden only** is a convenience/security tradeoff and should only be used if you enable MFA, keep strong admin credentials, and avoid exposing the rest of the homelab this way.[web:21][web:30]

## Monitoring

**Uptime Kuma** was selected because it supports free notifications through e-mail, Telegram, and ntfy, which makes it easy to choose a zero-cost alerting path.[web:22][web:25]
