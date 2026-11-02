"""Compatibility alias; edit the implementation in src.models.idcf.ivae."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.idcf.ivae")
