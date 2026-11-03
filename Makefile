.PHONY: help up down logs build test test-engine test-server lint validate

help:
	@echo "make up | down | logs | build | lint | test | validate"

up:
	docker compose up --build -d

down:
	docker compose down

logs:
	docker compose logs -f --tail=100

build:
	docker build -f server/Dockerfile -t looprun-server .

lint:
	ruff check engine server

test-engine:
	cd engine && python -m pytest

test-server:
	cd server && python -m pytest

test: test-engine test-server

# Static checks that need no Docker daemon.
validate:
	python3 -c "import yaml; [yaml.safe_load(open(f)) for f in ('docker-compose.yml','docker-compose.prod.yml')]; print('compose yaml parses')"
	for f in deploy/setup-lightsail.sh deploy/backup.sh mobile/tool/bootstrap.sh mobile/tool/patch_android.sh mobile/tool/patch_signing.sh; do bash -n $$f || exit 1; done; echo 'bash -n ok'
