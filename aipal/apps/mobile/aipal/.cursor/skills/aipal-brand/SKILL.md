---
name: aipal-brand
description: >-
  AiPal brand guidelines: canonical AiPal spelling, check-brand-copy.sh, warm
  non-clinical tone, no third-party product names in shipped code. Use when
  writing UI copy, icons, onboarding text, or reviewing user-facing strings.
---

# AiPal Brand

## Canonical name

Always **AiPal** — capital A, capital P, lowercase i and al.

| Wrong | Right |
|-------|-------|
| AIpal, AIPAL, aipal | AiPal |

Wordmark widget: `apps/mobile/lib/widgets/aipal_logo.dart` (`AiPalLogo`, `AiPalBrandRow`).

## Brand check script

```bash
scripts/check-brand-copy.sh
```

Scans `apps/mobile/lib`, `apps/mobile/web`, `apps/api/app` for:
- Wrong casing variants (`AIpal`, `AIPAL`, quoted `aipal`)
- Forbidden third-party planner references

Run before every deploy (`deploy-all.sh` runs it automatically).

## Visual tokens

| Token | Hex | Use |
|-------|-----|-----|
| Background | `#0D1117` | scaffold |
| Surface | `#161B22` | cards, sheets |
| Gold | `#E8A838` | primary, wordmark |
| Lavender | `#9B7EDE` | secondary, orb resting |

Icons: `scripts/generate_aipal_icons.py` → `assets/brand/`, Android mipmaps, web favicon.

## Tone

- Warm, proactive, conversational — not clinical or gamified
- Use wake name when known (`profile.wake_name`)
- Medical disclaimer: subtle in onboarding/settings ("Not a substitute for emergency or professional care")
- Crisis path via `safety.py` — never dismissive

## Shipped code rules

- **No third-party product names** in code, comments, or user-facing copy
- Reference patterns in comments generically ("priority lanes", "focus dial") — never name inspiration apps
- Web title/meta: `AiPal` in `web/index.html`, `manifest.json`, `AndroidManifest.xml`
