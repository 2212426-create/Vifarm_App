"""Label-conditional Naive Bayes propensity, calibrated without held-out labels.

The released Coat CDR code estimates P(O=1|Y) by Bayes' rule. Here the
calibration labels come exclusively from the project's random validation log;
the released script instead samples labels from its evaluation log.
"""
import hashlib

import numpy as np


def naive_bayes_propensity(train_labels, calibration_labels, observed_fraction):
    """P(O=1|Y=y) = P(Y=y|O=1) P(O=1) / P(Y=y)."""
    train = np.asarray(train_labels, dtype=np.float64)
    calibration = np.asarray(calibration_labels, dtype=np.float64)
    for values in (train, calibration):
        if values.ndim != 1 or not len(values) or not np.isin(values, [0, 1]).all():
            raise ValueError("Naive Bayes propensity requires nonempty binary labels")
        if not 0 < values.mean() < 1:
            raise ValueError("Naive Bayes propensity requires both classes in train and calibration")
    if not np.isfinite(observed_fraction) or not 0 < observed_fraction <= 1:
        raise ValueError("Invalid observed fraction for propensity calibration")
    train_rates = np.array([1 - train.mean(), train.mean()])
    calibration_rates = np.array([1 - calibration.mean(), calibration.mean()])
    class_propensity = observed_fraction * train_rates / calibration_rates
    if np.any(class_propensity > 1):
        raise ValueError("Calibration frequencies imply propensity > 1; check data or use provided propensity")
    inverse = (1 / class_propensity[train.astype(np.int64)]).astype(np.float32)
    return inverse, dict(calibration_rows=len(calibration),
        calibration_positive_rate=float(calibration.mean()),
        train_positive_rate=float(train.mean()),
        observed_fraction=float(observed_fraction),
        class_propensity=class_propensity.tolist(),
        calibration_labels_sha256=hashlib.sha256(calibration.tobytes()).hexdigest())


def validation_labels(data):
    """Read only validation pools, including users with no positive feedback."""
    return np.asarray([float(item in data["val_ground_truth"].get(user, set()))
        for user in sorted(data["val_candidates"])
        for item in sorted(data["val_candidates"][user])], dtype=np.float32)


def propensity_diagnostics(inverse):
    weights = np.asarray(inverse, dtype=np.float64)
    imputation = weights ** 3 * (1 - 1 / weights) ** 2
    top_count = max(1, int(np.ceil(.01 * len(weights))))
    return dict(inverse_propensity_max=float(weights.max()),
        ips_ess=float(weights.sum() ** 2 / np.square(weights).sum()),
        imputation_weight_max=float(imputation.max()),
        top_1pct_count=top_count,
        top_1pct_imputation_weight_share=(float(np.sort(imputation)[-top_count:].sum() / imputation.sum())
                                        if imputation.sum() else 0.0))
