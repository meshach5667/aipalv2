---
name: aipal-release
description: >-
  AiPal production deploy workflow: brand check, pytest, smoke test, API rsync
  to /opt/aipal-v2, SQL migrations, restart aipal-v2.service, deploy-all.sh,
  pubspec version bump, APK/web URLs, UPLOAD_PLAY. Use when deploying, releasing,
  publishing builds, or running pre-deploy QA.
---

# AiPal Release

## Pre-deploy checklist

1. **Brand copy** — `scripts/check-brand-copy.sh` (blocks wrong casing and third-party names)
2. **API tests** — `cd apps/api && python3 -m pytest tests/ -q` (or `.venv/bin/python -m pytest`)
3. **Smoke** — `scripts/smoke-test.sh` (requires `aipal-v2.service` on `:8102`)
4. **Flutter tests** — `cd apps/mobile && flutter test`
5. **Bump version** (if shipping) — `apps/mobile/pubspec.yaml` e.g. `2.4.3+21`

## API deploy (server)

```bash
# Sync API source to production path
rsync -a --delete \
  --exclude=.venv --exclude=__pycache__ \
  apps/api/ /opt/aipal-v2/apps/api/

# SQL migrations (run new scripts as needed)
psql "$DATABASE_URL" -f scripts/migrate_v11_brain.sql
# Also: scripts/migrate_tasks_v10.sql when applicable

# Restart service
sudo systemctl restart aipal-v2.service
sudo systemctl status aipal-v2.service
```

Or use Ansible: `ansible-playbook -i infra/inventory.ini infra/playbooks/deploy-v2.yml`

## Mobile + web deploy

```bash
# Full pipeline (brand → pytest → smoke → icons → flutter test → flutter build → publish)
scripts/deploy-all.sh

# Play Internal upload (optional)
UPLOAD_PLAY=1 scripts/deploy-all.sh
```

`deploy-all.sh` builds with `--dart-define=API_BASE_URL=https://43.160.220.9.sslip.io/api/v2` and `--base-href /app/`.

## Published URLs

| Artifact | URL |
|----------|-----|
| Web app | https://43.160.220.9.sslip.io/app/ |
| APK downloads | https://43.160.220.9.sslip.io/downloads/ |
| Latest APK | https://43.160.220.9.sslip.io/downloads/aipal-latest.apk |

## Verify after deploy

- `curl -sf https://43.160.220.9.sslip.io/api/v2/health`
- `scripts/smoke-test.sh`
- `cd apps/mobile && flutter test && flutter analyze lib/`
