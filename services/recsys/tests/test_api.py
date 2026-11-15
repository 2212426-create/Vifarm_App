"""RecSys API: dữ liệu giả nhỏ, không gọi mạng."""
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

import pandas as pd
import torch
from fastapi.testclient import TestClient

from src.api.app import create_app
from src.api.auth import ApiAuth, FirebaseTokenVerifier, TokenRejected, VerifierUnavailable
from src.api.firebase_bridge import (INTERACTION_COLUMNS, InteractionLog, Snapshot,
                                     behavior_label, likes_from_notifications,
                                     load_snapshot, normalize_video, parse_fs_value,
                                     unique_username_map)
from src.api.conalign_random import fit_conalign_with_random_log
from src.api.service import RANDOM_SERVED_TTL, RecEngine


def make_snapshot():
    videos = {}
    for j in range(8):
        vid = f"v{j}"
        videos[vid] = normalize_video({"videoId": vid, "videoUri": f"https://cdn/{vid}.mp4",
                                       "watchCount": 10 * j, "totalLikes": j,
                                       "moderationStatus": "approved"})
    videos["v7"]["moderationStatus"] = "rejected"
    videos["v6"]["videoUri"] = ""
    rows = []
    # u0 thích nhóm v0-v2, u1 thích nhóm v3-v5; mỗi user có cả nhãn âm.
    for user, liked, disliked in (("u0", "v0 v1 v2", "v3 v4"), ("u1", "v3 v4 v5", "v0 v1"),
                                  ("u2", "v0 v1", "v4 v5"), ("u3", "v4 v5", "v1 v2")):
        rows += [{"user_id": user, "video_id": v, "label": 1.0, "play_time_ms": 9000,
                  "is_like": True, "source": "test"} for v in liked.split()]
        rows += [{"user_id": user, "video_id": v, "label": 0.0, "play_time_ms": 500,
                  "is_like": False, "source": "test"} for v in disliked.split()]
    return Snapshot(videos=videos, users=[], interactions=pd.DataFrame(rows, columns=INTERACTION_COLUMNS),
                    source="test")


def make_engine(**kwargs):
    kwargs.setdefault("epochs", 200)
    kwargs.setdefault("min_interactions", 5)
    return RecEngine(make_snapshot, **kwargs)


