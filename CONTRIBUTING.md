# Contributing

- Work is tracked as GitHub issues grouped by milestone; each issue carries a requirement and acceptance criteria. `docs/BACKLOG.md` is the human-readable mirror of `.github/issues.json`; regenerate it with `python3 tools/issues.py render` and (re)create issues with `python3 tools/issues.py create` (needs `gh` authenticated with push access).
- `source/ble/FreelapProtocol.mc` is the only file allowed to know Freelap's packet format. Anything decoded from a capture goes there, with the capture (hex + arrival timestamps) committed under `captures/`.
- Keep `minApiLevel` at 3.1.0 unless an issue explicitly raises it; note API-level requirements in code comments.
- Branch from `main`, open a PR that references its issue (`Closes #N`), and tick the acceptance criteria in the PR description.
