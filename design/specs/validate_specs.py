#!/usr/bin/env python3
"""Validate kotoha's design contracts with synthetic fixtures."""
from __future__ import annotations
import copy
import hashlib
import json
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata
from collections import defaultdict, deque
from pathlib import Path
from typing import Any, Callable

try:
    from jsonschema import Draft202012Validator, ValidationError
except ImportError as exc:
    raise SystemExit("Install the inspection dependency: python -m pip install jsonschema") from exc

ROOT = Path(__file__).resolve().parents[1]
RESULTS: list[dict[str, str]] = []


def load(path: str) -> Any:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def require(condition: bool, detail: str) -> None:
    if not condition:
        raise ValueError(detail)


def check(name: str, action: Callable[[], Any], rejected: bool = False) -> None:
    try:
        action()
    except (ValueError, ValidationError, sqlite3.IntegrityError) as exc:
        if rejected:
            RESULTS.append({"name": name, "status": "pass", "case": "incompatible"})
            return
        raise RuntimeError(f"{name}: {exc}") from exc
    if rejected:
        raise RuntimeError(f"{name}: incompatible input was accepted")
    RESULTS.append({"name": name, "status": "pass", "case": "compatible"})


SCHEMAS = {name: load(f"specs/{name}.schema.json")
           for name in ("model_manifest", "mode_recipe", "engine_event")}


def structural(name: str, data: Any) -> None:
    Draft202012Validator(SCHEMAS[name]).validate(data)


def safe_path(value: str) -> str:
    require(bool(value) and not value.startswith(("/", "\\")), "relative path required")
    require(not re.match(r"^[A-Za-z]:", value), "drive path")
    require(not any(ord(c) < 32 or c in '\\<>:"|?*' for c in value), "path characters")
    parts = value.split("/")
    reserved = {"con", "prn", "aux", "nul", *(f"com{i}" for i in range(1, 10)), *(f"lpt{i}" for i in range(1, 10))}
    for part in parts:
        require(part not in ("", ".", "..") and not part.endswith((".", " ")), "path component")
        require(part.split(".")[0].casefold() not in reserved, "reserved path component")
    return unicodedata.normalize("NFC", value).casefold()


def validate_model(data: dict[str, Any]) -> None:
    structural("model_manifest", data)
    files = data["files"]
    keys = [safe_path(x["path"]) for x in files]
    require(len(keys) == len(set(keys)), "duplicate asset path")
    by_path = {x["path"]: x for x in files}
    require(sum(x["size_bytes"] for x in files) == data["resources"]["storage_bytes"], "storage total")
    coverage: set[str] = set()
    terms_ids: set[str] = set()
    for term in data["terms"]:
        require(term["id"] not in terms_ids, "duplicate terms")
        terms_ids.add(term["id"])
        asset = by_path.get(term["text_file"])
        require(asset is not None and asset["role"] == "terms", "terms file reference")
        require(asset["sha256"] == term["text_sha256"], "terms digest")
        require(set(term["covered_files"]) <= set(by_path), "terms coverage reference")
        coverage.update(term["covered_files"])
    require(coverage == set(by_path), "asset terms coverage")
    seen_caps: set[str] = set()
    required = set(data["executor"]["required_capabilities"])
    for task in data["tasks"]:
        cap = task["capability"]
        require(cap not in seen_caps, "duplicate task capability")
        require(cap in required, "task capability missing from executor")
        seen_caps.add(cap)
        langs = task["languages"]
        for side in ("source", "target"):
            tags = [x.casefold() for x in langs[side]]
            require(len(tags) == len(set(tags)), "duplicate language tag")
        pairs = set()
        for route in langs["routes"]:
            source, target = route["source"].casefold(), route["target"].casefold()
            require(source in {x.casefold() for x in langs["source"]}, "route source")
            require(target in {x.casefold() for x in langs["target"]}, "route target")
            require((source, target) not in pairs, "duplicate language route")
            pairs.add((source, target))
            if route["evidence"] == "evaluation":
                require(bool(route.get("evidence_ref")), "evaluation reference")
        if cap.startswith("translation."):
            require(bool(pairs), "translation routes required")


