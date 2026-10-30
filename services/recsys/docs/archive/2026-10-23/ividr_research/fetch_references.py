"""Research only: pinned source inspection and verified reference PDFs; no training."""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

from pypdf import PdfReader

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent


def fetch(url):
    return subprocess.run(['curl.exe', '--fail', '--location', '--silent', '--show-error',
                           '--max-time', '90', url], check=True, capture_output=True).stdout


def repo(spec):
    name, paths = spec
    metadata = json.loads(fetch('https://api.github.com/repos/' + name))
    commit = json.loads(fetch('https://api.github.com/repos/' + name + '/commits/'
                              + metadata['default_branch']))['sha']
    tree = json.loads(fetch(f'https://api.github.com/repos/{name}/git/trees/{commit}?recursive=1'))
    available = {e['path'] for e in tree['tree'] if e['type'] == 'blob'}
    selected = paths or [p for p in sorted(available) if p.startswith('models/') and p.endswith('.py')]
    inspected = []
    for p in selected:
        if p not in available:
            continue
        url = f'https://raw.githubusercontent.com/{name}/{commit}/{p}'
        raw = fetch(url)
        text = raw.decode('utf-8', errors='replace')
        matches = [dict(line=i, text=line.strip()[:220]) for i, line in enumerate(text.splitlines(), 1)
                   if re.search(r'^\s*(?:class |def )|pinverse|linalg|binary_cross_entropy|BCELoss|MSELoss|anneal', line)]
        inspected.append(dict(path=p, url=url, bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(),
                              symbols_and_relevant_lines=matches))
    return dict(repository=name, url='https://github.com/' + name, commit=commit,
                default_branch=metadata['default_branch'],
                license_api=metadata.get('license'), files=inspected,
                code_saved_or_integrated=False, executed=False)


def paper(spec):
    name, url, title_marker = spec
    destination = ROOT/'docs/papers'/name
    if destination.exists():
        raise FileExistsError(destination)
    raw = fetch(url)
    if not raw.startswith(b'%PDF-'):
        raise ValueError('Not a PDF: ' + url)
    import io
    reader = PdfReader(io.BytesIO(raw))
    first = reader.pages[0].extract_text()
    if title_marker.lower() not in re.sub(r'\s+', ' ', first).lower():
        raise ValueError('Wrong PDF title: ' + url)
    with destination.open('xb') as f:
        f.write(raw)
    return dict(path=destination.relative_to(ROOT).as_posix(), url=url,
                bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), pages=len(reader.pages),
                title_check=title_marker, title_verified=True)


def main():
    sources = [
        ('BgmLover/iDCF', ['README.md', 'ivae_exposure.py', 'iDCF.py', 'models/vae.py', 'models/mf.py', 'utils.py']),
        ('ilkhem/iVAE', []),
        ('Ethan00Si/Instrumental-variables-for-recommendation', ['README.md', 'model.py', 'models.py', 'config.py']),
        ('liyuan9988/DeepFeatureIV', ['README.md', 'src/models/DFIV/model.py', 'src/utils/pytorch_linear_reg_utils.py']),
    ]
    papers = [
        ('iVAE_AISTATS2020.pdf', 'https://proceedings.mlr.press/v108/khemakhem20a/khemakhem20a.pdf',
         'Variational Autoencoders and Nonlinear ICA'),
        ('IV4Rec_WWW2022.pdf', 'https://arxiv.org/pdf/2202.04514v1',
         'A Model-Agnostic Causal Learning Framework'),
        ('IDCIV_RS_IJCAI2025.pdf', 'https://www.ijcai.org/proceedings/2025/0329.pdf',
         'Interaction-Data-guided Conditional Instrumental Variables'),
    ]
    with ThreadPoolExecutor(max_workers=4) as pool:
        repositories = list(pool.map(repo, sources))
        downloads = list(pool.map(paper, papers))
    result = dict(checked_at_utc=datetime.now(timezone.utc).isoformat(),
                  purpose='IViDR reference research, no changes to production model/data/loss/protocol',
                  repositories=repositories, papers=downloads,
                  official_ividr_v1_source_found=False)
    destination = ROOT/'docs/papers/ividr_reference_sources_20261023.json'
    with destination.open('x', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write('\n')
    print(json.dumps(dict(repositories=[dict(name=r['repository'], commit=r['commit'],
                        inspected=[f['path'] for f in r['files']]) for r in repositories],
                          papers=downloads), indent=2))


if __name__ == '__main__':
    main()
