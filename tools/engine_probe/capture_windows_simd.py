"""Capture the pinned vec.h branch selected by the Release ggml-cpu target."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import tempfile

REVISION = "31424b7cf14604ca65a9195123da1413f31c4472"
VEC_SHA256 = "6afaaa70b626987e15dc37594e434a0cec28437b02391e8f72367239654ec768"
EXP_CONDITIONS = (
    "defined(__ARM_FEATURE_SVE) && defined(__aarch64__)",
    "defined(__ARM_NEON) && defined(__aarch64__)",
    "defined(__AVX512F__) && defined(__AVX512DQ__)",
    "defined(__AVX2__) && defined(__FMA__)",
    "defined(__SSE2__)",
    "defined(__VXE__) || defined(__VXE2__)",
    "defined(__riscv_v)",
)


def fail(message):
    raise ValueError(message)


def run(args, **kwargs):
    try:
        return subprocess.run(args, capture_output=True, timeout=20, check=False, **kwargs)
    except (OSError, subprocess.SubprocessError):
        fail("required tool invocation failed")


def cache_values(path):
    found = {}
    for line in Path(path).read_text(encoding="utf-8-sig").splitlines():
        match = re.fullmatch(r"([^:#=]+):[^=]+=(.*)", line)
        if match:
            found.setdefault(match.group(1), []).append(match.group(2))
    return found


def file_api(build):
    reply = Path(build) / ".cmake/api/v1/reply"
    indexes = sorted(reply.glob("index-*.json"))
    if len(indexes) != 1:
        fail("CMake File API index missing or ambiguous")
    index = json.loads(indexes[0].read_text(encoding="utf-8"))
    codemodels = [v for v in index.get("objects", []) if v.get("kind") == "codemodel" and v.get("version", {}).get("major") == 2]
    if len(codemodels) != 1:
        fail("CMake codemodel missing or ambiguous")
    model = json.loads((reply / codemodels[0]["jsonFile"]).read_text(encoding="utf-8"))
    configurations = [c for c in model.get("configurations", []) if c.get("name") == "Release"]
    if len(configurations) != 1:
        fail("Release configuration missing or ambiguous")
    targets = []
    for ref in configurations[0].get("targets", []):
        data = json.loads((reply / ref["jsonFile"]).read_text(encoding="utf-8"))
        if data.get("name") == "ggml-cpu":
            targets.append(data)
    if len(targets) != 1:
        fail("ggml-cpu target missing or ambiguous")
    groups = [g for g in targets[0].get("compileGroups", []) if g.get("language") == "CXX"]
    if len(groups) != 1:
        fail("ggml-cpu CXX compile group missing or ambiguous")
    return groups[0]


def conditions(source):
    """Validate the enclosing vec.h branch chain for the SSE2 definition."""
    lines = source.splitlines()
    starts = [i for i, line in enumerate(lines) if re.search(
        r"\binline\s+static\s+__m128\s+ggml_v_expf\s*\(\s*__m128\s+x\s*\)", line)]
    if len(starts) != 1:
        fail("ggml_v_expf definition missing or ambiguous")

    # Keep the complete nesting tree: conditions inside an implementation are
    # not siblings of the architecture-selection chain.
    stack, groups, active = [], [], None
    signature = starts[0]
    for index, line in enumerate(lines):
        match = re.match(r"\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b\s*(.*?)\s*$", line)
        if not match:
            if index == signature:
                active = [(group, group["current"]) for group in stack]
            continue
        directive, expression = match.groups()
        expression = expression.split("//", 1)[0].strip()
        if directive in ("if", "ifdef", "ifndef"):
            group = {"conditions": [expression], "current": expression, "end": None}
            groups.append(group)
            stack.append(group)
        elif directive in ("elif", "else"):
            if not stack:
                fail("unbalanced vec.h conditional")
            group = stack[-1]
            if directive == "elif":
                group["conditions"].append(expression)
                group["current"] = expression
            else:
                group["current"] = None
        elif directive == "endif":
            if not stack:
                fail("unbalanced vec.h conditional")
            group = stack.pop()
            group["end"] = index
    if stack:
        fail("unbalanced vec.h conditional")
    if active is None:
        fail("ggml_v_expf definition is not on a preprocessor branch")

    candidates = [group for group, condition in active
                  if condition == "defined(__SSE2__)"
                  and tuple(group["conditions"]) == EXP_CONDITIONS
                  and group["end"] is not None]
    if len(candidates) != 1:
        fail("pinned ggml_v_expf branch chain mismatch")
    return list(candidates[0]["conditions"])


def evaluate(expr, macros):
    """Evaluate only known branch expressions; no general expression execution."""
    expr = " ".join(expr.split())
    tests = {
        EXP_CONDITIONS[0]: lambda m: {"__ARM_FEATURE_SVE", "__aarch64__"} <= m,
        EXP_CONDITIONS[1]: lambda m: {"__ARM_NEON", "__aarch64__"} <= m,
        EXP_CONDITIONS[2]: lambda m: {"__AVX512F__", "__AVX512DQ__"} <= m,
        EXP_CONDITIONS[3]: lambda m: {"__AVX2__", "__FMA__"} <= m,
        EXP_CONDITIONS[4]: lambda m: "__SSE2__" in m,
        EXP_CONDITIONS[5]: lambda m: bool({"__VXE__", "__VXE2__"} & m),
        EXP_CONDITIONS[6]: lambda m: "__riscv_v" in m,
    }
    if expr not in tests:
        fail("unsupported vec.h condition")
    return tests[expr](set(macros))


def branch_name(expr):
    names = dict(zip(EXP_CONDITIONS, ("arm_sve", "arm_neon", "avx512", "avx2", "sse2", "vxe", "riscv_v")))
    if expr is None: return "none"
    if expr not in names: fail("unknown ggml_v_expf branch")
    return names[expr]


def selected_branch(ordered, macros):
    return branch_name(next((expr for expr in ordered if evaluate(expr, macros)), None))


def compiler_version(output):
    versions = set(re.findall(r"Compiler Version ([0-9]+\.[0-9]+\.[0-9]+)", output))
    if len(versions) != 1: fail("MSVC version missing or ambiguous")
    return next(iter(versions))


def invoked_compiler_version(compiler):
    # CL still requires a source file when /Bv is requested.
    with tempfile.TemporaryDirectory() as work:
        Path(work, "version_probe.cpp").write_text(
            "int kotoha_compiler_version_probe;\n", encoding="ascii")
        result = run([str(compiler), "/nologo", "/Bv", "/c",
                      "/Foversion_probe.obj", "version_probe.cpp"], cwd=work)
    if result.returncode:
        fail("MSVC identity query failed")
    output = (result.stdout + result.stderr).decode("ascii", "ignore")
    return compiler_version(output)


def compiler_identity(build):
    cache = cache_values(Path(build) / "CMakeCache.txt")
    generators = cache.get("CMAKE_GENERATOR", [])
    if len(generators) != 1 or not generators[0].startswith("Visual Studio "):
        fail("CMake generator is not Visual Studio")
    if cache.get("CMAKE_GENERATOR_PLATFORM") != ["x64"]:
        fail("generator platform is not x64")
    instances = cache.get("CMAKE_GENERATOR_INSTANCE", [])
    if len(instances) != 1 or not instances[0]:
        fail("Visual Studio instance missing or ambiguous")
    version_parts = [cache.get("CMAKE_CACHE_" + part + "_VERSION", []) for part in ("MAJOR", "MINOR", "PATCH")]
    if any(len(part) != 1 or not part[0].isdigit() for part in version_parts):
        fail("CMake cache version missing or ambiguous")
    cmake_version = ".".join(part[0] for part in version_parts)
    compiler_file = Path(build) / "CMakeFiles" / cmake_version / "CMakeCXXCompiler.cmake"
    if not compiler_file.is_file():
        fail("CMake CXX compiler metadata missing")
    text = compiler_file.read_text(encoding="utf-8-sig")
    metadata = {}
    for key in ("CMAKE_CXX_COMPILER", "CMAKE_CXX_COMPILER_ID", "CMAKE_CXX_COMPILER_VERSION"):
        matches = re.findall(r'^\s*set\(\s*' + key + r'\s+"([^"]+)"\s*\)\s*$', text, re.MULTILINE)
        if len(matches) != 1:
            fail("CMake CXX compiler metadata missing or ambiguous")
        metadata[key] = matches[0]
    compiler = Path(metadata["CMAKE_CXX_COMPILER"]).resolve(strict=True)
    instance = Path(instances[0]).resolve(strict=True)
    try:
        compiler.relative_to(instance)
    except ValueError:
        fail("CXX compiler is outside the selected Visual Studio instance")
    if compiler.name.casefold() != "cl.exe" or "\\vc\\tools\\msvc\\" not in str(compiler).casefold().replace("/", "\\"):
        fail("CMake CXX compiler is not the selected MSVC toolset")
    if metadata["CMAKE_CXX_COMPILER_ID"] != "MSVC":
        fail("cached CXX compiler identity is not MSVC")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", metadata["CMAKE_CXX_COMPILER_VERSION"]):
        fail("CMake CXX compiler version is invalid")
    return compiler, metadata["CMAKE_CXX_COMPILER_VERSION"]


def capture(source_root, build, output):
    root = Path(source_root).resolve(strict=True)
    revision = run(["git", "-C", str(root), "rev-parse", "HEAD"])
    if revision.returncode or revision.stdout.decode("ascii", "ignore").strip() != REVISION:
        fail("upstream source revision mismatch")
    source = root / "ggml/src/ggml-cpu/vec.h"
    if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != VEC_SHA256:
        fail("pinned vec.h missing or changed")
    passed, cached_version = compiler_identity(build)
    group = file_api(build)
    definitions = [d["define"] for d in group.get("defines", []) if isinstance(d, dict) and isinstance(d.get("define"), str)]
    includes = [i["path"] for i in group.get("includes", []) if isinstance(i, dict) and isinstance(i.get("path"), str)]
    fragments = [f.get("fragment") for f in group.get("compileCommandFragments", []) if isinstance(f, dict) and isinstance(f.get("fragment"), str)]
    if len(definitions) != len(group.get("defines", [])) or len(includes) != len(group.get("includes", [])) or not fragments:
        fail("incomplete target compile group")
    flags = []
    for fragment in fragments:
        flags.extend(shlex.split(fragment, posix=False))
    args = [str(passed), "/nologo", "/EP", "/TP", *flags]
    args.extend("/D" + d for d in definitions)
    args.extend("/I" + i for i in includes)
    text = source.read_text(encoding="utf-8")
    ordered = conditions(text)
    macro_names = sorted({"__ARM_FEATURE_SVE", "__aarch64__", "__ARM_NEON", "__AVX512F__", "__AVX512DQ__", "__AVX2__", "__FMA__", "__SSE2__", "__VXE__", "__VXE2__", "__riscv_v"})
    witness = "KOTOHA_PROBE_OK\n" + "".join(f"#ifdef {name}\nKOTOHA_{name}\n#endif\n" for name in macro_names)
    with tempfile.TemporaryDirectory() as temp:
        probe = Path(temp) / "probe.cpp"
        probe.write_text(witness, encoding="ascii")
        result = run([*args, str(probe)])
    if result.returncode:
        fail("target compile-group preprocessing failed")
    tokens = set(result.stdout.decode("ascii", "strict").split())
    expected = {"KOTOHA_PROBE_OK"} | {"KOTOHA_" + name for name in macro_names}
    if "KOTOHA_PROBE_OK" not in tokens or not tokens.issubset(expected):
        fail("unexpected target preprocessing output")
    macros = {name for name in macro_names if "KOTOHA_" + name in tokens}
    selected = selected_branch(ordered, macros)
    invoked_version = invoked_compiler_version(passed)
    if invoked_version != cached_version:
        fail("invoked MSVC version disagrees with CMake compiler metadata")
    result_data = {"schema": 2, "source_revision": REVISION, "source_sha256": VEC_SHA256,
        "target": "ggml-cpu", "configuration": "Release", "architecture": "x64",
        "compiler": "MSVC", "compiler_version": invoked_version,
        "macros": {name: name in macros for name in macro_names}, "selected_branch": selected,
        "method": "CMake File API Release CXX compile group preprocessing witness"}
    Path(output).write_text(json.dumps(result_data, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    return result_data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.unlink(missing_ok=True)
    try:
        capture(args.source_root, args.build, args.output)
    except (OSError, ValueError, subprocess.SubprocessError, KeyError, TypeError, json.JSONDecodeError):
        parser.exit(1, "Windows SIMD capture failed; evidence incomplete\n")


if __name__ == "__main__":
    main()
