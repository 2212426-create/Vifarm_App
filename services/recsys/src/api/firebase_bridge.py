# -*- coding: utf-8 -*-
"""
Nạp dữ liệu TopTop cho RecSys API: video/user từ Firestore, tương tác từ file
export (data/firebase_export/toptop_interactions.csv), lượt like trong RTDB và
nhật ký tương tác do chính API ghi nhận.

Nhãn hành vi video ngắn: y = 1  <=>  is_like  hoặc  play_time_ms >= 3000.
Project: ViFarm (services/recsys)
"""

import csv
import json
import os
import threading
import time
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path

import pandas as pd

PROJECT_ID = os.environ.get("TOPTOP_FIREBASE_PROJECT", "mytiktokclone-f9789")
RTDB_URL = os.environ.get("TOPTOP_RTDB_URL", f"https://{PROJECT_ID}-default-rtdb.firebaseio.com/")
FIRESTORE_URL = f"https://firestore.googleapis.com/v1/projects/{PROJECT_ID}/databases/(default)/documents"
POSITIVE_PLAY_MS = 3000
INTERACTION_COLUMNS = ["user_id", "video_id", "label", "play_time_ms", "is_like", "source"]


def behavior_label(is_like, play_time_ms):
    return 1.0 if bool(is_like) or int(play_time_ms) >= POSITIVE_PLAY_MS else 0.0


# =============================================================================
# 1. TRUY CẬP FIREBASE QUA REST
# =============================================================================

def _http_json(url, method="GET", payload=None, timeout=10):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        body = res.read().decode("utf-8")
    return json.loads(body) if body else None


