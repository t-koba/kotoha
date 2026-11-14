"""Loader-resolved Windows runtime providers for the exact probe executable.

Developer probe only. Not engine adoption, redistribution approval, or a
licensing determination. No model fixture is read, no DLL is copied or
shipped, and no product behavior or upstream engine source is changed.

Method: launch the exact configured executable under the Windows debug API
with ``DEBUG_PROCESS`` and observe ``LOAD_DLL_DEBUG_EVENT`` records until
the initial ``EXCEPTION_BREAKPOINT`` fires. That breakpoint arrives before
the application entrypoint runs, so the observed set is the loader-resolved
pre-entrypoint provider set for the launched command
(``llama-simple.exe --help`` or the Release ``kotoha.exe`` with no args).
The helper terminates at the first breakpoint before the executable entrypoint;
the GUI target is never resumed. Windows loader and dependency initialization
may run while providers are mapped, but the Kotoha entrypoint and inference do
not run.

Privacy: absolute provider paths exist only in debugger memory. Published
records contain only SHA-256, size, file/product version, cache-only Windows
trust status, and a path classified as ``app/<rel>`` (exe
directory), ``windows/<rel>`` (``%SystemRoot%`` subtree), or
``redacted/<basename>`` (outside known roots, basename only). Absolute
paths, drive letters, usernames and runner directories are never emitted.
``api-ms-win-*``/``ext-ms-win-*`` direct imports are ApiSet contracts, not
file paths, and are recorded without requiring a matching loaded file
unless exact host mapping is evidenced by the debug observation itself.

Fail-closed: missing/empty debug observation, unreadable provider bytes,
malformed version/signer metadata, unclassifiable paths, absolute-path
leak, missing ordinary direct-import ties, or linkage for another executable
all fail without writing passing outputs. An explicit ``unavailable`` version
or ``Unknown:0x...`` trust result is recorded as unknown, never treated as
signing or licensing approval. Stale outputs are removed on failure like
``compiler_reads.py``.
"""

import argparse
import hashlib
import json
import math
import os
import platform
import re
import sys
import time
from pathlib import Path


SCHEMA = 1
PROVIDERS_JSON = 'runtime-providers.json'
SUMMARY = 'runtime-summary.txt'
CAPTURE = 'debug-initial-breakpoint'
COMMANDS = {
    'llama-simple.exe': ['llama-simple.exe', '--help'],
    'kotoha.exe': ['kotoha.exe'],
}
SIGNER_CHECK = 'WinVerifyTrust WTD_UI_NONE WTD_REVOKE_NONE WTD_CACHE_ONLY_URL_RETRIEVAL'

DEFAULT_MAX_PROVIDERS = 256
DEFAULT_MAX_IMPORTS = 256
SHA_RE = re.compile(r'[0-9a-f]{64}')
VERSION_RE = re.compile(r'\d+\.\d+\.\d+\.\d+')
DLL_LINE_RE = re.compile(r'^\s*([A-Za-z0-9][A-Za-z0-9_.\-]*\.dll)\s*$', re.IGNORECASE)
DLL_NAME_RE = re.compile(r'DLL\s+Name\s*:\s*(\S+\.dll)', re.IGNORECASE)
DUMP_FILE_RE = re.compile(r'^\s*Dump of file\s+(.+?)\s*$', re.IGNORECASE | re.MULTILINE)
BASENAME_RE = re.compile(r'[a-z0-9][a-z0-9_.\-]*\.[a-z0-9]+')
SIGNER_RE = re.compile(r'Valid|NotSigned|HashMismatch|Untrusted|Expired|Revoked|Unknown(?::0x[0-9A-Fa-f]{1,8})?')


def is_api_contract(name_lower):
    """ApiSet contracts resolve via the host schema, not to same-named files."""
    return name_lower.startswith('api-ms-win-') or name_lower.startswith('ext-ms-win-')


def _basename_lower(value):
    base = value.replace('\\', '/').rsplit('/', 1)[-1].lower()
    if not BASENAME_RE.fullmatch(base):
        raise ValueError('Provider basename is not safely representable; closure incomplete')
    return base


def _linkage_target(text):
    matches = list(DUMP_FILE_RE.finditer(text))
    if len(matches) != 1:
        raise ValueError('Linkage image identity is missing or ambiguous; closure incomplete')
    return matches[0].group(1)


def _normalize_dos(value):
    """Lowercase DOS path with forward slashes and no extended prefix."""
    text = value.replace('\\', '/')
    lower = text.lower()
    if lower.startswith('//?/unc/'):
        text = '//' + text[len('//?/UNC/'):]
    elif lower.startswith('//?/'):
        text = text[len('//?/'):]
    return text.lower()


