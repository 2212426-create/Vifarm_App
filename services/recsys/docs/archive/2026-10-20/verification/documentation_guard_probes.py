import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile

root = Path.cwd().resolve()
spec = importlib.util.spec_from_file_location('recsys_doc_guard', root / 'docs/check_docs.py')
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)
expected = ['protected-artifact-change', 'source-drift', 'unclassified-document', 'broken-link', 'broken-heading', 'original-zip-change']
with tempfile.TemporaryDirectory(prefix='recsys_docs_guard_') as work:
    sandbox = Path(work).resolve()
    assert sandbox.parent == Path(tempfile.gettempdir()).resolve() and sandbox.name.startswith('recsys_docs_guard_')
    for folder in ('src', 'experiments', 'tests', 'notebooks', 'docs', 'results'):
        shutil.copytree(root / folder, sandbox / folder,
                        ignore=shutil.ignore_patterns('__pycache__', '*.pyc', '*.log') if folder in ('src', 'experiments') else None)
    for name in ('README.md', 'AGENTS.md'):
        shutil.copyfile(root / name, sandbox / name)
    checker.ROOT, checker.DOCS = sandbox, sandbox / 'docs'
    with contextlib.redirect_stdout(io.StringIO()):
        assert checker.main() == 0
    targets = [
        (sandbox / 'results/coat_seeds_c25da453e8909e5b.json', b'\n', 'Protected file changed'),
        (sandbox / 'src/models/matrix_factorization.py', b'\n# Documentation guard negative probe\n', 'Source differs'),
        (sandbox / 'docs/unclassified_probe.md', b'# Probe\n', 'Unclassified file'),
        (sandbox / 'docs/README.md', b'\n[Broken](missing_probe.md)\n', 'Broken link'),
        (sandbox / 'docs/README.md', b'\n[Heading](CURRENT_STATE.md#heading_absent_probe)\n', 'Missing heading'),
        (sandbox / 'docs/archive/2026-10-20/documentation_before_cleanup.zip', b'\n', 'ZIP checksum differs'),
    ]
    for name, (path, added, message) in zip(expected, targets):
        exists = path.exists()
        original = path.read_bytes() if exists else None
        path.write_bytes((original or b'') + added)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = checker.main()
        assert code == 1 and message in output.getvalue(), (name, output.getvalue())
        if exists:
            path.write_bytes(original)
        else:
            path.unlink()
        print('PASS negative probe:', name)
    with contextlib.redirect_stdout(io.StringIO()):
        assert checker.main() == 0
print('Original workspace left unchanged by negative probes.')


