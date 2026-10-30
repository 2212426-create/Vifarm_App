"""Relocation regressions: one module object, patching and stable data paths."""
import importlib
import json
from pathlib import Path
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]


class PackageLayoutTests(unittest.TestCase):
    def test_old_and_new_module_names_share_state(self):
        moves = json.loads((ROOT / 'docs/archive/2026-10-22/package_layout/moves.json').read_text())
        for row in moves['moves']:
            if not row['old'].endswith('.py') or row['old'].endswith('__init__.py'):
                continue
            old, new = (path.removesuffix('.py').replace('/', '.')
                        for path in (row['old'], row['new']))
            with self.subTest(old=old):
                self.assertIs(importlib.import_module(old), importlib.import_module(new))
        with patch('src.causal.idcf.train_ividr.train_dual_ivae') as old_patch:
            new = importlib.import_module('src.models.ividr.train_ividr')
            self.assertIs(new.train_dual_ivae, old_patch)

    def test_storage_paths_do_not_follow_model_packages(self):
        from src.utils import helpers
        self.assertEqual(Path(helpers.PROJECT_ROOT), ROOT)
        self.assertEqual(Path(helpers.CHECKPOINT_DIR), ROOT / 'checkpoints')
        self.assertEqual(Path(helpers.RESULTS_DIR), ROOT / 'results')
        from src.models.mf import train_mf
        from src.models.cdr import train_dr_bias_cdr
        trainer = importlib.import_module('src.models.cdr.train_dr_bias_cdr')
        self.assertEqual(Path(train_mf.PROJECT_ROOT), ROOT)
        self.assertEqual(Path(trainer.PROJECT_ROOT), ROOT)


if __name__ == '__main__':
    unittest.main()