def classify_provider(absolute, app_root, windows_root):
    """Classify an absolute provider path without ever emitting it.

    ``app_root``/``windows_root`` are absolute DOS strings (any casing or
    slash style). Returns ``app/<rel>``, ``windows/<rel>`` or
    ``redacted/<basename>`` in lowercase with forward slashes. Raises on
    non-absolute or unsafe inputs. Never includes drive letters or hosts.
    """
    normalized = _normalize_dos(absolute)
    if not re.match(r'^[a-z]:/', normalized) and not normalized.startswith('//'):
        raise ValueError('Provider path is not absolute; closure incomplete')
    if '..' in normalized.split('/'):
        raise ValueError('Provider path contains traversal; closure unsafe')
    roots = sorted(((app_root, 'app'), (windows_root, 'windows')),
                   key=lambda item: len(_normalize_dos(item[0])), reverse=True)
    norm_roots = [(_normalize_dos(root), label) for root, label in roots]
    if len({root for root, _ in norm_roots}) != 2:
        raise ValueError('Provider roots must be distinct; closure incomplete')
    for root, label in norm_roots:
        prefix = root.rstrip('/') + '/'
        if normalized.startswith(prefix):
            relative = normalized[len(prefix):]
            if not relative or '..' in relative.split('/') or ':' in relative or '\\' in relative:
                raise ValueError('Provider relative path is unsafe; closure incomplete')
            if not BASENAME_RE.fullmatch(relative.rsplit('/', 1)[-1]):
                raise ValueError('Provider basename is not safely representable; closure incomplete')
            return label + '/' + relative
    return 'redacted/' + _basename_lower(absolute)


def parse_linkage_log(text, expected_exe, max_imports=DEFAULT_MAX_IMPORTS):
    """Parse dumpbin linkage for the exact executable into direct/delay DLL names.

    Handles both ``Image has the following dependencies:`` and
    ``Image has the following delay load dependencies:`` sections plus
    ``DLL Name:`` rows from /HEADERS. Delay imports are recorded but never
    required pre-entrypoint. Raises when the expected section is missing.
    """
    if '\x00' in text:
        raise ValueError('Linkage evidence is not text; closure incomplete')
    if max_imports < 1:
        raise ValueError('Import count limit must be positive; closure incomplete')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.\-]*\.exe', expected_exe):
        raise ValueError('Expected executable name is malformed; closure incomplete')
    target = _linkage_target(text)
    if _basename_lower(target) != expected_exe.lower():
        raise ValueError('Linkage evidence does not name the exact executable; closure incomplete')
    normalized = text.replace('\r\n', '\n').replace('\r', '\n')
    if 'following dependencies' not in normalized.lower():
        raise ValueError('Missing dumpbin dependencies section; closure incomplete')
    direct, delay = set(), set()
    in_delay = False
    seen_section = False
    for line in normalized.split('\n'):
        lower = line.lower()
        if 'delay load dependencies' in lower:
            in_delay = True
            seen_section = True
            continue
        if 'following dependencies' in lower:
            # Plain section header resets to ordinary imports; a later delay
            # header switches back. The plain header also matches inside the
            # delay header text, so check delay first.
            if 'delay' not in lower:
                in_delay = False
                seen_section = True
            continue
        match = DLL_LINE_RE.match(line)
        if match and seen_section:
            (delay if in_delay else direct).add(match.group(1).lower())
            continue
        for found in DLL_NAME_RE.finditer(line):
            if seen_section:
                (delay if in_delay else direct).add(found.group(1).lower())
    if not seen_section or not direct:
        raise ValueError('Missing direct import evidence; closure incomplete')
    if len(direct) > max_imports or len(delay) > max_imports:
        raise ValueError('Import count exceeds bound; closure incomplete')
    # A DLL listed in both sections stays direct: the loader must resolve it.
    delay -= direct
    return sorted(direct), sorted(delay)


def verify_no_absolute(text):
    """Reject any runner-private absolute path that would leak into outputs."""
    lower = text.lower()
    if re.search(r'[a-z]:[\\/]', lower):
        raise ValueError('Absolute path leak; closure unsafe')
    if re.search(r'(?<![a-z0-9])/(?!/)', lower):
        raise ValueError('POSIX absolute path leak; closure unsafe')
    if '\\' in text:
        raise ValueError('Backslash path leak; closure unsafe')
    if '//' in text:
        raise ValueError('UNC path leak; closure unsafe')
    for marker in ('/home/', '/tmp/', 'users/', 'runner/', 'runneradmin', 'program files/'):
        if marker in lower:
            raise ValueError('Runner-private path leak; closure unsafe')
    if '..' in lower.replace('\\', '/').split('/'):
        raise ValueError('Traversal leak; closure unsafe')


def sha256_file(path):
    """Stream a file read-only; returns (size, hex). No copy or execute."""
    digest = hashlib.sha256()
    size = 0
    with path.open('rb') as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            size += len(chunk)
            digest.update(chunk)
    if size <= 0:
        raise ValueError('Provider file is empty; closure incomplete')
    return size, digest.hexdigest()


