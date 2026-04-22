# DNS and remote access

## Recommended approach

- Locally, use names in the `*.home.arpa` zone, such as `immich.home.arpa` and `ha.home.arpa`.
- Configure the router to use the mini PC as local DNS through `dnsmasq`, or define local DNS records directly on the router.
- Outside the house, use Tailscale + MagicDNS.

## Why not expose everything publicly

Public exposure of Jellyfin, Home Assistant, Portainer, or Dozzle increases the attack surface without much practical benefit, because Tailscale provides simpler and safer remote access for private services.[web:27][web:30]

## Vaultwarden without VPN

If you really want to use Vaultwarden without VPN:
- use a dedicated subdomain,
- expose that one service only,
- enable 2FA in Vaultwarden,
- consider additional protection through Cloudflare Access or extra WAF restrictions.
