# -*- coding: utf-8 -*-
"""
Hợp đồng JSON giữa RecSys API và app TopTop
(apps/mobile-flutter/lib/features/video_feed/services/recsys_service.dart).
Project: ViFarm (services/recsys)
"""

from typing import List, Optional

from pydantic import BaseModel, Field


class RecommendRequest(BaseModel):
    user_id: str = "guest"
    k: int = Field(default=10, ge=1, le=100)
    model: str = "conalign"
    filter_rejected: bool = True
    exclude_video_ids: List[str] = Field(default_factory=list)


class InteractionRequest(BaseModel):
    user_id: str = "guest"
    video_id: str
    play_time_ms: int = Field(default=0, ge=0)
    is_like: bool = False


class CompareRequest(BaseModel):
    user_id: str = "guest"
    k: int = Field(default=10, ge=1, le=100)
    filter_rejected: bool = True


class RecommendResponse(BaseModel):
    user_id: str
    model_requested: str
    model_used: str
    is_cold_start: bool
    fallback_reason: Optional[str] = None
    # Mỗi phần tử giữ nguyên trường camelCase của Firestore để VideoModel.fromMap đọc trực tiếp.
    recommendations: List[dict]