def validate_linkage_target(text, executable):
    """Bind dumpbin output to the exact path whose bytes are hashed.

    The logged path stays in memory and is never copied to the manifest.
    """
    target = _linkage_target(text)
    reported = os.path.normcase(os.path.abspath(target))
    expected = os.path.normcase(os.path.abspath(os.fspath(executable)))
    if reported != expected:
        raise ValueError('Linkage evidence targets another executable path; closure incomplete')


def _read_linkage_text(path):
    raw = path.read_bytes()
    if not raw:
        raise ValueError('Linkage evidence is empty; closure incomplete')
    for encoding in ('utf-8-sig', 'utf-16'):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise ValueError('Linkage evidence is not decodable text; closure incomplete')


def _check_file_info(info):
    if not isinstance(info, dict):
        raise ValueError('Provider record is malformed; closure incomplete')
    if not SHA_RE.fullmatch(info.get('sha256', '')):
        raise ValueError('Provider hash is malformed; closure incomplete')
    if not isinstance(info.get('size'), int) or isinstance(info.get('size'), bool) or info['size'] <= 0:
        raise ValueError('Provider size is malformed; closure incomplete')
    for key in ('file_version', 'product_version'):
        value = info.get(key, '')
        if value != 'unavailable' and not VERSION_RE.fullmatch(value):
            raise ValueError('Provider version is malformed; closure incomplete')
    if not SIGNER_RE.fullmatch(info.get('signer_status', '')):
        raise ValueError('Provider signer status is malformed; closure incomplete')


def assemble(*, exe_name, exe_sha256, exe_size, exe_classified,
             linkage_text, linkage_sha256, debug_paths,
             file_info, app_root, windows_root,
             max_providers=DEFAULT_MAX_PROVIDERS, max_imports=DEFAULT_MAX_IMPORTS):
    """Build the privacy-safe manifest from debug-observed absolute paths.

    ``debug_paths`` are absolute provider paths in loader observation order
    (memory only). ``file_info`` maps each absolute path to its
    ``{sha256,size,file_version,product_version,signer_status}``
    record. Returns ``(manifest, summary)``. Raises without partial outputs
    on any incomplete or unsafe input. Never emits absolute paths.
    """
    if max_providers < 1:
        raise ValueError('Provider count limit must be positive; closure incomplete')
    if max_imports < 1:
        raise ValueError('Import count limit must be positive; closure incomplete')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.\-]*\.exe', exe_name):
        raise ValueError('Executable name is malformed; closure incomplete')
    command = COMMANDS.get(exe_name.lower())
    if command is None:
        raise ValueError('Unexpected executable; capture target is not configured')
    if not SHA_RE.fullmatch(exe_sha256):
        raise ValueError('Executable hash is malformed; closure incomplete')
    if not isinstance(exe_size, int) or isinstance(exe_size, bool) or exe_size <= 0:
        raise ValueError('Executable size is malformed; closure incomplete')
    if not SHA_RE.fullmatch(linkage_sha256):
        raise ValueError('Linkage hash is malformed; closure incomplete')
    if exe_classified != classify_provider(app_root + '/placeholder.exe', app_root, windows_root).rsplit('/', 1)[0] + '/' + exe_name.lower():
        # Binds the exe record to the same app-root classification without
        # ever emitting the absolute exe path.
        raise ValueError('Executable is outside the app root; closure incomplete')
    direct, delay = parse_linkage_log(linkage_text, exe_name, max_imports)
    contracts = sorted(name for name in direct if is_api_contract(name))
    ordinary = sorted(name for name in direct if not is_api_contract(name))
    if not debug_paths or len(debug_paths) > max_providers:
        raise ValueError('Loader observation is missing or exceeds bound; closure incomplete')
    seen = set()
    providers = []
    for index, absolute in enumerate(debug_paths):
        base = _basename_lower(absolute)
        if base in seen:
            raise ValueError('Ambiguous provider basename; closure incomplete')
        seen.add(base)
        classified = classify_provider(absolute, app_root, windows_root)
        info = file_info(absolute)
        _check_file_info(info)
        if classified.startswith('redacted/') and classified != 'redacted/' + base:
            raise ValueError('Redacted path mismatch; closure unsafe')
        if not classified.startswith(('app/', 'windows/', 'redacted/')):
            raise ValueError('Provider classification is malformed; closure unsafe')
        tie = 'transitive'
        if base in ordinary:
            tie = 'direct'
        elif base in delay:
            tie = 'delay'
        providers.append({
            'basename': base,
            'classified_path': classified,
            'sha256': info['sha256'],
            'size': info['size'],
            'file_version': info['file_version'],
            'product_version': info['product_version'],
            'signer_status': info['signer_status'],
            'tie': tie,
            'load_index': index,
        })
    observed = {item['basename'] for item in providers}
    missing = [name for name in ordinary if name not in observed]
    if missing:
        raise ValueError('Direct import without loader resolution; closure incomplete')
    providers.sort(key=lambda item: item['basename'])
    redacted = sum(1 for item in providers if item['classified_path'].startswith('redacted/'))
    manifest = {
        'schema': SCHEMA,
        'capture': CAPTURE,
        'command': list(command),
        'exe': {
            'basename': exe_name.lower(),
            'classified_path': exe_classified,
            'sha256': exe_sha256,
            'size': exe_size,
        },
        'linkage': {'sha256': linkage_sha256},
        'signer_check': SIGNER_CHECK,
        'direct_imports': direct,
        'delay_imports': delay,
        'contracts': contracts,
        'providers': providers,
        'counts': {
            'direct': len(direct),
            'delay': len(delay),
            'contracts': len(contracts),
            'providers': len(providers),
            'redacted': redacted,
        },
    }
    lines = [
        'Loader-resolved Windows providers; debug initial breakpoint before entrypoint.',
        'No model fixture reads, no DLL copies, no redistribution or licensing approval.',
        'Signer status: ' + SIGNER_CHECK + '.',
        'Rows: lowercase SHA256, size, classified path; UTF-8/LF. Contracts have no file paths.',
        'Capture: ' + CAPTURE + ' command ' + ' '.join(command),
        'Executable ' + manifest['exe']['classified_path'] + ' SHA256 ' + exe_sha256,
        'Direct imports: ' + str(len(direct)) + '; delay: ' + str(len(delay)) +
        '; contracts: ' + str(len(contracts)) + '; providers: ' + str(len(providers)) +
        '; redacted: ' + str(redacted),
        'Direct: ' + (', '.join(direct) if direct else '(none)'),
        'Contracts: ' + (', '.join(contracts) if contracts else '(none)'),
    ]
    for item in providers:
        lines.append(item['sha256'] + ' ' + str(item['size']) + ' ' + item['classified_path'] +
                     ' ' + item['file_version'] + ' ' + item['signer_status'] + ' ' + item['tie'])
    if exe_name.lower() == 'kotoha.exe':
        lines.insert(2, 'Windows 11 behavior and runtime redistribution entitlement are not claimed.')
    manifest_text = json.dumps(manifest, sort_keys=True, indent=2) + '\n'
    lines.append('Manifest SHA256: ' + hashlib.sha256(manifest_text.encode('utf-8')).hexdigest())
    summary = '\n'.join(lines) + '\n'
    verify_no_absolute(manifest_text)
    verify_no_absolute(summary)
    return manifest, summary


