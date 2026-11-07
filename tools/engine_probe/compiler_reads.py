"""Hash selected MSBuild compiler reads, not the entire pinned source archive."""

import argparse
import hashlib
import re
from pathlib import Path, PureWindowsPath


MANIFESTS = ('source-sha256.txt', 'generated-sha256.txt',
             'toolchain-sha256.txt', 'compiler-tracking-sha256.txt')
SUMMARY = 'compiler-summary.txt'


def identity(value):
    path = PureWindowsPath(value)
    # POSIX absolute paths permit the same bounded file tests on non-Windows hosts.
    if not (path.is_absolute() or str(value).startswith('/')) or '..' in path.parts:
        raise ValueError('Compiler paths must be absolute without parent traversal')
    return path.as_posix().lower()


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def manifest(rows):
    return ''.join(f'{value}  {key}\n' for key, value in sorted(rows.items()))


def capture(source, generated, msvc, sdk):
    roots = {name: path.resolve(strict=True) for name, path in
             zip(('source', 'generated', 'msvc', 'sdk'), (source, generated, msvc, sdk))}
    scopes = {identity(path): name for name, path in roots.items()}
    if len(scopes) != len(roots) or not all(path.is_dir() for path in roots.values()):
        raise ValueError('Configured provider roots must be distinct directories')
    # A nested generated root wins over any enclosing source/provider root.
    scopes = sorted(scopes.items(), key=lambda item: len(item[0]), reverse=True)
    selected, compiled, tracking = {}, set(), {}

    def select(raw):
        identity(raw)  # Reject relative/traversing records before canonicalization.
        resolved = Path(raw).resolve(strict=True)
        key = identity(resolved)
        for scope, label in scopes:
            if key.startswith(scope.rstrip('/') + '/'):
                qualified = f'{label}/{key[len(scope.rstrip("/")) + 1:]}'
                if qualified not in selected:
                    if not resolved.is_relative_to(roots[label]) or not resolved.is_file():
                        raise ValueError('Compiler input is not a file within its configured root')
                    selected[qualified] = digest(resolved)
                return qualified
        raise ValueError('Compiler input outside configured roots; closure incomplete')

    logs = sorted(path for path in roots['generated'].rglob('*.txt')
                  if re.fullmatch(r'CL\.read\..*\.tlog\.txt', path.name, re.IGNORECASE))
    if not logs:
        raise ValueError('Missing CL.read tracking evidence')
    for log in logs:
        relative = log.relative_to(roots['generated']).as_posix().lower()
        if relative in tracking:
            raise ValueError('Ambiguous tracking path')
        tracking[relative] = digest(log)
        active, reads = False, 0
        for line in log.read_text(encoding='utf-8-sig').splitlines():
            if not line:
                continue
            if line.startswith('^'):
                if active and not reads:
                    raise ValueError('Compiler source key without read dependencies')
                for raw in line[1:].split('|'):
                    compiled.add(select(raw))
                active, reads = True, 0
            else:
                if not active:
                    raise ValueError('Read dependency before compiler source key')
                select(line)
                reads += 1
        if not active or not reads:
            raise ValueError('Empty or incomplete compiler tracking evidence')

    source_rows, generated_rows, toolchain_rows = {}, {}, {}
    for key, value in selected.items():
        label, relative = key.split('/', 1)
        if label == 'source':
            source_rows[relative] = value
        elif label == 'generated':
            generated_rows[relative] = value
        else:
            toolchain_rows[key] = value
    outputs = dict(zip(MANIFESTS, map(manifest,
                   (source_rows, generated_rows, toolchain_rows, tracking))))
    source_keys = manifest({key: selected[key] for key in compiled})
    summary = ['Selected actual compiler inputs only; path scopes are not legal approval or binary-member closure.',
               'Rows: lowercase SHA256, two spaces, lowercase root-relative path; UTF-8/LF.',
               f'Unique compiler source keys: {len(compiled)}',
               f'Unique compiler inputs (keys plus dependencies): {len(selected)}',
               f'Compiler source-key manifest SHA256: {hashlib.sha256(source_keys.encode()).hexdigest()}']
    for label in roots:
        keys = [key for key in selected if key.startswith(label + '/')]
        summary.append(f'{label}: {len(keys)} inputs; {len(compiled.intersection(keys))} compiler source keys')
    summary.append(f'Source C/C++ reads: {sum(Path(key).suffix in (".c", ".cc", ".cpp", ".cxx") for key in source_rows)}')
    summary.append(f'Source model CPP reads: {sum(key.startswith("src/models/") and key.endswith(".cpp") for key in source_rows)}')
    summary.append(f'Source header reads: {sum(Path(key).suffix in (".h", ".hpp", ".hxx", ".inl") for key in source_rows)}')
    summary.append(f'Tracking files: {len(tracking)}')
    for name, text in outputs.items():
        summary.append(f'{name}: {hashlib.sha256(text.encode()).hexdigest()}')
    outputs[SUMMARY] = '\n'.join(summary) + '\n'
    return outputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('source', 'generated', 'msvc', 'sdk', 'output'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    # Do not leave an older passing manifest beside failed new evidence.
    for name in (*MANIFESTS, SUMMARY):
        (args.output / name).unlink(missing_ok=True)
    try:
        outputs = capture(args.source, args.generated, args.msvc, args.sdk)
        for name, text in outputs.items():
            (args.output / name).write_text(text, encoding='utf-8', newline='\n')
    except (OSError, ValueError) as error:
        # OS errors can contain runner-private absolute paths; manifests never do.
        reason = str(error) if type(error) is ValueError else type(error).__name__
        parser.exit(1, f'Compiler-read capture failed: {reason}; audit evidence incomplete\n')


if __name__ == '__main__':
    main()
