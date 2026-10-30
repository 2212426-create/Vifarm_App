"""Read-only checks for documentation provenance, links and immutable artifacts.

Run from any directory: python services/recsys/docs/check_docs.py
Only the standard library is required. This does not run model tests or validate
the scientific claims of a paper; it guards the recorded documentation boundary.
"""
import hashlib
import json
from pathlib import Path
import re
import sys
from urllib.parse import unquote, urlsplit
import zipfile

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
ROLES = {
    "current_state", "current_guide", "current_index", "current_tool", "guidance",
    "state_snapshot", "documentation_audit", "planning_draft", "historical_entrypoint",
    "historical_result", "validation_result", "diagnostic_result", "source_reference",
    "paper_transcript", "archive_snapshot", "archive_index", "archived_draft",
    "historical_evidence", "archived_presentation", "verification_log",
    "current_notebook", "notebook_builder",
    "benchmark_result",
}


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_signature():
    result = hashlib.sha256()
    for folder in ("src", "experiments"):
        for path in sorted((ROOT / folder).rglob("*.py")):
            result.update(path.relative_to(ROOT).as_posix().encode())
            result.update(path.read_bytes())
    return result.hexdigest()


def managed_files():
    files = {ROOT / "README.md", ROOT / "AGENTS.md"}
    files.update((ROOT / "notebooks/build_notebook.py", ROOT / "notebooks/TopTop_RecSys_Colab_API.ipynb"))
    files.update(p for p in DOCS.rglob("*") if p.is_file()
                 and "__pycache__" not in p.parts and p.name != "catalog.json")
    files.update(p for p in (ROOT / "results").rglob("*")
                 if p.is_file() and p.suffix in (".md", ".json"))
    return {p.relative_to(ROOT).as_posix() for p in files}


def markdown_content(path):
    text = path.read_text(encoding="utf-8-sig")
    text = re.sub(r"```.*?```|~~~.*?~~~", "", text, flags=re.S)
    # LaTeX contains bracket/parenthesis sequences which are not Markdown links.
    return re.sub(r"\$\$.*?\$\$|\$[^$\n]*\$", "", text, flags=re.S)


