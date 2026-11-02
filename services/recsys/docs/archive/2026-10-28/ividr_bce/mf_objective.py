"""Controlled MF objective test on Coat: one loop, one change per variant.

Same data, MF(64) author_uniform init, Adam with coupled weight decay on all parameters,
batch 512, up to 300 epochs, patience 20, validation-NDCG@5 selection, test once.
Variants:
  mse            squared error on raw score (control; should match MF-MSE ~.61 validation)
  bce            logistic loss, no global bias (current IViDR feedback with C disabled)
  bce_global     logistic loss + trainable global bias
  bce_init01     logistic loss, embeddings N(0, 0.1^2) instead of U(-0.01, 0.01)
  bce_neg0.5     logistic loss, negatives (rating < 4) weighted 0.5
  bce_neg0.2     logistic loss, negatives weighted 0.2
Usage (from services/recsys): python docs/archive/2026-10-28/ividr_bce/mf_objective.py VARIANT LR SEED
"""
import copy
import json
import sys
from pathlib import Path

import numpy as np
import torch
import torch.nn.functional as F

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
from src.data_pipeline.coat_dataset import load_coat_processed
from src.evaluation.evaluator import evaluate_unbiased_model
from src.models.mf.matrix_factorization import MatrixFactorization
from src.utils.helpers import set_seed

variant, lr, seed = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
torch.set_num_threads(2)
data = load_coat_processed()
set_seed(seed)
model = MatrixFactorization(data['n_users'], data['n_items'], 64, use_bias=True,
                            train_global_bias=variant == 'bce_global', init_scheme='author_uniform')
if variant == 'bce_init01':
    for embedding in (model.user_embedding, model.item_embedding):
        torch.nn.init.normal_(embedding.weight, 0.0, 0.1)
optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=1e-6)
u = torch.as_tensor(data['train_u'], dtype=torch.long)
i = torch.as_tensor(data['train_i'], dtype=torch.long)
y = torch.as_tensor(data['train_y'], dtype=torch.float32)
negative_weight = {'bce_neg0.5': .5, 'bce_neg0.2': .2}.get(variant, 1.)
weights = torch.where(y > 0, torch.ones_like(y), torch.full_like(y, negative_weight))


def evaluate(split):
    model.eval()
    return evaluate_unbiased_model(model, data[f'{split}_candidates'], data[f'{split}_ground_truth'], k=5,
                                   include_zero_positive_users=False)


best, stale, history = dict(val=-1., epoch=0, state=None), 0, []
for epoch in range(1, 301):
    model.train()
    for idx in torch.randperm(len(y)).split(512):
        score = model(u[idx], i[idx])
        if variant == 'mse':
            loss = F.mse_loss(score, y[idx])
        else:
            loss = (F.binary_cross_entropy_with_logits(score, y[idx], reduction='none') * weights[idx]).mean()
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
    val = evaluate('val')['NDCG@5']
    history.append(val)
    if val > best['val']:
        best, stale = dict(val=val, epoch=epoch, state=copy.deepcopy(model.state_dict())), 0
    else:
        stale += 1
        if stale >= 20:
            break
model.load_state_dict(best['state'])
test = evaluate('test')
report = dict(variant=variant, lr=lr, seed=seed, val_ndcg=best['val'], best_epoch=best['epoch'], epochs_run=epoch,
              test={k: test[k] for k in ('NDCG@5', 'Recall@5', 'Recall@5_bounded')}, val_history=history)
out = ROOT / f'results/ividr_bce_objective_{variant}_lr{lr:g}_seed{seed}_20261028.json'
with out.open('x', encoding='utf-8') as stream:
    json.dump(report, stream, indent=2)
print(json.dumps(dict(variant=variant, lr=lr, seed=seed, val=best['val'], test=test['NDCG@5'], epoch=best['epoch'])))
