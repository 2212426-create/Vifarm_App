"""The cf-dl report keeps every per-seed row next to the seed list."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from experiments.workflows import cf_dl
from tests.test_ncf import ranking_data


class CFDLReportTests(unittest.TestCase):
    def test_report_keeps_per_seed_rows(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()), \
                mock.patch.dict(cf_dl.LOADERS, {"coat": ranking_data}), \
                mock.patch.object(cf_dl, "RESULTS_DIR", folder), mock.patch.object(cf_dl, "CHECKPOINT_DIR", folder), \
                mock.patch.dict(cf_dl.NCF_CONFIG["coat"], {"embedding_dim": 4, "layers": (8, 4), "batch_size": 16}):
            cf_dl.main(["--dataset", "coat", "--models", "NeuMF", "--seeds", "1", "2", "--epochs", "1"])
            report = json.loads(next(Path(folder).glob("cf_dl_coat_*.json")).read_text(encoding="utf-8"))
        self.assertEqual(report["seeds"], [1, 2])
        self.assertEqual(sorted(report["per_seed"]), ["1", "2"])
        self.assertIn("checkpoint_path", report["per_seed"]["1"]["NeuMF"])
        self.assertEqual(report["summary"]["NeuMF"]["NDCG@5"]["n"], 2)


if __name__ == "__main__":
    unittest.main()
