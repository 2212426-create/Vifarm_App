"""Compatibility alias; edit the implementation in src.models.ividr.ividr_staged."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.ividr.ividr_staged")
