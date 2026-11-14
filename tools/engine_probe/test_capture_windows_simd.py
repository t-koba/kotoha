import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import capture_windows_simd as capture




def exp_source(conditions=None, duplicate=False):
    chain = list(capture.EXP_CONDITIONS if conditions is None else conditions)
    lines = ["#if " + chain[0]]
    lines.extend("#elif " + condition + (" // __AVX2__ / __ARM_NEON" if condition == "defined(__SSE2__)" else "") for condition in chain[1:5])
    lines.extend(["#if defined(__FMA__)", "#else", "#endif", "inline static __m128 ggml_v_expf(__m128 x) {", "}"])
    for condition in chain[5:]:
        lines.extend(["#elif " + condition, "int other_impl;"])
    lines.extend(["#else", "#endif"])
    text = "\n".join(lines)
    return text + "\ninline static __m128 ggml_v_expf(__m128 x) { }" if duplicate else text


class CaptureWindowsSimdTest(unittest.TestCase):
    def test_exp_chain_and_branch_precedence(self):
        self.assertEqual(capture.conditions(exp_source()), list(capture.EXP_CONDITIONS))
        cases = [
            ({"__ARM_FEATURE_SVE", "__aarch64__", "__ARM_NEON", "__AVX512F__", "__AVX512DQ__"}, "arm_sve"),
            ({"__ARM_NEON", "__aarch64__", "__AVX512F__", "__AVX512DQ__"}, "arm_neon"),
            ({"__AVX512F__", "__AVX512DQ__", "__AVX2__", "__FMA__"}, "avx512"),
            ({"__AVX2__", "__FMA__", "__SSE2__"}, "avx2"),
            ({"__SSE2__", "__VXE__"}, "sse2"),
            ({"__VXE2__", "__riscv_v"}, "vxe"),
            ({"__riscv_v"}, "riscv_v"),
            (set(), "none"),
        ]
        for macros, expected in cases:
            with self.subTest(expected=expected):
                self.assertEqual(capture.selected_branch(list(capture.EXP_CONDITIONS), macros), expected)
        with self.assertRaises(ValueError): capture.conditions(exp_source(capture.EXP_CONDITIONS[:-1]))
        with self.assertRaises(ValueError): capture.conditions(exp_source(duplicate=True))

    def fixture(self, root, compiler_id="MSVC", target_name="ggml-cpu", extra_targets=(), compiler_inside=True):
        source = root / "source"; build = root / "build"; source.mkdir(); build.mkdir()
        instance = root / "Visual Studio"; instance.mkdir()
        compiler = (instance / "VC/Tools/MSVC/14.51.36231/bin/Hostx64/x64/cl.exe" if compiler_inside else root / "Other/cl.exe")
        compiler.parent.mkdir(parents=True, exist_ok=True); compiler.write_text("")
        cache = ["CMAKE_GENERATOR:INTERNAL=Visual Studio 18 2026", "CMAKE_GENERATOR_PLATFORM:INTERNAL=x64",
                 "CMAKE_GENERATOR_INSTANCE:INTERNAL=" + str(instance), "CMAKE_CACHE_MAJOR_VERSION:INTERNAL=4",
                 "CMAKE_CACHE_MINOR_VERSION:INTERNAL=4", "CMAKE_CACHE_PATCH_VERSION:INTERNAL=5"]
        (build / "CMakeCache.txt").write_text("\n".join(cache))
        metadata = build / "CMakeFiles/4.4.5/CMakeCXXCompiler.cmake"; metadata.parent.mkdir(parents=True)
        metadata.write_text('set(CMAKE_CXX_COMPILER "' + str(compiler) + '")\n'
                            'set(CMAKE_CXX_COMPILER_ID "' + compiler_id + '")\n'
                            'set(CMAKE_CXX_COMPILER_VERSION "19.38.33135")\n')
        reply = build / ".cmake/api/v1/reply"; reply.mkdir(parents=True)
        names = [target_name, *extra_targets]
        refs = []
        for i, name in enumerate(names):
            filename = f"target-{i}.json"; refs.append({"jsonFile": filename})
            (reply / filename).write_text(json.dumps({"name": name, "compileGroups": [{"language": "CXX", "defines": [{"define": "GOOD=1"}], "includes": [{"path": "private/include"}], "compileCommandFragments": [{"fragment": "/O2 /DTEST=1"}]}]}))
        (reply / "model.json").write_text(json.dumps({"configurations": [{"name": "Release", "targets": refs}]}))
        (reply / "index-a.json").write_text(json.dumps({"objects": [{"kind": "codemodel", "version": {"major": 2}, "jsonFile": "model.json"}]}))
        return source, build, compiler

    def test_outer_build_capture_is_sanitized(self):
        with tempfile.TemporaryDirectory() as d:
            source, build, compiler = self.fixture(Path(d))
            text = exp_source()
            with patch.object(capture, "REVISION", "revision"), patch.object(capture, "VEC_SHA256", __import__('hashlib').sha256(text.encode()).hexdigest()), patch.object(capture, "run") as run:
                (source / "ggml/src/ggml-cpu").mkdir(parents=True)
                (source / "ggml/src/ggml-cpu/vec.h").write_text(text)
                run.side_effect = [SimpleNamespace(returncode=0, stdout=b"revision", stderr=b""),
                                   SimpleNamespace(returncode=0, stdout=b"KOTOHA_PROBE_OK\n", stderr=b""),
                                   SimpleNamespace(returncode=0, stdout=b"Compiler Version 19.38.33135", stderr=b"")]
                output = Path(d) / "result.json"
                data = capture.capture(source, build, output)
            self.assertEqual(data["selected_branch"], "none")
            probe_args = run.call_args_list[1].args[0]
            self.assertIn("/O2", probe_args)
            self.assertIn("/DTEST=1", probe_args)
            self.assertIn("/DGOOD=1", probe_args)
            self.assertIn("/Iprivate/include", probe_args)
            raw = output.read_text()
            for secret in (str(Path(d)), "/O2", "GOOD=1", "private/include"):
                self.assertNotIn(secret, raw)
            self.assertEqual(set(json.loads(raw)), {"schema", "source_revision", "source_sha256", "target", "configuration", "architecture", "compiler", "compiler_version", "macros", "selected_branch", "method"})

    def test_invalid_target_compiler_and_source_fail_closed(self):
        import hashlib
        for kwargs, message in (({"target_name": "wrong"}, "target missing or ambiguous"),
                                ({"extra_targets": ("ggml-cpu",)}, "target missing or ambiguous"),
                                ({"compiler_id": "Clang"}, "identity is not MSVC"),
                                ({"compiler_inside": False}, "outside the selected Visual Studio instance")):
            with self.subTest(kwargs=kwargs), tempfile.TemporaryDirectory() as d:
                source, build, compiler = self.fixture(Path(d), **kwargs)
                text = exp_source()
                (source / "ggml/src/ggml-cpu").mkdir(parents=True)
                (source / "ggml/src/ggml-cpu/vec.h").write_text(text)
                with patch.object(capture, "REVISION", "revision"), \
                     patch.object(capture, "VEC_SHA256", hashlib.sha256(text.encode()).hexdigest()), \
                     patch.object(capture, "run", return_value=SimpleNamespace(returncode=0, stdout=b"revision", stderr=b"")):
                    with self.assertRaisesRegex(ValueError, message):
                        capture.capture(source, build, Path(d) / "out.json")
        with tempfile.TemporaryDirectory() as d:
            source, build, compiler = self.fixture(Path(d))
            with patch.object(capture, "REVISION", "revision"), patch.object(capture, "run", return_value=SimpleNamespace(returncode=0, stdout=b"revision", stderr=b"")):
                with self.assertRaisesRegex(ValueError, "vec.h missing or changed"):
                    capture.capture(source, build, Path(d) / "out.json")

    def test_invoked_version_must_match_cmake_metadata(self):
        with tempfile.TemporaryDirectory() as d:
            source, build, compiler = self.fixture(Path(d))
            text = exp_source()
            (source / "ggml/src/ggml-cpu").mkdir(parents=True)
            (source / "ggml/src/ggml-cpu/vec.h").write_text(text)
            import hashlib
            with patch.object(capture, "REVISION", "revision"), patch.object(capture, "VEC_SHA256", hashlib.sha256(text.encode()).hexdigest()), patch.object(capture, "run") as run:
                run.side_effect = [SimpleNamespace(returncode=0, stdout=b"revision", stderr=b""), SimpleNamespace(returncode=0, stdout=b"KOTOHA_PROBE_OK\n", stderr=b""), SimpleNamespace(returncode=0, stdout=b"Compiler Version 19.39.1", stderr=b"")]
                with self.assertRaisesRegex(ValueError, "disagrees"):
                    capture.capture(source, build, Path(d) / "output.json")


    def test_missing_compiler_metadata_fails_closed(self):
        import hashlib
        with tempfile.TemporaryDirectory() as d:
            source, build, _ = self.fixture(Path(d))
            text = exp_source()
            (source / "ggml/src/ggml-cpu").mkdir(parents=True)
            (source / "ggml/src/ggml-cpu/vec.h").write_text(text)
            (build / "CMakeFiles/4.4.5/CMakeCXXCompiler.cmake").unlink()
            with patch.object(capture, "REVISION", "revision"), \
                 patch.object(capture, "VEC_SHA256", hashlib.sha256(text.encode()).hexdigest()), \
                 patch.object(capture, "run", return_value=SimpleNamespace(returncode=0, stdout=b"revision", stderr=b"")):
                with self.assertRaisesRegex(ValueError, "CMake CXX compiler metadata missing"):
                    capture.capture(source, build, Path(d) / "out.json")

    def test_ambiguous_file_api_and_version_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            source, build, compiler = self.fixture(Path(d), extra_targets=("ggml-cpu",))
            with self.assertRaises(ValueError): capture.file_api(build)
            with self.assertRaises(ValueError): capture.compiler_version("Compiler Version 1.2.3\nCompiler Version 2.3.4")

if __name__ == "__main__": unittest.main()
