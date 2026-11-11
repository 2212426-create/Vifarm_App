# -*- coding: utf-8 -*-
"""
FastAPI RecSys & Weather API cho app ViFarm / TopTop.

Chạy cục bộ (từ thư mục services/recsys):
    python -m uvicorn src.api.app:app --port 8000

Biến môi trường:
    AGROMONITORING_API_KEY  Secret API key cho AgroMonitoring
    RECSYS_DATA_SOURCE      auto | live | export   (mặc định auto)
    RECSYS_EXPORT_DIR       thư mục chứa toptop_interactions.csv (mặc định data/firebase_export ở gốc repo)
    RECSYS_INTERACTION_LOG  CSV ghi nối tương tác từ app (mặc định data/api/interactions_log.csv)
    RECSYS_AUTH_MODE        firebase (mặc định) | off — xem src/api/auth.py
    RECSYS_ADMIN_KEY        khóa X-Admin-Key cho /api/v1/sync
Project: ViFarm (services/recsys)
"""

import json
import logging
import os
import urllib.error
import urllib.request
from functools import partial
from pathlib import Path

from typing import Optional

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from src.api.auth import ApiAuth
from src.api.firebase_bridge import InteractionLog, load_snapshot
from src.api.schemas import CompareRequest, InteractionRequest, RecommendRequest, RecommendResponse

logger = logging.getLogger(__name__)

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def build_engine_from_env():
    try:
        from src.api.service import RecEngine
        export_dir = Path(os.environ.get("RECSYS_EXPORT_DIR", PROJECT_ROOT.parents[1] / "data" / "firebase_export"))
        log_path = Path(os.environ.get("RECSYS_INTERACTION_LOG", PROJECT_ROOT / "data" / "api" / "interactions_log.csv"))
        loader = partial(load_snapshot, source=os.environ.get("RECSYS_DATA_SOURCE", "auto"),
                         export_dir=export_dir if export_dir.exists() else None, interaction_log=log_path)
        return RecEngine(loader, interaction_log=InteractionLog(log_path))
    except Exception as e:
        err_msg = str(e)
        logger.warning("RecEngine build skipped/failed: %s", err_msg)
        class DummyEngine:
            def health(self):
                return {"status": "recsys_disabled", "models_available": [], "reason": err_msg}
            def recommend(self, *args, **kwargs):
                return [], "fallback", True, err_msg
            def log_interaction(self, *args, **kwargs):
                return {"status": "logged_fallback"}
            def refresh(self):
                pass
        return DummyEngine()


def create_app(engine=None, auth=None):
    auth = auth or ApiAuth.from_env()
    app = FastAPI(title="ViFarm API Server", version="2.0.0",
                  description="Backend API cung cấp RecSys (ConAlign / DR-BIAS+CDR / MF) và Weather Proxy cho ViFarm.")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=False,  # API không dùng cookie; xác thực bằng Bearer token
        allow_methods=["GET", "POST"],
        allow_headers=["Authorization", "Content-Type", "X-Admin-Key"],
    )
    state = {"engine": engine}

    def get_engine():
        if state["engine"] is None:
            state["engine"] = build_engine_from_env()
        return state["engine"]

    @app.get("/")
    def root():
        return {"service": "ViFarm API Server", "docs": "/docs", "health": "/health"}

    @app.get("/health")
    def health():
        return get_engine().health()

    @app.get("/api/v1/weather")
    def weather(lat: float, lon: float):
        if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
            raise HTTPException(status_code=400, detail="Tọa độ lat/lon không hợp lệ.")

        api_key = os.environ.get("AGROMONITORING_API_KEY", "").strip()
        if not api_key:
            return JSONResponse(
                status_code=401,
                content={
                    "error": "Chưa cấu hình AGROMONITORING_API_KEY trên server backend",
                    "code": "MISSING_KEY",
                },
            )

        # AgroMonitoring chỉ nhận key qua query string: không log URL này hoặc exception chứa nó.
        url = f"https://api.agromonitoring.com/agro/1.0/weather?lat={lat}&lon={lon}&appid={api_key}"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ViFarm/1.0"})
            with urllib.request.urlopen(req, timeout=10) as response:
                body = response.read().decode("utf-8")
                data = json.loads(body)
                return data
        except urllib.error.HTTPError as e:
            if e.code == 401:
                return JSONResponse(
                    status_code=401,
                    content={
                        "error": "API key AgroMonitoring không hợp lệ hoặc chưa được kích hoạt (HTTP 401)",
                        "code": "UNAUTHORIZED",
                    },
                )
            elif e.code == 429:
                return JSONResponse(
                    status_code=429,
                    content={
                        "error": "Hạn mức API AgroMonitoring đã vượt quá limit",
                        "code": "RATE_LIMITED",
                    },
                )
            else:
                return JSONResponse(
                    status_code=e.code,
                    content={
                        "error": f"Lỗi từ dịch vụ thời tiết AgroMonitoring ({e.code})",
                        "code": "SERVICE_ERROR",
                    },
                )
        except Exception:
            return JSONResponse(
                status_code=500,
                content={
                    "error": "Không thể kết nối đến AgroMonitoring API",
                    "code": "CONNECTION_ERROR",
                },
            )

    @app.post("/api/v1/recommend", response_model=RecommendResponse)
    def recommend(req: RecommendRequest, authorization: Optional[str] = Header(default=None)):
        user_id = auth.user_id(authorization, req.user_id, required=False)
        recs, used, cold, reason = get_engine().recommend(
            user_id, k=req.k, model=req.model, filter_rejected=req.filter_rejected,
            exclude_video_ids=req.exclude_video_ids)
        return RecommendResponse(user_id=user_id, model_requested=req.model, model_used=used,
                                 is_cold_start=cold, fallback_reason=reason, recommendations=recs)

    @app.post("/api/v1/interaction")
    def interaction(req: InteractionRequest, authorization: Optional[str] = Header(default=None)):
        user_id = auth.user_id(authorization, req.user_id, required=True)
        return get_engine().log_interaction(user_id, req.video_id, req.play_time_ms, req.is_like)

    @app.post("/api/v1/compare")
    def compare(req: CompareRequest, authorization: Optional[str] = Header(default=None)):
        user_id = auth.user_id(authorization, req.user_id, required=False)
        engine = get_engine()
        out = {}
        for name in engine.health()["models_available"]:
            recs, used, cold, reason = engine.recommend(user_id, k=req.k, model=name,
                                                        filter_rejected=req.filter_rejected)
            out[name] = {"model_used": used, "is_cold_start": cold, "fallback_reason": reason,
                         "video_ids": [r["videoId"] for r in recs],
                         "scores": [r["score"] for r in recs]}
        return {"user_id": user_id, "results": out}

    @app.get("/api/v1/items/popular")
    def popular(k: int = 10):
        recs, _, _, _ = get_engine().recommend("__popular__", k=k, model="popularity")
        return {"recommendations": recs}

    @app.post("/api/v1/sync")
    def sync(x_admin_key: Optional[str] = Header(default=None)):
        auth.require_admin(x_admin_key)
        engine = get_engine()
        engine.refresh()
        return engine.health()

    return app


app = create_app()
