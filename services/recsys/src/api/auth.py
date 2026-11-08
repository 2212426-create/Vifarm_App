# -*- coding: utf-8 -*-
"""
Xác thực cho RecSys API.

RECSYS_AUTH_MODE
    firebase (mặc định)  App gửi `Authorization: Bearer <Firebase ID token>`. user_id được lấy
                         từ token, không tin user_id trong body. /interaction bắt buộc token;
                         /recommend và /compare không có token thì phục vụ như khách (popularity).
    off                  Tin user_id trong body. Chỉ dùng khi chạy cục bộ hoặc kiểm thử.
RECSYS_ADMIN_KEY         Header `X-Admin-Key` cho /api/v1/sync. Không đặt thì /sync bị tắt,
                         trừ khi RECSYS_AUTH_MODE=off.
TOPTOP_FIREBASE_PROJECT  Project Firebase dùng để kiểm tra `aud`/`iss` của token.
Project: ViFarm (services/recsys)
"""

import hmac
import os
import threading
import time
from typing import Callable, Optional

from fastapi import HTTPException

from src.api.firebase_bridge import PROJECT_ID

GUEST = "guest"
AUTH_MODES = ("firebase", "off")


class TokenRejected(Exception):
    """Token sai chữ ký, hết hạn hoặc không thuộc project."""


class VerifierUnavailable(Exception):
    """Không kiểm tra được token (thiếu thư viện hoặc không tải được khóa công khai của Google)."""


class FirebaseTokenVerifier:
    """Kiểm tra Firebase ID token bằng khóa công khai của Google, có cache theo thời hạn token.

    Mỗi token hợp lệ chỉ cần tải khóa một lần; các lần gọi sau trong vòng đời token (~1 giờ)
    trả uid từ cache.
    """

    def __init__(self, project_id, max_cache=10_000):
        self.project_id = project_id
        self.max_cache = max_cache
        self._cache = {}
        self._lock = threading.Lock()
        self._request = None

    def __call__(self, token):
        now = time.time()
        with self._lock:
            hit = self._cache.get(token)
        if hit and hit[1] > now:
            return hit[0]
        try:
            from google.auth import exceptions as google_exceptions
            from google.auth.transport import requests as google_requests
            from google.oauth2 import id_token
        except ImportError as exc:
            raise VerifierUnavailable("Server thiếu thư viện google-auth/requests.") from exc
        if self._request is None:
            self._request = google_requests.Request()
        try:
            claims = id_token.verify_firebase_token(token, self._request, audience=self.project_id,
                                                    clock_skew_in_seconds=10)
        except google_exceptions.TransportError as exc:
            raise VerifierUnavailable("Không tải được khóa công khai của Google.") from exc
        except (ValueError, google_exceptions.GoogleAuthError) as exc:
            raise TokenRejected(str(exc)) from exc
        if claims.get("iss") != f"https://securetoken.google.com/{self.project_id}":
            raise TokenRejected("Token không do Firebase Auth của project này cấp.")
        uid = claims.get("sub")
        if not uid:
            raise TokenRejected("Token không có uid.")
        with self._lock:
            if len(self._cache) >= self.max_cache:
                self._cache = {k: v for k, v in self._cache.items() if v[1] > now}
                if len(self._cache) >= self.max_cache:
                    self._cache.clear()
            self._cache[token] = (uid, float(claims.get("exp", now)))
        return uid


def _bearer(authorization):
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="Header Authorization phải có dạng 'Bearer <token>'.")
    return token.strip()


class ApiAuth:
    def __init__(self, mode="firebase", verify: Optional[Callable[[str], str]] = None,
                 admin_key: Optional[str] = None):
        if mode not in AUTH_MODES:
            raise ValueError(f"RECSYS_AUTH_MODE phải là một trong {AUTH_MODES}, nhận '{mode}'.")
        self.mode = mode
        self.verify = verify
        self.admin_key = admin_key or None
        if mode == "firebase" and verify is None:
            raise ValueError("Chế độ firebase cần hàm kiểm tra token.")

    @classmethod
    def from_env(cls):
        mode = os.environ.get("RECSYS_AUTH_MODE", "firebase").strip().lower()
        project = os.environ.get("TOPTOP_FIREBASE_PROJECT", PROJECT_ID)
        verify = FirebaseTokenVerifier(project) if mode == "firebase" else None
        return cls(mode, verify, os.environ.get("RECSYS_ADMIN_KEY", "").strip())

    def user_id(self, authorization, claimed, required):
        """uid của người gọi. Ở chế độ off trả về user_id trong body."""
        if self.mode == "off":
            return claimed
        token = _bearer(authorization)
        if token is None:
            if required:
                raise HTTPException(status_code=401,
                                    detail="Cần đăng nhập: gửi Authorization: Bearer <Firebase ID token>.")
            return GUEST
        try:
            uid = self.verify(token)
        except TokenRejected:
            raise HTTPException(status_code=401, detail="Firebase ID token không hợp lệ hoặc đã hết hạn.") from None
        except VerifierUnavailable as exc:
            raise HTTPException(status_code=503, detail=str(exc)) from exc
        if claimed not in (None, "", GUEST, uid):
            raise HTTPException(status_code=403, detail="user_id không khớp với tài khoản đăng nhập.")
        return uid

    def require_admin(self, key):
        if self.admin_key is None:
            if self.mode == "off":
                return
            raise HTTPException(status_code=403, detail="/sync bị tắt: đặt RECSYS_ADMIN_KEY trên server.")
        if not key or not hmac.compare_digest(key.encode(), self.admin_key.encode()):
            raise HTTPException(status_code=403, detail="X-Admin-Key không đúng.")
