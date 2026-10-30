"""Compatibility alias; edit the implementation in src.models.cdr.observations."""
import importlib
import sys

sys.modules[__name__] = importlib.import_module("src.models.cdr.observations")
