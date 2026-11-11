#!/usr/bin/env python3
"""Deterministic OC2-shaped QA server; no provider, shell, or filesystem actions.

Explicit start only:
    python3 tool/qa/scheduled_prompt_fixture.py --serve

This always binds 127.0.0.1:4497. For the dedicated emulator only:
    adb -s emulator-5562 reverse tcp:4497 tcp:4497
The app profile then uses http://127.0.0.1:4497 (not its Ubuntu port).
Stop the recorded fixture PID, never a process-name pattern.

--seed-preferences prints a JSON map of STRING preference values for a fresh QA
emulator. Android's FlutterSharedPreferences.xml prefixes every key with
"flutter.". Merge into the emulator's existing map while the app is stopped;
do not replace unrelated settings. All values are non-secret; no secure-storage
entry is needed. Loopback needs no cleartext consent. The optional cleartext key
shown is the exact loopback origin and is harmless. Never seed an owner's phone.

State is intentionally in memory and resets on process restart. Every response
message and the profile/model names explicitly say QA fixture. This proves app
transport, scheduling and UI behavior, not a real provider or Ubuntu cold-start.
Requests log method/path/status only, never headers, prompt bodies, or secrets.
"""
from __future__ import annotations

import argparse
import copy
import json
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlsplit

HOST = "127.0.0.1"
PORT = 4497
PROFILE_ID = "schedule_qa_fixture"
PROJECT = "/qa/scheduled-prompts"
VERSION = "2.0.29-qa-fixture"
FIXTURE_REPLY = (
    "QA fixture response — scheduled prompt transport completed. "
    "This is a deterministic test response, not AI-generated work."
)
MODEL = {
    "id": "fixture", "modelID": "fixture", "providerID": "qa",
    "name": "QA fixture (no AI provider)", "enabled": True, "status": "active",
    "capabilities": {"tools": False, "input": ["text"], "output": ["text"]},
    "limit": {"context": 16000, "input": 12000, "output": 4000},
    "cost": [{"input": 0, "output": 0, "cache": {"read": 0, "write": 0}}],
}
AGENT = {
    "id": "build", "name": "QA fixture", "description": "Deterministic QA fixture; no tools or provider",
    "mode": "primary", "hidden": False, "permissions": [],
    "model": {"providerID": "qa", "id": "fixture"},
}


def stamp() -> int:
    return time.time_ns() // 1_000_000


def seed_preferences() -> dict[str, str]:
    profile = {
        "id": PROFILE_ID, "name": "Scheduled prompts QA fixture",
        "baseUrl": f"http://{HOST}:{PORT}", "backend": "openCode",
        "username": "opencode", "flavor": "v2", "serverVersion": VERSION,
    }
    return {
        "oc.profiles": json.dumps([profile], separators=(",", ":")),
        "oc.activeProfile": PROFILE_ID,
        f"oc.location.{PROFILE_ID}": json.dumps({"directory": PROJECT, "workspace": None}),
        f"oc.cleartextOk.{PROFILE_ID}": f"http://{HOST}:{PORT}",
        f"oc.model.{PROFILE_ID}": "qa|fixture",
        f"oc.agent.{PROFILE_ID}": "build",
    }


