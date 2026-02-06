.PHONY: setup install dev dev-backend db-up db-down migrate

setup: install
	cp backend/.env.example backend/.env
	@echo "Edit backend/.env if needed, then: make db-up && make migrate"

install:
	cd backend && poetry install

dev: dev-backend

dev-backend:
	cd backend && poetry run uvicorn app.main:app --reload --port 8000

db-up:
	docker compose up -d db

db-down:
	docker compose down

migrate:
	cd backend && poetry run alembic upgrade head
