"""App-managed runtime observations, settled fixture writes and owned cleanup.

OC2 HTTP reads support static preservation. The historical OC1 live-survival
fixture is retired and refuses all actions. No server start, provider config reads or credential persistence.
"""

import base64
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request

from .common import PACKAGE, DriverFailure
from .live_fixture import COMMAND, tick_progress
from .terminal import project_terminal
from .observations import (
    ongoing_notification,
    process_start,
    service_foreground,
    socket_identity,
)

FILES = f"/data/user/0/{PACKAGE}/files"
ID_PATTERN = r"[A-Za-z0-9_-]{1,100}"
FGS = PACKAGE + "/.BackgroundConnectionService"
BUILTIN_FGS = PACKAGE + "/.BuiltinServerService"


_PROTOCOL_STAGES = frozenset(
    {
        "oc1_health",
        "oc2_health",
        "oc2_info",
        "session_status",
        "session_create",
        "session_read",
        "session_messages",
        "session_message_create",
        "other",
    }
)
_PROTOCOL_FAILURE_KINDS = frozenset({"http", "transport", "invalid_json"})


def _protocol_stage(method, path):
    fixed = {
        ("GET", "/global/health"): "oc1_health",
        ("GET", "/api/health"): "oc2_health",
        ("GET", "/api/info"): "oc2_info",
        ("GET", "/session/status"): "session_status",
        ("GET", "/api/session/active"): "session_status",
        ("POST", "/session"): "session_create",
    }
    if (method, path) in fixed:
        return fixed[method, path]
    if re.fullmatch(r"/(?:api/)?session/" + ID_PATTERN, path):
        return "session_read" if method == "GET" else "other"
    if re.fullmatch(r"/(?:api/)?session/" + ID_PATTERN + r"/message", path):
        return {"GET": "session_messages", "POST": "session_message_create"}.get(
            method, "other"
        )
    return "other"


def safe_protocol_failure(value):
    """Project only closed failure facts, including when a caller masks errors."""
    if (
        type(value) is not dict
        or set(value) - {"stage", "kind", "httpStatus"}
        or type(value.get("stage")) is not str
        or value["stage"] not in _PROTOCOL_STAGES
        or type(value.get("kind")) is not str
        or value["kind"] not in _PROTOCOL_FAILURE_KINDS
        or (
            "httpStatus" in value
            and (
                type(value["httpStatus"]) is not int
                or not 100 <= value["httpStatus"] <= 599
            )
        )
    ):
        return None
    return dict(value)


class ProtocolResponseFailure(DriverFailure):
    def __init__(self, kind, stage="other", status=None):
        super().__init__("protocol_response_invalid")
        facts = {"stage": stage, "kind": kind}
        if type(status) is int and 100 <= status <= 599:
            facts["httpStatus"] = status
        self.safe_facts = safe_protocol_failure(facts)


class ProtocolHTTPFailure(ProtocolResponseFailure):
    """Retain only HTTP status internally, never response bodies or headers."""

    def __init__(self, status, stage="other"):
        super().__init__("http", stage, status)
        self.status = status


