# CDR released script: yahoo

Diagnostic under published script conditions; NOT project held-out evaluation.

Protocol: {'metric_revision': 'cdr_source_v1', 'scope': 'cdr_source_protocol', 'recall_denominator': 'min(k,n_positive)', 'calibration': 'evaluation_5_percent', 'supplementary_metrics': ['Recall@5', 'Precision@5', 'HitRate@5'], 'auxiliary_aggregation': 'same source-eligible users; empty users: Recall=1, precision/hit-rate=0', 'paper_scores_directly_comparable': False}. Adaptations: [].

Metrics: {'NDCG@5': 0.655928916666389, 'Recall@5': 0.7060595972957084, 'Recall@5_bounded': 0.7312993827160493, 'Precision@5': 0.2637777777777778, 'HitRate@5': 0.6309259259259259, 'AUC_global': 0.6849303841590881, 'users': 5400}.

Seed 2020; epochs run 39; source 6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9.