class State:
    def __init__(self) -> None:
        self.changed = threading.Condition(threading.RLock())
        self.sessions: dict[str, dict] = {}
        self.messages: dict[str, list[dict]] = {}
        self.events: list[dict] = []
        self.counter = 0
        self.prompt_count = 0
        self.new_session({"title": "QA fixture conversation", "location": {"directory": PROJECT}})

    def emit(self, kind: str, data: dict, directory: str = PROJECT) -> None:
        with self.changed:
            self.events.append({"id": f"evt_qa_{len(self.events) + 1:06d}", "created": stamp(),
                                "type": kind, "location": {"directory": directory}, "data": data})
            self.changed.notify_all()

    def new_session(self, body: dict) -> dict:
        with self.changed:
            self.counter += 1
            sid = f"ses_qa_{self.counter:06d}"
            now = stamp()
            location = body.get("location") or {"directory": PROJECT}
            row = {"id": sid, "title": body.get("title") or "QA scheduled prompt",
                   "projectID": "project_qa", "agent": body.get("agent") or "build",
                   "model": body.get("model") or {"providerID": "qa", "id": "fixture"},
                   "location": location, "time": {"created": now, "updated": now},
                   "permissions": [], "metadata": body.get("metadata") or {},
                   "tokens": {"input": 0, "output": 0}, "cost": 0}
            self.sessions[sid] = row
            self.messages[sid] = []
            self.emit("session.created", {**row, "sessionID": sid}, location["directory"])
            return copy.deepcopy(row)

    def prompt(self, sid: str, body: dict) -> dict:
        with self.changed:
            self.prompt_count += 1
            now = stamp()
            suffix = f"{self.prompt_count:06d}"
            user_id, assistant_id = f"msg_qa_user_{suffix}", f"msg_qa_assistant_{suffix}"
            directory = self.sessions[sid]["location"]["directory"]
            self.messages[sid].extend([
                {"id": user_id, "type": "user", "text": str(body.get("text", "")),
                 "time": {"created": now, "completed": now}, "files": []},
                {"id": assistant_id, "type": "assistant", "agent": "build",
                 "model": {"providerID": "qa", "id": "fixture"},
                 "time": {"created": now, "streamed": now, "completed": now},
                 "content": [{"type": "text", "text": FIXTURE_REPLY}], "finish": "stop",
                 "tokens": {"input": 0, "output": 0}, "cost": 0},
            ])
            self.sessions[sid]["time"].update({"updated": now, "idle": now})
            self.sessions[sid]["outcome"] = "success"
            common = {"sessionID": sid, "assistantMessageID": assistant_id}
            self.emit("session.execution.started", {"sessionID": sid}, directory)
            self.emit("session.step.started", common, directory)
            self.emit("session.text.started", {**common, "id": "text_qa"}, directory)
            self.emit("session.text.delta", {**common, "id": "text_qa", "delta": FIXTURE_REPLY}, directory)
            self.emit("session.text.ended", {**common, "id": "text_qa", "text": FIXTURE_REPLY}, directory)
            self.emit("session.step.ended", {**common, "finish": "stop", "cost": 0}, directory)
            self.emit("session.execution.succeeded", {"sessionID": sid}, directory)
            return {"id": f"inbox_qa_{suffix}", "sessionID": sid, "timeCreated": now,
                    "type": "prompt", "payload": {"text": str(body.get("text", ""))}, "delivery": "queue"}


class FixtureServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False

    def __init__(self) -> None:
        self.state = State()
        super().__init__((HOST, PORT), Handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "ScheduledPromptQAFixture/1"

    def log_message(self, _format: str, *args: object) -> None:
        # Base class logs raw request lines; deliberately suppress all of them.
        pass

    def reply(self, value: object, code: int = 200) -> None:
        encoded = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)
        print(f"QA fixture {self.command} {urlsplit(self.path).path} {code}", flush=True)

    def data(self, value: object) -> None:
        self.reply({"data": value, "cursor": {"next": None, "previous": None}})

    def body(self) -> dict:
        size = int(self.headers.get("Content-Length", "0"))
        if size < 0 or size > 256_000:
            raise ValueError("Request too large")
        value = json.loads(self.rfile.read(size)) if size else {}
        if not isinstance(value, dict):
            raise ValueError("Expected object")
        return value

    def route(self) -> tuple[str, dict[str, list[str]]]:
        parsed = urlsplit(self.path)
        path = unquote(parsed.path)
        return path.removeprefix("/api"), parse_qs(parsed.query)

    def do_GET(self) -> None:
        path, query = self.route()
        state = self.server.state
        if path == "/health":
            # Stable dialect is intentionally negotiated through /api/info.
            return self.reply({"_tag": "NotFoundError"}, 404)
        if path == "/info":
            return self.reply({"version": VERSION, "urls": [f"http://{HOST}:{PORT}"], "qaFixture": True})
        if path == "/qa/status":
            return self.reply({"qaFixture": True, "promptCount": state.prompt_count,
                               "sessions": len(state.sessions), "providerUsed": False})
        if path == "/event":
            return self.events()
        directory = query.get("location[directory]", [PROJECT])[0]
        if path == "/location":
            return self.reply({"directory": directory, "project": {"id": "project_qa", "directory": PROJECT, "canonical": PROJECT}})
        if path in ("/project", "/project/current"):
            value = {"id": "project_qa", "directory": PROJECT, "canonical": PROJECT, "name": "QA fixture"}
            return self.data([value] if path == "/project" else value)
        if path == "/model":
            return self.data([MODEL])
        if path == "/model/default":
            return self.data(MODEL)
        if path == "/provider":
            return self.data([{"id": "qa", "name": "QA fixture (no provider)", "activation": "enabled"}])
        if path == "/agent":
            return self.data([AGENT])
        if path.startswith("/agent/"):
            return self.data(AGENT)
        if path == "/session/active":
            return self.data({})
        if path == "/session":
            with state.changed:
                rows = copy.deepcopy(list(state.sessions.values()))
            search = query.get("search", [""])[0].casefold()
            rows = [row for row in rows if search in row["title"].casefold()]
            rows.sort(key=lambda row: row["time"]["updated"], reverse=query.get("order", ["desc"])[0] != "asc")
            return self.data(rows)
        if path.startswith("/session/"):
            parts = path.strip("/").split("/")
            sid = parts[1]
            with state.changed:
                if sid not in state.sessions:
                    return self.reply({"_tag": "NotFoundError"}, 404)
                if len(parts) == 2:
                    return self.data(copy.deepcopy(state.sessions[sid]))
                if parts[2] == "message":
                    rows = copy.deepcopy(state.messages[sid])
                    if len(parts) > 3:
                        row = next((row for row in rows if row["id"] == parts[3]), None)
                        return self.data(row)
                    if query.get("order", ["desc"])[0] == "desc":
                        rows.reverse()
                    return self.data(rows)
                if parts[2] in ("inbox", "permission", "form", "todo", "diff", "log", "note"):
                    return self.data([])
        if path in ("/permission/request", "/form", "/form/request", "/vcs/diff", "/worktree", "/skill", "/command", "/tool", "/integration", "/plugin", "/shell"):
            return self.data([])
        if path == "/mcp":
            return self.data([])
        if path == "/vcs":
            return self.reply({"directory": PROJECT, "branch": "qa-fixture", "type": "git"})
        if path == "/path":
            return self.reply({"directory": PROJECT, "worktree": PROJECT, "home": "/qa"})
        if path.startswith("/config"):
            return self.reply({"data": {}, "model": "qa/fixture", "agent": "build"})
        return self.reply({"_tag": "NotFoundError", "message": "Not implemented by QA fixture"}, 404)

    def do_POST(self) -> None:
        try:
            body = self.body()
        except (ValueError, json.JSONDecodeError):
            return self.reply({"_tag": "BadRequestError"}, 400)
        path, _ = self.route()
        state = self.server.state
        if path == "/session":
            return self.data(state.new_session(body))
        parts = path.strip("/").split("/")
        if len(parts) == 3 and parts[0] == "session":
            sid, operation = parts[1:]
            with state.changed:
                if sid not in state.sessions:
                    return self.reply({"_tag": "NotFoundError"}, 404)
                if operation == "prompt":
                    return self.data(state.prompt(sid, body))
                if operation in ("agent", "model"):
                    state.sessions[sid][operation] = body.get(operation)
                    return self.data(copy.deepcopy(state.sessions[sid]))
                if operation in ("wait", "viewed", "interrupt"):
                    return self.reply({"ok": True, "interrupted": False})
        if path.startswith("/experimental/session/") and path.endswith("/wait"):
            return self.reply({"ok": True})
        return self.reply({"_tag": "NotFoundError"}, 404)

    def do_PATCH(self) -> None:
        try:
            body = self.body()
        except (ValueError, json.JSONDecodeError):
            return self.reply({"_tag": "BadRequestError"}, 400)
        path, _ = self.route()
        parts = path.strip("/").split("/")
        state = self.server.state
        if len(parts) == 2 and parts[0] == "session":
            with state.changed:
                if parts[1] not in state.sessions:
                    return self.reply({"_tag": "NotFoundError"}, 404)
                row = state.sessions[parts[1]]
                for key in ("title", "permissions", "metadata", "agent", "model"):
                    if key in body:
                        row[key] = body[key]
                return self.data(copy.deepcopy(row))
        return self.reply({"_tag": "NotFoundError"}, 404)

    def events(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        self.end_headers()
        state = self.server.state
        try:
            self.wfile.write(b'data: {"type":"server.connected","data":{}}\n\n')
            self.wfile.flush()
            with state.changed:
                cursor = len(state.events)
            while True:
                with state.changed:
                    state.changed.wait_for(lambda: len(state.events) > cursor, timeout=10)
                    events = copy.deepcopy(state.events[cursor:])
                    cursor = len(state.events)
                for event in events:
                    self.wfile.write(b"data: " + json.dumps(event, ensure_ascii=False).encode() + b"\n\n")
                if not events:
                    self.wfile.write(b": QA fixture heartbeat\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            pass
        finally:
            self.close_connection = True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument("--serve", action="store_true", help="explicitly bind loopback port 4497")
    action.add_argument("--seed-preferences", action="store_true", help="print emulator-only preference string values; no socket")
    args = parser.parse_args()
    if args.seed_preferences:
        print(json.dumps(seed_preferences(), indent=2))
        return
    server = FixtureServer()
    def stop(_signum: int, _frame: object) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print(f"QA fixture listening on {HOST}:{PORT}; deterministic responses, no AI provider", flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
