# CDR released script: kuairand

Diagnostic under published script conditions; NOT project held-out evaluation.

Protocol: {'metric_revision': 'cdr_source_v1', 'scope': 'cdr_source_protocol', 'recall_denominator': 'all_positive', 'calibration': 'validation_5_percent', 'paper_scores_directly_comparable': False}. Adaptations: ['local KuaiRand preprocessing/user split; original processed CSVs unavailable', 'array trainer sampling instead of source Torch DataLoader', 'zero-based local user IDs, including user 0 in evaluation', 'global AUC half-credit ties instead of source arbitrary tie ranks', 'bounded-memory catalog sampling with replacement'].

Metrics: {'NDCG@5': 0.2739622599746859, 'Recall@5': 0.2600890318669043, 'AUC_global': 0.6361510753631592, 'users': 13502}.

Seed 2020; epochs run 24; source 6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9.
