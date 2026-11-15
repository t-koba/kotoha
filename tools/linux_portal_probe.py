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

APP_ID = "org.kotoha.portalprobe"
CONTROL_APP_ID = "org.kotoha.portalcontrol"
BACKEND_BUS = "org.freedesktop.impl.portal.desktop.kotoha_test"
BACKEND_IFACE = "org.freedesktop.impl.portal.FileChooser"
DESKTOP_BUS = "org.freedesktop.portal.Desktop"
DESKTOP_PATH = "/org/freedesktop/portal/desktop"
DOCS_BUS = "org.freedesktop.portal.Documents"
DOCS_PATH = "/org/freedesktop/portal/documents"
DOCS_IFACE = "org.freedesktop.portal.Documents"
FIXTURE = b"Kotoha portal probe fixture v1\n"
CLIENT_STARTED_MARKER = "KOTOHA_PORTAL_PROBE_CLIENT_STARTED"
PYTHON_PREFLIGHT_MARKER = "KOTOHA_PORTAL_PROBE_PYTHON_PREFLIGHT"


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


# Documents encodes filesystem paths as NUL-terminated D-Bus byte strings.
def _decode_dbus_path(value: object, failure_stage: str) -> str:
    raw = bytes(value)
    if not raw.endswith(b"\x00") or b"\x00" in raw[:-1]:
        raise ProbeFailure(failure_stage)
    return os.fsdecode(raw[:-1])


def _sandbox_client_started(stderr: str) -> bool:
    # subprocess.run already captures stderr; search all of it because later
    # diagnostics can evict this early marker from the bounded stage tail.
    return CLIENT_STARTED_MARKER in stderr


