"""Recompute additional source metrics from saved checkpoints; never trains."""
import argparse
from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
from uuid import uuid4
import torch

from src.models.cdr.source_protocol import evaluate_source_checkpoint
from src.utils.artifacts import source_signature
from src.utils.helpers import RESULTS_DIR
from experiments.workflows.run_all_benchmarks import generate_console_grid_report,generate_markdown_report


def refresh_report(input_path,output_dir=None,threads=2):
    if threads<1:raise ValueError('threads must be positive')
    torch.set_num_threads(threads)
    path=Path(input_path).resolve()
    payload=json.loads(path.read_text(encoding='utf-8'))
    if payload.get('artifact_version')!=4:raise ValueError('Expected benchmark artifact v4')
    additions={}
    for dataset in ('coat','yahoo','kuairand'):
        row=payload.get(dataset,{}).get('DR-BIAS + CDR',{})
        if row.get('evaluation_scope')!='cdr_source_protocol':continue
        checkpoint=Path(row['checkpoint_path'])
        if not checkpoint.is_file():raise FileNotFoundError(f'Missing source checkpoint: {checkpoint}')
        print(f'[REPORT][{dataset.upper()}] Tính bổ sung metric từ checkpoint; không huấn luyện lại',flush=True)
        actual=evaluate_source_checkpoint(checkpoint)
        metrics={key:value for key,value in actual.items() if key not in ('metadata','evaluation_scope')}
        # Preserve original training metadata and verify all original measurements.
        for key,before in row.get('metrics',{}).items():
            if key in metrics and before is not None:
                if not math.isclose(before,metrics[key],rel_tol=0,abs_tol=1e-12):
                    raise ValueError(f'Original metric changed: {dataset}/{key}: {before} -> {metrics[key]}')
        additions[dataset]=[key for key in metrics if key not in row.get('metrics',{})]
        row.update(metrics)
        row['metrics']=metrics
        row['metric_evaluation_code_sha256']=source_signature()
        row['supplementary_metric_policy']='same source-eligible users/ranking; empty users Recall=1, Precision/HitRate=0'
    payload['report_refresh']=dict(input_path=str(path),input_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        evaluation_code_sha256=source_signature(),retrained=False,added_metrics=additions,
        note='Training metadata preserved; original scores checked, supplemental metrics recomputed from checkpoints')
    folder=Path(output_dir or RESULTS_DIR);folder.mkdir(parents=True,exist_ok=True)
    run_id=datetime.now().strftime('%Y%m%d_%H%M%S')+'_'+uuid4().hex[:8]
    output=folder/f'benchmark_report_{run_id}.json'
    markdown=generate_markdown_report(payload)
    with output.open('x',encoding='utf-8') as f:json.dump(payload,f,ensure_ascii=False,indent=2)
    with output.with_suffix('.md').open('x',encoding='utf-8') as f:f.write(markdown)
    print(generate_console_grid_report(payload))
    print(f'[REPORT] JSON: {output}',flush=True)
    print(f'[REPORT] Markdown: {output.with_suffix(".md")}',flush=True)
    return output,payload


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--input',type=Path,required=True)
    p.add_argument('--output-dir',type=Path,default=None)
    p.add_argument('--threads',type=int,default=2)
    a=p.parse_args(argv)
    refresh_report(a.input,a.output_dir,a.threads)


if __name__=='__main__':main()