class BridgeTests(unittest.TestCase):
    def test_behavior_label_rule(self):
        self.assertEqual(behavior_label(False, 2999), 0.0)
        self.assertEqual(behavior_label(False, 3000), 1.0)
        self.assertEqual(behavior_label(True, 0), 1.0)

    def test_parse_firestore_typed_values(self):
        value = {"mapValue": {"fields": {"n": {"integerValue": "3"},
                                         "tags": {"arrayValue": {"values": [{"stringValue": "a"}]}}}}}
        self.assertEqual(parse_fs_value(value), {"n": 3, "tags": ["a"]})

    def test_normalize_snake_case_bundle_video(self):
        video = normalize_video({"video_id": "1", "video_uri": "u", "total_likes": "4"})
        self.assertEqual((video["videoId"], video["videoUri"], video["totalLikes"]), ("1", "u", 4))

    def test_likes_are_attributed_to_liker_not_notification_owner(self):
        users = [{"uid": "liker", "username": "An"}, {"uid": "author", "username": "Binh"}]
        notifications = {"author": {"n1": {"action": "2", "fromUsername": "An", "videoId": "v1"}}}
        rows = likes_from_notifications(notifications, unique_username_map(users))
        self.assertEqual([(r["user_id"], r["video_id"]) for r in rows], [("liker", "v1")])

    def test_ambiguous_username_is_dropped(self):
        users = [{"uid": "a", "username": "Trung"}, {"uid": "b", "username": "Trung"}]
        self.assertEqual(unique_username_map(users), {})

    def test_export_snapshot_merges_log_and_drops_unknown_videos(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "toptop_processed_bundle.json").write_text(
                '{"videos": [{"video_id": "v1", "video_uri": "u"}], "users": []}', encoding="utf-8")
            (tmp / "toptop_interactions.csv").write_text(
                "user_id,video_id,is_like,play_time_ms\nu,v1,0,100\nu,gone,1,0\n", encoding="utf-8")
            log = InteractionLog(tmp / "log.csv")
            log.append("u", "v1", 5000, False)
            snap = load_snapshot("export", export_dir=tmp, interaction_log=tmp / "log.csv")
        self.assertEqual(list(snap.videos), ["v1"])
        self.assertEqual(snap.interactions[["user_id", "video_id", "label"]].values.tolist(), [["u", "v1", 1.0]])

    def _export_fixture(self, tmp):
        (tmp / "toptop_processed_bundle.json").write_text(
            '{"videos": [{"video_id": "v1", "video_uri": "u"}], "users": []}', encoding="utf-8")
        (tmp / "toptop_interactions.csv").write_text(
            "user_id,video_id,is_like,play_time_ms\nu,v1,0,100\nu,gone,1,0\n", encoding="utf-8")
        InteractionLog(tmp / "log.csv").append("u", "v1", 5000, False)
        return tmp / "log.csv"

    def test_snapshot_reads_random_log_separately(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            log_path = self._export_fixture(tmp)
            rpath = tmp / "random.csv"
            rlog = InteractionLog(rpath)
            rlog.append("u9", "v1", 800, False)
            rlog.append("u9", "vX", 9000, True)
            snap = load_snapshot("export", export_dir=tmp, interaction_log=log_path, random_log=rpath)
        self.assertEqual(len(snap.random_interactions), 1)
        self.assertEqual(set(snap.random_interactions["source"]), {"api_random"})
        self.assertNotIn(("u9", "v1"), set(zip(snap.interactions.user_id, snap.interactions.video_id)))

    def test_snapshot_without_random_log_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            log_path = self._export_fixture(tmp)
            snap = load_snapshot("export", export_dir=tmp, interaction_log=log_path,
                                 random_log=tmp / "missing.csv")
        self.assertEqual(list(snap.random_interactions.columns), INTERACTION_COLUMNS)
        self.assertEqual(len(snap.random_interactions), 0)


class EngineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = make_engine()

    def test_trains_real_models(self):
        self.assertEqual(sorted(self.engine.models), ["cdr", "conalign", "mf"])
        from src.models.cdr.released import ReleasedCDR
        self.assertIsInstance(self.engine.models['cdr'], ReleasedCDR)
        from src.models.conalign.model import DualTowerMF
        self.assertIsInstance(self.engine.models['conalign'], DualTowerMF)
        self.assertEqual(self.engine.training_stats['cdr']['implementation'], 'cdr_released')
        self.assertEqual(self.engine.training_stats['cdr']['scope'], 'serving_adaptation_not_paper_experiment')

    def test_conalign_learns_user_preferences(self):
        def top(user):
            recs, used, cold, _ = self.engine.recommend(user, k=3, model="conalign", filter_rejected=True)
            self.assertEqual((used, cold), ("conalign", False))
            return [r["videoId"] for r in recs]
        self.assertTrue(set(top("u0")) & {"v0", "v1", "v2"})
        self.assertNotEqual(top("u0"), top("u1"))

    def test_mf_learns_user_preferences(self):
        def top(user):
            recs, used, cold, _ = self.engine.recommend(user, k=3, model="mf", filter_rejected=True)
            self.assertEqual((used, cold), ("mf", False))
            return [r["videoId"] for r in recs]
        self.assertTrue(set(top("u0")) & {"v0", "v1", "v2"})
        self.assertNotEqual(top("u0"), top("u1"))

    def test_recommendation_is_deterministic(self):
        first = self.engine.recommend("u0", k=5)[0]
        second = self.engine.recommend("u0", k=5)[0]
        self.assertEqual([r["score"] for r in first], [r["score"] for r in second])

    def test_filters_rejected_and_unplayable(self):
        recs, *_ = self.engine.recommend("u0", k=10, filter_rejected=True)
        ids = {r["videoId"] for r in recs}
        self.assertNotIn("v7", ids)
        self.assertNotIn("v6", ids)

    def test_cold_start_uses_popularity(self):
        recs, used, cold, reason = self.engine.recommend("stranger", k=3)
        self.assertEqual((used, cold), ("popularity", True))
        self.assertIsNotNone(reason)
        self.assertEqual(recs[0]["videoId"], "v5")

    def test_unknown_model_request_reports_fallback(self):
        _, used, _, reason = self.engine.recommend("u0", k=3, model="no_such_model")
        self.assertEqual(used, "conalign")
        self.assertIn("no_such_model", reason)

    def test_too_little_data_serves_popularity(self):
        engine = make_engine(min_interactions=10_000)
        _, used, _, reason = engine.recommend("u0", k=3, model="mf")
        self.assertEqual(used, "popularity")
        self.assertIn("Chưa đủ dữ liệu", reason)


class InteractionTests(unittest.TestCase):
    def test_watched_videos_are_excluded_and_retrain_triggers(self):
        engine = make_engine(retrain_every=2, epochs=20)
        self.assertFalse(engine.log_interaction("u0", "v0", 9000, False)["retrain_started"])
        result = engine.log_interaction("u0", "v1", 100, False)
        self.assertTrue(result["retrain_started"])
        self.assertTrue(engine.wait_for_retrain(60))
        ids = {r["videoId"] for r in engine.recommend("u0", k=10)[0]}
        self.assertFalse({"v0", "v1"} & ids)

    def test_new_user_becomes_warm_after_retrain(self):
        engine = make_engine(retrain_every=2, epochs=20)
        engine.log_interaction("newbie", "v0", 9000, True)
        engine.log_interaction("newbie", "v3", 100, False)
        self.assertTrue(engine.wait_for_retrain(60))
        self.assertFalse(engine.recommend("newbie", k=3)[2])

    def test_synchronous_mode_retrains_before_returning(self):
        engine = make_engine(retrain_every=2, epochs=20, background_retrain=False)
        engine.log_interaction("newbie", "v0", 9000, True)
        self.assertTrue(engine.log_interaction("newbie", "v3", 100, False)["retrain_started"])
        self.assertFalse(engine.recommend("newbie", k=3)[2])


class BackgroundRetrainTests(unittest.TestCase):
    def slow_engine(self):
        engine = make_engine(retrain_every=1, epochs=20)
        gate = threading.Event()
        original = engine._train_state

        def slow(*args):
            gate.wait(30)
            return original(*args)
        engine._train_state = slow
        return engine, gate

    def test_recommend_is_served_by_old_models_while_retraining(self):
        engine, gate = self.slow_engine()
        try:
            self.assertTrue(engine.log_interaction("newbie", "v0", 9000, True)["retrain_started"])
            self.assertTrue(engine.retraining)
            started = time.monotonic()
            _, used, cold, _ = engine.recommend("newbie", k=3)
            self.assertLess(time.monotonic() - started, 2.0)
            self.assertEqual((used, cold), ("popularity", True))
            self.assertTrue(engine.health()["retraining"])
        finally:
            gate.set()
        self.assertTrue(engine.wait_for_retrain(60))
        self.assertFalse(engine.recommend("newbie", k=3)[2])

    def test_only_one_retrain_runs_at_a_time(self):
        engine, gate = self.slow_engine()
        try:
            self.assertTrue(engine.log_interaction("u0", "v3", 9000, True)["retrain_started"])
            first = engine._retrain_thread
            self.assertFalse(engine.log_interaction("u0", "v4", 9000, True)["retrain_started"])
            self.assertIs(engine._retrain_thread, first)
        finally:
            gate.set()
        self.assertTrue(engine.wait_for_retrain(60))

    def test_failed_retrain_keeps_previous_models(self):
        engine = make_engine(retrain_every=1, epochs=20)
        models = engine.models

        def boom(*args):
            raise RuntimeError("disk full")
        engine._train_state = boom
        with self.assertLogs("src.api.service", level="ERROR"):
            engine.log_interaction("u0", "v3", 9000, True)
            self.assertTrue(engine.wait_for_retrain(60))
        self.assertIs(engine.models, models)
        self.assertIn("disk full", engine.health()["last_retrain_error"])


class HttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(create_app(make_engine(epochs=50), auth=ApiAuth("off")))

    def test_health(self):
        body = self.client.get("/health").json()
        self.assertEqual(body["status"], "ok")
        self.assertIn("mf", body["models_available"])

    def test_recommend_contract_matches_flutter_client(self):
        body = self.client.post("/api/v1/recommend",
                                json={"user_id": "u1", "k": 4, "model": "conalign", "filter_rejected": True}).json()
        self.assertEqual(len(body["recommendations"]), 4)
        item = body["recommendations"][0]
        for key in ("videoId", "videoUri", "authorId", "username", "totalLikes", "watchCount", "moderationStatus"):
            self.assertIn(key, item)
        self.assertEqual(body["model_used"], "conalign")

    def test_interaction_and_compare(self):
        res = self.client.post("/api/v1/interaction",
                               json={"user_id": "u2", "video_id": "v2", "play_time_ms": 4000, "is_like": False})
        self.assertTrue(res.json()["is_positive_interaction"])
        results = self.client.post("/api/v1/compare", json={"user_id": "u2", "k": 3}).json()["results"]
        self.assertEqual(set(results), {"conalign", "mf", "cdr", "popularity"})

    def test_invalid_k_is_rejected(self):
        self.assertEqual(self.client.post("/api/v1/recommend", json={"k": 0}).status_code, 422)


TOKENS = {"tok-u0": "u0", "tok-u1": "u1"}


def fake_verify(token):
    if token == "tok-down":
        raise VerifierUnavailable("Không tải được khóa công khai của Google.")
    if token not in TOKENS:
        raise TokenRejected("bad")
    return TOKENS[token]


def bearer(token):
    return {"Authorization": f"Bearer {token}"}


class AuthHttpTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.engine = make_engine(epochs=50, retrain_every=0)
        cls.client = TestClient(create_app(cls.engine, auth=ApiAuth("firebase", fake_verify, "admin-secret")))

    def post(self, path, json, headers=None):
        return self.client.post(path, json=json, headers=headers or {})

    def test_interaction_requires_token(self):
        res = self.post("/api/v1/interaction", {"user_id": "u0", "video_id": "v2"})
        self.assertEqual(res.status_code, 401)

    def test_interaction_is_recorded_for_token_owner(self):
        res = self.post("/api/v1/interaction", {"video_id": "v5", "play_time_ms": 4000}, bearer("tok-u1"))
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["user_id"], "u1")
        self.assertIn("v5", self.engine.watched["u1"])

    def test_http_interaction_accepts_exposure_field(self):
        res = self.post("/api/v1/interaction",
                        {"video_id": "v3", "play_time_ms": 800, "is_like": False, "exposure": "random"},
                        bearer("tok-u1"))
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["exposure"], "normal")

    def test_spoofed_user_id_is_rejected(self):
        res = self.post("/api/v1/interaction", {"user_id": "u1", "video_id": "v2"}, bearer("tok-u0"))
        self.assertEqual(res.status_code, 403)

    def test_invalid_and_malformed_tokens_are_rejected(self):
        self.assertEqual(self.post("/api/v1/recommend", {"k": 3}, bearer("forged")).status_code, 401)
        self.assertEqual(self.post("/api/v1/recommend", {"k": 3}, {"Authorization": "Basic abc"}).status_code, 401)

    def test_verifier_outage_is_503_not_401(self):
        self.assertEqual(self.post("/api/v1/recommend", {"k": 3}, bearer("tok-down")).status_code, 503)

    def test_recommend_without_token_serves_guest(self):
        body = self.post("/api/v1/recommend", {"user_id": "u0", "k": 3}).json()
        self.assertEqual((body["user_id"], body["model_used"], body["is_cold_start"]),
                         ("guest", "popularity", True))

    def test_recommend_with_token_is_personalised(self):
        body = self.post("/api/v1/recommend", {"k": 3}, bearer("tok-u0")).json()
        self.assertEqual((body["user_id"], body["model_used"], body["is_cold_start"]), ("u0", "conalign", False))

    def test_sync_requires_admin_key(self):
        self.assertEqual(self.client.post("/api/v1/sync").status_code, 403)
        self.assertEqual(self.client.post("/api/v1/sync", headers={"X-Admin-Key": "nope"}).status_code, 403)
        self.assertEqual(self.client.post("/api/v1/sync", headers={"X-Admin-Key": "admin-secret"}).status_code, 200)

    def test_sync_disabled_without_configured_key(self):
        client = TestClient(create_app(self.engine, auth=ApiAuth("firebase", fake_verify)))
        self.assertEqual(client.post("/api/v1/sync", headers={"X-Admin-Key": ""}).status_code, 403)

    def test_unknown_auth_mode_fails_fast(self):
        with self.assertRaises(ValueError):
            ApiAuth("none")


