# CDR released script: kuairand

Diagnostic under published script conditions; NOT project held-out evaluation.

Protocol: {'metric_revision': 'cdr_source_v1', 'scope': 'cdr_source_protocol', 'recall_denominator': 'all_positive', 'calibration': 'validation_5_percent', 'supplementary_metrics': ['Recall@5_bounded', 'Precision@5', 'HitRate@5'], 'auxiliary_aggregation': 'same source-eligible users; empty users: Recall=1, precision/hit-rate=0', 'paper_scores_directly_comparable': False}. Adaptations: ['local KuaiRand preprocessing/user split; original processed CSVs unavailable', 'array trainer sampling instead of source Torch DataLoader', 'zero-based local user IDs, including user 0 in evaluation', 'global AUC half-credit ties instead of source arbitrary tie ranks', 'bounded-memory catalog sampling with replacement'].

Metrics: {'NDCG@5': 0.27508164294680865, 'Recall@5': 0.2603896274230597, 'Recall@5_bounded': 0.3298980397965733, 'Precision@5': 0.21887127832913644, 'HitRate@5': 0.6485705821359798, 'AUC_global': 0.6376748085021973, 'users': 13502}.

Seed 2020; epochs run 22; source 6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9.