# ---------------------------------------------------------------------------
# Windows-only loader observation and file metadata. Imported lazily so the
# pure manifest logic above stays testable on POSIX hosts.
# ---------------------------------------------------------------------------

def _require_windows_x64():
    if os.name != 'nt' or sys.platform != 'win32':
        raise RuntimeError('Loader capture requires Windows')
    machine = platform.machine().lower()
    if machine not in ('amd64', 'x86_64'):
        raise RuntimeError('Loader capture requires Windows x64')


def _terminate_before_continuing_event(kernel32, process_handle, pid, tid, continue_status):
    """Request termination before releasing a stopped debug event.

    This prevents application code from running after a failed/incomplete
    loader observation. If termination cannot be requested, do not continue
    the event; the debugger remains attached until process exit.
    """
    if not kernel32.TerminateProcess(process_handle, 1):
        raise ValueError('Could not terminate at initial breakpoint; closure incomplete')
    if not kernel32.ContinueDebugEvent(pid, tid, continue_status):
        raise ValueError('Could not release terminated initial breakpoint; closure incomplete')


def debug_capture_windows(executable, timeout_seconds, max_providers=DEFAULT_MAX_PROVIDERS):
    """Observe pre-entrypoint DLLs via DEBUG_PROCESS until initial breakpoint.

    Returns absolute provider paths in load order (memory only, never
    published). Uses configured command metadata; the GUI target has no
    arguments. Terminates at the first
    first-chance ``EXCEPTION_BREAKPOINT``; any exit before that breakpoint,
    timeout, or unreadable DLL handle fails closed.
    """
    _require_windows_x64()
    if not math.isfinite(timeout_seconds) or timeout_seconds <= 0:
        raise ValueError('Debug timeout must be finite positive; closure incomplete')
    if max_providers < 1:
        raise ValueError('Provider count limit must be positive; closure incomplete')
    import ctypes
    import ctypes.wintypes as w

    DEBUG_PROCESS = 0x00000001
    DEBUG_ONLY_THIS_PROCESS = 0x00000002
    DBG_CONTINUE = 0x00010002
    DBG_EXCEPTION_NOT_HANDLED = 0x80010001
    EXCEPTION_BREAKPOINT = 0x80000003
    INFINITEish = 100  # Poll in 100 ms slices to enforce the bounded deadline.

    class EXCEPTION_RECORD(ctypes.Structure):
        _fields_ = [('ExceptionCode', w.DWORD), ('ExceptionFlags', w.DWORD),
                    ('ExceptionRecord', ctypes.c_void_p), ('ExceptionAddress', ctypes.c_void_p),
                    ('NumberParameters', w.DWORD), ('ExceptionInformation', ctypes.c_size_t * 15)]

    class EXCEPTION_DEBUG_INFO(ctypes.Structure):
        _fields_ = [('ExceptionRecord', EXCEPTION_RECORD), ('dwFirstChance', w.DWORD)]

    class CREATE_PROCESS_DEBUG_INFO(ctypes.Structure):
        _fields_ = [('hFile', ctypes.c_void_p), ('hProcess', ctypes.c_void_p),
                    ('hThread', ctypes.c_void_p), ('lpBaseOfImage', ctypes.c_void_p),
                    ('dwDebugInfoFileOffset', w.DWORD), ('nDebugInfoSize', w.DWORD),
                    ('lpThreadLocalBase', ctypes.c_void_p), ('lpStartAddress', ctypes.c_void_p),
                    ('lpImageName', ctypes.c_void_p), ('fUnicode', w.WORD)]

    class LOAD_DLL_DEBUG_INFO(ctypes.Structure):
        _fields_ = [('hFile', ctypes.c_void_p), ('lpBaseOfDll', ctypes.c_void_p),
                    ('dwDebugInfoFileOffset', w.DWORD), ('nDebugInfoSize', w.DWORD),
                    ('lpImageName', ctypes.c_void_p), ('fUnicode', w.WORD)]

    class EXIT_PROCESS_DEBUG_INFO(ctypes.Structure):
        _fields_ = [('dwExitCode', w.DWORD)]

    class DEBUG_UNION(ctypes.Union):
        _fields_ = [('Exception', EXCEPTION_DEBUG_INFO),
                    ('CreateProcessInfo', CREATE_PROCESS_DEBUG_INFO),
                    ('LoadDll', LOAD_DLL_DEBUG_INFO),
                    ('ExitProcess', EXIT_PROCESS_DEBUG_INFO)]

    class DEBUG_EVENT(ctypes.Structure):
        _fields_ = [('dwDebugEventCode', w.DWORD), ('dwProcessId', w.DWORD),
                    ('dwThreadId', w.DWORD), ('u', DEBUG_UNION)]

    class STARTUPINFOW(ctypes.Structure):
        _fields_ = [('cb', w.DWORD), ('lpReserved', w.LPWSTR), ('lpDesktop', w.LPWSTR),
                    ('lpTitle', w.LPWSTR), ('dwX', w.DWORD), ('dwY', w.DWORD),
                    ('dwXSize', w.DWORD), ('dwYSize', w.DWORD), ('dwXCountChars', w.DWORD),
                    ('dwYCountChars', w.DWORD), ('dwFillAttribute', w.DWORD), ('dwFlags', w.DWORD),
                    ('wShowWindow', w.WORD), ('cbReserved2', w.WORD), ('lpReserved2', ctypes.c_void_p),
                    ('hStdInput', ctypes.c_void_p), ('hStdOutput', ctypes.c_void_p),
                    ('hStdError', ctypes.c_void_p)]

    class PROCESS_INFORMATION(ctypes.Structure):
        _fields_ = [('hProcess', ctypes.c_void_p), ('hThread', ctypes.c_void_p),
                    ('dwProcessId', w.DWORD), ('dwThreadId', w.DWORD)]

    kernel32 = ctypes.windll.kernel32
    kernel32.CreateProcessW.argtypes = [w.LPCWSTR, w.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
                                        w.BOOL, w.DWORD, ctypes.c_void_p, w.LPCWSTR,
                                        ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION)]
    kernel32.CreateProcessW.restype = w.BOOL
    kernel32.WaitForDebugEvent.argtypes = [ctypes.POINTER(DEBUG_EVENT), w.DWORD]
    kernel32.WaitForDebugEvent.restype = w.BOOL
    kernel32.ContinueDebugEvent.argtypes = [w.DWORD, w.DWORD, w.DWORD]
    kernel32.ContinueDebugEvent.restype = w.BOOL
    kernel32.TerminateProcess.argtypes = [ctypes.c_void_p, w.UINT]
    kernel32.TerminateProcess.restype = w.BOOL
    kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
    kernel32.CloseHandle.restype = w.BOOL
    kernel32.GetFinalPathNameByHandleW.argtypes = [ctypes.c_void_p, w.LPWSTR, w.DWORD, w.DWORD]
    kernel32.GetFinalPathNameByHandleW.restype = w.DWORD
    kernel32.GetLastError.argtypes = []
    kernel32.GetLastError.restype = w.DWORD

    def final_path(handle):
        # DOS volume path (``\\?\C:\...``); caller strips the prefix only for
        # classification, never publishes the absolute.
        size = 32768
        buffer = ctypes.create_unicode_buffer(size)
        length = kernel32.GetFinalPathNameByHandleW(handle, buffer, size, 0)
        if length == 0 or length >= size:
            raise ValueError('Loader handle without resolvable path; closure incomplete')
        return buffer.value

    exe_str = str(executable)
    args = COMMANDS.get(Path(executable).name.lower())
    if not args:
        raise ValueError('Executable command metadata missing; closure incomplete')
    command_line = ' '.join(['"' + exe_str + '"'] + args[1:])
    command_buffer = ctypes.create_unicode_buffer(command_line)
    startup = STARTUPINFOW()
    startup.cb = ctypes.sizeof(STARTUPINFOW)
    proc = PROCESS_INFORMATION()
    created = kernel32.CreateProcessW(None, command_buffer, None, None, False,
                                      DEBUG_PROCESS | DEBUG_ONLY_THIS_PROCESS,
                                      None, None, ctypes.byref(startup), ctypes.byref(proc))
    if not created:
        raise ValueError('Debugger launch failed; closure incomplete')
    deadline = time.monotonic() + timeout_seconds
    observed = []
    breakpoint_seen = False
    try:
        while True:
            if time.monotonic() > deadline:
                raise ValueError('Debugger breakpoint timeout; closure incomplete')
            event = DEBUG_EVENT()
            waited = kernel32.WaitForDebugEvent(ctypes.byref(event), INFINITEish)
            if not waited:
                # 121 is ERROR_SEM_TIMEOUT for the polling slice; keep waiting.
                if kernel32.GetLastError() == 121:
                    continue
                raise ValueError('Debug wait failed; closure incomplete')
            code = event.dwDebugEventCode
            pid = event.dwProcessId
            tid = event.dwThreadId
            status = DBG_CONTINUE
            if code == 3:  # CREATE_PROCESS_DEBUG_EVENT: bind debuggee image.
                handle = event.u.CreateProcessInfo.hFile
                if not handle:
                    _terminate_before_continuing_event(kernel32, proc.hProcess, pid, tid, DBG_CONTINUE)
                    raise ValueError('Executable debug event without file handle; closure incomplete')
                try:
                    image_path = final_path(handle)
                    if _normalize_dos(image_path) != _normalize_dos(exe_str):
                        raise ValueError('Debug event image differs from requested executable; closure incomplete')
                except ValueError as error:
                    kernel32.CloseHandle(handle)
                    _terminate_before_continuing_event(kernel32, proc.hProcess, pid, tid, DBG_CONTINUE)
                    raise error
                kernel32.CloseHandle(handle)
            elif code == 6:  # LOAD_DLL_DEBUG_EVENT: pre-entrypoint provider.
                handle = event.u.LoadDll.hFile
                if not handle:
                    _terminate_before_continuing_event(kernel32, proc.hProcess, pid, tid, DBG_CONTINUE)
                    raise ValueError('Loader DLL without file handle; closure incomplete')
                try:
                    observed.append(final_path(handle))
                finally:
                    kernel32.CloseHandle(handle)
                if len(observed) > max_providers:
                    _terminate_before_continuing_event(kernel32, proc.hProcess, pid, tid, DBG_CONTINUE)
                    raise ValueError('Loader observation exceeds bound; closure incomplete')
            elif code == 1:  # EXCEPTION_DEBUG_EVENT.
                exc = event.u.Exception.ExceptionRecord.ExceptionCode
                first = event.u.Exception.dwFirstChance
                if exc == EXCEPTION_BREAKPOINT and first == 1:
                    _terminate_before_continuing_event(kernel32, proc.hProcess, pid, tid, DBG_CONTINUE)
                    breakpoint_seen = True
                    break
                status = DBG_EXCEPTION_NOT_HANDLED
            elif code == 5:  # EXIT_PROCESS_DEBUG_EVENT before breakpoint.
                kernel32.ContinueDebugEvent(pid, tid, DBG_CONTINUE)
                raise ValueError('Process exited before breakpoint; closure incomplete')
            else:
                status = DBG_CONTINUE
            if not kernel32.ContinueDebugEvent(pid, tid, status):
                raise ValueError('Debug continue failed; closure incomplete')
            if len(observed) > max_providers:
                raise ValueError('Loader observation exceeds bound; closure incomplete')
        if not breakpoint_seen:
            raise ValueError('Missing initial breakpoint; closure incomplete')
        if not observed:
            raise ValueError('No loader providers observed; closure incomplete')
        return list(observed)
    finally:
        try:
            if proc.hProcess:
                kernel32.TerminateProcess(proc.hProcess, 1)
        except OSError:
            pass
        # Keep the debugger attached until the target has been terminated;
        # detaching while an event is outstanding could resume application code.
        # Windows kills a debuggee when its debugger exits (the default policy).
        try:
            if proc.hThread:
                kernel32.CloseHandle(proc.hThread)
        except OSError:
            pass
        try:
            if proc.hProcess:
                kernel32.CloseHandle(proc.hProcess)
        except OSError:
            pass


