# -*- coding: utf-8 -*-
"""
Metric của ConAlign, port từ third_party/conalign/utils/metrics.py (commit f6171bb).
Định nghĩa giữ nguyên source, khác evaluator chung của project:
  - AUC/BCE toàn cục trên mọi cặp test; UAUC trung bình AUC của user có cả hai nhãn.
  - UNDCG@5: user có ít nhất một positive; Precision/Recall/NDCG@5 (`calc`): chỉ user có cả
    positive lẫn negative. Không có tie-break tường minh (argsort của numpy).
Tên kết quả giữ đúng khóa source; không đổi thành NDCG@5 của protocol iDCF.
Project: ViFarm (services/recsys)
"""

import numpy as np
import torch

TOP_K = 5


def calc(ttuser, ttitem, pre, ttrating, atk=TOP_K):
    user = ttuser.cpu().detach().numpy()
    item = ttitem.cpu().detach().numpy()
    pre = pre.cpu().detach().numpy()
    rating = ttrating.cpu().numpy()
    posid = np.where(rating == 1)
    posuser, positem = user[posid], item[posid]
    user_labels = {}
    for i in range(len(user)):
        user_labels.setdefault(user[i], set()).add(rating[i])
    valid_users = {u for u, labels in user_labels.items() if 1 in labels and 0 in labels}
    user_preds, user_items = {}, {}
    for i in range(len(user)):
        u = user[i]
        if u not in valid_users:
            continue
        user_preds.setdefault(u, []).append(pre[i])
        user_items.setdefault(u, []).append(item[i])
    logsum = np.cumsum(1 / np.log2(np.arange(int(item.max()) + 3)[2:]))
    precision = recall = ndcg = 0
    n_interacted_user = 0
    keys, user_pos_count = set(), {}
    for i in range(len(posuser)):
        u = posuser[i]
        if u not in valid_users:
            continue
        keys.add((u, positem[i]))
        user_pos_count[u] = user_pos_count.get(u, 0) + 1
    for u in user_preds:
        if user_pos_count.get(u, 0) == 0:
            continue
        n_interacted_user += 1
        preds, items = np.array(user_preds[u]), np.array(user_items[u])
        n_pos = user_pos_count[u]
        topk_items = items[np.argsort(preds)[::-1][:atk]]
        hit = sum(1 for it in topk_items if (u, it) in keys)
        precision += hit / atk
        recall += hit / n_pos
        dcg = sum(1.0 / np.log2(rank + 2) for rank, it in enumerate(topk_items) if (u, it) in keys)
        idcg = logsum[min(n_pos, atk) - 1]
        if idcg > 0:
            ndcg += dcg / idcg
    if n_interacted_user == 0:
        return [0.0, 0.0, 0.0]
    return [precision / n_interacted_user, recall / n_interacted_user, ndcg / n_interacted_user]


def auc(vector_predict, vector_true, device='cpu'):
    pos_indexes = torch.where(vector_true == 1)[0].to(device)
    n_pos = len(pos_indexes)
    n_total = len(vector_predict)
    n_neg = n_total - n_pos
    if n_pos == 0 or n_neg == 0:
        return 0.5
    pos_whe = (vector_true == 1).to(device)
    sort_indexes = torch.argsort(vector_predict).to(device)
    rank = torch.zeros((n_total)).to(device)
    rank[sort_indexes] = torch.FloatTensor(list(range(n_total))).to(device)
    rank = rank * pos_whe
    return ((torch.sum(rank) - n_pos * (n_pos - 1) / 2) / (n_pos * n_neg)).item()


def uauc(ut_dict, pt_dict):
    total, valid = 0.0, 0
    for user_id in ut_dict:
        trues, preds = ut_dict[user_id], pt_dict[user_id]
        if 1 in trues and 0 in trues:
            total += auc(torch.tensor(preds), torch.tensor(trues))
            valid += 1
    return total / valid if valid else 0.0


def undcg(ut_dict, pt_dict, atk=TOP_K):
    total, valid = 0.0, 0
    for user_id in ut_dict:
        trues, preds = np.array(ut_dict[user_id]), np.array(pt_dict[user_id])
        if 1 not in trues:
            continue
        ranked = trues[np.argsort(preds)[::-1]]
        dcg = sum(1.0 / np.log2(i + 2) for i in range(min(atk, len(ranked))) if ranked[i] == 1)
        idcg = sum(1.0 / np.log2(i + 2) for i in range(min(atk, int(np.sum(trues == 1)))))
        if idcg > 0:
            total += dcg / idcg
            valid += 1
    return total / valid if valid else 0.0


def bce(vector_predict, vector_true):
    eps = 1e-6
    vector_predict = torch.clamp(vector_predict.float(), eps, 1 - eps)
    vector_true = vector_true.float()
    value = -torch.mean(vector_true * torch.log(vector_predict) + (1 - vector_true) * torch.log(1 - vector_predict))
    return float('nan') if torch.isinf(value) or torch.isnan(value) else value.item()


def train_metrics(preds, trues):
    return {'BCE': bce(preds, trues), 'AUC': auc(preds, trues)}


def test_metrics(preds, trues, users, items):
    """BCE, AUC, UAUC, UNDCG, Precision, Recall, NDCG như run_test của mymodel.py."""
    ut_dict, pt_dict = {}, {}
    for user, rating, score in zip(users.tolist(), trues.tolist(), preds.tolist()):
        ut_dict.setdefault(user, []).append(rating)
        pt_dict.setdefault(user, []).append(score)
    precision, recall, ndcg = calc(users, items, preds, trues)
    return {'BCE': bce(preds, trues), 'AUC': auc(preds, trues), 'UAUC': uauc(ut_dict, pt_dict),
            'UNDCG': undcg(ut_dict, pt_dict), 'Precision': precision, 'Recall': recall, 'NDCG': ndcg}
