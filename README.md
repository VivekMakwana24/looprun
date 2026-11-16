# Looprun

Run a loop, fill the map. An Android-first running game on a shared city map built on H3 hex cells.
The phone records; the server decides loops, ownership and cheating.

- `engine/`: pure Python game logic (loops, cells, ownership, anti-cheat)
- `server/`: FastAPI + Celery + MongoDB + Redis
- `mobile/`: Flutter app
- `docs/`: contract, specs, board, decisions

## Local development stack

```bash
docker compose up --build        # API on http://localhost:8000, dev login enabled
```

If Redis (6379), MongoDB (27017) or port 8000 are already in use on your machine, move the host ports
(the containers are unaffected):

```bash
LOOPRUN_REDIS_PORT=6380 LOOPRUN_MONGO_PORT=27018 LOOPRUN_API_PORT=8001 docker compose up --build
```

| Variable | Default | Host port of |
| --- | --- | --- |
| `LOOPRUN_API_PORT` | 8000 | the API (the app's `API_BASE_URL` must use the same port) |
| `LOOPRUN_REDIS_PORT` | 6379 | Redis |
| `LOOPRUN_MONGO_PORT` | 27017 | MongoDB |

The mobile app: see `mobile/README.md`. Design mockups: `docs/design/`.
