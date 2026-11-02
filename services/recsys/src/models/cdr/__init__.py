# -*- coding: utf-8 -*-
from src.models.cdr.cdr_model import CDRFramework
from src.models.cdr.imputation_model import ImputationModel
from src.models.cdr.dr_bias_loss import dr_bias_closed_form_imputation_loss, cdr_recommendation_loss
from src.models.cdr.train_dr_bias_cdr import train_dr_bias_cdr
from src.models.cdr.released import ReleasedCDR


def train_cdr(*args, **kwargs):
    """Default CDR entrypoint: published-source algorithm and protocol."""
    from src.models.cdr.source_protocol import run_source
    return run_source(*args, **kwargs)

__all__ = [
    "CDRFramework",
    "ReleasedCDR",
    "train_cdr",
    "ImputationModel",
    "dr_bias_closed_form_imputation_loss",
    "cdr_recommendation_loss",
    "train_dr_bias_cdr"
]