def validate_recipe(data: dict[str, Any], registry: dict[str, Any]) -> None:
    structural("mode_recipe", data)
    nodes = {n["id"]: n for n in data["nodes"]}
    require(len(nodes) == len(data["nodes"]), "duplicate node")
    required_permissions: set[str] = set()
    for node in nodes.values():
        entry = registry.get(node["operation"])
        require(entry is not None, "operation registration")
        for field in ("role", "inputs", "outputs"):
            require(node[field] == entry[field], f"registered {field}")
        require(set(node["required_capabilities"]) == set(entry["required_capabilities"]), "required capability contract")
        Draft202012Validator(entry["parameters_schema"]).validate(node["parameters"])
        required_permissions.update(entry["permissions"])
    require(set(data["permissions"]) == required_permissions, "permission scope")
    incoming: dict[tuple[str, str], int] = defaultdict(int)
    out: dict[str, list[str]] = defaultdict(list)
    reverse: dict[str, list[str]] = defaultdict(list)
    indegree = {k: 0 for k in nodes}
    for edge in data["edges"]:
        a, b = edge["from_node"], edge["to_node"]
        require(a in nodes and b in nodes, "edge endpoint")
        left = nodes[a]["outputs"].get(edge["from_port"])
        right = nodes[b]["inputs"].get(edge["to_port"])
        require(left is not None and right is not None and left == right, "port types")
        incoming[(b, edge["to_port"])] += 1
        require(incoming[(b, edge["to_port"])] == 1, "input cardinality")
        out[a].append(b)
        reverse[b].append(a)
        indegree[b] += 1
    for key, node in nodes.items():
        for port in node["inputs"]:
            require(incoming[(key, port)] == 1, "required input")
    queue = deque(k for k, d in indegree.items() if d == 0)
    processed = []
    while queue:
        key = queue.popleft()
        processed.append(key)
        for nxt in out[key]:
            indegree[nxt] -= 1
            if indegree[nxt] == 0:
                queue.append(nxt)
    require(len(processed) == len(nodes), "graph cycle")
    sources = {key for key, n in nodes.items() if n["role"] == "source"}
    sinks = {key for key, n in nodes.items() if n["role"] == "sink"}
    require(bool(sources) and bool(sinks), "source and sink")
    def reach(start: set[str], edges: dict[str, list[str]]) -> set[str]:
        found = set(start)
        pending = list(start)
        while pending:
            for nxt in edges[pending.pop()]:
                if nxt not in found:
                    found.add(nxt)
                    pending.append(nxt)
        return found
    require(reach(sources, out) == set(nodes), "reachable from source")
    require(reach(sinks, reverse) == set(nodes), "can reach output")


def validate_events(events: list[dict[str, Any]], expected_snapshots: dict[str, str] | None = None) -> None:
    states: dict[tuple[str, str], dict[str, Any]] = {}
    seen: dict[tuple[str, str, int], str] = {}
    for event in events:
        structural("engine_event", event)
        run = (event["job_id"], event["run_id"])
        key = (*run, event["sequence"])
        content = json.dumps(event, sort_keys=True, ensure_ascii=False)
        if key in seen:
            require(seen[key] == content, "event collision")
            continue
        state = states.setdefault(run, {"last": -1, "terminal": False, "committed": set()})
        require(not state["terminal"], "event after terminal")
        require(event["sequence"] > state["last"], "event order")
        payload = event["payload"]
        if event["kind"].startswith("segment."):
            segment = payload["segment_id"]
            if expected_snapshots is not None:
                require(expected_snapshots.get(segment) == payload["input_snapshot"], "current input snapshot")
            point = (segment, payload["input_snapshot"])
            if event["kind"] == "segment.partial":
                require(point not in state["committed"], "partial after commit")
            else:
                state["committed"].add(point)
        if event["kind"] == "job.progress":
            require(payload["processed"] <= payload["total"], "progress bound")
        if event["kind"] == "job.terminal":
            state["terminal"] = True
        state["last"] = event["sequence"]
        seen[key] = content
    require(bool(states) and all(s["terminal"] for s in states.values()), "terminal per run")