class FirebaseVerifierTests(unittest.TestCase):
    ISS = "https://securetoken.google.com/proj"

    def claims(self, **overrides):
        return {"iss": self.ISS, "sub": "uid-1", "aud": "proj", "exp": time.time() + 3600, **overrides}

    def test_valid_token_is_cached_until_expiry(self):
        verifier = FirebaseTokenVerifier("proj")
        with mock.patch("google.oauth2.id_token.verify_firebase_token", return_value=self.claims()) as verify:
            self.assertEqual(verifier("t"), "uid-1")
            self.assertEqual(verifier("t"), "uid-1")
        self.assertEqual(verify.call_count, 1)
        self.assertEqual(verify.call_args.kwargs["audience"], "proj")

    def test_token_from_other_issuer_is_rejected(self):
        verifier = FirebaseTokenVerifier("proj")
        with mock.patch("google.oauth2.id_token.verify_firebase_token",
                        return_value=self.claims(iss="https://accounts.google.com")):
            with self.assertRaises(TokenRejected):
                verifier("t")

    def test_bad_signature_is_rejected(self):
        verifier = FirebaseTokenVerifier("proj")
        with mock.patch("google.oauth2.id_token.verify_firebase_token", side_effect=ValueError("sig")):
            with self.assertRaises(TokenRejected):
                verifier("t")

    def test_cert_download_failure_is_unavailable(self):
        from google.auth.exceptions import TransportError
        verifier = FirebaseTokenVerifier("proj")
        with mock.patch("google.oauth2.id_token.verify_firebase_token", side_effect=TransportError("dns")):
            with self.assertRaises(VerifierUnavailable):
                verifier("t")