def query_version_windows(absolute):
    """Read file/product version via version.dll; ``unavailable`` if absent."""
    import ctypes
    import ctypes.wintypes as w
    version = ctypes.windll.version
    version.GetFileVersionInfoSizeW.argtypes = [w.LPCWSTR, ctypes.POINTER(w.DWORD)]
    version.GetFileVersionInfoSizeW.restype = w.DWORD
    version.GetFileVersionInfoW.argtypes = [w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p]
    version.GetFileVersionInfoW.restype = w.BOOL
    version.VerQueryValueW.argtypes = [ctypes.c_void_p, w.LPCWSTR,
                                       ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(w.UINT)]
    version.VerQueryValueW.restype = w.BOOL
    handle = w.DWORD(0)
    size = version.GetFileVersionInfoSizeW(absolute, ctypes.byref(handle))
    if size == 0:
        return 'unavailable', 'unavailable'
    buffer = ctypes.create_string_buffer(size)

    class VS_FIXEDFILEINFO(ctypes.Structure):
        _fields_ = [('dwSignature', w.DWORD), ('dwStrucVersion', w.DWORD),
                    ('dwFileVersionMS', w.DWORD), ('dwFileVersionLS', w.DWORD),
                    ('dwProductVersionMS', w.DWORD), ('dwProductVersionLS', w.DWORD),
                    ('dwFileFlagsMask', w.DWORD), ('dwFileFlags', w.DWORD),
                    ('dwFileOS', w.DWORD), ('dwFileType', w.DWORD),
                    ('dwFileSubtype', w.DWORD), ('dwFileDateMS', w.DWORD),
                    ('dwFileDateLS', w.DWORD)]

    if not version.GetFileVersionInfoW(absolute, 0, size, buffer):
        return 'unavailable', 'unavailable'
    pointer = ctypes.c_void_p()
    length = w.UINT(0)
    if not version.VerQueryValueW(buffer, '\\', ctypes.byref(pointer), ctypes.byref(length)):
        return 'unavailable', 'unavailable'
    info = ctypes.cast(pointer, ctypes.POINTER(VS_FIXEDFILEINFO)).contents
    if info.dwSignature != 0xFEEF04BD:
        return 'unavailable', 'unavailable'

    def dotted(ms, ls):
        return str((ms >> 16) & 0xFFFF) + '.' + str(ms & 0xFFFF) + '.' + \
            str((ls >> 16) & 0xFFFF) + '.' + str(ls & 0xFFFF)

    file_version = dotted(info.dwFileVersionMS, info.dwFileVersionLS)
    product_version = dotted(info.dwProductVersionMS, info.dwProductVersionLS)
    if not VERSION_RE.fullmatch(file_version) or not VERSION_RE.fullmatch(product_version):
        return 'unavailable', 'unavailable'
    return file_version, product_version