def license_terms(expression: str, allowed: set[str]) -> set[str] | None:
    tokens = re.findall(r"\(|\)|[A-Za-z0-9.+-]+", expression)
    require("".join(tokens) == re.sub(r"\s+", "", expression), "license expression characters")
    pos = 0
    def atom() -> Any:
        nonlocal pos
        require(pos < len(tokens), "license expression operand")
        token = tokens[pos]
        pos += 1
        if token == "(":
            value = disjunction()
            require(pos < len(tokens) and tokens[pos] == ")", "license expression group")
            pos += 1
            return value
        require(token not in {"AND", "OR", "WITH", ")"}, "license identifier")
        if pos < len(tokens) and tokens[pos] == "WITH":
            pos += 1
            require(pos < len(tokens) and tokens[pos] not in {"AND", "OR", "WITH", "(", ")"}, "exception identifier")
            token += " WITH " + tokens[pos]
            pos += 1
        return ("license", token)
    def conjunction() -> Any:
        nonlocal pos
        value = atom()
        while pos < len(tokens) and tokens[pos] == "AND":
            pos += 1
            value = ("and", value, atom())
        return value
    def disjunction() -> Any:
        nonlocal pos
        value = conjunction()
        while pos < len(tokens) and tokens[pos] == "OR":
            pos += 1
            value = ("or", value, conjunction())
        return value
    tree = disjunction()
    require(pos == len(tokens), "license expression trailing token")
    def evaluate(node: Any) -> set[str] | None:
        if node[0] == "license":
            return {node[1]} if node[1] in allowed else None
        left, right = evaluate(node[1]), evaluate(node[2])
        if node[0] == "and":
            return left | right if left is not None and right is not None else None
        return left if left is not None else right
    return evaluate(tree)


def validate_license(expression: str) -> None:
    policy = load("specs/dependency_policy.json")
    require(license_terms(expression, set(policy["acceptable_code_licenses"])) is not None, "license policy")


def mutate(data: Any, fn: Callable[[Any], None]) -> Any:
    result = copy.deepcopy(data)
    fn(result)
    return result


def database_tests() -> None:
    db = sqlite3.connect(":memory:")
    db.executescript((ROOT / "specs/storage_schema.sql").read_text())
    check("SQL structure and references", lambda: require(not db.execute("PRAGMA foreign_key_check").fetchall(), "foreign key check"))
    db.execute("INSERT INTO projects VALUES (?,?,?,?,?,?,?)", ("p", "fixture", "saved", None, "{}", "now", "now"))
    db.execute("INSERT INTO projects VALUES (?,?,?,?,?,?,?)", ("other", "fixture", "saved", None, "{}", "now", "now"))
    check("SQL retention conditions", lambda: db.execute("INSERT INTO projects VALUES ('exp','x','expires',NULL,'{}','now','now')"), True)
    db.execute("INSERT INTO source_assets VALUES (?,?,?,?,?,?,?,?)", ("asset", "p", "a"*64, "text/plain", 1, None, None, "{}"))
    db.execute("INSERT INTO participants VALUES (?,?,?,?,?,?,?)", ("person", "p", "fixture", '["de","ar"]', "{}", None, None))
    check("SQL profile consent", lambda: db.execute("INSERT INTO participants VALUES ('bad','p','x','[]','{}','blob',NULL)"), True)
    check("SQL asset membership", lambda: db.execute("INSERT INTO segments VALUES ('bad','other','asset',0,'{}',NULL,'ready')"), True)
    check("SQL participant membership", lambda: db.execute("INSERT INTO segments VALUES ('bad','other',NULL,0,'{}','person','ready')"), True)
    db.execute("INSERT INTO segments VALUES ('seg','p','asset',0,'{}','person','ready')")
    db.execute("INSERT INTO segments VALUES ('seg-other','other',NULL,0,'{}',NULL,'ready')")
    snap = "b"*64
    db.execute("INSERT INTO segment_snapshots VALUES (?,?,?,?,?,?,?,?,?,?)", (snap, "seg", None, "c"*64, "fixture", "und", "[]", "input", "{}", "now"))
    check("SQL current snapshot", lambda: db.execute("INSERT INTO segment_heads VALUES (?,?)", ("seg", snap)))
    check("SQL snapshot membership", lambda: db.execute("INSERT INTO segment_heads VALUES (?,?)", ("seg-other", snap)), True)
    check("SQL parent membership", lambda: db.execute("INSERT INTO segment_snapshots VALUES (?,?,?,?,?,?,?,?,?,?)", ("d"*64, "seg-other", snap, "e"*64, "x", "und", "[]", "input", "{}", "now")), True)
    check("SQL translation input", lambda: db.execute("INSERT INTO translations VALUES ('t','absent','und','x',NULL,'confirmed',NULL,'{}','now')"), True)
    db.execute("INSERT INTO jobs VALUES ('job','p',NULL,'queued','x','{}',NULL,'now')")
    db.execute("INSERT INTO job_runs VALUES ('job','run-a','succeeded','{}',NULL)")
    db.execute("INSERT INTO job_runs VALUES ('job','run-b','running','{}',NULL)")
    check("SQL concurrent run history", lambda: db.execute("INSERT INTO committed_events VALUES ('job','run-a',0,'{}')"))
    check("SQL event run reference", lambda: db.execute("INSERT INTO committed_events VALUES ('job','absent',0,'{}')"), True)
    check("SQL event uniqueness", lambda: db.execute("INSERT INTO committed_events VALUES ('job','run-a',0,'{}')"), True)
    db.commit()
    check("SQL project deletion", lambda: db.execute("DELETE FROM projects WHERE project_id='p'"))
    check("SQL cascading integrity", lambda: require(not db.execute("PRAGMA foreign_key_check").fetchall() and db.execute("SELECT count(*) FROM committed_events").fetchone()[0] == 0, "cascade"))
    db.close()