class RandomExposureTests(unittest.TestCase):
    def test_explore_marks_random_items(self):
        engine = make_engine(random_rate=1.0, random_seed=0)
        recs, _, _, _ = engine.recommend("u0", k=3, explore=True)
        self.assertEqual([r["exposure"] for r in recs], ["random"] * 3)
        self.assertTrue(all(r["model"] == "random" and r["score"] is None for r in recs))
        self.assertEqual(len({r["videoId"] for r in recs}), 3)
        self.assertTrue(all(("u0", r["videoId"]) in engine.random_served for r in recs))

    def test_served_random_interaction_goes_to_random_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            rlog = InteractionLog(Path(tmp) / "random.csv")
            engine = make_engine(random_rate=1.0, random_seed=0, random_log=rlog, retrain_every=0)
            vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
            out = engine.log_interaction("u0", vid, 800, False, exposure="random")
            self.assertEqual(out["exposure"], "random")
            self.assertEqual(len(engine.pending_random), 1)
            self.assertEqual(engine.pending_random[0]["label"], 0.0)
            self.assertEqual(engine.pending_random[0]["source"], "api_random")
            self.assertEqual(engine.pending, [])
            self.assertEqual(len(pd.read_csv(rlog.path)), 1)

    def test_unserved_random_claim_is_recorded_as_normal(self):
        engine = make_engine(random_rate=0.0, retrain_every=0)
        out = engine.log_interaction("u0", "v3", 800, False, exposure="random")
        self.assertEqual(out["exposure"], "normal")
        self.assertEqual(engine.pending_random, [])
        self.assertEqual(len(engine.pending), 1)

    def test_expired_random_claim_is_recorded_as_normal(self):
        engine = make_engine(random_rate=1.0, random_seed=0, retrain_every=0)
        vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
        engine.random_served[("u0", vid)] -= RANDOM_SERVED_TTL + 10
        out = engine.log_interaction("u0", vid, 800, False, exposure="random")
        self.assertEqual(out["exposure"], "normal")
        self.assertEqual(engine.pending_random, [])

    def test_normal_flag_on_served_item_stays_normal(self):
        engine = make_engine(random_rate=1.0, random_seed=0, retrain_every=0)
        vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
        out = engine.log_interaction("u0", vid, 800, False)
        self.assertEqual(out["exposure"], "normal")
        self.assertEqual(engine.pending_random, [])

    def test_refresh_cuts_pending_random_when_log_configured(self):
        with tempfile.TemporaryDirectory() as tmp:
            rlog = InteractionLog(Path(tmp) / "random.csv")
            engine = make_engine(random_rate=1.0, random_seed=0, random_log=rlog,
                                 interaction_log=InteractionLog(Path(tmp) / "log.csv"), retrain_every=0)
            vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
            engine.log_interaction("u0", vid, 800, False, exposure="random")
            engine.refresh()
            self.assertEqual(engine.pending_random, [])

    def test_refresh_cut_of_pending_random_follows_random_log(self):
        # Chỉ có random_log (không có interaction_log): lượt ngẫu nhiên đã ghi file nên được cắt.
        with tempfile.TemporaryDirectory() as tmp:
            rlog = InteractionLog(Path(tmp) / "random.csv")
            engine = make_engine(random_rate=1.0, random_seed=0, random_log=rlog, retrain_every=0)
            vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
            engine.log_interaction("u0", vid, 800, False, exposure="random")
            engine.log_interaction("u0", "v5", 800, False)
            engine.refresh()
            self.assertEqual(engine.pending_random, [])
            self.assertEqual(len(engine.pending), 1)

    def test_no_explore_keeps_model_ranking(self):
        engine = make_engine(random_rate=1.0, random_seed=0)
        recs, _, _, _ = engine.recommend("u0", k=3)
        self.assertEqual({r["exposure"] for r in recs}, {"normal"})
        self.assertEqual(engine.random_served, {})

    def test_guest_and_empty_pool_get_no_random_items(self):
        engine = make_engine(random_rate=1.0, random_seed=0)
        guest, _, _, _ = engine.recommend("guest", k=3, explore=True)
        self.assertEqual({r["exposure"] for r in guest}, {"normal"})
        allv = ["v0", "v1", "v2", "v3", "v4", "v5"]
        recs, _, _, _ = engine.recommend("u0", k=3, explore=True, exclude_video_ids=allv)
        self.assertEqual(len(recs), 3)
        self.assertEqual(len({r["videoId"] for r in recs}), 3)

    def test_http_recommend_explores(self):
        client = TestClient(create_app(engine=make_engine(random_rate=1.0, random_seed=0),
                                       auth=ApiAuth("off")))
        body = client.post("/api/v1/recommend", json={"user_id": "u0", "k": 2}).json()
        self.assertEqual({r["exposure"] for r in body["recommendations"]}, {"random"})


