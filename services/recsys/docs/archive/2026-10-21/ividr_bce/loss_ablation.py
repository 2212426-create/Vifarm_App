"""Planned Coat loss comparison: frozen identical IViDR latents, equal search budget.

No architecture/default changes. Both losses select on validation, never test.
The matched-config MSE trial is also reported against the BCE winner.
"""
import argparse
import contextlib
import hashlib
import json
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parents[4]
sys.path.insert(0,str(ROOT))
import numpy as np
import torch
from src.causal.idcf.train_idcf import train_idcf
from src.causal.idcf.train_ividr import PAPER_FEEDBACK_GRID
from src.data_pipeline.coat_dataset import load_coat_processed
from src.utils.artifacts import evaluate_checkpoint, load_checkpoint, source_signature


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--input',type=Path,required=True)
    args=parser.parse_args()
    torch.set_num_threads(2)
    report=json.loads(args.input.read_text(encoding='utf-8'))
    bce=report['coat']['IViDR']
    saved=load_checkpoint(bce['checkpoint_path'],'cpu')
    config=saved['metadata']['config']; model_cfg=saved['metadata']['model_kwargs']
    assert config['loss']=='bce' and len(bce['validation_search']['trials'])==10
    mean=saved['model_state_dict']['c_mean'];std=saved['model_state_dict']['c_std']
    latents=hashlib.sha256(mean.numpy().tobytes()+std.numpy().tobytes()).hexdigest()
    data=load_coat_processed()
    directory=ROOT/'checkpoints/ividr_loss_ablation_20261021'
    directory.mkdir(parents=True,exist_ok=True)
    trials=[];winner=None;matched=None
    with (ROOT/'docs/archive/2026-10-21/ividr_bce/loss_ablation_training.log').open('x',encoding='utf-8') as log:
        with contextlib.redirect_stdout(log):
            for number,(lr,wd) in enumerate(PAPER_FEEDBACK_GRID):
                result=train_idcf(data,mean,std,'coat',seed=config['seed'],lr=lr,weight_decay=wd,
                    embedding_dim=model_cfg['embedding_dim'],batch_size=config['batch_size'],
                    epochs=config['epochs'],patience=config['patience'],evaluate_test=False,
                    checkpoint_dir=directory,checkpoint_tag=f'mse_trial{number}',device='cpu',
                    init_scheme=model_cfg['init_scheme'],loss_name='mse',
                    extra_config={'variant':'ividr_loss_ablation_mse','display_name':'IViDR-MSE-ablation',
                        'implementation_status':'controlled_loss_ablation_only',
                        'confounder_training':config['confounder_training'],
                        'fixed_latents_sha256':latents})
                trials.append({'lr':lr,'weight_decay':wd,'validation_NDCG@5':result['best_val_ndcg'],
                    'best_epoch':result['best_epoch'],'checkpoint':result['checkpoint_path']})
                if winner is None or result['best_val_ndcg']>winner['best_val_ndcg']:winner=result
                if lr==config['lr'] and wd==config['weight_decay']:matched=result
    assert matched is not None
    best=evaluate_checkpoint(winner['checkpoint_path'],data,'cpu')
    same=best if matched['checkpoint_path']==winner['checkpoint_path'] else evaluate_checkpoint(matched['checkpoint_path'],data,'cpu')
    def metrics(r):return {k:r[k] for k in ['NDCG@5','Recall@5','Recall@5_bounded','best_val_ndcg','best_epoch','checkpoint_path']}
    value={'kind':'planned_one_seed_loss_ablation_not_multi_seed_claim','dataset':'coat','seed':config['seed'],
        'identity':{'code_sha256':source_signature()},'frozen_latents_sha256':latents,
        'fixed':{'stage1':'identical trained learned-IV/dual-iVAE checkpoint','init':model_cfg['init_scheme'],
            'embedding_dim':model_cfg['embedding_dim'],'batch_size':config['batch_size'],
            'epochs':config['epochs'],'patience':config['patience'],'split':saved['metadata']['data']},
        'protocol':'Both losses select by validation only; report planned matched-config and equal-grid comparisons',
        'bce_validation_grid':bce['validation_search'], 'mse_validation_grid':trials,
        'test':{'BCE_validation_selected':metrics(bce),'MSE_same_config_as_BCE':metrics(same),
                'MSE_validation_selected':metrics(best)},
        'matched_config':{'lr':config['lr'],'weight_decay':config['weight_decay']},
        'bce_report':str(args.input),'default_loss_changed_by_this_comparison':False}
    path=ROOT/'results/ividr_mse_bce_ablation_20261021.json'
    with path.open('x',encoding='utf-8') as f:json.dump(value,f,indent=2)
    print(json.dumps(value['test'],indent=2))
    print(path)

if __name__=='__main__':main()
