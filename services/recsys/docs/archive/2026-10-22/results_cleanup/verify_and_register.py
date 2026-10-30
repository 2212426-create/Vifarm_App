"""Verify every original result byte, retained dependency and unchanged source."""
from pathlib import Path
import collections
import hashlib
import importlib.util
import json
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
plan = json.loads((HERE / 'plan.json').read_text())
inventory = json.loads((HERE / 'inventory_v2.json').read_text())
mapping = {row['old']: row['new'] for row in plan['moves']}
mutable_results = {'results/README.md', 'results/CATALOG.md'}
count = 0
for row in inventory['files']:
    old = row['path']
    destination = ROOT / mapping.get(old, old)
    assert destination.is_file(), destination
    if old not in mutable_results:
        assert hashlib.sha256(destination.read_bytes()).hexdigest() == row['sha256'], destination
        count += 1
    if old in mapping:
        assert not (ROOT / old).exists(), old
    if row['references']:
        assert (ROOT / old).is_file(), ('Dependency path moved', old)
with zipfile.ZipFile(HERE / 'mutable_documents_before.zip') as bundle:
    for row in inventory['files']:
        if row['path'] in mutable_results:
            assert hashlib.sha256(bundle.read(row['path'])).hexdigest() == row['sha256']
spec = importlib.util.spec_from_file_location('docs_guard', ROOT / 'docs/check_docs.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
assert guard.source_signature() == plan['source_before']
root_count = sum(path.is_file() for path in (ROOT / 'results').iterdir())
assert root_count == plan['root_files_after_moves']

verification = dict(scope='Archive old unreferenced result artifacts; no permanent deletion or training',
    source_before=plan['source_before'], source_after=guard.source_signature(),
    archived_files=len(plan['moves']), archived_bytes=plan['archived_bytes'],
    root_files_before=inventory['root_files'], root_files_after=root_count,
    original_artifacts_byte_verified=count, mutable_result_indexes_backed_up=True,
    retained_dependency_paths_verified=True, permanent_deletions=0,
    categories=dict(collections.Counter(row['category'] for row in plan['moves'])),
    latest_user_mf_crib_report='results/mf_crib_20261022_070114_6b5eeb3a.json',
    checkpoints_and_data_touched=False, model_tests_rerun=False,
    reason_no_training='Source hash and all original result bytes are unchanged; validation milestone remains applicable')
with (HERE / 'verification.json').open('x', encoding='utf-8') as stream:
    json.dump(verification, stream, indent=2)

state_path = ROOT / 'docs/state_snapshot.json'
state = json.loads(state_path.read_text(encoding='utf-8'))
state['results_cleanup'] = dict(reviewed_on='2026-10-22',
    verification='docs/archive/2026-10-22/results_cleanup/verification.json',
    archived_files=len(plan['moves']), root_files_before=inventory['root_files'], root_files_after=root_count,
    source_unchanged=True, training_rerun=False,
    latest_user_mf_crib_report=verification['latest_user_mf_crib_report'])
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

catalog_path = ROOT / 'docs/catalog.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
known = {row['path'] for row in catalog['files']}
all_moved = set(mapping.values())
for relative in sorted((guard.managed_files() | all_moved) - known):
    path = ROOT / relative
    immutable = True
    if relative.startswith('docs/archive/2026-10-22/results_cleanup/'):
        role = 'documentation_audit' if path.name == 'verification.json' else 'archive_snapshot'
    elif relative == 'results/archive/2026-10-22/README.md':
        role = 'archive_index'
    elif path.suffix == '.log':
        role = 'verification_log'
    else:
        role = 'benchmark_result'
    entry = dict(path=relative, role=role, immutable=immutable,
                 sha256=hashlib.sha256(path.read_bytes()).hexdigest())
    for old, new in mapping.items():
        if relative == new:
            entry['archived_from'] = old
            entry['relocation_record'] = 'docs/archive/2026-10-22/results_cleanup/plan.json'
    catalog['files'].append(entry)
catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print(json.dumps(verification, indent=2))
