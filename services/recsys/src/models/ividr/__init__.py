"""IViDR reference implementation and explicitly named legacy variants.

The default pipeline is fit_ividr_pipeline in train_ividr. Training modules
are imported on demand to avoid a cycle with the shared iDCF trainer.
"""
from .ividr_reference import IViDRMarginalMF, PaperExposureIVAE

__all__ = ["IViDRMarginalMF", "PaperExposureIVAE"]
