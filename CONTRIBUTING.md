# Contributing

- Work is tracked as [GitHub issues](https://github.com/MaximumTrainer/garmin-freelap/issues) grouped by milestone; each issue carries a requirement and acceptance criteria, and those criteria are the test list for the PR that closes it. The issues are the source of truth — there is no file mirror to keep in step. `AGENTS.md` describes the outside-in loop the repo follows.
- Before pushing, run what CI runs: `python tools/validate_resources.py` and `python -m pytest tools/tests -q`. The Monkey C rings (`monkeyc -l 1`, `monkeydo -t`) need the SDK and only run locally — see README **Test**.
- `source/ble/BroadcastFrame.mc` is the only Monkey C file that knows Freelap's frame layout, and `tools/freelap_frame.py` is its reference twin — change them in the same commit, which `tools/tests/test_monkeyc_vectors.py` enforces. Captures (hex + arrival timestamps) go under `captures/`.
- The frame specification was shared by Freelap in confidence: implement it, do not reproduce it. It is not in this repo, `*.pdf` is git-ignored, and byte tables do not belong in public issues.
- Keep `minApiLevel` at 3.1.0 unless an issue explicitly raises it; note API-level requirements in code comments.
- Branch from `main`, open a PR that references its issue (`Closes #N`), and tick the acceptance criteria in the PR description.
