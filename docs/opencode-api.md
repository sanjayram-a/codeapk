# OpenCode HTTP API used by the app

The app talks to its own `opencode serve` (127.0.0.1, HTTP Basic `opencode:<password>`). Native screens use
only the routes below; chat is the OpenCode web UI in a WebView.

**Status: written from OpenCode's published server API for the pinned 1.19.x line, not yet checked against the
running server.** Verify each row on a device (the server serves its OpenAPI document at `GET /doc`) and correct
this file and `app/lib/api/opencode_api.dart` if anything differs. The tests in `app/test/opencode_api_test.dart`
pin the behaviour the app expects.

| Use | Request | Notes |
|---|---|---|
| List sessions | `GET /session?directory=<dir>&search=<text>&limit=<n>` + header `x-opencode-directory: <dir>` | One call per project directory (each directory is its own OpenCode instance). The app merges, de-duplicates by id, sorts by `time.updated` and filters by title again in case `search` is ignored. |
| New session | `POST /session?directory=<dir>` body `{"title": "..."}` | Returns the session object. |
| Rename | `PATCH /session/<id>` body `{"title": "..."}` | |
| Delete | `DELETE /session/<id>` | |
| Projects | `GET /project` | Array with `worktree`; the global project (`/`) is ignored. Non-git folders under `/root/projects` are discovered by the app from the file system instead. |
| Busy check (idle stop) | `GET /session/status` | Object keyed by session id with `{"type": "idle" | "busy" | "retry"}`. Any error or non-object body counts as **busy**, so a wrong endpoint can never cause a premature idle stop (see `RuntimeHost.statusIsBusy`). |
| Open a session in the web UI | `GET /<base64url(directory)>/session/<id>` | `base64url` without padding. Falls back to `/` if the directory is unknown. |

Session JSON fields used: `id`, `title`, `directory`, `time.updated` (ms since epoch, falls back to `time.created`).
