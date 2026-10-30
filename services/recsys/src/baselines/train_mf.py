"""Compatibility alias; edit the implementation in src.models.mf.train_mf."""
import importlib
import sys

from pathlib import Path
_root = str(Path(__file__).resolve().parents[2])
if _root not in sys.path:
    sys.path.insert(0, _root)

if __name__ == "__main__":
    import runpy
    runpy.run_module("src.models.mf.train_mf", run_name="__main__")
else:
    sys.modules[__name__] = importlib.import_module("src.models.mf.train_mf")
