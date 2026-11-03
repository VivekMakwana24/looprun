# Looprun

Run a loop, fill the map. An Android-first running game on a shared city map built on H3 hex cells.
The phone records; the server decides loops, ownership and cheating.

- `engine/`: pure Python game logic (loops, cells, ownership, anti-cheat)
- `server/`: FastAPI + Celery + MongoDB + Redis
- `mobile/`: Flutter app
- `docs/`: contract, specs, board, decisions
