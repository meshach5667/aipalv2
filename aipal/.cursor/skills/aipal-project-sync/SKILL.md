---
name: aipal-project-sync
description: >-
  Sync docs/PRODUCT.md phase backlog to GitHub Project "AiPal Roadmap" and Issues.
  Use after phase ships, deploy, or when user asks to sync/update the GitHub project board.
---

# AiPal GitHub Project sync

Canonical source: [`docs/PRODUCT.md`](../../docs/PRODUCT.md).  
Script: [`scripts/sync_github_project.py`](../../scripts/sync_github_project.py).

## When to use

- After shipping a phase (A/B/C0–C4) or Play release
- User says "sync github project", "update roadmap board", "refresh project status"
- After editing `PRODUCT.md` backlog checkboxes

## Workflow

1. **Update product docs first**
   - [`docs/PRODUCT.md`](../../docs/PRODUCT.md) — checkboxes `[x]` / `[ ]`, phase headers
   - [`docs/stakeholder/ROADMAP.md`](../../docs/stakeholder/ROADMAP.md) — stakeholder "Now/Next" if milestone shifted
   - [`apps/mobile/pubspec.yaml`](../../apps/mobile/pubspec.yaml) — version if release shipped

2. **Commit and push to `main`** (preferred — triggers [`.github/workflows/sync-project.yml`](../../.github/workflows/sync-project.yml))

3. **Or run locally** (needs `PROJECT_SYNC_TOKEN`, `GITHUB_TOKEN`, `GH_TOKEN`, or `gh auth login`):
   ```bash
   cd /home/dev/aipal
   chmod +x scripts/sync-github-project.sh
   ./scripts/sync-github-project.sh --bootstrap   # first time only
   ./scripts/sync-github-project.sh
   ```

4. **Report to user**
   - Project URL from [`.github/project.json`](../../.github/project.json) `project_url`
   - Counts: Done / Todo / Deferred
   - Remind: testers use **Issues** for bugs; phase board is for roadmap only

## Status mapping

| PRODUCT.md | GitHub Project Status |
|------------|----------------------|
| `- [x]` | Done |
| `- [ ]` + "deferred" in text | Deferred |
| `- [ ]` otherwise | Todo |

## Do not

- Duplicate backlog in issues manually — script creates `[Phase] title` issues with `track:backlog` label
- Commit `.secrets/` or `.env`
- Edit the plan file in `.cursor/plans/`

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No GitHub token` locally | `gh auth login` or export `GITHUB_TOKEN` / `PROJECT_SYNC_TOKEN` |
| Project empty after push | Add repo secret `PROJECT_SYNC_TOKEN` (classic PAT: `repo` + `project` scopes); run **Sync GitHub Project** workflow |
| Permission denied in CI | Repo Settings → Actions → **Read and write** workflow permissions; sync step uses `PROJECT_SYNC_TOKEN` (GITHUB_TOKEN cannot access Projects v2) |
| Commit step fails (`git add project.json`) | Add `!.github/project.json` to `.gitignore` after `*.json` / `!**/package.json`; workflow uses `git add -f` as backup |
