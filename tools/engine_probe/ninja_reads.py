"""Actual Ninja dependency records matched to configured Clang commands.

POSIX/Android only. No MSVC tlog assumptions; no claim that header reads survive
linking. Unknown dependencies or unrepresented built objects fail closed.
"""
import argparse
import json
from pathlib import Path
import re
import shlex

from compiler_reads import digest, manifest


OUTPUTS = ('android-selected-sha256.txt', 'android-compiled-sha256.txt', 'android-compiler-summary.txt')


def absolute(raw, base):
    path = Path(raw)
    if '..' in path.parts:
        raise ValueError('parent traversal in compiler record')
    return path if path.is_absolute() else base / path


def capture(build, source, ndk, probe):
    roots = {name: path.resolve(strict=True) for name, path in
             (('source', source), ('generated', build), ('ndk', ndk), ('probe', probe))}
    if (len(set(roots.values())) != len(roots)
            or not all(p.is_dir() and p.parent != p for p in roots.values())):
        raise ValueError('roots must be distinct directories')
    scopes = sorted(roots.items(), key=lambda item: len(str(item[1])), reverse=True)
    build = roots['generated']
    selected = {}

    def select(path):
        path = path.resolve(strict=True)
        if not path.is_file():
            raise ValueError('compiler dependency is not a file')
        for label, root in scopes:
            if path.is_relative_to(root):
                key = label + '/' + path.relative_to(root).as_posix()
                value = digest(path)
                if key in selected and selected[key] != value:
                    raise ValueError('compiler identity collision')
                selected[key] = value
                return key
        raise ValueError('compiler dependency outside configured roots')

    commands = {}
    database = json.loads((build / 'compile_commands.json').read_text(encoding='utf-8'))
    if not isinstance(database, list) or not database:
        raise ValueError('missing configured compile commands')
    for row in database:
        directory = Path(row['directory'])
        if not directory.is_absolute() or '..' in directory.parts:
            raise ValueError('noncanonical compiler directory')
        args = row.get('arguments') or shlex.split(row['command'])
        if args.count('-o') != 1 or args.count('-c') != 1:
            raise ValueError('unknown compile command format')
        output = absolute(args[args.index('-o') + 1], directory).resolve()
        source_path = absolute(row['file'], directory).resolve(strict=True)
        if (absolute(args[args.index('-c') + 1], directory).resolve(strict=True) != source_path
                or not output.is_relative_to(build) or output in commands):
            raise ValueError('escaping/colliding compiler object or source mismatch')
        commands[output] = source_path

    log = (build / '.ninja_log').read_text(encoding='utf-8').splitlines()
    # Ninja v7 keeps the same five tab-separated fields as v5. Accept only
    # these reviewed versions; unknown log formats remain fail-closed.
    if not log or log[0] not in ('# ninja log v5', '# ninja log v7'):
        raise ValueError('missing/unknown Ninja build log')
    built = set()
    for line in log[1:]:
        fields = line.split('\t')
        if (len(fields) != 5 or not all(value.isdigit() for value in fields[:3])
                or not re.fullmatch('[0-9a-f]+', fields[4])):
            raise ValueError('malformed Ninja build log')
        output = absolute(fields[3], build).resolve()
        if not output.is_relative_to(build):
            raise ValueError('escaping Ninja build output')
        if output in commands:
            if output in built:
                raise ValueError('repeated compiled object in clean-build log')
            built.add(output)
        elif output.suffix in ('.o', '.obj'):
            raise ValueError('unrepresented compiled object in build log')

    objects, compiled = set(), {}
    active = None
    expected = 0
    dependencies = []

    def record_name(path):
        return (path.relative_to(build).as_posix()
                if path.is_relative_to(build) else path.name)

    def finish():
        if active is None:
            return
        name = record_name(active)
        if active not in commands:
            # Ninja may keep depfile records for linker outputs as well as
            # compiler outputs. The probe records the link target separately;
            # keep rejecting any unrepresented object file, and below require
            # a dependency record for every compiled object in the build log.
            if active.suffix in ('.o', '.obj'):
                raise ValueError(f'unrepresented Ninja dependency object {name}')
            return
        if not expected:
            raise ValueError(f'empty Ninja dependency record for {name}')
        if len(dependencies) != expected:
            raise ValueError(f'Ninja dependency count mismatch for {name}: '
                             f'expected {expected}, parsed {len(dependencies)}')
        if not active.is_file() or active in objects:
            raise ValueError('missing or duplicate built object')
        # Ninja records a dependency multiset, while the selected-input manifest
        # represents the canonical set of files. Validate every spelling above;
        # duplicate or symlink-aliased paths to one real file add no new input.
        keys = {select(absolute(raw, build)) for raw in dependencies}
        source_key = select(commands[active])
        if source_key not in keys:
            raise ValueError('compiled source absent from actual dependency record')
        objects.add(active)
        compiled[source_key] = selected[source_key]

    for line in (build / 'ninja-deps.txt').read_text(encoding='utf-8').splitlines():
        if not line:
            continue
        if line.startswith('    '):
            if active is None:
                raise ValueError('dependency before Ninja object')
            dependencies.append(line[4:])
        else:
            finish()
            match = re.fullmatch(r'(.+): #deps ([0-9]+), deps mtime [0-9]+ \(VALID\)', line)
            if not match:
                raise ValueError('unknown/stale Ninja dependency record')
            active = absolute(match[1], build).resolve()
            expected = int(match[2])
            dependencies = []
    finish()
    if not objects or objects != built:
        raise ValueError('missing actual Ninja dependencies for built compiler objects')
    return dict(zip(OUTPUTS, (manifest(selected), manifest(compiled),
                f'Actual built objects represented: {len(objects)}\n'
                f'Unique compiled source keys: {len(compiled)}\n'
                f'Unique selected inputs: {len(selected)}\n'
                'Selected compiler reads only; not surviving binary members or legal approval.\n')))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('build', 'source', 'ndk', 'probe'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    for name in OUTPUTS:
        (args.build / name).unlink(missing_ok=True)
    try:
        outputs = capture(args.build, args.source, args.ndk, args.probe)
        for name, text in outputs.items():
            (args.build / name).write_text(text, encoding='utf-8', newline='\n')
    except (OSError, ValueError, KeyError, IndexError, TypeError) as error:
        reason = str(error) if type(error) is ValueError else type(error).__name__
        parser.exit(1, f'Android compiler-read capture failed: {reason}\n')