LIKED = {"u0": "v0 v1 v2", "u1": "v3 v4 v5", "u2": "v0 v1", "u3": "v4 v5"}


def make_random_snapshot(n_random):
    """Thêm log ngẫu nhiên: duyệt u0..u3, v0..v5; nhãn 1 nếu video thuộc nhóm thích của user."""
    snap = make_snapshot()
    rows = []
    for user in ("u0", "u1", "u2", "u3"):
        for j in range(6):
            vid = f"v{j}"
            liked = vid in LIKED[user].split()
            rows.append({"user_id": user, "video_id": vid, "label": 1.0 if liked else 0.0,
                         "play_time_ms": 9000 if liked else 800, "is_like": liked, "source": "api_random"})
    snap.random_interactions = pd.DataFrame(rows[:n_random], columns=INTERACTION_COLUMNS)
    return snap


def cluster_rows(n_users, source, invert=False, prefix="u"):
    """Hai cụm: user chẵn thích v0-v2, user lẻ thích v3-v5; mỗi user có đủ 6 video."""
    rows = []
    for k in range(n_users):
        for j in range(6):
            liked = (j < 3) == (k % 2 == 0)
            liked = liked != invert
            rows.append({"user_id": f"{prefix}{k}", "video_id": f"v{j}", "label": 1.0 if liked else 0.0,
                         "play_time_ms": 9000 if liked else 800, "is_like": liked, "source": source})
    return pd.DataFrame(rows, columns=INTERACTION_COLUMNS)


