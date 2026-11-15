#!/usr/bin/env python3
"""Bounded GTK-free FileChooser/Documents portal probe for Linux CI.

The test backend returns one synthetic fixture URI. The installed desktop-portal
frontend and Documents portal remain real; no chooser UI or Kotoha Linux support
is exercised by this probe.
"""

from __future__ import annotations

import argparse
import configparser
import errno
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
from urllib.request import url2pathname

APP_ID = "org.kotoha.PortalProbe"
BACKEND_BUS = "org.freedesktop.impl.portal.desktop.kotoha_test"
BACKEND_IFACE = "org.freedesktop.impl.portal.FileChooser"
DESKTOP_BUS = "org.freedesktop.portal.Desktop"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
DOCS_BUS = "org.freedesktop.portal.Documents"
DOCS_PATH = "/org/freedesktop/portal/documents"
DOCS_IFACE = "org.freedesktop.portal.Documents"
FIXTURE = b"Kotoha portal probe fixture v1\n"


class ProbeFailure(Exception):
    def __init__(self, stage: str):
        super().__init__(stage)
        self.stage = stage


def _dbus_modules():
    try:
        import dbus
        import dbus.service
        from dbus.mainloop.glib import DBusGMainLoop
        from gi.repository import GLib
    except ImportError as exc:
        raise ProbeFailure("python-dbus-or-glib-unavailable") from exc
    return dbus, dbus.service, DBusGMainLoop, GLib


