# Contributing to AiPal

Thank you for helping test and improve AiPal.

## For testers (collaborators)

1. **Install** — Play Internal opt-in link (from maintainer) or see [docs/releases/PLAY_INTERNAL_v2.md](docs/releases/PLAY_INTERNAL_v2.md).
2. **Report bugs** — [GitHub Issues](https://github.com/tfasanya79/aipal/issues/new/choose) (use the bug report template).
3. **Roadmap visibility** — [AiPal Roadmap board](https://github.com/users/tfasanya79/projects/24) (phase status synced from `docs/PRODUCT.md`).

Include in every bug report:

- Device + OS version
- App build from **Settings** (e.g. `2.4.3 (21)`)
- Steps to reproduce + screenshot if possible

Suggested labels (maintainer may apply): `voice`, `today`, `wake`, `crash`, `android`.

## For maintainers

### Project sync

Bootstrap is **complete**: the **AiPal Roadmap** board is live and [`.github/project.json`](.github/project.json) is committed sync config (field IDs + project URL).

**First-time setup** (new fork or empty Projects tab):

1. **GitHub → Settings → Secrets → Actions** → add `PROJECT_SYNC_TOKEN` (classic PAT with `repo` + `project` scopes).
2. **GitHub → Settings → Actions → General → Workflow permissions** → choose **Read and write permissions** → Save.
3. **Actions → Sync GitHub Project → Run workflow** (workflow_dispatch).
4. Local alternative: `gh auth login` then `./scripts/sync-github-project.sh --bootstrap`.

If the workflow commit step fails, ensure `.gitignore` includes `!.github/project.json` (the repo ignores `*.json` by default).

### Product status (source of truth)

Update [`docs/PRODUCT.md`](docs/PRODUCT.md) when a phase item ships or is deferred. Push to `main` — the **Sync GitHub Project** workflow updates Issues and the Project board automatically.

Manual sync:

```bash
./scripts/sync-github-project.sh --bootstrap   # first time
./scripts/sync-github-project.sh
```

### Releases

See [`.cursor/skills/aipal-release/SKILL.md`](.cursor/skills/aipal-release/SKILL.md) and [`scripts/deploy-all.sh`](scripts/deploy-all.sh).

### Secrets (never commit)

- `apps/api/.env` — copy from `apps/api/.env.example`
- `.secrets/` — signing keys, Play API JSON, status page credentials (deploy VM only)

### Stakeholder status page

Password-protected dashboard for non-GitHub stakeholders:

- **URL:** `https://43.160.220.9.sslip.io/status/`
- **Generate:** `scripts/build-status-page.sh` (runs automatically in `deploy-all.sh`)
- **First-time auth:** `scripts/setup-status-auth.sh` → writes `/etc/caddy/status-auth.env` and `.secrets/status-page-credentials.txt`
- **Rotate password:** delete both files above and re-run `setup-status-auth.sh`, then `sudo systemctl restart caddy`

## CI

- **API** — pytest on `apps/api/**` changes
- **Mobile** — `flutter analyze` on `apps/mobile/**` changes
- **Project sync** — on `docs/PRODUCT.md` changes
