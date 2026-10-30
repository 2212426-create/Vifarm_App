"""Compatibility alias; edit the implementation in src.models.mf.matrix_factorization."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.mf.matrix_factorization")
