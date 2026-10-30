"""Read-only inventory and conservative reference analysis before cleanup."""
from pathlib import Path
import collections
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RESULTS = ROOT / 'results'
catalog = json.loads((ROOT / 'docs/catalog.json').read_text(encoding='utf-8'))
entries = {row['path']: row for row in catalog['files']}
files = [p for p in RESULTS.rglob('*') if p.is_file()]
names = collections.defaultdict(set)
for path in files:
    names[path.name].add(path.relative_to(ROOT).as_posix())
pattern = re.compile('|'.join(re.escape(name) for name in sorted(names, key=len, reverse=True)))
refs = collections.defaultdict(set)
for directory in ('src', 'experiments', 'tests', 'notebooks', 'docs', 'results'):
    for path in (ROOT / directory).rglob('*'):
        if not path.is_file() or '__pycache__' in path.parts or path.suffix not in ('.py', '.ps1', '.md', '.json', '.ipynb'):
            continue
        rel = path.relative_to(ROOT).as_posix()
        if rel == 'docs/catalog.json' or rel.startswith('docs/archive/2026-10-22/results_cleanup/'):
            continue
        # Mutable guides may have their links repointed. Preserve targets of all
        # executable files and immutable Markdown/JSON evidence at old locations.
        protect = (path.suffix in ('.py', '.ps1', '.ipynb')
                   or (entries.get(rel, {}).get('immutable') and path.suffix in ('.md', '.json')))
        if not protect:
            continue
        text = path.read_text(encoding='utf-8-sig', errors='replace')
        for name in set(pattern.findall(text)):
            for target in names[name]:
                if target != rel:
                    refs[target].add(rel)
rows = []
for path in files:
    relative = path.relative_to(ROOT).as_posix()
    protected = entries.get(relative, {})
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    if protected.get('immutable') and protected['sha256'] != sha:
        raise ValueError('Protected file has changed: ' + relative)
    rows.append(dict(path=relative, bytes=path.stat().st_size, sha256=sha,
                     references=sorted(refs[relative]), immutable=protected.get('immutable', False)))
inventory = dict(root_files=sum(path.parent == RESULTS for path in files), all_files=len(files),
                 bytes=sum(row['bytes'] for row in rows), files=rows)
with (HERE / 'inventory_v2.json').open('x', encoding='utf-8') as stream:
    json.dump(inventory, stream, indent=2)
root_rows = [row for row in rows if Path(row['path']).parent.as_posix() == 'results']
print(json.dumps(dict(root_files=len(root_rows),
    referenced=sum(bool(row['references']) for row in root_rows),
    unreferenced=sum(not row['references'] for row in root_rows),
    unreferenced_bytes=sum(row['bytes'] for row in root_rows if not row['references']),
    referencer_counts=dict(collections.Counter(Path(ref).suffix for row in root_rows for ref in row['references']))), indent=2))
