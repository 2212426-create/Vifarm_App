"""Record this verified milestone; register only new evidence checksums."""
import hashlib
import json
from pathlib import Path
import re
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from src.utils.artifacts import source_signature

code = source_signature()
validation = json.loads((ROOT / 'results/package_layout_validation_20261022.json').read_text())
parity = json.loads((ROOT / 'results/package_layout_parity_20261022.json').read_text())
assert validation['identity']['code_sha256'] == parity['identity']['code_sha256'] == code
tests = (HERE / 'tests.log').read_text(encoding='utf-8')
assert 'Ran 134 tests' in tests and 'OK (skipped=1)' in tests
smoke_log = (HERE / 'smoke.log').read_text(encoding='utf-8')
smoke = []
for dataset in ('coat', 'yahoo', 'kuairand'):
    matches = list(re.finditer(rf'benchmark_{dataset}_all_quick_[^\s/\\]+_v4\.json', smoke_log))
    assert matches, dataset
    name = matches[-1].group()
    path = ROOT / 'results' / name
    content = json.loads(path.read_text(encoding='utf-8'))
    models = [key for key in content[dataset] if key in ('MF', 'iDCF', 'DR-BIAS + CDR') or key.startswith('IViDR')]
    assert len(models) == 4, models
    smoke.append(dict(dataset=dataset, report=path.relative_to(ROOT).as_posix(),
                      purpose='smoke_not_quality', models=models))

verification = dict(identity=dict(code_sha256=code),
    scope='Package relocation and compatibility; MF-CRIB/EGMN selected, pending implementation',
    test_suite=dict(total=134, passed=133, skipped=1, skip_reason='CUDA unavailable',
                    log='docs/archive/2026-10-22/package_layout/tests.log'),
    parity_artifact='results/package_layout_parity_20261022.json',
    validation_artifact='results/package_layout_validation_20261022.json', smoke=smoke,
    full_training_rerun=False, checkpoint_re_evaluation_only=True,
    new_models=dict(mf_crib='selected_pending_integration', egmn='selected_pending_integration'),
    existing_artifacts_relabelled=False)
with (ROOT / 'results/package_layout_verification_20261022.json').open('x', encoding='utf-8') as stream:
    json.dump(verification, stream, indent=2)

state_path = ROOT / 'docs/state_snapshot.json'
state = json.loads(state_path.read_text(encoding='utf-8'))
old_keys = ('source_sha256', 'scope', 'test_suite', 'validation_artifact', 'independent_cdr_validation')
state['pre_package_layout_milestone'] = {key: state[key] for key in old_keys}
state.update(source_sha256=code,
    scope='Per-model src/models packages; compatibility aliases; no algorithm/protocol changes; new model slots pending integration',
    test_suite=verification['test_suite'],
    validation_artifact=verification['validation_artifact'],
    independent_cdr_validation=[dict(seed=run['seed'], epoch=run['best_epoch'], val_ndcg=run['best_val_ndcg'])
                               for run in validation['runs']],
    package_layout=dict(guide='docs/architecture/directory_layout.md',
                        verification='results/package_layout_verification_20261022.json',
                        selected_next_models=['MF-CRIB', 'EGMN'], integrated_next_models=[]))
state_path.write_text(json.dumps(state, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

catalog_path = ROOT / 'docs/catalog.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
known = {entry['path'] for entry in catalog['files']}
sys.path.insert(0, str(ROOT / 'docs'))
from check_docs import managed_files
extra = {'src/models/mf_crib/source.json', 'src/models/egmn/source.json'}
for relative in sorted((managed_files() | extra) - known):
    path = ROOT / relative
    immutable = True
    if relative == 'docs/architecture/directory_layout.md':
        role, immutable = 'current_guide', False
    elif relative in extra:
        role, immutable = 'source_reference', False
    elif relative.startswith('docs/archive/'):
        role = 'verification_log' if path.suffix == '.log' else 'archive_snapshot'
    elif relative.endswith('package_layout_validation_20261022.json'):
        role = 'validation_result'
    elif 'package_layout_' in relative:
        role = 'diagnostic_result'
    else:
        role = 'benchmark_result'
    entry = dict(path=relative, role=role, immutable=immutable)
    if immutable:
        entry['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    catalog['files'].append(entry)
catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print('Recorded verification, source milestone and new catalog entries for', code)
