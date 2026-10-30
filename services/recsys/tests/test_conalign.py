"""ConAlign port parity against the pinned author source in third_party/conalign."""
import argparse
import contextlib
import hashlib
import importlib
import io
import json
import re
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import torch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from src.models.conalign.data import load_conalign_data, raw_rating_frames
from src.models.conalign.model import DualTowerMF
from src.models.conalign.train import setup_seed, train_conalign

SOURCE = ROOT / "third_party/conalign"
MANIFEST = json.loads((SOURCE / "upstream_manifest.json").read_text(encoding="utf-8"))
HAS_COAT = (ROOT / "data/raw/coat/train.ascii").is_file()
HAS_YAHOO = (ROOT / "data/raw/yahoo/ydata-ymusic-rating-study-v1_0-train.txt").is_file()


def rows_text(frame):
    return "".join(f"{u},{i},{r}\n" for u, i, r in frame[["uid", "iid", "rating"]].itertuples(index=False)).encode()


@contextlib.contextmanager
def source_modules(dataset_files=None):
    """Copy the pinned source to a temporary folder and import it in isolation."""
    with tempfile.TemporaryDirectory() as folder:
        shutil.copytree(SOURCE, folder, dirs_exist_ok=True)
        for relative, content in (dataset_files or {}).items():
            target = Path(folder) / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        names = ("mymodel", "model", "arguments", "utils", "utils.data_loader", "utils.metrics",
                 "utils.early_stop", "utils.load_dataset_new", "utils.load_kuairand")
        saved = {name: sys.modules.pop(name) for name in names if name in sys.modules}
        sys.path.insert(0, folder)
        try:
            yield importlib.import_module("mymodel"), folder
        finally:
            sys.path.remove(folder)
            for name in names:
                sys.modules.pop(name, None)
            sys.modules.update(saved)


class ConAlignSourceParityTest(unittest.TestCase):
    def test_vendored_files_match_manifest(self):
        for relative, expected in MANIFEST["files"].items():
            self.assertEqual(hashlib.sha256((SOURCE / relative).read_bytes()).hexdigest(), expected, relative)

    @unittest.skipUnless(HAS_COAT and HAS_YAHOO, "Coat/Yahoo raw data unavailable")
    def test_rebuilt_rows_are_byte_identical_to_source_datasets(self):
        blobs = MANIFEST["excluded_datasets"]["blobs_sha256"]
        for dataset, folder in (("coat", "coat"), ("yahooR3", "yahooR3")):
            biased, random = raw_rating_frames(dataset)
            self.assertEqual(hashlib.sha256(rows_text(biased)).hexdigest(), blobs[f"datasets/{folder}/user.txt"])
            self.assertEqual(hashlib.sha256(rows_text(random)).hexdigest(), blobs[f"datasets/{folder}/random.txt"])

    def test_dual_tower_forward_and_init_match_source(self):
        users, items = torch.tensor([0, 1, 2, 2]), torch.tensor([3, 0, 1, 4])
        with source_modules() as (source, _):
            torch.manual_seed(7)
            reference = source.DualTowerMF(5, 6, dim=4, alignment_weight=.2)
            expected = reference(users, items)
        torch.manual_seed(7)
        port = DualTowerMF(5, 6, dim=4, alignment_weight=.2)
        for key, tensor in reference.state_dict().items():
            self.assertTrue(torch.equal(tensor, port.state_dict()[key]), key)
        for left, right in zip(expected, port(users, items)):
            self.assertTrue(torch.equal(left, right))

    @unittest.skipUnless(HAS_COAT, "Coat raw data unavailable")
    def test_two_epoch_training_matches_source_on_coat(self):
        biased, random = raw_rating_frames("coat")
        files = {"datasets/coat/user.txt": rows_text(biased), "datasets/coat/random.txt": rows_text(random)}
        with source_modules(files) as (source, folder):
            import utils.load_dataset_new as source_loader
            args = argparse.Namespace(dataset="coat", seed=0, test_only=False)
            source.para(args)
            args.training_args.update(pretrain_epochs=2, finetune_epochs=2)
            setup_seed(0)
            splits = source_loader.load_dataset(data_name="coat", unif_ratio=0.5, seed=0, device="cpu")
            stream = io.StringIO()
            with contextlib.redirect_stdout(stream):
                source.train_and_eval(*splits, args, device="cpu")
            printed = stream.getvalue()
        setup_seed(0)
        data = load_conalign_data("coat", seed=0)
        for name, tensor in zip(("train_biased", "val_biased", "train_unbiased", "val_unbiased",
                                 "test_unbiased", "test_biased"), splits):
            self.assertTrue(torch.equal(tensor._indices(), data[name]._indices()), name)
            self.assertTrue(torch.equal(tensor._values(), data[name]._values()), name)
        with tempfile.TemporaryDirectory() as folder:
            result = train_conalign(data, "coat", seed=0, device="cpu", checkpoint_dir=folder, verbose=False,
                                    overrides=dict(pretrain_epochs=2, finetune_epochs=2))
        for stage, label in (("stage1", "Stage 1"), ("stage2", "Stage 2")):
            lines = re.findall(rf"\[{label}\] Epoch +\d+ \| Train BCE: ([\d.]+) AUC: ([\d.]+) \| "
                               rf"Val BCE: ([\d.]+) AUC: ([\d.]+)", printed)
            self.assertEqual(len(lines), len(result["history"][stage]))
            for line, row in zip(lines, result["history"][stage]):
                ours = [f"{row[key]:.4f}" for key in ("train_bce", "train_auc", "val_bce", "val_auc")]
                self.assertEqual(list(line), ours)
        blocks = printed.split("Test Results]")[1:]
        for block, name in zip(blocks, ("test_unbiased", "test_biased")):
            for tower, header in (("biased_tower", "Biased Tower Predictions:"),
                                  ("unbiased_tower", "Unbiased Tower Predictions:")):
                section = block.split(header)[1]
                for key, value in result["source_metrics"][name][tower].items():
                    printed_value = re.search(rf"\n  {key}: ([\d.]+)", section).group(1)
                    self.assertEqual(printed_value, f"{value:.4f}", (name, tower, key))


