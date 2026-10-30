"""Compatibility alias; edit the implementation in src.models.ividr.ividr_reference."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.ividr.ividr_reference")