def header_test(language: str, compiler: str, standard: str) -> None:
    tool = shutil.which(compiler)
    require(tool is not None, f"compiler required: {compiler}")
    suffix = ".c" if language == "C" else ".cpp"
    with tempfile.TemporaryDirectory() as tmp:
        source = Path(tmp) / ("contract"+suffix)
        source.write_text('#include "kotoha_api.h"\nint main(void) { kotoha_runtime_config c = {0}; c.struct_size = sizeof(c); return c.struct_size == 0; }\n')
        result = subprocess.run([tool, f"-std={standard}", "-Wall", "-Wextra", "-Werror", "-Wno-missing-field-initializers", "-fsyntax-only", "-I", str(ROOT/"specs"), str(source)], capture_output=True, text=True, timeout=30)
        require(result.returncode == 0, result.stderr)


def main() -> int:
    for name, schema in SCHEMAS.items():
        check(f"Schema: {name}", lambda schema=schema: Draft202012Validator.check_schema(schema))
    model = load("examples/model_manifest.json")
    recipe = load("examples/mode_recipe.json")
    registry = load("examples/operation_registry.json")
    events = load("examples/engine_events.json")
    check("Model fixture", lambda: validate_model(model))
    for title, fn in [
        ("Model extra executable field", lambda d: d.update(execute="command")),
        ("Model duplicate file", lambda d: d["files"].append(copy.deepcopy(d["files"][0]))),
        ("Model storage accounting", lambda d: d["resources"].update(storage_bytes=1)),
        ("Model traversal", lambda d: d["files"][0].update(path="../weights.bin")),
        ("Model absolute path", lambda d: d["files"][0].update(path="/weights.bin")),
        ("Model terms digest", lambda d: d["terms"][0].update(text_sha256="0"*64)),
        ("Model terms file", lambda d: d["terms"][0].update(text_file="missing.txt")),
        ("Model terms coverage", lambda d: d["terms"][0].update(covered_files=["terms.txt"])),
        ("Model source route", lambda d: d["tasks"][0]["languages"]["routes"][0].update(source="it")),
        ("Model target route", lambda d: d["tasks"][0]["languages"]["routes"][0].update(target="it")),
        ("Model route uniqueness", lambda d: d["tasks"][0]["languages"]["routes"].append(copy.deepcopy(d["tasks"][0]["languages"]["routes"][0]))),
        ("Model evaluation evidence", lambda d: d["tasks"][0]["languages"]["routes"][0].update(evidence="evaluation")),
        ("Model required capability", lambda d: d["executor"].update(required_capabilities=["other.capability"])),
        ("Model consent contract", lambda d: d["terms"][0].update(consent="implicit")),
    ]:
        check(title, lambda fn=fn: validate_model(mutate(model, fn)), True)
    check("Unicode asset path", lambda: safe_path("資料/語彙.dat"))
    check("Private language syntax", lambda: Draft202012Validator(SCHEMAS["model_manifest"]["properties"]["tasks"]["items"]["properties"]["languages"]["properties"]["source"]["items"]).validate("x-fixture"))
    check("Mode fixture", lambda: validate_recipe(recipe, registry))
    for title, fn in [
        ("Mode duplicate node", lambda d: d["nodes"].append(copy.deepcopy(d["nodes"][0]))),
        ("Mode endpoint", lambda d: d["edges"][0].update(to_node="absent")),
        ("Mode port", lambda d: d["edges"][0].update(to_port="absent")),
        ("Mode type contract", lambda d: d["nodes"][1]["inputs"].update(text="audio")),
        ("Mode input connection", lambda d: d["edges"].pop()),
        ("Mode operation registration", lambda d: d["nodes"][1].update(operation="remote.execute")),
        ("Mode parameter contract", lambda d: d["nodes"][1]["parameters"].update(script="command")),
        ("Mode permission scope", lambda d: d["permissions"].append("camera")),
        ("Mode local execution", lambda d: d.update(processing_location="remote")),
        ("Mode declared capability", lambda d: d["nodes"][1].update(required_capabilities=[])),
    ]:
        check(title, lambda fn=fn: validate_recipe(mutate(recipe, fn), registry), True)
    cyc_registry = copy.deepcopy(registry)
    cyc_registry["processing.pass"] = {"role":"processor","inputs":{"value":"text"},"outputs":{"value":"text"},"required_capabilities":[],"permissions":[],"parameters_schema":{"type":"object","maxProperties":0}}
    cyc = copy.deepcopy(recipe)
    cyc["nodes"] += [{"id": key,"operation":"processing.pass","role":"processor","inputs":{"value":"text"},"outputs":{"value":"text"},"required_capabilities":[],"parameters":{}} for key in ("a","b")]
    cyc["edges"] += [{"from_node":a,"from_port":"value","to_node":b,"to_port":"value"} for a,b in (("a","b"),("b","a"))]
    check("Mode cyclic subgraph", lambda: validate_recipe(cyc,cyc_registry), True)
    check("Events fixture", lambda: validate_events(events))
    check("Events idempotent replay", lambda: validate_events([events[0], events[0], events[1]]))
    check("Events current input", lambda: validate_events(events,{"segment-example":events[0]["payload"]["input_snapshot"]}))
    check("Events stale input", lambda: validate_events(events,{"segment-example":"0"*64}), True)
    check("Events missing terminal", lambda: validate_events(events[:1]), True)
    check("Events after terminal", lambda: validate_events([events[1], events[0]]), True)
    collision=copy.deepcopy(events[0]); collision["payload"]["source_text"]="changed"
    check("Events sequence collision", lambda: validate_events([events[0],collision,events[1]]), True)
    partial=copy.deepcopy(events[0]); partial.update(sequence=1,kind="segment.partial")
    term=copy.deepcopy(events[1]);term["sequence"]=2
    check("Events partial after commit", lambda: validate_events([events[0],partial,term]), True)
    bad_progress={"job_id":"job-example","run_id":"run-example","sequence":0,"kind":"job.progress","payload":{"processed":2,"total":1,"unit":"segment"}}
    check("Events progress bound", lambda: validate_events([bad_progress,events[1]]), True)
    bad_terminal=copy.deepcopy(events[1]);bad_terminal["payload"]["outcome"]="failed"
    check("Events failure reason", lambda: validate_events([events[0],bad_terminal]), True)
    for expr in ["MIT","MIT AND BSD-3-Clause","MIT OR GPL-3.0-only","(Apache-2.0 OR MIT) AND ISC","Apache-2.0 WITH LLVM-exception"]:
        check("License: "+expr, lambda expr=expr: validate_license(expr))
    for expr in ["GPL-3.0-only","AGPL-3.0-only","LGPL-2.1-only","MIT AND GPL-3.0-only","MIT AND (GPL-3.0-only OR LGPL-2.1-only)","MIT OR", "MIT; ISC"]:
        check("License condition: "+expr, lambda expr=expr: validate_license(expr), True)
    database_tests()
    check("C header", lambda: header_test("C","cc","c11"))
    check("C++ header", lambda: header_test("C++","c++","c++20"))
    doc=(ROOT/"kotoha_design.md").read_text()
    acceptance=(ROOT/"appendices/acceptance_matrix.md").read_text()
    ids=lambda text: set(re.findall(r"\bF\d{2}\b",text))
    expected={f"F{i:02}" for i in range(1,39)}
    check("Feature traceability",lambda: require(ids(doc)==ids(acceptance)==expected,"feature mapping"))
    check("Contract identifiers",lambda: require(all(re.fullmatch(r"urn:kotoha:[a-z-]+",s["$id"]) for s in SCHEMAS.values()),"contract names"))
    report={"checks":len(RESULTS),"passed":len(RESULTS),"results":RESULTS,"scope":"design_contracts_and_synthetic_fixtures"}
    (ROOT/"appendices/validation_results.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n")
    print(json.dumps({"checks":len(RESULTS),"passed":len(RESULTS)},ensure_ascii=False))
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"Inspection failed: {exc}",file=sys.stderr)
        raise SystemExit(1)
