# CDR released script: kuairand

Diagnostic under published script conditions; NOT project held-out evaluation.

Protocol: {'metric_revision': 'cdr_source_v1', 'scope': 'cdr_source_protocol', 'recall_denominator': 'all_positive', 'calibration': 'validation_5_percent', 'supplementary_metrics': ['Recall@5_bounded', 'Precision@5', 'HitRate@5'], 'auxiliary_aggregation': 'same source-eligible users; empty users: Recall=1, precision/hit-rate=0', 'paper_scores_directly_comparable': False}. Adaptations: ['local KuaiRand preprocessing/user split; original processed CSVs unavailable', 'array trainer sampling instead of source Torch DataLoader', 'zero-based local user IDs, including user 0 in evaluation', 'global AUC half-credit ties instead of source arbitrary tie ranks', 'smoke-only calibration expanded to all validation rows to retain both classes'].

Metrics: {'NDCG@5': 0.5246731657552482, 'Recall@5': 0.6725806451612903, 'Recall@5_bounded': 0.6822580645161291, 'Precision@5': 0.2774193548387097, 'HitRate@5': 0.9354838709677419, 'AUC_global': 0.5104907751083374, 'users': 31}.

Seed 2020; epochs run 1; source 6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9.
