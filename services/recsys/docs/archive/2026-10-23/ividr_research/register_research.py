"""Register new research records without changing old immutable checksums."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
catalog_path = ROOT/'docs/catalog.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
old_entries = catalog['files']


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


old_protected = [e for e in old_entries if e.get('immutable')]
for entry in old_protected:
    assert sha(ROOT/entry['path']) == entry['sha256'], entry['path']
digest = hashlib.sha256()
for folder in ('src','experiments'):
    for p in sorted((ROOT/folder).rglob('*.py')):
        digest.update(p.relative_to(ROOT).as_posix().encode())
        digest.update(p.read_bytes())
source_hash = digest.hexdigest()
snapshot = json.loads((ROOT/'docs/state_snapshot.json').read_text(encoding='utf-8'))
assert source_hash == snapshot['source_sha256']
manifest = json.loads((ROOT/'docs/papers/ividr_reference_sources_20261023.json').read_text(encoding='utf-8'))
for paper in manifest['papers']:
    assert sha(ROOT/paper['path']) == paper['sha256']
diagnostics = json.loads((ROOT/'results/ividr_research_diagnostics_20261023.json').read_text(encoding='utf-8'))
assert diagnostics['diagnostic_source_sha256'] == source_hash
assert diagnostics['checkpoint_sha256_before'] == diagnostics['checkpoint_sha256_after']
assert sha(ROOT/diagnostics['checkpoint_path']) == diagnostics['checkpoint_sha256_before']
assert diagnostics['diagnostics']['cached_mean_exact'] and diagnostics['diagnostics']['cached_std_exact']

verification = dict(checked_at_utc=datetime.now(timezone.utc).isoformat(),
    scope='research_documents_and_read_only_diagnostics', source_sha256=source_hash,
    runtime_source_unchanged=True, training_performed=False, quality_improvement_measured=False,
    external_models_executed_or_integrated=False,
    existing_protected_files_checked=len(old_protected), existing_protected_checksums_unchanged=True,
    new_pdf_title_page_sha_checks_passed=True, pdfs=manifest['papers'],
    checkpoint_sha256_unchanged=diagnostics['checkpoint_sha256_before'],
    cached_latents_exact=True,
    report='docs/benchmarks/ividr_optimization_research_20261023.md',
    diagnostics='results/ividr_research_diagnostics_20261023.json',
    limits=['Diagnostic measurements are not a quality ablation.',
            'Original IViDR v1 complete author-code parity remains unverified.',
            'Model test suite was not rerun for this research-only change.'])
with (ROOT/'results/ividr_research_verification_20261023.json').open('x',encoding='utf-8') as f:
    json.dump(verification,f,indent=2);f.write('\n')

registered = {e['path'] for e in old_entries}
new = [
    ('docs/benchmarks/ividr_optimization_research_20261023.md','source_reference'),
    ('docs/papers/ividr_reference_sources_20261023.json','source_reference'),
    ('results/ividr_research_diagnostics_20261023.json','diagnostic_result'),
    ('results/ividr_research_verification_20261023.json','diagnostic_result'),
]
new += [(p['path'],'source_reference') for p in manifest['papers']]
archive = ROOT/'docs/archive/2026-10-23/ividr_research'
new += [(p.relative_to(ROOT).as_posix(), 'archive_snapshot' if p.suffix=='.zip' else 'historical_evidence')
        for p in sorted(archive.iterdir()) if p.is_file()]
for path,role in new:
    assert path not in registered, path
    old_entries.append(dict(path=path,role=role,immutable=True,sha256=sha(ROOT/path)))
    registered.add(path)
catalog['reviewed_on']='2026-10-23'
catalog_path.write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
print(json.dumps(dict(source_sha256=source_hash,old_protected_checked=len(old_protected),
    new_files_registered=len(new),runtime_changed=False),indent=2))
