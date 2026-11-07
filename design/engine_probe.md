# Native-engine feasibility probe

This is **developer tooling only**, not a translation feature or distribution
approval. The Flutter app still has no inference; memory-only drafts and platform
support are unchanged. Windows x64 is the first candidate because it already has
a supported app host, CMake builds, editable results and explicit copy/export.
This choice does not establish engine support. Linux has no application host.

## Reproducible source build

`tools/engine_probe/fixtures.json` pins llama.cpp b12183, commit
`31424b7cf14604ca65a9195123da1413f31c4472`, and its 39,104,147-byte source archive
with SHA-256 `541aeea240dbceb48de352122b30a26ac32ec5fd936c62442037bf04310a0270`.
CMake reads this manifest and verifies the archive digest before extraction.

The probe builds upstream `llama-simple` with static CPU dependencies separately
from Flutter. It disables common/tools, other examples, server/app/UI, MTMD,
connect/OpenSSL/subprocess, system ggml, dynamic backends, host ISA detection,
SSE4.2/BMI2/AVX-family/FMA/F16C, accelerators, OpenMP, BLAS and optional CPU
providers. Inspect generated targets and compile/link settings, not just cache
booleans, before accepting the dependency closure or baseline-CPU claim.

On a Windows x64 developer host with CMake, MSVC, Python and source-download access:

```powershell
cmake -S tools/engine_probe -B build/engine-probe -A x64
cmake --build build/engine-probe --config Release --target llama-simple --parallel 2
python tools/engine_probe/smoke.py --executable build/engine-probe/bin/Release/llama-simple.exe --timeout-seconds 30 --output-bytes 8192
```

The script invokes the actual executable with missing and truncated GGUF files.
Both must exit exactly 1 with the model-load rejection diagnostic; crashes,
timeouts and other failures do not pass. Temporary files are removed on exit.
Timeout and printed-output budgets are required arguments, configured by CI as
30 seconds and 8192 bytes per invocation. The workflow sets two build workers
and a 15-minute job deadline. These are experiment policy, not product limits. Output is spooled to a temporary file; neither its disk use nor engine
memory use is limited by the printed-tail budget.

The `Native engine probe` workflow retains `windows-x64-engine-probe`: configure/build/smoke logs,
CMake cache/file-API target information, MSBuild projects, extracted source hashes,
upstream CMake/license/notice files, executable hash and dumpbin headers/imports.
These are audit inputs, not a license verdict. A failed build yields only partial
evidence. Artifacts expire under repository/Actions retention policy; runner
scratch is disposable. No model or executable is uploaded or bundled with the app.

## Real inference and adoption gates

The probe runs automatically on reviewed `mizu` publications when its workflow
or source inputs change; manual dispatch is also declared. Observe its exact
publication SHA before requesting a missing run. Unrelated editor/mobile changes
do not rebuild this independent experiment. It tests rejection only and prints **REAL INFERENCE NOT RUN**. After
independent acquisition and license review, an explicit real-model experiment can
add these arguments (only public test prompts: output persists in logs):

```powershell
--model C:/models/audited-model.gguf --tokens 16 --prompt "Translate to French: Hello."
```

A missing file fails; the script never downloads or discovers models. Exit 0 is
an upstream invocation result, not translation quality or performance evidence.
Inspect and evaluate the generated sample before making such claims.

The official `Qwen/Qwen2.5-0.5B-Instruct-GGUF` Q4_K_M is a **search-only candidate**,
not acquired or audited: revision `9217f5db79a29953eb74d5343926648285ec7e67`,
491,400,032 bytes, SHA-256
`74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db`.
The source archive is retained by trusted fixture materialization, but the local
sandbox currently lacks its cache mount and cannot compile or run it.

The full upstream root MIT license was read (SHA-256
`94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d`), not the
full selected-file closure. Adoption still needs exact-source Windows build and
loader evidence; selected-file terms, Unicode provenance, runtime linkage and
notice delivery; licensed-model positive inference; model/language validation;
cancellation/resource failures; no-network/no-text-persistence verification; and
Flutter integration. The watchdog is not cancellation evidence, CPU switches are
not privacy proof, and draft persistence has separate security/recovery gates.
