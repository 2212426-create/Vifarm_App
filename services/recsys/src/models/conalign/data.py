# -*- coding: utf-8 -*-
"""
Dữ liệu ConAlign dựng từ data/raw, theo third_party/conalign/utils (commit f6171bb):
  - Coat/Yahoo (load_dataset_new.load_dataset): biased = rating do user chọn, unbiased = random;
    nhãn rating >= 4; nén ID theo thứ tự xuất hiện; biased chia ngẫu nhiên 70/10/20,
    unbiased 50/10/40 (unif_ratio=0.5 như mymodel.py), cùng seed cho cả hai.
  - KuaiRand-Pure (load_kuairand.load_kuairand): standard log là biased, random log là unbiased;
    val 06/05, test 07–08/05; cặp trùng lấy mean(is_click) rồi nhị phân hóa ngưỡng 0.5.
    Cửa sổ train (kuairand_window):
      'paper'  (mặc định): Sec. 4.1 của paper, chỉ dùng log 22/04–08/05, train 22/04–05/05.
      'source': đúng source, ngày train sinh bằng 20220408 + i (i < 28) nên chạy 20220408..20220430
                rồi 20220431..20220435 (không phải ngày thật): 01–05/05 không vào train.
Dòng (user, item, rating) dựng lại khớp từng byte với user.txt/random.txt của repo
(SHA-256 ghi trong third_party/conalign/upstream_manifest.json).
Project: ViFarm (services/recsys)
"""

import hashlib
import os

import numpy as np
import pandas as pd
import scipy.sparse as sp
import torch

from src.utils.helpers import resolve_dataset_dir

KUAIRAND_LOGS = ('log_standard_4_08_to_4_21_pure.csv', 'log_standard_4_22_to_5_08_pure.csv',
                 'log_random_4_22_to_5_08_pure.csv')
KUAIRAND_TRAIN_DATES = [20220408 + i for i in range(28)]
KUAIRAND_PAPER_FIRST_DATE = 20220422
KUAIRAND_PAPER_TRAIN_DATES = list(range(20220422, 20220431)) + list(range(20220501, 20220506))
KUAIRAND_WINDOWS = ('paper', 'source')
KUAIRAND_VAL_DATE = 20220506
KUAIRAND_TEST_DATES = [20220507, 20220508]
SPLITS = ('train_biased', 'val_biased', 'test_biased', 'train_unbiased', 'val_unbiased', 'test_unbiased')


def raw_rating_frames(dataset, data_dir=None):
    """(biased, random) DataFrame uid,iid,rating đúng thứ tự dòng của user.txt/random.txt."""
    if dataset == 'coat':
        root = resolve_dataset_dir('coat', data_dir)
        frames = []
        for name in ('train.ascii', 'test.ascii'):
            matrix = np.loadtxt(os.path.join(root, name)).astype(int)
            users, items = np.nonzero(matrix)
            frames.append(pd.DataFrame({'uid': users, 'iid': items, 'rating': matrix[users, items]}))
        return tuple(frames)
    if dataset == 'yahooR3':
        root = resolve_dataset_dir('yahoo', data_dir)
        frames = []
        for name in ('train', 'test'):
            values = pd.read_csv(os.path.join(root, f'ydata-ymusic-rating-study-v1_0-{name}.txt'),
                                 sep='\t', header=None).values
            frames.append(pd.DataFrame({'uid': values[:, 0] - 1, 'iid': values[:, 1] - 1,
                                        'rating': values[:, 2]}))
        return tuple(frames)
    raise ValueError(f'Unknown explicit ConAlign dataset: {dataset}')


def seed_randomly_split(df, ratio, split_seed, shape):
    np.random.seed(split_seed)
    indices = np.random.permutation(len(df))
    idx1 = int(ratio[0] * len(df))
    idx2 = int((ratio[0] + ratio[1]) * len(df))

    def to_matrix(part):
        return sp.csr_matrix((part['rating'], (part['uid'], part['iid'])), shape=shape, dtype='float32')

    return to_matrix(df.iloc[indices[:idx1]]), to_matrix(df.iloc[indices[idx1:idx2]]), to_matrix(df.iloc[indices[idx2:]])


def sparse_mx_to_torch_sparse_tensor(sparse_mx):
    sparse_mx = sparse_mx.tocoo()
    indices = torch.from_numpy(np.vstack((sparse_mx.row, sparse_mx.col)).astype(np.int64))
    values = torch.from_numpy(sparse_mx.data).float()
    return torch.sparse_coo_tensor(indices, values, torch.Size(sparse_mx.shape))


def load_explicit(dataset, seed=0, unif_ratio=0.5, threshold=4, data_dir=None, device='cpu'):
    user_df, random_df = (frame.copy() for frame in raw_rating_frames(dataset, data_dir))
    all_uids = pd.unique(pd.concat([user_df['uid'], random_df['uid']]))
    all_iids = pd.unique(pd.concat([user_df['iid'], random_df['iid']]))
    uid_map = {old: new for new, old in enumerate(all_uids)}
    iid_map = {old: new for new, old in enumerate(all_iids)}
    for frame in (user_df, random_df):
        frame['uid'] = frame['uid'].map(uid_map)
        frame['iid'] = frame['iid'].map(iid_map)
        frame['rating'] = np.where(frame['rating'] >= threshold, 1.0, 0.0)
    shape = (len(all_uids), len(all_iids))
    biased = seed_randomly_split(user_df, (0.7, 0.1, 0.2), seed, shape)
    unbiased = seed_randomly_split(random_df, (unif_ratio, 0.1, 1 - unif_ratio - 0.1), seed, shape)
    matrices = dict(zip(SPLITS, (*biased, *unbiased)))
    info = dict(protocol='conalign_source_random_split_v1', dataset=dataset, seed=seed,
                unif_ratio=unif_ratio, threshold=threshold,
                biased_ratio=[0.7, 0.1, 0.2], unbiased_ratio=[unif_ratio, 0.1, round(1 - unif_ratio - 0.1, 10)])
    return finish(matrices, shape, info, device)


