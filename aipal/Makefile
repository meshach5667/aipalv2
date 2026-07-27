.PHONY: dev db api-test mobile-analyze

dev:
	docker compose up -d postgres
	cd apps/api && . .venv/bin/activate 2>/dev/null || true; uvicorn app.main:app --reload --host 0.0.0.0 --port 8102

db:
	docker compose up -d postgres

api-test:
	cd apps/api && . .venv/bin/activate && pytest -q

mobile-analyze:
	cd apps/mobile && flutter analyze