class AndroidRuntimeMixin:
    def terminal_snapshot(self):
        raise DriverFailure("legacy_fixture_retired")

    def find_live_receipt(self, directory):
        raise DriverFailure("legacy_fixture_retired")

    def _connect(self, engine):
        if engine != "opencode2":
            raise DriverFailure("legacy_fixture_retired")
        self._runtime_mismatch = None
        if self._forward is None:
            socket = socket_identity(
                self.text("shell", "cat", "/proc/net/tcp", "/proc/net/tcp6"), self._uid
            )
            if not service_foreground(self.services(), BUILTIN_FGS):
                raise DriverFailure("app_managed_engine_unavailable")
            if self._socket is not None and self._socket != socket:
                raise DriverFailure("app_managed_socket_unavailable")
            self._socket = socket
            password = self.private_bytes(
                FILES + "/linux/ubuntu/root/.oc-builtin/server.password", limit=512
            )
            if (
                not password
                or len(password) > 512
                or b"\n" in password
                or b"\r" in password
            ):
                raise DriverFailure("runtime_password_unavailable")
            self._password = password
            forwarded = self.text("forward", "tcp:0", "tcp:4097")
            if not forwarded.isdigit() or not 1024 <= int(forwarded) <= 65535:
                raise DriverFailure("forward_failed")
            self._forward = int(forwarded)
        try:
            health = self.protocol(
                "GET", "/api/health"
            )
        except ProtocolResponseFailure as failure:
            if (
                engine != "opencode2"
                or not isinstance(failure, ProtocolHTTPFailure)
                or failure.status != 404
            ):
                raise
            info = self.protocol("GET", "/api/info")
            health = {"healthy": True, **info} if type(info) is dict else None
        version = health.get("version") if type(health) is dict else None
        if (
            type(health) is not dict
            or health.get("healthy") is not True
            or not isinstance(version, str)
            or not re.fullmatch(
                r"2\.[0-9]{1,5}\.[0-9]{1,5}(?:[-+][A-Za-z0-9.-]{1,40})?", version
            )
            or not version.startswith("2.")
        ):
            raise DriverFailure("app_managed_engine_unavailable")
        self._runtime_version = version

    def protocol(self, method, path, *, query=None, body=None):
        self._protocol_failure_facts = None
        if self._forward is None or self._password is None:
            raise DriverFailure("protocol_unavailable")
        stage = _protocol_stage(method, path)
        url = f"http://127.0.0.1:{self._forward}{path}"
        if query:
            url += "?" + urllib.parse.urlencode(query)
        header = base64.b64encode(b"opencode:" + self._password).decode("ascii")
        request = urllib.request.Request(
            url,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": "Basic " + header,
                "Content-Type": "application/json",
            },
        )
        try:
            # No env proxy or redirect may receive the in-memory credential.
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({}), _NoRedirect()
            )
            with opener.open(request, timeout=5) as response:
                status = getattr(response, "status", None)
                raw = response.read(2 * 1024 * 1024 + 1)
            if len(raw) > 2 * 1024 * 1024:
                raise DriverFailure("history_too_large")
            try:
                return json.loads(raw)
            except (ValueError, UnicodeError):
                failure = ProtocolResponseFailure("invalid_json", stage, status)
                self._protocol_failure_facts = failure.safe_facts
                raise failure from None
        except DriverFailure:
            raise
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            failure = ProtocolHTTPFailure(status, stage)
            self._protocol_failure_facts = failure.safe_facts
            raise failure from None
        except (OSError, ValueError, urllib.error.URLError):
            failure = ProtocolResponseFailure("transport", stage)
            self._protocol_failure_facts = failure.safe_facts
            raise failure from None

    def _session_history(self, receipt, session):
        engine, directory = receipt["engine"], receipt["directory"]
        self._connect(engine)
        prefix = "/api"
        query = (
            {"location[directory]": directory} if prefix else {"directory": directory}
        )
        info = self.protocol("GET", f"{prefix}/session/{session['id']}", query=query)
        if prefix:
            info = info.get("data") if type(info) is dict else None
        if (
            type(info) is not dict
            or info.get("id") != session["id"]
            or info.get("title") != session["title"]
            or (
                info.get("location", {}).get("directory")
                if prefix
                else info.get("directory")
            )
            != directory
        ):
            raise DriverFailure("history_scope_mismatch")
        history = self.protocol(
            "GET",
            f"{prefix}/session/{session['id']}/message",
            query={**query, "limit": "200", **({"order": "asc"} if prefix else {})},
        )
        if prefix:
            history = history.get("data") if type(history) is dict else None
        if (
            type(history) is not list
            or not history
            or len(history) >= 200
            or any(type(m) is not dict for m in history)
        ):
            raise DriverFailure("history_fixture_missing")
        for message in history:
            owner = (
                message.get("sessionID")
                if prefix
                else message.get("info", {}).get("sessionID")
            )
            if (owner is not None and owner != session["id"]) or (
                not prefix and owner is None
            ):
                raise DriverFailure("history_scope_mismatch")
        return history

    def _history_digests(self):
        if self.history is None:
            raise DriverFailure("preservation_fixture_required")
        result = []
        for session in self.history["sessions"]:
            history = self._session_history(self.history, session)
            result.append(
                hashlib.sha256(json.dumps(history, sort_keys=True).encode()).digest()
            )
        return result

    def _main_process(self):
        pid = self.text("shell", "pidof", PACKAGE)
        if not pid.isdigit():
            raise DriverFailure("live_snapshot_invalid")
        stat = self.text("shell", "cat", f"/proc/{pid}/stat")
        start = process_start(stat)
        if start is None:
            raise DriverFailure("live_snapshot_invalid")
        return pid, start

    def live_snapshot(self):
        raise DriverFailure("legacy_fixture_retired")

    def cleanup_turn(self):
        raise DriverFailure("legacy_fixture_retired")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise DriverFailure("protocol_response_invalid")
