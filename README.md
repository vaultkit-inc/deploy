# VaultKit Deployment

Deploy VaultKit — a runtime governance layer for AI agents and production data.

Full documentation: [docs.vaultkit.io/deployment](https://docs.vaultkit.io/deployment.html)

---

## What's in this package

- `docker-compose.yml` — wires all services together
- `.env.example` — configuration template
- `scripts/install.sh` — generates keys and secrets
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

Generates signing keys and creates your `.env` from `.env.example`.

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

---

## Deployment Models

**Single-Domain (recommended for design partners)**
One domain serves both frontend and backend. No external reverse proxy required.

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