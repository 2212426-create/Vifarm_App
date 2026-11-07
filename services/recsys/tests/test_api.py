"""RecSys API: dữ liệu giả nhỏ, không gọi mạng."""
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

import pandas as pd
from fastapi.testclient import TestClient

from src.api.app import create_app
from src.api.auth import ApiAuth, FirebaseTokenVerifier, TokenRejected, VerifierUnavailable
from src.api.firebase_bridge import (INTERACTION_COLUMNS, InteractionLog, Snapshot,
                                     behavior_label, likes_from_notifications,
                                     load_snapshot, normalize_video, parse_fs_value,
                                     unique_username_map)
from src.api.service import RecEngine


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


if __name__ == "__main__":
    unittest.main()
