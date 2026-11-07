"""Developer-only ADB transport. Run only inside an exclusively owned emulator.

The caller MUST destroy that emulator on every exit (including cancellation).
Device timeout bounds each real engine process; emulator lifetime is the final
backstop for ADB loss/cleanup failure. No physical-device mode is provided.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import shlex
import tempfile
import uuid

import smoke


def device_root(value):
    path = PurePosixPath(value)
    if (not re.fullmatch(r'/data/local/tmp(?:/[A-Za-z0-9_-]+)*', value)
            or str(path) != value):
        raise argparse.ArgumentTypeError('root must be canonical beneath /data/local/tmp')
    return path


def serial(value):
    if not re.fullmatch(r'emulator-[0-9]+', value):
        raise argparse.ArgumentTypeError('explicit emulator serial required')
    return value


# Pinned Android 15 linker record syntax:
# https://raw.githubusercontent.com/aosp-mirror/platform_bionic/android-15.0.0_r1/linker/linker_main.cpp
# sha256 cf65df734b5e8235e6394e8556f74b2cd97ddec2779186a31ccdb6476be4688d
# lines 807-810 (--list sets g_is_ldd) and 489-492 (exits before constructors);
# https://raw.githubusercontent.com/aosp-mirror/platform_bionic/android-15.0.0_r1/linker/linker.cpp
# sha256 d19c5ace78827e3c12b3238778beacb51fe789768251726df3b4cc56b04ae62b
# lines 3336-3338 (each non-main library as '\t%s => %s (%p)\n' with
# get_soname(), get_realpath(), base).
_LINKER_RECORD = re.compile(r'\t([A-Za-z0-9_+.~\-]+\.so) => (/[A-Za-z0-9_./+\-]+\.so) \(0x[0-9a-fA-F]+\)')
# Android 15's linker --list includes this exact non-file kernel mapping. It is
# retained in the raw smoke log but cannot be hashed like a shared-library path.
_LINKER_VDSO_RECORD = re.compile(r'\tlinux-vdso\.so\.1 => \[vdso\] \(0x[0-9a-fA-F]+\)')


def parse_linker_providers(raw):
    """Strict complete linker --list capture. Accept file-backed providers and
    at most one exact kernel-vDSO row; every row must match a known record.
    Returns sorted unique file paths, not the vDSO pseudo-mapping."""
    text = raw.strip(' \r\n')
    if not text:
        raise RuntimeError('missing runtime linker provider evidence')
    names, seen = set(), set()
    vdso_seen = False
    for line in text.splitlines():
        if _LINKER_VDSO_RECORD.fullmatch(line):
            if vdso_seen:
                raise RuntimeError('duplicate/ambiguous runtime linker vDSO record')
            vdso_seen = True
            continue
        match = _LINKER_RECORD.fullmatch(line)
        if not match:
            raise RuntimeError('unknown/malformed runtime linker provider record')
        name, path = match.group(1), match.group(2)
        posix = PurePosixPath(path)
        if (not path.startswith(('/apex/', '/system/'))
                or '..' in posix.parts or str(posix) != path):
            raise RuntimeError('missing/unknown runtime linker provider evidence')
        if name in names or path in seen:
            raise RuntimeError('duplicate/ambiguous runtime linker provider identity')
        names.add(name)
        seen.add(path)
    if not seen:
        raise RuntimeError('missing runtime linker file-provider evidence')
    return sorted(seen)


class Android:
    def __init__(self, adb, target, avd_name, root, transport_timeout, output_bytes):
        self.adb = [str(adb), '-s', serial(target)]
        if not re.fullmatch(r'kotoha-engine-[A-Za-z0-9_-]+', avd_name):
            raise ValueError('invalid owned AVD name')
        self.avd_name = avd_name
        self.base = device_root(str(root))
        self.root = self.base / ('kotoha-probe-' + uuid.uuid4().hex)
        self.timeout = transport_timeout
        self.output_bytes = output_bytes
        self.owned = False

    def control(self, script):
        result = smoke.invoke(self.adb + ['shell', '-T', 'sh -c ' + shlex.quote(script)],
                              self.timeout, self.output_bytes, 0)
        if result[2]:
            raise RuntimeError('truncated ADB control evidence')
        # Preserve leading tabs: linker --list records start with '\t'.
        return result[0].decode('utf-8').strip(' \r\n')

    def __enter__(self):
        # A unique AVD name binds this serial to the emulator the caller started.
        name = smoke.invoke(self.adb + ['emu', 'avd', 'name'], self.timeout,
                            self.output_bytes, 0)
        if name[2] or name[0].decode('utf-8').split() != [self.avd_name, 'OK']:
            raise RuntimeError('serial does not identify the owned AVD')
        # No device access before fixture consent/verification in run().
        if self.control('getprop ro.kernel.qemu') != '1':
            raise RuntimeError('only an exclusively owned emulator is supported')
        if (self.control('getprop ro.build.version.sdk') != '35'
                or self.control('getprop ro.product.cpu.abi') != 'x86_64'):
            raise RuntimeError('runtime must be Android API 35 x86_64')
        fingerprint = self.control('getprop ro.build.fingerprint')
        if not fingerprint:
            raise RuntimeError('missing runtime fingerprint')
        print('Android runtime fingerprint: ' + json.dumps(fingerprint))
        base = shlex.quote(str(self.base))
        if self.control(f'readlink -f {base}') != str(self.base):
            raise RuntimeError('device root alias or missing root')
        # Fixed Android toybox provider; no PATH-selected substitute for watchdog.
        self.control(shlex.join(['/system/bin/toybox', 'timeout', '-s', 'KILL',
                                 str(math.ceil(self.timeout)), '/system/bin/true']))
        # mkdir is exclusive: never remove a pre-existing directory. If the ADB
        # result is lost, ownership is uncertain: caller destroys the emulator.
        self.control('umask 077; mkdir ' + shlex.quote(str(self.root)))
        self.owned = True
        return self

    def __exit__(self, *error):
        if self.owned:
            root = shlex.quote(str(self.root))
            self.control(f'rm -r {root} && test ! -e {root}')
            self.owned = False

    def push(self, local, name):
        if name not in ('llama-simple', 'model.gguf', 'truncated.gguf'):
            raise ValueError('unowned destination')
        remote = self.root / name
        with local.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        smoke.invoke(self.adb + ['push', str(local.absolute()), str(remote)],
                     self.timeout, self.output_bytes, 0)
        found = self.control('sha256sum ' + shlex.quote(str(remote)))
        if found.split() != [digest, str(remote)]:
            raise RuntimeError('transferred file identity mismatch')
        return remote

    def invoke(self, command, timeout, output_bytes, expected_code, load_failure=False):
        # The timeout utility execs/monitors the real binary, not an ADB-only
        # timeout. No pipeline or shell children are created by llama-simple.
        script = shlex.join(['/system/bin/toybox', 'timeout', '-s', 'KILL',
                             str(math.ceil(timeout)), *command])
        return smoke.invoke(self.adb + ['shell', '-T', 'sh -c ' + shlex.quote(script)],
                            math.ceil(timeout) + self.timeout, output_bytes,
                            expected_code, load_failure=load_failure)


def run(args):
    # In particular, never hash/read/push weights or call any loader before this.
    model = smoke.verify_fixtures(args.fixture_dir, args.accept_terms_sha256)
    with args.executable.open('rb') as stream:
        pin = {'size': args.executable.stat().st_size,
               'sha256': hashlib.file_digest(stream, 'sha256').hexdigest()}
    smoke.verify_file(args.executable, pin)
    print('Android executable identity: ' + json.dumps(pin, sort_keys=True))
    with Android(args.adb, args.serial, args.avd_name, args.device_root,
                 args.adb_timeout_seconds, args.output_bytes) as device:
        executable = device.push(args.executable, 'llama-simple')
        device.control('chmod 700 ' + shlex.quote(str(executable)))
        # Runtime-resolved ELF providers, not configured link options. Pinned
        # Android 15 format: linker_main.cpp --list sets g_is_ldd and exits
        # before constructors; linker.cpp emits each non-main library as
        # '\t<soname> => <realpath> (<base>)\n'. No mandatory library names
        # are inferred from link flags; every represented row is retained and
        # hashed. Raw output is retained for audit; this is loader resolution
        # evidence, not live mappings, all dlopen paths, static members or
        # legal closure.
        providers = device.control('/system/bin/linker64 --list ' + shlex.quote(str(executable)))
        paths = parse_linker_providers(providers)
        print('Android linker providers: ' + json.dumps(providers))
        hashes = device.control('sha256sum ' + shlex.join(paths)).splitlines()
        if (len(hashes) != len(paths) or any(
                not re.fullmatch(r'[0-9a-f]{64}  ' + re.escape(path), line)
                for path, line in zip(paths, hashes))):
            raise RuntimeError('missing runtime provider hashes')
        with tempfile.TemporaryDirectory(prefix='kotoha-android-invalid-') as directory:
            malformed = Path(directory) / 'truncated.gguf'
            smoke.write_malformed(malformed)
            device.push(malformed, 'truncated.gguf')
        remote_model = device.push(model, 'model.gguf')
        smoke.exercise(str(executable), device.root, remote_model, args.tokens,
                       args.timeout_seconds, args.output_bytes, run=device.invoke)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('executable', 'fixture-dir', 'adb'):
        parser.add_argument('--' + name, required=True, type=Path)
    parser.add_argument('--serial', required=True, type=serial)
    parser.add_argument('--device-root', required=True, type=device_root)
    parser.add_argument('--avd-name', required=True)
    parser.add_argument('--accept-terms-sha256', required=True)
    parser.add_argument('--tokens', required=True, type=smoke.positive_int)
    parser.add_argument('--timeout-seconds', required=True, type=smoke.positive_seconds)
    parser.add_argument('--adb-timeout-seconds', required=True, type=smoke.positive_seconds)
    parser.add_argument('--output-bytes', required=True, type=smoke.positive_int)
    run(parser.parse_args())


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, UnicodeError) as error:
        raise SystemExit(f'FAIL: {error}') from error
