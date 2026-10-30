"""Plan top-level archive moves; preserve all immutable/executable dependencies."""
from pathlib import Path
import hashlib
import importlib.util
import json
import re
from urllib.parse import urlsplit, unquote
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RESULTS = ROOT / 'results'
ARCHIVE = RESULTS / 'archive/2026-10-22'
inventory = json.loads((HERE / 'inventory_v2.json').read_text())
catalog = json.loads((ROOT / 'docs/catalog.json').read_text(encoding='utf-8'))
spec = importlib.util.spec_from_file_location('docs_guard', ROOT / 'docs/check_docs.py')
guard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guard)
source_before = guard.source_signature()
keep = {'results/README.md': 'Current entrypoint', 'results/CATALOG.md': 'Current catalog',
    'results/mf_crib_20261022_070114_6b5eeb3a.json': 'Latest completed user MF-CRIB run, 20 epochs',
    'results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.md': 'Readable companion of verified reference-v2 Coat benchmark',
    'results/source_cleanup_completion_20261021.json': 'Explicit source-removal completion record'}
for path in RESULTS.glob('*.md'):
    # Immutable Markdown cannot have its relative links rewritten after relocation.
    for target in re.findall(r'\]\(([^\n)]+)\)', guard.markdown_content(path)):
        target = target.strip().strip('<>')
        if not urlsplit(target).scheme and not target.startswith('//') and target.split('#')[0]:
            keep[path.relative_to(ROOT).as_posix()] = 'Markdown has relative links; preserve original context'


def category(path):
    if path.suffix == '.log':
        return 'logs'
    if '_reload_' in path.name:
        return 'reload'
    if '_quick_' in path.name:
        return 'smoke'
    payload_path = path if path.suffix == '.json' else path.with_suffix('.json')
    if payload_path.is_file():
        try:
            payload = json.loads(payload_path.read_text(encoding='utf-8'))
        except (ValueError, UnicodeError):
            return 'unclassified'
        if payload.get('identity', {}).get('config', {}).get('smoke') is True:
            return 'smoke'
        if 'validation' in path.name:
            return 'validation'
    if path.name.startswith('cdr_source_'):
        return 'cdr_source_history'
    if path.name.startswith(('benchmark_', 'coat_seeds_', 'tuning_')):
        return 'benchmark_history'
    return 'diagnostics'


if ARCHIVE.exists():
    raise FileExistsError(ARCHIVE)
rows, retained = [], []
for row in inventory['files']:
    path = ROOT / row['path']
    if path.parent != RESULTS:
        retained.append(dict(path=row['path'], reason='Existing nested evidence bundle'))
        continue
    reason = keep.get(row['path'])
    if not reason and row['references']:
        reason = 'Referenced by immutable evidence or executable code'
    group = category(path)
    if group == 'unclassified':
        reason = 'Unparseable JSON: retain for manual inspection'
    if reason:
        retained.append(dict(path=row['path'], reason=reason))
    else:
        dest = ARCHIVE / group / path.name
        assert dest.resolve().is_relative_to(RESULTS.resolve())
        assert not dest.exists()
        rows.append(dict(old=row['path'], new=dest.relative_to(ROOT).as_posix(),
                         sha256=row['sha256'], bytes=row['bytes'], category=group))

with zipfile.ZipFile(HERE / 'mutable_documents_before.zip', 'x', zipfile.ZIP_DEFLATED) as bundle:
    paths = {ROOT / 'docs/catalog.json', ROOT / 'docs/state_snapshot.json'}
    paths.update(ROOT / row['path'] for row in catalog['files']
                 if not row.get('immutable') and row['path'].endswith(('.md', '.json')))
    for path in sorted(paths):
        bundle.write(path, path.relative_to(ROOT).as_posix())
plan = dict(scope='Archive only unreferenced top-level result artifacts; no permanent deletion',
            source_before=source_before, moves=rows, retained=retained,
            root_files_before=inventory['root_files'], root_files_after_moves=inventory['root_files'] - len(rows),
            archived_bytes=sum(row['bytes'] for row in rows))
with (HERE / 'plan.json').open('x', encoding='utf-8') as stream:
    json.dump(plan, stream, indent=2)
print(json.dumps({key: value for key, value in plan.items() if key not in ('moves', 'retained')}, indent=2))