def parse_fs_value(value):
    """Chuyển một Firestore REST typed value sang giá trị Python."""
    if "stringValue" in value:
        return value["stringValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "doubleValue" in value:
        return float(value["doubleValue"])
    if "booleanValue" in value:
        return bool(value["booleanValue"])
    if "timestampValue" in value:
        return value["timestampValue"]
    if "arrayValue" in value:
        return [parse_fs_value(v) for v in value["arrayValue"].get("values", [])]
    if "mapValue" in value:
        return {k: parse_fs_value(v) for k, v in value["mapValue"].get("fields", {}).items()}
    return None


def fetch_firestore_collection(name, page_size=300):
    """Đọc toàn bộ collection, đi theo nextPageToken."""
    docs, token = [], None
    while True:
        url = f"{FIRESTORE_URL}/{name}?pageSize={page_size}"
        if token:
            url += f"&pageToken={token}"
        res = _http_json(url) or {}
        for doc in res.get("documents", []):
            item = {k: parse_fs_value(v) for k, v in doc.get("fields", {}).items()}
            item["_doc_id"] = doc.get("name", "").rsplit("/", 1)[-1]
            docs.append(item)
        token = res.get("nextPageToken")
        if not token:
            return docs


def fetch_rtdb(path):
    return _http_json(f"{RTDB_URL.rstrip('/')}/{path.strip('/')}.json")


def publish_server_url(url):
    """Ghi URL công khai vào server_config/recsys_url để app tự phát hiện."""
    return _http_json(f"{RTDB_URL.rstrip('/')}/server_config/recsys_url.json", method="PUT", payload=url)


# =============================================================================
# 2. CHUẨN HÓA DỮ LIỆU
# =============================================================================

def normalize_video(raw):
    """Đưa video về khóa camelCase mà VideoModel.fromMap của app đọc."""
    video = dict(raw)
    aliases = {"video_id": "videoId", "video_uri": "videoUri", "author_id": "authorId",
               "author_username": "username", "watch_count": "watchCount",
               "total_likes": "totalLikes", "total_comments": "totalComments",
               "moderation_status": "moderationStatus"}
    for snake, camel in aliases.items():
        if camel not in video and snake in video:
            video[camel] = video[snake]
    video["videoId"] = str(video.get("videoId") or video.get("_doc_id") or "")
    for key in ("watchCount", "totalLikes", "totalComments"):
        try:
            video[key] = int(video.get(key) or 0)
        except (TypeError, ValueError):
            video[key] = 0
    video["moderationStatus"] = str(video.get("moderationStatus") or "pending").strip().lower()
    for key in ("videoUri", "authorId", "username", "description"):
        video[key] = str(video.get(key) or "")
    return video


def likes_from_notifications(notifications, username_to_uid):
    """Lượt like trong Notifications/{người nhận}. Người thích chỉ có fromUsername,
    nên chỉ giữ những username ánh xạ duy nhất tới một uid."""
    rows = []
    for items in (notifications or {}).values():
        if not isinstance(items, dict):
            continue
        for n in items.values():
            if not isinstance(n, dict) or str(n.get("action")) not in ("2", "like") or not n.get("videoId"):
                continue
            uid = username_to_uid.get(str(n.get("fromUsername") or ""))
            if uid:
                rows.append({"user_id": uid, "video_id": str(n["videoId"]), "label": 1.0,
                             "play_time_ms": 0, "is_like": True, "source": "rtdb_like"})
    return rows


def unique_username_map(users):
    seen = {}
    for u in users:
        name = str(u.get("username") or "")
        uid = str(u.get("uid") or u.get("userId") or u.get("_doc_id") or "")
        if name and uid:
            seen.setdefault(name, set()).add(uid)
    return {name: next(iter(uids)) for name, uids in seen.items() if len(uids) == 1}


def read_interactions_csv(path, source):
    path = Path(path)
    if not path.exists():
        return []
    frame = pd.read_csv(path, dtype={"user_id": str, "video_id": str})
    rows = []
    for r in frame.itertuples(index=False):
        play = int(getattr(r, "play_time_ms", 0) or 0)
        like = bool(int(getattr(r, "is_like", 0) or 0))
        rows.append({"user_id": r.user_id, "video_id": r.video_id, "label": behavior_label(like, play),
                     "play_time_ms": play, "is_like": like, "source": source})
    return rows


# =============================================================================
# 3. SNAPSHOT DỮ LIỆU
# =============================================================================

@dataclass
class Snapshot:
    videos: dict
    users: list
    interactions: pd.DataFrame
    source: str
    loaded_at: float = field(default_factory=time.time)


def _load_export_videos(export_dir):
    export_dir = Path(export_dir)
    fs_file = export_dir / "firestore_data.json"
    if fs_file.exists():
        data = json.loads(fs_file.read_text(encoding="utf-8"))
        return data.get("videos", []), data.get("users", [])
    bundle = export_dir / "toptop_processed_bundle.json"
    if bundle.exists():
        data = json.loads(bundle.read_text(encoding="utf-8"))
        users = [{"uid": u.get("user_id"), "username": u.get("username")} for u in data.get("users", [])]
        return data.get("videos", []), users
    return [], []


def load_snapshot(source="auto", export_dir=None, interaction_log=None):
    """source: 'live' (Firebase REST), 'export' (file cục bộ) hoặc 'auto' (live, lỗi thì export)."""
    if source not in ("auto", "live", "export"):
        raise ValueError("source must be auto, live or export")
    videos, users, used, rows = [], [], "export", []
    if source in ("auto", "live"):
        try:
            videos = fetch_firestore_collection("videos")
            users = fetch_firestore_collection("users")
            rows += likes_from_notifications(fetch_rtdb("Notifications"), unique_username_map(users))
            used = "live"
        except Exception:
            if source == "live":
                raise
            videos, users, rows = [], [], []
    if not videos and export_dir is not None:
        videos, users = _load_export_videos(export_dir)
        used = "export"
    if export_dir is not None:
        rows += read_interactions_csv(Path(export_dir) / "toptop_interactions.csv", "export_csv")
    if interaction_log is not None:
        rows += read_interactions_csv(interaction_log, "api_log")

    catalog = {}
    for raw in videos:
        video = normalize_video(raw)
        if video["videoId"]:
            catalog[video["videoId"]] = video
    frame = pd.DataFrame(rows, columns=INTERACTION_COLUMNS)
    frame = frame[frame["video_id"].isin(catalog)]
    # Cặp lặp được gộp: dương nếu có ít nhất một lần dương (cùng quy ước benchmark KuaiRand).
    frame = (frame.groupby(["user_id", "video_id"], as_index=False)
             .agg(label=("label", "max"), play_time_ms=("play_time_ms", "max"),
                  is_like=("is_like", "max"), source=("source", "first")))
    return Snapshot(videos=catalog, users=users, interactions=frame, source=used)


class InteractionLog:
    """Ghi nối tương tác nhận từ app vào CSV để lần huấn luyện sau dùng lại."""

    def __init__(self, path, max_bytes=10 * 1024 * 1024):
        self.path = Path(path)
        self.max_bytes = max_bytes
        self._lock = threading.Lock()

    def append(self, user_id, video_id, play_time_ms, is_like):
        with self._lock:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if self.path.exists() and self.path.stat().st_size > self.max_bytes:
                bak = self.path.with_suffix(".csv.bak")
                try:
                    if bak.exists():
                        bak.unlink()
                    self.path.rename(bak)
                except OSError:
                    pass
            new = not self.path.exists()
            with open(self.path, "a", newline="", encoding="utf-8") as f:
                writer = csv.writer(f)
                if new:
                    writer.writerow(["user_id", "video_id", "is_like", "play_time_ms", "timestamp"])
                writer.writerow([user_id, video_id, int(bool(is_like)), int(play_time_ms), int(time.time() * 1000)])
