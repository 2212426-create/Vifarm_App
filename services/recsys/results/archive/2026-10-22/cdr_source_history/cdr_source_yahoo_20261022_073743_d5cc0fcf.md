# CDR released script: yahoo

Diagnostic under published script conditions; NOT project held-out evaluation.

Protocol: {'metric_revision': 'cdr_source_v1', 'scope': 'cdr_source_protocol', 'recall_denominator': 'min(k,n_positive)', 'calibration': 'evaluation_5_percent', 'supplementary_metrics': ['Recall@5', 'Precision@5', 'HitRate@5'], 'auxiliary_aggregation': 'same source-eligible users; empty users: Recall=1, precision/hit-rate=0', 'paper_scores_directly_comparable': False}. Adaptations: [].

Metrics: {'NDCG@5': 0.6003965892758625, 'Recall@5': 0.6581586566725456, 'Recall@5_bounded': 0.6826111111111112, 'Precision@5': 0.23937037037037034, 'HitRate@5': 0.6033333333333334, 'AUC_global': 0.6328597664833069, 'users': 5400}.

Seed 2020; epochs run 1; source 6b4e6cca3df23b8d85b38fdc2e7eb5c812861ea9.
