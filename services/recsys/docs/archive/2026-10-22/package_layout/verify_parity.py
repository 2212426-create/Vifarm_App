"""Prove relocation-only AST changes and reload existing four-model weights."""
import ast
import hashlib
import json
from pathlib import Path
import sys
import zipfile
import torch

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.utils.artifacts import evaluate_checkpoint, source_signature

torch.set_num_threads(2)
code = source_signature()
rows = json.loads((HERE / 'moves.json').read_text())['moves']
moves = {row['old']: row['new'] for row in rows}
replacements = {a.removesuffix('.py').replace('/', '.'): b.removesuffix('.py').replace('/', '.')
                for a, b in moves.items() if a.endswith('.py') and not a.endswith('__init__.py')}
replacements['src.causal.cdr'] = 'src.models.cdr'
checked = []
with zipfile.ZipFile(HERE / 'before_change.zip') as bundle:
    for old in bundle.namelist():
        if not old.endswith('.py') or not old.startswith(('src/', 'experiments/')):
            continue
        new = moves.get(old, old)
        expected = bundle.read(old).decode('utf-8')
        for a, b in sorted(replacements.items(), key=lambda pair: -len(pair[0])):
            expected = expected.replace(a, b)
        if new == 'src/models/mf/train_mf.py':
            expected = expected.replace('os.path.dirname(__file__), "..", ".."',
                                        'os.path.dirname(__file__), "..", "..", ".."')
        actual = (ROOT / new).read_text(encoding='utf-8')
        assert ast.dump(ast.parse(expected)) == ast.dump(ast.parse(actual)), old
        checked.append(dict(before=old, after=new))

report_path = 'results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.json'
report = json.loads((ROOT / report_path).read_text())
data = load_coat_processed()
parity = []
for name in ('MF', 'iDCF', 'IViDR-BCE', 'DR-BIAS + CDR'):
    # The benchmark display label can differ from its stored model key.
    if name not in report['coat']:
        assert name == 'IViDR-BCE'
        name = next(key for key in report['coat'] if key.startswith('IViDR'))
    old = report['coat'][name]
    checkpoint = Path(old['checkpoint_path'])
    before = hashlib.sha256(checkpoint.read_bytes()).hexdigest()
    result = evaluate_checkpoint(checkpoint, data, device='cpu')
    metrics = {key: value for key, value in old.items()
               if key.startswith(('NDCG@', 'Recall@', 'Precision@', 'HitRate@')) or key in ('AUC', 'AUC_global')}
    for key, value in metrics.items():
        assert result[key] == value, (name, key, result.get(key), value)
    assert hashlib.sha256(checkpoint.read_bytes()).hexdigest() == before
    parity.append(dict(model=name, metrics=metrics, metrics_exact=True,
        checkpoint_sha256=before, checkpoint_bytes_unchanged=True,
        training_code_sha256=old['metadata']['code_sha256']))
assert source_signature() == code
with (ROOT / 'results/package_layout_parity_20261022.json').open('x', encoding='utf-8') as stream:
    json.dump(dict(identity=dict(code_sha256=code), scope='Package relocation; existing checkpoint re-evaluation, not retraining',
        original_report=report_path, normalized_ast_equal=checked, checkpoint_reload=parity), stream, indent=2)
print('PASS: source AST parity and exact four-model checkpoint metrics')
