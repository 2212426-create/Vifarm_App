"""Download Yahoo! R3 and survey files from the user's pinned CDR repository."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

from src.data_pipeline.yahoo_dataset import YAHOO_PREFIX, CDR_COMMIT, CDR_REPOSITORY, load_yahoo_raw
from src.utils.helpers import RAW_DATA_DIR


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir",type=Path,default=Path(RAW_DATA_DIR)/"yahoo")
    args=parser.parse_args(argv)
    args.data_dir.mkdir(parents=True,exist_ok=True)
    base=f"https://raw.githubusercontent.com/{CDR_REPOSITORY}/{CDR_COMMIT}/data/yahoo/"
    names=[f"{YAHOO_PREFIX}{name}.txt" for name in ("train","test","survey-questions","survey-answers","readme")]+["WebscopeReadMe.txt"]
    files=[]
    for name in names:
        payload=urllib.request.urlopen(base+name,timeout=60).read()
        path=args.data_dir/name
        if path.exists():
            if path.read_bytes()!=payload: raise ValueError(f"Existing file differs from pinned source: {path}")
        else:
            with path.open("xb") as stream: stream.write(payload)
        files.append(dict(path=name,url=base+name,size=len(payload),sha256=hashlib.sha256(payload).hexdigest()))
        print(path)
    manifest=dict(repository=CDR_REPOSITORY,commit=CDR_COMMIT,files=files,raw_data_gitignored=True)
    target=args.data_dir/"source_manifest.json"
    if target.exists():
        if json.loads(target.read_text("utf-8"))!=manifest: raise ValueError("Existing source manifest differs")
    else:
        with target.open("x",encoding="utf-8") as stream: json.dump(manifest,stream,indent=2)
    raw=load_yahoo_raw(args.data_dir)
    print(f"Yahoo ready: {raw['n_users']} users, {raw['n_items']} items; {raw['user_feature_info']}")


if __name__=="__main__": main()
