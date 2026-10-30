"""One-shot package relocation, with a byte-preserving before snapshot."""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
MOVES = {
    'src/models/matrix_factorization.py': 'src/models/mf/matrix_factorization.py',
    'src/baselines/train_mf.py': 'src/models/mf/train_mf.py',
}
for path in sorted((ROOT / 'src/causal/cdr').glob('*')):
    if path.is_file():
        MOVES[path.relative_to(ROOT).as_posix()] = 'src/models/cdr/' + path.name
for path in sorted((ROOT / 'src/causal/idcf').glob('*.py')):
    model = 'ividr' if 'ividr' in path.name else 'idcf'
    MOVES[path.relative_to(ROOT).as_posix()] = f'src/models/{model}/' + path.name


def sha(data):
    return hashlib.sha256(data).hexdigest()


def module(path):
    return path.removesuffix('.py').replace('/', '.')


def main():
    # Fail before mutations if any destination already exists or escapes ROOT.
    for old, new in MOVES.items():
        source, dest = (ROOT / old).resolve(), (ROOT / new).resolve()
        assert source.is_relative_to(ROOT) and dest.is_relative_to(ROOT)
        assert source.is_file() and not dest.exists(), (old, new)
    before = [ROOT / p for p in ('README.md', 'docs/CURRENT_STATE.md',
        'docs/README.md', 'docs/state_snapshot.json', 'docs/catalog.json', 'results/CATALOG.md')]
    for directory in ('src', 'experiments', 'tests'):
        before.extend(p for p in (ROOT / directory).rglob('*')
                      if p.is_file() and '__pycache__' not in p.parts)
    with zipfile.ZipFile(HERE / 'before_change.zip', 'x', zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(before):
            bundle.write(path, path.relative_to(ROOT).as_posix())
    replacements = {module(a): module(b) for a, b in MOVES.items()
                    if a.endswith('.py') and not a.endswith('__init__.py')}
    replacements['src.causal.cdr'] = 'src.models.cdr'
    # Do NOT rewrite the whole idcf prefix: IViDR now has its own package.
    rows = []
    wrappers = set()
    for old, new in MOVES.items():
        source, dest = ROOT / old, ROOT / new
        original = source.read_bytes()
        dest.parent.mkdir(parents=True, exist_ok=True)
        source.rename(dest)
        if old.endswith('.py'):
            wrappers.add(old)
            if old.endswith('__init__.py'):
                package = new.removesuffix('/__init__.py').replace('/', '.')
                content = f'"""Compatibility exports; implementation lives in {package}."""\nfrom {package} import *\n'
            else:
                target = module(new)
                content = ('"""Compatibility alias; edit the implementation in ' + target + '."""\n'
                    'import importlib\nimport sys\n\n')
                if old in ('src/baselines/train_mf.py', 'src/causal/cdr/train_dr_bias_cdr.py'):
                    depth = 2 if old.startswith('src/baselines') else 3
                    content += (f'from pathlib import Path\n'
                                f'_root = str(Path(__file__).resolve().parents[{depth}])\n'
                                'if _root not in sys.path:\n    sys.path.insert(0, _root)\n\n'
                                'if __name__ == "__main__":\n'
                                f'    import runpy\n    runpy.run_module("{target}", run_name="__main__")\n'
                                'else:\n'
                                f'    sys.modules[__name__] = importlib.import_module("{target}")\n')
                else:
                    content += f'sys.modules[__name__] = importlib.import_module("{target}")\n'
            source.write_text(content, encoding='utf-8', newline='\n')
        rows.append(dict(old=old, new=new, before_sha256=sha(original)))
    for directory in ('src', 'experiments'):
        for path in (ROOT / directory).rglob('*.py'):
            if path.relative_to(ROOT).as_posix() in wrappers:
                continue
            text = path.read_text(encoding='utf-8')
            for old, new in sorted(replacements.items(), key=lambda pair: -len(pair[0])):
                text = text.replace(old, new)
            if path == ROOT / 'src/models/mf/train_mf.py':
                text = text.replace('os.path.dirname(__file__), "..", ".."',
                                    'os.path.dirname(__file__), "..", "..", ".."')
            # Retain exact original bytes when no import/path change is needed.
            if text != path.read_text(encoding='utf-8'):
                path.write_text(text, encoding='utf-8', newline='\n')
    for row in rows:
        row['after_sha256'] = sha((ROOT / row['new']).read_bytes())
    with (HERE / 'moves.json').open('x', encoding='utf-8') as stream:
        json.dump(dict(moves=rows, compatibility='Python module aliases; legacy non-Python license moved alongside implementation',
                       snapshot_sha256=sha((HERE / 'before_change.zip').read_bytes())), stream, indent=2)
    print(f'Relocated {len(rows)} files; original bytes retained in before_change.zip')


if __name__ == '__main__':
    main()
