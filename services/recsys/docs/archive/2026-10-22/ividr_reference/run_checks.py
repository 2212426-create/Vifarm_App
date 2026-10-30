"""Run actual verification jobs, retaining UTF-8 logs and process exit status."""
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[4]
commands={
    'tests':['experiments/run.py','test','--verbosity','1'],
    'full_coat':['experiments/run.py','benchmark','--dataset','coat','--model','all','--device','cpu','--threads','2'],
    'smoke':['experiments/run.py','smoke','--dataset','all','--model','all','--threads','2'],
    'validation':[str(Path(__file__).with_name('validate.py'))],
}
name=sys.argv[1]
log=Path(__file__).with_name(name+'.log')
print('Running',name,'->',log,flush=True)
with log.open('x',encoding='utf-8') as stream:
    result=subprocess.run([sys.executable,*commands[name]],cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
print('Finished',name,'exit',result.returncode,flush=True)
print('\n'.join(log.read_text(encoding='utf-8').splitlines()[-12:]))
raise SystemExit(result.returncode)