def deduplicate_and_binarize_interactions(df, threshold=0.5):
    if df.empty:
        return df[['user_id', 'video_id', 'is_click']].copy()
    dedup = df.groupby(['user_id', 'video_id'], as_index=False)['is_click'].mean()
    dedup['is_click'] = (dedup['is_click'] >= threshold).astype(np.float32)
    return dedup


def load_kuairand(data_dir=None, device='cpu', smoke_users=None, seed=0, kuairand_window='paper'):
    if kuairand_window not in KUAIRAND_WINDOWS:
        raise ValueError(f'Unknown KuaiRand window: {kuairand_window}')
    root = resolve_dataset_dir('kuairand_pure', data_dir)
    root = os.path.join(root, 'data') if os.path.isdir(os.path.join(root, 'data')) else root
    early, late, unbiased_df = (pd.read_csv(os.path.join(root, name)) for name in KUAIRAND_LOGS)
    biased_df = pd.concat([early, late], ignore_index=True)
    columns = ['user_id', 'video_id', 'date', 'is_click']
    biased_df = biased_df[columns].copy().dropna()
    unbiased_df = unbiased_df[columns].copy().dropna()
    train_dates = KUAIRAND_TRAIN_DATES
    if kuairand_window == 'paper':
        # Paper: only the 17 days 22/04–08/05; rows are dropped before ID mapping.
        biased_df = biased_df[biased_df['date'] >= KUAIRAND_PAPER_FIRST_DATE].reset_index(drop=True)
        unbiased_df = unbiased_df[unbiased_df['date'] >= KUAIRAND_PAPER_FIRST_DATE].reset_index(drop=True)
        train_dates = KUAIRAND_PAPER_TRAIN_DATES
    if smoke_users is not None:
        # Smoke only: keep the first users in source ID order; not the paper protocol.
        keep = pd.unique(pd.concat([biased_df['user_id'], unbiased_df['user_id']]))[:smoke_users]
        biased_df = biased_df[biased_df['user_id'].isin(keep)]
        unbiased_df = unbiased_df[unbiased_df['user_id'].isin(keep)]
    all_users = pd.unique(pd.concat([biased_df['user_id'], unbiased_df['user_id']]))
    all_items = pd.unique(pd.concat([biased_df['video_id'], unbiased_df['video_id']]))
    user_map = {old: new for new, old in enumerate(all_users)}
    item_map = {old: new for new, old in enumerate(all_items)}
    for frame in (biased_df, unbiased_df):
        frame['user_id'] = frame['user_id'].map(user_map)
        frame['video_id'] = frame['video_id'].map(item_map)
    shape = (len(all_users), len(all_items))
    parts = {}
    for kind, frame in (('biased', biased_df), ('unbiased', unbiased_df)):
        for split, mask in (('train', frame['date'].isin(train_dates)),
                            ('val', frame['date'] == KUAIRAND_VAL_DATE),
                            ('test', frame['date'].isin(KUAIRAND_TEST_DATES))):
            part = deduplicate_and_binarize_interactions(frame[mask].copy())
            parts[f'{split}_{kind}'] = sp.csr_matrix(
                (part['is_click'].values, (part['user_id'].values, part['video_id'].values)),
                shape=shape, dtype='float32')
    info = dict(protocol=f'conalign_{kuairand_window}_kuairand_temporal_v1', dataset='KuaiRand', seed=seed,
                window=kuairand_window, train_dates=[train_dates[0], train_dates[-1]], val_date=KUAIRAND_VAL_DATE,
                test_dates=KUAIRAND_TEST_DATES, duplicate_label='mean_is_click_ge_0.5',
                smoke_users=smoke_users)
    return finish({name: parts[name] for name in SPLITS}, shape, info, device)


def finish(matrices, shape, info, device):
    tensors = {name: sparse_mx_to_torch_sparse_tensor(matrix).to(device) for name, matrix in matrices.items()}
    digest = hashlib.sha256()
    for name in SPLITS:
        coo = matrices[name].tocoo()
        for array in (coo.row.astype(np.int64), coo.col.astype(np.int64), coo.data.astype(np.float32)):
            digest.update(name.encode())
            digest.update(np.ascontiguousarray(array).tobytes())
    info.update(n_users=shape[0], n_items=shape[1], sha256=digest.hexdigest(),
                counts={name: int(matrices[name].nnz) for name in SPLITS})
    return dict(tensors, n_users=shape[0], n_items=shape[1], info=info)


def load_conalign_data(dataset, seed=0, data_dir=None, device='cpu', smoke_users=None, kuairand_window='paper'):
    if dataset == 'coat':
        return load_explicit('coat', seed=seed, data_dir=data_dir, device=device)
    if dataset == 'yahoo':
        return load_explicit('yahooR3', seed=seed, data_dir=data_dir, device=device)
    if dataset == 'kuairand':
        return load_kuairand(data_dir=data_dir, device=device, smoke_users=smoke_users, seed=seed,
                             kuairand_window=kuairand_window)
    raise ValueError(f'Unknown ConAlign dataset: {dataset}')
