"""Compatibility alias; edit the implementation in src.models.idcf.idcf_model."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.idcf.idcf_model")