def query_signer_windows(absolute):
    """Verify cached Windows trust status without online URL retrieval."""
    import ctypes
    import ctypes.wintypes as w

    class GUID(ctypes.Structure):
        _fields_ = [('Data1', w.DWORD), ('Data2', w.WORD), ('Data3', w.WORD),
                    ('Data4', w.BYTE * 8)]

    class WINTRUST_FILE_INFO(ctypes.Structure):
        _fields_ = [('cbStruct', w.DWORD), ('pcwszFilePath', w.LPCWSTR),
                    ('hFile', ctypes.c_void_p), ('pgKnownSubject', ctypes.c_void_p)]

    class WINTRUST_DATA(ctypes.Structure):
        _fields_ = [('cbStruct', w.DWORD), ('pPolicyCallbackData', ctypes.c_void_p),
                    ('pSIPClientData', ctypes.c_void_p), ('dwUIChoice', w.DWORD),
                    ('fdwRevocationChecks', w.DWORD), ('dwUnionChoice', w.DWORD),
                    ('pFile', ctypes.POINTER(WINTRUST_FILE_INFO)),
                    ('dwStateAction', w.DWORD), ('hWVTStateData', ctypes.c_void_p),
                    ('pwszURLReference', w.LPCWSTR), ('dwProvFlags', w.DWORD),
                    ('dwUIContext', w.DWORD)]

    action = GUID(0x00AAC56B, 0xCD44, 0x11D0,
                  (w.BYTE * 8)(0x8C, 0xC2, 0x00, 0xC0, 0x4F, 0xC2, 0x95, 0xEE))
    file_info = WINTRUST_FILE_INFO(ctypes.sizeof(WINTRUST_FILE_INFO), absolute, None, None)
    # WTD_CACHE_ONLY_URL_RETRIEVAL avoids online certificate downloads.
    data = WINTRUST_DATA(ctypes.sizeof(WINTRUST_DATA), None, None, 2, 0, 1,
                         ctypes.pointer(file_info), 1, None, None, 0x00001000, 0)
    wintrust = ctypes.windll.wintrust
    wintrust.WinVerifyTrust.argtypes = [ctypes.c_void_p, ctypes.POINTER(GUID),
                                        ctypes.POINTER(WINTRUST_DATA)]
    wintrust.WinVerifyTrust.restype = ctypes.c_long
    result = wintrust.WinVerifyTrust(None, ctypes.byref(action), ctypes.byref(data))
    try:
        data.dwStateAction = 2
        wintrust.WinVerifyTrust(None, ctypes.byref(action), ctypes.byref(data))
    except OSError:
        pass
    unsigned = int(result) & 0xFFFFFFFF
    mapping = {
        0x00000000: 'Valid',
        0x800B0100: 'NotSigned',
        0x80096010: 'HashMismatch',
        0x800B0109: 'Untrusted',
        0x800B0111: 'Untrusted',
        0x800B0101: 'Expired',
        0x800B010C: 'Revoked',
    }
    status = mapping.get(unsigned, 'Unknown:0x%08X' % unsigned)
    if not SIGNER_RE.fullmatch(status):
        status = 'Unknown'
    return status


