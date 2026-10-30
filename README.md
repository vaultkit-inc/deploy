# VaultKit Deployment

Deploy VaultKit — a runtime governance layer for AI agents and production data.

Full documentation: [docs.vaultkit.io/deployment](https://docs.vaultkit.io/deployment.html)

---

## What's in this package

- `docker-compose.yml` — wires all services together
- `.env.example` — configuration template
- `scripts/install.sh` — generates keys and secrets, and selects the release
- `secrets/` — signing keys generated at install time

VaultKit runs four containers:

- **Control Plane** — Governs every data request: authentication, policy evaluation, approvals, and audit logging
- **FUNL Runtime** — Data plane and execution engine: translates queries into native SQL, applies field-level masking, and executes against your datasources
- **Console** — React web UI served via nginx
- **Postgres** — Metadata and application state

---

## Prerequisites

- Docker 24+
- Docker Compose v2
- A Linux host (VM, EC2, bare metal)
- A domain name

---

## Quick Start

### 1. Clone this repository

```bash
git clone https://github.com/vaultkit-inc/deploy.git
cd deploy
```

### 2. Run the installer

```bash
./scripts/install.sh
```

Generates signing keys, creates your `.env` from `.env.example`, and selects the latest
release. To install a specific one:

```bash
./scripts/install.sh --version 0.9.2-alpha
```

The version is saved as `VAULTKIT_VERSION` in `.env`, and all three images use it. The
installer refuses versions that don't exist or are known to be broken.

### 3. Configure your environment

Edit `.env` and set:

- `APP_HOST` — your public domain e.g. `https://vaultkit.yourdomain.com`
- `FRONTEND_BASE_URL` — usually same as `APP_HOST`
- `POSTGRES_PASSWORD` — choose a strong password

### 4. Start VaultKit

```bash
docker compose up -d
```

### 5. Verify

```bash
docker compose ps
```

All containers should be running. Visit your domain to access the VaultKit console.

A custom domain needs a reverse proxy in front of VaultKit for HTTPS; see
[Running behind a reverse proxy](#running-behind-a-reverse-proxy).

---

## Running behind a reverse proxy

Forward all paths to the console on port 5173. Its nginx handles routing, so don't send
anything to ports 3000 or 8080, which are internal.

Caddy gets a Let's Encrypt certificate automatically:

```
vaultkit.example.com {
    reverse_proxy localhost:5173
}
```

Bind the console to localhost in `.env`:

```bash
CONSOLE_BIND=127.0.0.1
```

The console trusts the incoming `X-Forwarded-Proto`, so if port 5173 is reachable from
the internet, anyone can skip the HTTPS redirect. Close 5173 in your firewall or security
group too. Besides SSH, only ports 80 and 443 need to be open.

If Cloudflare is in front, set its SSL mode to **Full** or **Full (strict)**, not
Flexible. Flexible sends plain HTTP to your server, which causes a redirect loop.

---

## Upgrading

An install stays on its version until you change it, so pulling this repository never
upgrades you. To upgrade, back up the database first. This reads the connection,
including the database name, from `DATABASE_URL`, so it works whatever your database is
called:

```bash
docker compose exec -T postgres sh -c 'pg_dump "$DATABASE_URL"' > vaultkit-backup.sql
```

Then:

```bash
./scripts/install.sh --version <version>
docker compose pull
docker compose up -d
```

The installer switches this folder to that release, so run it instead of `git pull`, and
keep your own settings in `.env`. It stops if tracked files have local changes.

VaultKit can't downgrade in place, because migrations don't run backwards, so the
installer refuses an older version. To go back, restore your backup.

Database migrations run automatically when the control plane starts. Always run the
`control-plane`, `funl-runtime` and `console` images from the same release.

Coming from `0.1.0-alpha`? Read the upgrade notes for every release in between in the
[deployment guide](https://docs.vaultkit.io/deployment.html). In particular:

- `funl-runtime` is no longer published on port 8080. The control plane reaches it at
  `http://funl-runtime:8080` on the Compose network; don't publish it or route it
  through a reverse proxy.
- Installs from before `VAULTKIT_VERSION` was in `.env`: run `./scripts/install.sh` once
  after updating this repository. `docker compose` asks for it until you do. If you
  edited `docker-compose.yml`, undo that first; `CONSOLE_BIND` replaces binding the
  console to localhost by hand.
- The control plane is no longer published on port 3000; the console proxies to it, so
  point your reverse proxy at port 5173. A multi-domain setup that routes to port 3000
  from outside Docker has to publish it again, on an address only the proxy can reach.
- Your reverse proxy must send `X-Forwarded-Proto: https`. Caddy and most others do by
  default. Without it, the control plane redirects forever.
- Keep `FUNL_URL` set in `.env`.
- `OIDC_ENABLED=false` now turns SSO off everywhere, including browser sign-in. If you
  sign in with SSO, set it to `true`.

---

## Deployment Models

**Single-Domain (recommended for design partners)**
One domain serves both frontend and backend. A reverse proxy only needs to handle TLS.

**Multi-Domain (advanced)**
Separate domains for frontend and backend. For larger organizations with existing infrastructure standards.

See the [full deployment guide](https://docs.vaultkit.io/deployment.html) for details.

---

## Next Steps

After deployment:

- Create your first organization
- Configure OIDC provider
- Generate agent tokens
- Register data sources
- Apply your first policy bundle

---

## Support

- Documentation: [docs.vaultkit.io](https://docs.vaultkit.io)
- Email: founders@vaultkit.io
- Logs: `docker compose logs`

---

**VaultKit is designed to deploy cleanly, predictably, and without surprises.**
If something feels harder than it should be, that's a signal — and we want to hear about it.