def write_kuairand_logs(folder):
    """Tiny KuaiRand-Pure logs covering 08/04-08/05 with the three file names of the source."""
    import numpy as np
    import pandas as pd
    rng = np.random.default_rng(3)
    days = pd.date_range("2022-04-08", "2022-05-08").strftime("%Y%m%d").astype(int)

    def frame(first, last, rows):
        dates = days[(days >= first) & (days <= last)]
        return pd.DataFrame({"user_id": rng.integers(0, 6, rows), "video_id": rng.integers(0, 12, rows),
                             "date": rng.choice(dates, rows), "is_click": rng.integers(0, 2, rows)})

    frame(20220408, 20220421, 120).to_csv(Path(folder) / "log_standard_4_08_to_4_21_pure.csv", index=False)
    frame(20220422, 20220508, 150).to_csv(Path(folder) / "log_standard_4_22_to_5_08_pure.csv", index=False)
    frame(20220422, 20220508, 150).to_csv(Path(folder) / "log_random_4_22_to_5_08_pure.csv", index=False)


class ConAlignKuaiRandWindowTest(unittest.TestCase):
    SPLITS = ("train_biased", "val_biased", "test_biased", "train_unbiased", "val_unbiased", "test_unbiased")

    def test_source_window_matches_released_loader(self):
        with tempfile.TemporaryDirectory() as data_dir:
            write_kuairand_logs(data_dir)
            with source_modules() as _:
                import utils.load_kuairand as source_loader
                with contextlib.redirect_stdout(io.StringIO()):
                    expected = source_loader.load_kuairand(data_dir=data_dir, device="cpu", verbose=False)
            port = load_conalign_data("kuairand", data_dir=data_dir, kuairand_window="source")
        self.assertEqual((port["n_users"], port["n_items"]), (expected["n_users"], expected["n_items"]))
        for name in self.SPLITS:
            left, right = expected[name].coalesce(), port[name].coalesce()
            self.assertTrue(torch.equal(left.indices(), right.indices()), name)
            self.assertTrue(torch.equal(left.values(), right.values()), name)
        self.assertEqual(port["info"]["train_dates"], [20220408, 20220435])

    def test_paper_window_trains_on_22_04_to_05_05_only(self):
        import pandas as pd
        with tempfile.TemporaryDirectory() as data_dir:
            write_kuairand_logs(data_dir)
            port = load_conalign_data("kuairand", data_dir=data_dir)
            logs = [pd.read_csv(Path(data_dir) / name) for name in ("log_standard_4_22_to_5_08_pure.csv",
                                                                    "log_random_4_22_to_5_08_pure.csv")]
        self.assertEqual((port["info"]["window"], port["info"]["train_dates"]), ("paper", [20220422, 20220505]))
        users = pd.unique(pd.concat([logs[0]["user_id"], logs[1]["user_id"]]))
        items = pd.unique(pd.concat([logs[0]["video_id"], logs[1]["video_id"]]))
        self.assertEqual((port["n_users"], port["n_items"]), (len(users), len(items)))
        for log, name in zip(logs, ("train_biased", "train_unbiased")):
            train = log[(log["date"] >= 20220422) & (log["date"] <= 20220505)]
            pairs = set(zip(train["user_id"].map({u: k for k, u in enumerate(users)}),
                            train["video_id"].map({i: k for k, i in enumerate(items)})))
            got = set(map(tuple, port[name].coalesce().indices().T.tolist()))
            self.assertEqual(got, pairs, name)
        self.assertGreater(sum(log["date"].between(20220501, 20220505).sum() for log in logs), 0)

    def test_rejects_unknown_window(self):
        with self.assertRaises(ValueError):
            load_conalign_data("kuairand", kuairand_window="intended")


if __name__ == "__main__":
    unittest.main()