def _write_json(path: str, value: dict[str, object]) -> None:
    temporary = path + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, sort_keys=True)
        handle.write("\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temporary, path)


def run_backend() -> None:
    dbus, service, DBusGMainLoop, GLib = _dbus_modules()
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    if bus.request_name(BACKEND_BUS, dbus.bus.NAME_FLAG_DO_NOT_QUEUE) != dbus.bus.REQUEST_NAME_REPLY_PRIMARY_OWNER:
        raise ProbeFailure("backend-name-not-owned")

    uri = os.environ["KOTOHA_PORTAL_TEST_URI"]
    report = os.environ["KOTOHA_PORTAL_BACKEND_REPORT"]
    ready = os.environ["KOTOHA_PORTAL_BACKEND_READY"]
    requests = []

    class ImplRequest(service.Object):
        def __init__(self, path: str):
            super().__init__(bus, path)

        @service.method("org.freedesktop.impl.portal.Request", in_signature="", out_signature="")
        def Close(self):
            return None

    class Backend(service.Object):
        @service.method(
            BACKEND_IFACE,
            in_signature="osssa{sv}",
            out_signature="ua{sv}",
            async_callbacks=("reply", "error"),
        )
        def OpenFile(self, handle, app_id, parent_window, title, options, reply, error):
            try:
                _write_json(report, {"app_id": str(app_id)})
                requests.append(ImplRequest(str(handle)))
                result = dbus.Dictionary(
                    {"uris": dbus.Array([uri], signature="s")}, signature="sv"
                )
                reply(dbus.UInt32(0), result)
            except Exception:
                error(dbus.DBusException("test backend failed"))

    backend = Backend(bus, DESKTOP_PATH)
    _write_json(ready, {"ready": True})
    loop = GLib.MainLoop()
    GLib.timeout_add_seconds(90, lambda: (loop.quit(), False)[1])
    loop.run()
    backend.remove_from_connection()


def _portal_response(dbus, GLib):
    DBusGMainLoop = _dbus_modules()[2]
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    loop = GLib.MainLoop()
    replies = []

    def on_response(code, results, **_kwargs):
        if not replies:
            replies.append((int(code), results))
            loop.quit()

    bus.add_signal_receiver(
        on_response,
        signal_name="Response",
        dbus_interface="org.freedesktop.portal.Request",
        bus_name=DESKTOP_BUS,
    )
    desktop = dbus.Interface(
        bus.get_object(DESKTOP_BUS, DESKTOP_PATH),
        "org.freedesktop.portal.FileChooser",
    )
    options = dbus.Dictionary(
        {
            "handle_token": dbus.String("kotoha_probe"),
            "modal": dbus.Boolean(False),
        },
        signature="sv",
    )
    try:
        desktop.OpenFile("", "Kotoha portal probe", options, timeout=10)
    except dbus.DBusException as exc:
        raise ProbeFailure("filechooser-openfile-call-failed") from exc

    if not replies:
        timer = GLib.timeout_add_seconds(20, lambda: (loop.quit(), False)[1])
        loop.run()
        GLib.source_remove(timer)
    if not replies:
        raise ProbeFailure("filechooser-response-timeout")
    return bus, replies[0]


def run_client() -> None:
    dbus, _, DBusGMainLoop, GLib = _dbus_modules()
    app_info = configparser.ConfigParser()
    if not app_info.read("/.flatpak-info") or app_info.get("Application", "name", fallback="") != APP_ID:
        raise ProbeFailure("synthetic-app-identity-missing")
    fixture_path = os.environ.get("KOTOHA_PORTAL_FIXTURE_PATH", "")
    if not fixture_path or os.path.exists(fixture_path):
        raise ProbeFailure("host-fixture-visible-inside-sandbox")

    bus, (response, results) = _portal_response(dbus, GLib)
    if response != 0 or "uris" not in results or len(results["uris"]) != 1:
        raise ProbeFailure("filechooser-response-not-one-file")
    uri = str(results["uris"][0])
    parsed = urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        raise ProbeFailure("filechooser-result-not-local-file-uri")
    path = url2pathname(unquote(parsed.path))
    mountpoint = os.path.join(os.environ["XDG_RUNTIME_DIR"], "doc")
    try:
        relative = os.path.relpath(path, mountpoint)
    except ValueError as exc:
        raise ProbeFailure("filechooser-result-not-under-document-mount") from exc
    parts = Path(relative).parts
    if not parts or relative == ".." or relative.startswith("../") or len(parts) < 2:
        raise ProbeFailure("filechooser-result-not-under-document-mount")
    doc_id = parts[0]
    if not doc_id or doc_id in (".", ".."):
        raise ProbeFailure("document-id-missing")

    digest = hashlib.sha256()
    fd = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
        total = 0
        while True:
            block = os.read(fd, 8192)
            if not block:
                break
            total += len(block)
            if total > 65536:
                raise ProbeFailure("fixture-read-exceeded-bound")
            digest.update(block)
        docs = dbus.Interface(bus.get_object(DOCS_BUS, DOCS_PATH), DOCS_IFACE)
        docs.RevokePermissions(
            doc_id,
            APP_ID,
            dbus.Array(["read", "grant-permissions"], signature="s"),
            timeout=10,
        )
    except ProbeFailure:
        raise
    except (OSError, dbus.DBusException) as exc:
        raise ProbeFailure("read-or-revoke-failed") from exc
    finally:
        if fd is not None:
            os.close(fd)

    try:
        denied_fd = os.open(path, os.O_RDONLY | os.O_CLOEXEC)
    except OSError as exc:
        denied = exc.errno in (errno.EACCES, errno.EPERM, errno.ENOENT)
        denied_errno = exc.errno
    else:
        os.close(denied_fd)
        denied = False
        denied_errno = 0
    if not denied:
        raise ProbeFailure("access-remained-after-revocation-and-close")

    print(
        json.dumps(
            {
                "app_id": APP_ID,
                "fixture_path_hidden": True,
                "doc_id": doc_id,
                "fixture_sha256": digest.hexdigest(),
                "read_bytes": total,
                "revoke_returned": True,
                "post_close_open_denied": True,
                "post_close_errno": denied_errno,
            },
            sort_keys=True,
        )
    )


def _get_property(dbus, bus, name: str, interface: str) -> int:
    properties = dbus.Interface(
        bus.get_object(name, "/org/freedesktop/portal/desktop"),
        "org.freedesktop.DBus.Properties",
    )
    return int(properties.Get(interface, "version", timeout=5))


def run_host() -> dict[str, object]:
    dbus, _, DBusGMainLoop, _ = _dbus_modules()
    DBusGMainLoop(set_as_default=True)
    root = Path(os.environ["KOTOHA_PORTAL_PROBE_ROOT"])
    data_home = Path(os.environ["XDG_DATA_HOME"])
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    fixture = root / "fixture.md"
    app_info_path = root / "flatpak-info"
    backend_report = str(root / "backend.json")
    backend_ready = str(root / "backend-ready.json")
    fixture.write_bytes(FIXTURE)
    app_info_path.write_text(f"[Application]\nname={APP_ID}\n", encoding="utf-8")
    portal_dir = data_home / "xdg-desktop-portal" / "portals"
    portal_dir.mkdir(parents=True, exist_ok=True)
    (portal_dir / "kotoha-test.portal").write_text(
        "[portal]\n"
        f"DBusName={BACKEND_BUS}\n"
        "Interfaces=org.freedesktop.impl.portal.FileChooser;\n"
        "UseIn=KOTOHA_PORTAL_TEST;\n",
        encoding="utf-8",
    )
    env = os.environ.copy()
    env.update(
        {
            "KOTOHA_PORTAL_TEST_URI": fixture.as_uri(),
            "KOTOHA_PORTAL_BACKEND_REPORT": backend_report,
            "KOTOHA_PORTAL_BACKEND_READY": backend_ready,
        }
    )
    backend = subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "--backend"],
        env=env,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        deadline = time.monotonic() + 10
        while not Path(backend_ready).is_file():
            if backend.poll() is not None or time.monotonic() >= deadline:
                raise ProbeFailure("backend-readiness-timeout")
            time.sleep(0.1)

        bus = dbus.SessionBus()
        manager = dbus.Interface(
            bus.get_object("org.freedesktop.DBus", "/org/freedesktop/DBus"),
            "org.freedesktop.DBus",
        )
        manager.StartServiceByName(DESKTOP_BUS, 0, timeout=10)
        docs = dbus.Interface(bus.get_object(DOCS_BUS, DOCS_PATH), DOCS_IFACE)
        mountpoint = os.fsdecode(bytes(docs.GetMountPoint(timeout=10))).rstrip(os.sep)
        if mountpoint != str(runtime / "doc") or not os.path.ismount(mountpoint):
            raise ProbeFailure("documents-fuse-mount-not-established")

        client_env = env.copy()
        client_env["DBUS_SESSION_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        client_env["KOTOHA_PORTAL_FIXTURE_PATH"] = str(fixture)
        command = [
            "bwrap",
            "--die-with-parent",
            "--unshare-all",
            "--ro-bind", "/", "/",
            "--tmpfs", "/home",
            "--tmpfs", "/run",
            "--proc", "/proc",
            "--dev", "/dev",
            "--ro-bind", str(app_info_path), "/.flatpak-info",
            "--ro-bind", str(Path(__file__).resolve()), "/run/portal-probe.py",
            "--bind", mountpoint, mountpoint,
            "--setenv", "DBUS_SESSION_BUS_ADDRESS", client_env["DBUS_SESSION_BUS_ADDRESS"],
            "--setenv", "KOTOHA_PORTAL_FIXTURE_PATH", client_env["KOTOHA_PORTAL_FIXTURE_PATH"],
            "--setenv", "XDG_RUNTIME_DIR", str(runtime),
            "--setenv", "PYTHONUNBUFFERED", "1",
            "--", sys.executable, "/run/portal-probe.py", "--client",
        ]
        try:
            completed = subprocess.run(
                command,
                env=client_env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=40,
                check=False,
            )
        except subprocess.TimeoutExpired as exc:
            raise ProbeFailure("sandbox-client-timeout") from exc
        if completed.returncode != 0:
            raise ProbeFailure("sandbox-client-failed")
        try:
            client = json.loads(completed.stdout)
        except (json.JSONDecodeError, TypeError) as exc:
            raise ProbeFailure("sandbox-client-result-invalid") from exc
        backend_info = json.loads(Path(backend_report).read_text(encoding="utf-8"))
        if client.get("app_id") != APP_ID or backend_info.get("app_id") != APP_ID:
            raise ProbeFailure("portal-app-id-mismatch")
        if client.get("fixture_sha256") != hashlib.sha256(FIXTURE).hexdigest():
            raise ProbeFailure("fixture-content-mismatch")
        if (
            client.get("read_bytes") != len(FIXTURE)
            or not client.get("post_close_open_denied")
            or not client.get("fixture_path_hidden")
        ):
            raise ProbeFailure("sandbox-access-check-failed")

        path_bytes, app_permissions = docs.Info(client["doc_id"], timeout=10)
        source_path = os.fsdecode(bytes(path_bytes))
        if os.path.realpath(source_path) != os.path.realpath(fixture):
            raise ProbeFailure("document-source-mismatch")
        remaining = set(app_permissions.get(APP_ID, []))
        if remaining.intersection({"read", "grant-permissions"}):
            raise ProbeFailure("revoked-permissions-still-recorded")
        all_docs = docs.List("", timeout=10)
        if client["doc_id"] not in all_docs:
            raise ProbeFailure("document-record-not-retained")

        filechooser_version = _get_property(
            dbus, bus, DESKTOP_BUS, "org.freedesktop.portal.FileChooser"
        )
        docs_properties = dbus.Interface(
            bus.get_object(DOCS_BUS, DOCS_PATH), "org.freedesktop.DBus.Properties"
        )
        documents_version = int(
            docs_properties.Get(DOCS_IFACE, "version", timeout=5)
        )
        return {
            "filechooser_version": filechooser_version,
            "documents_version": documents_version,
            "test_app_id": APP_ID,
            "backend_app_id_matches": True,
            "returned_uri_mapped_to_documents_mount": True,
            "fixture_path_hidden_from_client": client["fixture_path_hidden"],
            "fixture_sha256": client["fixture_sha256"],
            "read_bytes": client["read_bytes"],
            "revoke_read_and_grant_permissions_succeeded": client["revoke_returned"],
            "post_close_open_denied": client["post_close_open_denied"],
            "persistent_document_record_retained": True,
            "revoked_permissions_remaining": sorted(
                remaining.intersection({"read", "grant-permissions"})
            ),
        }
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()
            backend.wait(timeout=3)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--backend", action="store_true")
    parser.add_argument("--client", action="store_true")
    args = parser.parse_args()
    stage = "initialization"
    try:
        if args.backend:
            run_backend()
            return 0
        if args.client:
            run_client()
            return 0
        stage = "portal-documents-revocation"
        result = run_host()
        print(json.dumps(result, sort_keys=True))
        return 0
    except ProbeFailure as exc:
        print(f"Linux portal probe failed: {exc.stage}", file=sys.stderr)
        return 1
    except Exception:
        print(f"Linux portal probe failed: {stage}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
