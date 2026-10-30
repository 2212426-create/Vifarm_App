"""Construct binary exposure indicators and empirical pair labels for Eq. (7)."""
import numpy as np


def aggregate_observed_pairs(users, items, labels, num_items):
    """Give each observed pair one vote, retaining both clicks and non-clicks.

    A repeated pair receives its mean label: BCE is linear in the label, so this
    equals the empirical expected BCE for that pair. Other model loaders and
    held-out ranking labels are not changed.
    """
    users, items, labels = np.asarray(users), np.asarray(items), np.asarray(labels)
    if not (len(users) == len(items) == len(labels)) or not len(labels):
        raise ValueError("Observed training arrays must be nonempty and aligned")
    if not np.isfinite(labels).all() or np.any((labels < 0) | (labels > 1)):
        raise ValueError("CDR labels must lie in [0, 1]")
    pairs, inverse, counts = np.unique(users.astype(np.int64) * num_items + items,
                                       return_inverse=True, return_counts=True)
    means = np.bincount(inverse, weights=labels) / counts
    return pairs // num_items, pairs % num_items, means.astype(np.float32)