def _run_sandbox_preflight(bwrap_prefix: list[str]) -> None:
    """Check bwrap setup and Python startup without exposing child output."""
    try:
        completed = subprocess.run(
            [*bwrap_prefix, "/bin/true"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise ProbeFailure("sandbox-bwrap-timeout") from exc
    except FileNotFoundError as exc:
        raise ProbeFailure("sandbox-bwrap-executable-missing") from exc
    except OSError as exc:
        raise ProbeFailure("sandbox-bwrap-exec-failed") from exc
    if completed.returncode != 0:
        raise ProbeFailure("sandbox-bwrap-setup-failed")

    try:
        completed = subprocess.run(
            [
                *bwrap_prefix,
                sys.executable,
                "-c",
                f"print({PYTHON_PREFLIGHT_MARKER!r})",
            ],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
    except (subprocess.TimeoutExpired, OSError) as exc:
        raise ProbeFailure("sandbox-python-startup-failed") from exc
    if (
        completed.returncode != 0
        or PYTHON_PREFLIGHT_MARKER not in completed.stdout.splitlines()
    ):
        raise ProbeFailure("sandbox-python-startup-failed")


def _sandbox_failure_stage(stderr: str) -> str | None:
    marker = "Linux portal probe failed: "
    allowed = frozenset("abcdefghijklmnopqrstuvwxyz0123456789-")
    for line in reversed(stderr[-8192:].splitlines()):
        if not line.startswith(marker):
            continue
        stage = line[len(marker) :]
        if stage and len(stage) <= 64 and all(char in allowed for char in stage):
            return stage
    return None


def _sandbox_client_failure_stage(stderr: str) -> str:
    stage = _sandbox_failure_stage(stderr)
    if stage is not None:
        return f"sandbox-client-{stage}"
    if not _sandbox_client_started(stderr):
        return "sandbox-client-script-startup-failed"
    return "sandbox-client-failed"


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
    if (
        not parts
        or relative == ".."
        or relative.startswith("../")
        or len(parts) != 2
        or parts[1] != Path(fixture_path).name
    ):
        raise ProbeFailure("filechooser-result-not-under-document-mount")
    doc_id = parts[0]
    if not doc_id or doc_id in (".", ".."):
        raise ProbeFailure("document-id-missing")

    digest = hashlib.sha256()
    fd = None
    revoke_returned = False
    revoke_error = None
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
        # Prove grant-permissions works before testing same-app revocation.
        try:
            docs.GrantPermissions(
                doc_id,
                CONTROL_APP_ID,
                dbus.Array(["read"], signature="s"),
                timeout=10,
            )
            docs.RevokePermissions(
                doc_id,
                CONTROL_APP_ID,
                dbus.Array(["read"], signature="s"),
                timeout=10,
            )
        except dbus.DBusException as exc:
            raise ProbeFailure("other-app-grant-revoke-control-failed") from exc
        try:
            docs.RevokePermissions(
                doc_id,
                APP_ID,
                dbus.Array(["read", "grant-permissions"], signature="s"),
                timeout=10,
            )
            revoke_returned = True
        except dbus.DBusException as exc:
            if not str(exc.get_dbus_name()).endswith(".NotAllowed"):
                raise ProbeFailure("self-revoke-failed-unexpectedly") from exc
            revoke_error = "NotAllowed"
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
        if exc.errno not in (errno.EACCES, errno.EPERM, errno.ENOENT):
            raise ProbeFailure("post-revoke-open-failed-unexpectedly") from exc
        denied = True
        denied_errno = exc.errno
    else:
        os.close(denied_fd)
        denied = False
        denied_errno = 0
    if denied != revoke_returned:
        raise ProbeFailure("post-close-access-does-not-match-revocation-result")

    print(
        json.dumps(
            {
                "app_id": APP_ID,
                "fixture_path_hidden": True,
                "doc_id": doc_id,
                "fixture_sha256": digest.hexdigest(),
                "read_bytes": total,
                "other_app_control_succeeded": True,
                "revoke_returned": revoke_returned,
                "revoke_error": revoke_error,
                "post_close_open_denied": denied,
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


def _sandbox_client_prefix(
    app_info_path: Path,
    script_path: Path,
    mountpoint: str,
    dbus_address: str,
    fixture_path: Path,
    runtime: Path,
) -> list[str]:
    # Bind host sources before masking /home; the CI checkout is under /home.
    return [
        "bwrap",
        "--die-with-parent",
        "--unshare-all",
        "--ro-bind", "/", "/",
        "--tmpfs", "/run",
        "--proc", "/proc",
        "--dev", "/dev",
        "--ro-bind", str(app_info_path), "/.flatpak-info",
        "--ro-bind", str(script_path), "/run/portal-probe.py",
        "--bind", mountpoint, mountpoint,
        "--tmpfs", "/home",
        "--setenv", "DBUS_SESSION_BUS_ADDRESS", dbus_address,
        "--setenv", "KOTOHA_PORTAL_FIXTURE_PATH", str(fixture_path),
        "--setenv", "XDG_RUNTIME_DIR", str(runtime),
        "--setenv", "PYTHONUNBUFFERED", "1",
        "--",
    ]


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
        mountpoint = _decode_dbus_path(
            docs.GetMountPoint(byte_arrays=True, timeout=10),
            "documents-mountpoint-format-invalid",
        )
        if mountpoint != str(runtime / "doc") or not os.path.isdir(mountpoint):
            raise ProbeFailure("documents-mountpoint-path-invalid")

        # GetMountPoint returns the path before the Documents FUSE filesystem is
        # necessarily mounted. Add a separate temporary seed document first;
        # the selected fixture remains new so FileChooser must create/map it.
        mount_seed = root / "mount-seed.txt"
        seed_content = b"portal probe mount seed\n"
        mount_seed.write_bytes(seed_content)
        try:
            with open(mount_seed, "rb") as handle:
                seed_doc_id = str(docs.Add(handle.fileno(), True, False, timeout=10))
        except (OSError, dbus.DBusException) as exc:
            raise ProbeFailure("documents-mount-seed-add-failed") from exc
        seed_id_path = Path(seed_doc_id)
        if (
            not seed_doc_id
            or seed_id_path.is_absolute()
            or len(seed_id_path.parts) != 1
            or seed_doc_id in (".", "..")
        ):
            raise ProbeFailure("documents-mount-seed-id-invalid")
        try:
            with open(Path(mountpoint) / seed_id_path / mount_seed.name, "rb") as handle:
                seeded_content = handle.read(len(seed_content) + 1)
        except OSError as exc:
            raise ProbeFailure("documents-mount-seed-read-failed") from exc
        if seeded_content != seed_content:
            raise ProbeFailure("documents-mount-seed-read-mismatch")
        if not os.path.ismount(mountpoint):
            raise ProbeFailure("documents-fuse-mount-not-established")

        client_env = env.copy()
        client_env["DBUS_SESSION_BUS_ADDRESS"] = os.environ["DBUS_SESSION_BUS_ADDRESS"]
        client_env["KOTOHA_PORTAL_FIXTURE_PATH"] = str(fixture)
        bwrap_prefix = _sandbox_client_prefix(
            app_info_path,
            Path(__file__).resolve(),
            mountpoint,
            client_env["DBUS_SESSION_BUS_ADDRESS"],
            fixture,
            runtime,
        )
        _run_sandbox_preflight(bwrap_prefix)
        command = [*bwrap_prefix, sys.executable, "/run/portal-probe.py", "--client"]
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
            raise ProbeFailure(_sandbox_client_failure_stage(completed.stderr))
        try:
            client = json.loads(completed.stdout)
        except (json.JSONDecodeError, TypeError) as exc:
            raise ProbeFailure("sandbox-client-result-invalid") from exc
        backend_info = json.loads(Path(backend_report).read_text(encoding="utf-8"))
        if client.get("app_id") != APP_ID or backend_info.get("app_id") != APP_ID:
            raise ProbeFailure("portal-app-id-mismatch")
        if client.get("fixture_sha256") != hashlib.sha256(FIXTURE).hexdigest():
            raise ProbeFailure("fixture-content-mismatch")
        revoke_returned = client.get("revoke_returned")
        if (
            client.get("read_bytes") != len(FIXTURE)
            or not client.get("fixture_path_hidden")
            or not isinstance(revoke_returned, bool)
            or not client.get("other_app_control_succeeded")
            or client.get("post_close_open_denied") is not revoke_returned
            or client.get("revoke_error") != (None if revoke_returned else "NotAllowed")
        ):
            raise ProbeFailure("sandbox-access-check-failed")

        path_bytes, app_permissions = docs.Info(client["doc_id"], timeout=10)
        source_path = _decode_dbus_path(
            path_bytes, "document-source-path-format-invalid"
        )
        if os.path.realpath(source_path) != os.path.realpath(fixture):
            raise ProbeFailure("document-source-mismatch")
        remaining = set(app_permissions.get(APP_ID, []))
        control_remaining = set(app_permissions.get(CONTROL_APP_ID, []))
        expected_permissions = set() if revoke_returned else {"read", "grant-permissions"}
        if remaining.intersection({"read", "grant-permissions"}) != expected_permissions:
            raise ProbeFailure("app-permissions-do-not-match-revocation-result")
        if control_remaining:
            raise ProbeFailure("other-app-control-permissions-remain")
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
            "other_app_control_succeeded": client["other_app_control_succeeded"],
            "self_revoke_succeeded": client["revoke_returned"],
            "self_revoke_error": client["revoke_error"],
            "post_close_open_denied": client["post_close_open_denied"],
            "persistent_document_record_retained": True,
            "app_permissions_remaining": sorted(
                remaining.intersection({"read", "grant-permissions"})
            ),
            "other_app_control_permissions_remaining": sorted(control_remaining),
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
    if args.client:
        print(CLIENT_STARTED_MARKER, file=sys.stderr, flush=True)
    stage = "initialization"
    try:
        if args.backend:
            stage = "test-backend"
            run_backend()
            return 0
        if args.client:
            stage = "sandbox-client"
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