def anchors(path):
    result, counts = set(), {}
    text = path.read_text(encoding="utf-8-sig")
    text = re.sub(r"```.*?```|~~~.*?~~~", "", text, flags=re.S)
    for heading in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, flags=re.M):
        heading = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", heading)
        heading = re.sub(r"<[^>]+>", "", heading).replace("`", "").replace("*", "")
        slug = re.sub(r"[^\w\- ]", "", heading.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        result.add(slug + (f"-{count}" if count else ""))
        counts[slug] = count + 1
    result.update(re.findall(r'(?:id|name)=["\']([^"\']+)["\']', text))
    return result


def main():
    errors = []
    catalog = json.loads((DOCS / "catalog.json").read_text(encoding="utf-8"))
    entries = catalog["files"]
    paths = [entry["path"] for entry in entries]
    if len(paths) != len(set(paths)):
        errors.append("Duplicate paths in docs/catalog.json")
    known = set(paths)
    for path in sorted(managed_files() - known):
        errors.append(f"Unclassified file: {path}; register it without changing old checksums")
    immutable_count = 0
    for entry in entries:
        relative = entry["path"]
        path = (ROOT / relative).resolve()
        if not path.is_relative_to(ROOT):
            errors.append(f"Catalog path escapes service: {relative}")
            continue
        if entry["role"] not in ROLES:
            errors.append(f"Unknown role: {relative}: {entry['role']}")
        if not path.is_file():
            errors.append(f"Missing catalogued file: {relative}")
            continue
        if entry.get("immutable"):
            immutable_count += 1
            if sha256(path) != entry.get("sha256"):
                errors.append(f"Protected file changed: {relative}; restore original or create a new version")

    snapshot = json.loads((DOCS / "state_snapshot.json").read_text(encoding="utf-8"))
    if source_signature() != snapshot["source_sha256"]:
        errors.append("Source differs from CURRENT_STATE snapshot; review and record a new verification milestone")
    artifact = json.loads((ROOT / snapshot["validation_artifact"]).read_text(encoding="utf-8"))
    if artifact["identity"]["code_sha256"] != snapshot["source_sha256"]:
        errors.append("Validation artifact belongs to a different source milestone")
    actual = [{"seed": run["seed"], "epoch": run["best_epoch"], "val_ndcg": run["best_val_ndcg"]}
              for run in artifact["runs"]]
    if actual != snapshot["independent_cdr_validation"]:
        errors.append("State snapshot numbers differ from the recorded CDR validation artifact")
    if artifact["evaluation"] != "validation_only_no_held_out_test":
        errors.append("The state snapshot expects a validation-only artifact")

    manifest_path = DOCS / "archive/2026-10-20/backup_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    bundle_path = manifest_path.parent / "documentation_before_cleanup.zip"
    if sha256(bundle_path) != manifest["zip_sha256"]:
        errors.append("Original documentation ZIP checksum differs")
    with zipfile.ZipFile(bundle_path) as bundle:
        if set(bundle.namelist()) != set(manifest["members"]):
            errors.append("Original documentation ZIP member list differs")
        for name, expected in manifest["members"].items():
            if hashlib.sha256(bundle.read(name)).hexdigest() != expected:
                errors.append(f"Original ZIP member changed: {name}")

    notebook_manifest_path = manifest_path.parent / "notebook_documentation_manifest.json"
    notebook_manifest = json.loads(notebook_manifest_path.read_text(encoding="utf-8"))
    notebook_bundle = ROOT / notebook_manifest["original_zip"]
    if sha256(notebook_bundle) != notebook_manifest["original_zip_sha256"]:
        errors.append("Original notebook documentation ZIP checksum differs")
    with zipfile.ZipFile(notebook_bundle) as bundle:
        for name, expected in notebook_manifest["members_before"].items():
            if hashlib.sha256(bundle.read(name)).hexdigest() != expected:
                errors.append(f"Original notebook ZIP member changed: {name}")
    # Preserve the claim about this documentation-only edit. A later code-cell edit
    # needs a new verification milestone rather than reusing this evidence.
    notebook = json.loads((ROOT / "notebooks/TopTop_RecSys_Colab_API.ipynb").read_text(encoding="utf-8"))
    code_cells = [cell for cell in notebook["cells"] if cell["cell_type"] == "code"]
    code_digest = hashlib.sha256(json.dumps(code_cells, sort_keys=True, ensure_ascii=False).encode()).hexdigest()
    if code_digest != notebook_manifest["code_cells_sha256"]:
        errors.append("Notebook code cells differ from the documentation-only verification milestone")

    link_count = 0
    anchor_cache = {}
    for entry in entries:
        path = ROOT / entry["path"]
        if path.suffix != ".md" or not path.is_file():
            continue
        for raw in re.findall(r"\]\(([^\n)]+)\)", markdown_content(path)):
            target = raw.strip().removeprefix("<").removesuffix(">")
            if urlsplit(target).scheme or target.startswith("//"):
                continue
            local, _, fragment = target.partition("#")
            destination = (path.parent / unquote(local)).resolve() if local else path.resolve()
            link_count += 1
            if not destination.exists():
                errors.append(f"Broken link in {entry['path']}: {raw}")
            elif fragment and destination.is_file() and destination.suffix == ".md":
                if destination not in anchor_cache:
                    anchor_cache[destination] = anchors(destination)
                if unquote(fragment) not in anchor_cache[destination]:
                    errors.append(f"Missing heading in {entry['path']}: {raw}")

    if errors:
        for error in errors:
            print("ERROR:", error)
        return 1
    print(f"PASS: {len(entries)} classified files; {immutable_count} protected checksums; "
          f"{link_count} local links; original ZIP and source/validation milestone match.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
