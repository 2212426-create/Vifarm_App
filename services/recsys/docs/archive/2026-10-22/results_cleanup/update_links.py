"""Repoint only mutable guides/snapshot; preserve moved artifact bytes/checksums."""
from pathlib import Path
import json
import os
import re
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
plan = json.loads((HERE / 'plan.json').read_text())
mapping = {row['old']: row['new'] for row in plan['moves']}
catalog_path = ROOT / 'docs/catalog.json'
catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
changed = []
for entry in catalog['files']:
    if entry.get('immutable') or entry['path'] == 'docs/catalog.json':
        continue
    path = ROOT / entry['path']
    if path.suffix not in ('.md', '.json'):
        continue
    original = path.read_text(encoding='utf-8')
    text = original
    if path.suffix == '.md':
        def repoint(match):
            target = match.group(1).strip()
            if urlsplit(target).scheme or target.startswith('//'):
                return match.group(0)
            local, sep, fragment = target.partition('#')
            try:
                relative = (path.parent / unquote(local)).resolve().relative_to(ROOT).as_posix()
            except ValueError:
                return match.group(0)
            if relative not in mapping:
                return match.group(0)
            new = Path(os.path.relpath(ROOT / mapping[relative], path.parent)).as_posix()
            return '](' + new + (sep + fragment if sep else '') + ')'
        text = re.sub(r'\]\(([^\n)]+)\)', repoint, text)
    for old, new in mapping.items():
        text = text.replace(old, new).replace(old.replace('/', '\\'), new.replace('/', '\\'))
    if text != original:
        path.write_text(text, encoding='utf-8', newline='\n')
        changed.append(entry['path'])
for entry in catalog['files']:
    if entry['path'] in mapping:
        entry.update(archived_from=entry['path'], path=mapping[entry['path']],
                     relocation_record='docs/archive/2026-10-22/results_cleanup/plan.json')
catalog_path.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
with (HERE / 'link_updates.json').open('x', encoding='utf-8') as stream:
    json.dump(dict(updated_mutable_files=changed, immutable_contents_modified=False), stream, indent=2)

archive = ROOT / 'results/archive/2026-10-22'
lines = ['# Kết quả lưu trữ sau đợt dọn 22/10/2026', '',
    'Các file bên dưới là artifact cũ/smoke/diagnostic được chuyển nguyên byte.',
    'Không dùng việc nằm trong archive để suy ra file sai hoặc điểm paper đã được tái lập.',
    'Một số Markdown lịch sử có nhận định đã được đính chính trong tài liệu hiện hành.', '',
    '[Catalog kết quả](../../CATALOG.md) · [Manifest đường dẫn và checksum](../../../docs/archive/2026-10-22/results_cleanup/plan.json).', '',
    'File được script hoặc bằng chứng bất biến tham chiếu vẫn giữ đường dẫn cũ ở results/.', '',
    '| File | Nhóm |', '| :-- | :-- |']
for row in plan['moves']:
    relative = Path(row['new']).relative_to('results/archive/2026-10-22').as_posix()
    lines.append(f'| [{Path(relative).name}]({relative}) | {row["category"]} |')
with (archive / 'README.md').open('x', encoding='utf-8') as stream:
    stream.write('\n'.join(lines) + '\n')
print('Updated mutable references and archived catalog paths; immutable bytes retained')
