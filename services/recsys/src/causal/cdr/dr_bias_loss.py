"""Compatibility alias; edit the implementation in src.models.cdr.dr_bias_loss."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.cdr.dr_bias_loss")
