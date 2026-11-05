# -*- coding: utf-8 -*-
"""
FastAPI RecSys API cho app TopTop.

Chạy cục bộ (từ thư mục services/recsys):
    venv\\Scripts\\python.exe -m uvicorn src.api.app:app --port 8000

Biến môi trường:
    RECSYS_DATA_SOURCE      auto | live | export   (mặc định auto)
    RECSYS_EXPORT_DIR       thư mục chứa toptop_interactions.csv (mặc định data/firebase_export ở gốc repo)
    RECSYS_INTERACTION_LOG  CSV ghi nối tương tác từ app (mặc định data/api/interactions_log.csv)
Project: ViFarm (services/recsys)
"""

import os
from functools import partial
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from src.api.firebase_bridge import InteractionLog, load_snapshot
from src.api.schemas import CompareRequest, InteractionRequest, RecommendRequest, RecommendResponse
from src.api.service import RecEngine

PROJECT_ROOT = Path(__file__).resolve().parents[2]


def build_engine_from_env():
    export_dir = Path(os.environ.get("RECSYS_EXPORT_DIR", PROJECT_ROOT.parents[1] / "data" / "firebase_export"))
    log_path = Path(os.environ.get("RECSYS_INTERACTION_LOG", PROJECT_ROOT / "data" / "api" / "interactions_log.csv"))
    loader = partial(load_snapshot, source=os.environ.get("RECSYS_DATA_SOURCE", "auto"),
                     export_dir=export_dir if export_dir.exists() else None, interaction_log=log_path)
    return RecEngine(loader, interaction_log=InteractionLog(log_path))


def create_app(engine=None):
    app = FastAPI(title="TopTop RecSys API", version="2.0.0",
                  description="Gợi ý video TopTop bằng ConAlign (RecSys 2026) / DR-BIAS+CDR / MF huấn luyện trên tương tác thật.")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    state = {"engine": engine}

    def get_engine():
        if state["engine"] is None:
            state["engine"] = build_engine_from_env()
        return state["engine"]

    @app.get("/")
    def root():
        return {"service": "TopTop RecSys API", "docs": "/docs", "health": "/health"}

    @app.get("/health")
    def health():
        return get_engine().health()

    @app.post("/api/v1/recommend", response_model=RecommendResponse)
    def recommend(req: RecommendRequest):
        recs, used, cold, reason = get_engine().recommend(
            req.user_id, k=req.k, model=req.model, filter_rejected=req.filter_rejected,
            exclude_video_ids=req.exclude_video_ids)
        return RecommendResponse(user_id=req.user_id, model_requested=req.model, model_used=used,
                                 is_cold_start=cold, fallback_reason=reason, recommendations=recs)

    @app.post("/api/v1/interaction")
    def interaction(req: InteractionRequest):
        return get_engine().log_interaction(req.user_id, req.video_id, req.play_time_ms, req.is_like)

    @app.post("/api/v1/compare")
    def compare(req: CompareRequest):
        engine = get_engine()
        out = {}
        for name in engine.health()["models_available"]:
            recs, used, cold, reason = engine.recommend(req.user_id, k=req.k, model=name,
                                                        filter_rejected=req.filter_rejected)
            out[name] = {"model_used": used, "is_cold_start": cold, "fallback_reason": reason,
                         "video_ids": [r["videoId"] for r in recs],
                         "scores": [r["score"] for r in recs]}
        return {"user_id": req.user_id, "results": out}

    @app.get("/api/v1/items/popular")
    def popular(k: int = 10):
        recs, _, _, _ = get_engine().recommend("__popular__", k=k, model="popularity")
        return {"recommendations": recs}

    @app.post("/api/v1/sync")
    def sync():
        engine = get_engine()
        engine.refresh()
        return engine.health()

    return app


app = create_app()