def make_cluster_snapshot(invert_random=False, random_only_users=0):
    """Log thường và log ngẫu nhiên cùng cấu trúc cụm nên cặp validation dự đoán được từ train.

    invert_random=True đảo nhãn log ngẫu nhiên: validation xếp ngược với sở thích đã học.
    """
    snap = make_snapshot()
    snap.interactions = cluster_rows(12, "test")
    random = cluster_rows(12, "api_random", invert=invert_random)
    if random_only_users:
        random = pd.concat([random, cluster_rows(random_only_users, "api_random", prefix="r")],
                           ignore_index=True)
    snap.random_interactions = random
    return snap


class RandomTrainingTests(unittest.TestCase):
    def test_enough_random_log_trains_author_conalign(self):
        engine = RecEngine(make_cluster_snapshot, epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "random_log")
        self.assertEqual(engine.training_stats["random_interactions"], 72)
        info = engine.training_stats["conalign_random"]
        self.assertEqual(info["implementation"], "conalign_author_port")
        self.assertGreater(info["stage2_best_val_auc"], 0.5)
        self.assertNotIn("skipped", info)
        self.assertEqual(engine.training_stats["conalign_random"]["config"], "coat")
        self.assertEqual(engine.models["conalign"].user_latent_unbiased.embedding_dim, 10)
        recs, used, _, _ = engine.recommend("u0", k=3, model="conalign")
        self.assertEqual(used, "conalign")
        self.assertEqual(len(recs), 3)

    def test_unlearnable_random_log_falls_back_to_proxy(self):
        engine = RecEngine(lambda: make_cluster_snapshot(invert_random=True), epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "item_frequency_proxy")
        info = engine.training_stats["conalign_random"]
        self.assertEqual(info["skipped"], "val_auc<=0.5")
        self.assertLessEqual(info["stage2_best_val_auc"], 0.5)
        self.assertEqual(engine.models["conalign"].user_latent_unbiased.embedding_dim, engine.embedding_dim)

    def test_random_only_user_served_by_random_log_conalign_only(self):
        engine = RecEngine(lambda: make_cluster_snapshot(random_only_users=2), epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "random_log")
        self.assertEqual(engine.training_stats["users_with_history"], 12)
        _, used, cold, _ = engine.recommend("r0", k=3, model="conalign")
        self.assertEqual((used, cold), ("conalign", False))
        _, used, cold, reason = engine.recommend("r0", k=3, model="mf")
        self.assertEqual((used, cold), ("popularity", True))
        self.assertEqual(reason, "User chưa có lịch sử tương tác (cold-start).")

    def test_small_random_log_falls_back_to_proxy(self):
        engine = RecEngine(lambda: make_random_snapshot(4), epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "item_frequency_proxy")
        self.assertEqual(engine.training_stats["random_interactions"], 4)
        self.assertIn("conalign", engine.models)

    def test_unsplittable_random_log_falls_back_to_proxy(self):
        # 4 dòng nhãn 1,1,1,0: nhãn 0 chỉ có một dòng nên không chia được train/validation.
        engine = RecEngine(lambda: make_random_snapshot(4), epochs=50, min_interactions=5,
                           min_random_interactions=4)
        self.assertEqual(engine.training_stats["conalign_mode"], "item_frequency_proxy")
        self.assertIn("skipped", engine.training_stats["conalign_random"])

    def test_no_normal_data_means_no_conalign_mode(self):
        engine = RecEngine(lambda: make_random_snapshot(24), epochs=50, min_interactions=1000,
                           min_random_interactions=12)
        self.assertIsNone(engine.training_stats["conalign_mode"])
        self.assertEqual(engine.models, {})

    def test_retrain_counts_pending_random(self):
        engine = RecEngine(lambda: make_random_snapshot(4), epochs=50, min_interactions=5,
                           min_random_interactions=12, random_rate=1.0, random_seed=0,
                           retrain_every=1, background_retrain=False)
        vid = next(r["videoId"] for r in engine.recommend("u3", k=3, explore=True)[0])
        out = engine.log_interaction("u3", vid, 800, False, exposure="random")
        self.assertEqual(out["exposure"], "random")
        self.assertTrue(out["retrain_started"])
        self.assertEqual(engine.training_stats["random_interactions"], 5)

    def test_random_only_user_is_cold_in_proxy_mode(self):
        def loader():
            snap = make_random_snapshot(4)
            extra = pd.DataFrame([{"user_id": "u9", "video_id": "v0", "label": 1.0, "play_time_ms": 9000,
                                   "is_like": True, "source": "api_random"}], columns=INTERACTION_COLUMNS)
            snap.random_interactions = pd.concat([snap.random_interactions, extra], ignore_index=True)
            return snap
        engine = RecEngine(loader, epochs=50, min_interactions=5, min_random_interactions=12)
        self.assertIn("u9", engine.u2idx)
        self.assertEqual(engine.training_stats["conalign_mode"], "item_frequency_proxy")
        self.assertEqual(engine.training_stats["users_with_history"], 4)
        for model in ("conalign", "mf", "cdr"):
            _, used, cold, reason = engine.recommend("u9", k=3, model=model)
            self.assertEqual((used, cold), ("popularity", True))
            self.assertEqual(reason, "User chưa có lịch sử tương tác (cold-start).")

    def test_split_without_both_labels_returns_none(self):
        snap = make_snapshot()
        frame = snap.interactions
        u2idx = {u: k for k, u in enumerate(sorted(frame["user_id"].unique()))}
        i2idx = {v: k for k, v in enumerate(snap.videos)}
        biased = (torch.tensor(frame["user_id"].map(u2idx).to_numpy()),
                  torch.tensor(frame["video_id"].map(i2idx).to_numpy()),
                  torch.tensor(frame["label"].to_numpy(), dtype=torch.float32))
        random_all_positive = (torch.tensor([0, 0, 1, 1, 2, 3]), torch.tensor([0, 1, 3, 4, 0, 4]),
                               torch.ones(6))
        self.assertIsNone(fit_conalign_with_random_log(biased, random_all_positive, 4, 8, seed=42))

    def test_env_reads_min_random(self):
        from src.api import app as app_module
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict("os.environ", {
                "RECSYS_MIN_RANDOM": "7", "RECSYS_DATA_SOURCE": "export",
                "RECSYS_INTERACTION_LOG": str(Path(tmp) / "log.csv"),
                "RECSYS_RANDOM_LOG": str(Path(tmp) / "random.csv")}), \
                mock.patch("src.api.service.RecEngine.refresh"):
            engine = app_module.build_engine_from_env()
        self.assertEqual(engine.min_random_interactions, 7)


if __name__ == "__main__":
    unittest.main()
