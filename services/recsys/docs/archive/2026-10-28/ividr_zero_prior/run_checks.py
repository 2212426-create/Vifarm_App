"""Run verification after adding the optional IViDR zero prior mean, without overwriting earlier evidence."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
commands = {
    'tests': ['experiments/run.py', 'test', '--verbosity', '1'],
    'smoke': ['experiments/run.py', 'smoke', '--dataset', 'all', '--model', 'all', '--threads', '2'],
    'validation': [str(HERE / 'validate.py')],
}
name = sys.argv[1]
log = HERE / (name + '.log')
print('Running', name, '->', log, flush=True)
with log.open('x', encoding='utf-8') as stream:
    result = subprocess.run([sys.executable, *commands[name]], cwd=ROOT,
        env=dict(os.environ, PYTHONIOENCODING='utf-8'),
        stdout=stream, stderr=subprocess.STDOUT)
print('Finished', name, 'exit', result.returncode, flush=True)
print('\n'.join(log.read_text(encoding='utf-8').splitlines()[-12:]))
raise SystemExit(result.returncode)