def file_info_windows(absolute):
    size, digest = sha256_file(Path(absolute))
    try:
        file_version, product_version = query_version_windows(absolute)
    except OSError:
        raise ValueError('Provider version query failed; closure incomplete')
    try:
        status = query_signer_windows(absolute)
    except OSError:
        raise ValueError('Provider signer query failed; closure incomplete')
    return {'sha256': digest, 'size': size, 'file_version': file_version,
            'product_version': product_version, 'signer_status': status}


def positive_count(value):
    try:
        count = int(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError('must be an integer count') from error
    if count < 1:
        raise argparse.ArgumentTypeError('must be a positive integer count')
    return count


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError('must be finite positive')
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--executable', type=Path, required=True)
    parser.add_argument('--linkage-log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout-seconds', type=positive_seconds, default=60)
    parser.add_argument('--max-providers', type=positive_count, default=DEFAULT_MAX_PROVIDERS)
    parser.add_argument('--max-imports', type=positive_count, default=DEFAULT_MAX_IMPORTS)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    # Do not leave an older passing manifest beside failed new evidence.
    for name in (PROVIDERS_JSON, SUMMARY):
        (args.output / name).unlink(missing_ok=True)
    try:
        _require_windows_x64()
        exe = args.executable.resolve(strict=True)
        linkage_path = args.linkage_log.resolve(strict=True)
        if not exe.is_file() or not linkage_path.is_file():
            raise ValueError('Executable or linkage evidence is not a file; closure incomplete')
        linkage_text = _read_linkage_text(linkage_path)
        validate_linkage_target(linkage_text, exe)
        linkage_sha256 = hashlib.sha256(linkage_path.read_bytes()).hexdigest()
        system_root = os.environ.get('SystemRoot', '')
        if not system_root:
            raise ValueError('Windows provider SystemRoot missing; closure incomplete')
        windows_root = Path(system_root).resolve(strict=True)
        app_root = exe.parent.resolve(strict=True)
        if not windows_root.is_dir() or not app_root.is_dir():
            raise ValueError('Provider roots must be directories; closure incomplete')
        if windows_root == windows_root.parent:
            raise ValueError('Windows root cannot be a drive root; closure incomplete')
        if windows_root == app_root:
            raise ValueError('Provider roots must be distinct; closure incomplete')
        exe_size, exe_sha256 = sha256_file(exe)
        exe_classified = classify_provider(str(exe), str(app_root), str(windows_root))
        expected_exe = 'app/' + exe.name.lower()
        if exe_classified != expected_exe:
            raise ValueError('Executable is outside the app root; closure incomplete')
        debug_paths = debug_capture_windows(exe, args.timeout_seconds, args.max_providers)

        def info(absolute):
            return file_info_windows(absolute)

        manifest, summary = assemble(
            exe_name=exe.name, exe_sha256=exe_sha256, exe_size=exe_size,
            exe_classified=exe_classified, linkage_text=linkage_text,
            linkage_sha256=linkage_sha256, debug_paths=debug_paths,
            file_info=info, app_root=str(app_root), windows_root=str(windows_root),
            max_providers=args.max_providers, max_imports=args.max_imports)
        (args.output / PROVIDERS_JSON).write_text(
            json.dumps(manifest, sort_keys=True, indent=2) + '\n', encoding='utf-8', newline='\n')
        (args.output / SUMMARY).write_text(summary, encoding='utf-8', newline='\n')
        print('Captured loader-resolved providers via ' + CAPTURE + ': ' +
              str(manifest['counts']['providers']) + ' providers, ' +
              str(manifest['counts']['direct']) + ' direct, ' +
              str(manifest['counts']['contracts']) + ' contracts, ' +
              str(manifest['counts']['redacted']) + ' redacted')
    except Exception as error:
        for name in (PROVIDERS_JSON, SUMMARY):
            (args.output / name).unlink(missing_ok=True)
        # OS errors can contain runner-private absolute paths; manifests never do.
        reason = str(error) if type(error) is ValueError else type(error).__name__
        parser.exit(1, 'Runtime-provider capture failed: ' + reason + '; audit evidence incomplete\n')


if __name__ == '__main__':
    main()
