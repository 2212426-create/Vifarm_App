# -*- coding: utf-8 -*-
"""
Recommendation engine phục vụ app TopTop.

MF uses MSE. CDR uses the released DR-BIAS+CDR architecture and update rule.
CDR has no random-exposure labels in serving: item-frequency propensity and replacement
catalog sampling are explicit adaptations in training_stats.cdr.
ConAlign: khi log hiển thị ngẫu nhiên đủ min_random_interactions dòng và có cả hai nhãn,
dịch vụ huấn luyện bằng port tác giả (train_conalign, cấu hình "coat"); nếu không, dùng
proxy trọng số tần suất video. training_stats.conalign_mode ghi cách đã dùng.
Popularity serves new users.
CLEV-DR được huấn luyện và đánh giá ở pha Offline Benchmark; phục vụ online
trực tiếp sử dụng ConAlign, MF, CDR hoặc Popularity fallback với lý do rõ ràng.

Huấn luyện lại không giữ khóa phục vụ: mô hình mới được huấn luyện trên bản sao dữ liệu
rồi hoán đổi nguyên khối, nên /recommend vẫn trả lời bằng mô hình cũ trong lúc train.
Project: ViFarm (services/recsys)
"""

import logging
import threading
import time

import numpy as np
import pandas as pd
import torch
import torch.nn.functional as F

from src.api.conalign_random import fit_conalign_with_random_log
from src.models.cdr.released import ReleasedCDR, fit_released
from src.models.conalign.model import DualTowerMF
from src.models.mf.matrix_factorization import MatrixFactorization
from src.utils.helpers import set_seed
from src.api.firebase_bridge import behavior_label

logger = logging.getLogger(__name__)

MIN_RANDOM_VAL_AUC = 0.5  # ConAlign log ngẫu nhiên chỉ được dùng khi AUC validation giai đoạn 2 vượt mức đoán ngẫu nhiên
RANDOM_SERVED_TTL = 24 * 3600  # giây: thời gian nhớ video đã phát ngẫu nhiên cho tới khi có tương tác
TRAINABLE_MODELS = ("conalign", "mf", "cdr")
UNSUPPORTED_MODELS = {
    "clev_dr": "CLEV-DR chưa được tích hợp vào engine phục vụ (huấn luyện offline mất khoảng 4.000–4.700 s mỗi lượt trên CPU); online phục vụ qua ConAlign/MF/CDR.",
}


def item_frequency_weights(i, n_items):
    """Proxy IPS khi không có log hiển thị ngẫu nhiên: 1/clamp(tần suất tương đối, .05, 1).

    Video ít lượt nhất nhận trọng số tối đa gấp 20 lần video phổ biến nhất. Đây là điều chỉnh
    phục vụ, không phải propensity ước lượng; video chưa có lượt nào không xuất hiện trong loss.
    """
    counts = torch.bincount(i, minlength=n_items).float()
    item_prop = torch.clamp(counts / (counts.max() + 1e-6), 0.05, 1.0)
    return 1.0 / item_prop[i]


class RecEngine:
    def __init__(self, snapshot_loader, interaction_log=None, models=TRAINABLE_MODELS,
                 embedding_dim=16, epochs=150, lr=0.01, weight_decay=1e-3,
                 seed=42, retrain_every=20, min_interactions=10, device=None,
                 background_retrain=True, random_rate=0.0, random_seed=None, random_log=None,
                 min_random_interactions=50):
        unknown = set(models) - set(TRAINABLE_MODELS)
        if unknown:
            raise ValueError(f"Unsupported models: {sorted(unknown)}")
        self.snapshot_loader = snapshot_loader
        self.interaction_log = interaction_log
        self.model_names = tuple(models)
        self.embedding_dim = embedding_dim
        self.epochs = epochs
        self.lr = lr
        self.weight_decay = weight_decay
        self.seed = seed
        self.retrain_every = retrain_every
        self.min_interactions = min_interactions
        self.min_random_interactions = min_random_interactions
        self.device = device or torch.device("cpu")
        self.background_retrain = background_retrain
        self.random_rate = float(random_rate)
        self.random_log = random_log
        self._rng = np.random.default_rng(random_seed)
        self.random_served = {}               # (user_id, video_id) -> thời điểm phát ngẫu nhiên (giây)
        self._lock = threading.RLock()        # bảo vệ trạng thái phục vụ; chỉ giữ trong thời gian ngắn
        self._train_lock = threading.Lock()   # mỗi thời điểm chỉ một lượt huấn luyện
        self._retrain_thread = None
        self._since_fit = 0
        self.last_retrain_error = None
        self.watched = {}
        self.pending = []
        self.pending_random = []              # lượt xem ngẫu nhiên đã chấp nhận, cùng khóa với pending
        self.models = {}
        self.training_stats = {}
        self.refresh()

    # ------------------------------------------------------------------ data
    def refresh(self):
        """Nạp lại dữ liệu Firebase/export và huấn luyện lại toàn bộ mô hình.

        Người gọi chờ huấn luyện xong, nhưng /recommend vẫn phục vụ bằng mô hình cũ.
        """
        with self._train_lock:
            with self._lock:
                # Tương tác trước mốc này đã ghi vào log trước khi snapshot được đọc.
                cut = len(self.pending)
                cut_random = len(self.pending_random)
                self._since_fit = 0
            snapshot = self.snapshot_loader()
            with self._lock:
                # Có log thì snapshot đã chứa phần pending cũ; cặp trùng được gộp bằng max.
                pending = self.pending[cut:] if self.interaction_log is not None else list(self.pending)
                # Lượt ngẫu nhiên được ghi bởi random_log nên mốc cắt của chúng theo random_log.
                pending_random = (self.pending_random[cut_random:] if self.random_log is not None
                                  else list(self.pending_random))
            state = self._train_state(snapshot, pending, pending_random)
            with self._lock:
                if self.interaction_log is not None:
                    self.pending = self.pending[cut:]
                if self.random_log is not None:
                    self.pending_random = self.pending_random[cut_random:]
                self._install(state)

    def _retrain(self):
        with self._train_lock:
            with self._lock:
                snapshot, pending = self.snapshot, list(self.pending)
                pending_random = list(self.pending_random)
                self._since_fit = 0
            state = self._train_state(snapshot, pending, pending_random)
            with self._lock:
                self._install(state)

    def _retrain_safely(self):
        try:
            self._retrain()
            self.last_retrain_error = None
        except Exception as exc:  # giữ mô hình cũ và báo lỗi qua /health
            self.last_retrain_error = f"{type(exc).__name__}: {exc}"
            logger.exception("Background retrain failed; serving previous models")

    @property
    def retraining(self):
        thread = self._retrain_thread
        return thread is not None and thread.is_alive()

    def wait_for_retrain(self, timeout=None):
        """Chờ lượt huấn luyện nền hiện tại (dùng cho kiểm thử và script)."""
        thread = self._retrain_thread
        if thread is not None:
            thread.join(timeout)
        return not self.retraining

    @staticmethod
    def _interactions(frame, pending):
        """Gộp pending vào frame; cặp (user, video) lặp lấy max (dương nếu từng dương)."""
        if pending:
            extra = pd.DataFrame(pending, columns=frame.columns)
            frame = (pd.concat([frame, extra], ignore_index=True)
                     .groupby(["user_id", "video_id"], as_index=False)
                     .agg(label=("label", "max"), play_time_ms=("play_time_ms", "max"),
                          is_like=("is_like", "max"), source=("source", "first")))
        return frame

    def _train_state(self, snapshot, pending, pending_random=()):
        """Huấn luyện trên bản sao dữ liệu; không đọc hay ghi trạng thái phục vụ."""
        started = time.time()
        frame = self._interactions(snapshot.interactions, pending)
        random_frame = self._interactions(snapshot.random_interactions, pending_random)
        video_ids = list(snapshot.videos)
        i2idx = {vid: i for i, vid in enumerate(video_ids)}
        # Người dùng chỉ có lượt xem ngẫu nhiên vẫn cần chỉ số để tháp unbiased học được họ.
        normal_users = set(frame["user_id"])
        user_ids = sorted(normal_users | set(random_frame["user_id"]))
        u2idx = {uid: i for i, uid in enumerate(user_ids)}
        models, cdr_info = {}, None
        conalign_mode, conalign_random = None, None
        n = len(frame)
        # Log ngẫu nhiên chỉ thay giai đoạn 2 của ConAlign; giai đoạn 1 vẫn cần log thường.
        if n >= self.min_interactions and frame["label"].nunique() > 1:
            u, i, y = self._tensors(frame, u2idx, i2idx)
            sizes = (len(user_ids), len(video_ids))
            for name in self.model_names:
                if name == "cdr":
                    models[name], cdr_info = self._train_cdr(u, i, y, *sizes)
                elif name == "conalign":
                    models[name], conalign_mode, conalign_random = self._train_conalign(
                        (u, i, y), random_frame, u2idx, i2idx, *sizes)
                else:
                    models[name] = getattr(self, f"_train_{name}")(u, i, y, *sizes)
        return {
            "snapshot": snapshot,
            "video_ids": video_ids,
            "i2idx": i2idx,
            "user_ids": user_ids,
            "u2idx": u2idx,
            "normal_users": normal_users,
            "popularity": self._popularity(snapshot, frame, i2idx),
            "models": models,
            "training_stats": {
                "interactions": n,
                "positives": int(frame["label"].sum()) if n else 0,
                "users_with_history": len(normal_users),
                "videos": len(video_ids),
                "trained_models": sorted(models),
                "train_seconds": round(time.time() - started, 3),
                "trained_at": int(time.time() * 1000),
                "cdr": cdr_info,
                "conalign_mode": conalign_mode,
                "random_interactions": len(random_frame),
                "conalign_random": conalign_random,
            },
        }

    def _install(self, state):
        """Hoán đổi trạng thái phục vụ nguyên khối; gọi khi đang giữ self._lock."""
        for key, value in state.items():
            setattr(self, key, value)

    @staticmethod
    def _popularity(snapshot, frame, i2idx):
        scores = np.array([np.log1p(v.get("watchCount", 0) + 5.0 * v.get("totalLikes", 0))
                           for v in snapshot.videos.values()], dtype=np.float64)
        if len(frame):
            pos = frame[frame["label"] > 0]["video_id"].map(i2idx).to_numpy()
            scores += np.log1p(np.bincount(pos, minlength=len(scores)))
        return scores

    def _tensors(self, frame, u2idx, i2idx):
        u = torch.tensor(frame["user_id"].map(u2idx).to_numpy(), dtype=torch.long, device=self.device)
        i = torch.tensor(frame["video_id"].map(i2idx).to_numpy(), dtype=torch.long, device=self.device)
        y = torch.tensor(frame["label"].to_numpy(dtype=np.float32), device=self.device)
        return u, i, y

    # -------------------------------------------------------------- training
    def _train_conalign(self, biased, random_frame, u2idx, i2idx, n_users, n_items):
        """Trả (mô hình, conalign_mode, info của lượt dùng log ngẫu nhiên hoặc None)."""
        info = None
        if len(random_frame) >= self.min_random_interactions and random_frame["label"].nunique() > 1:
            random = tuple(t.cpu() for t in self._tensors(random_frame, u2idx, i2idx))
            try:
                fitted = fit_conalign_with_random_log(tuple(t.cpu() for t in biased), random,
                                                      n_users, n_items, seed=self.seed)
            except Exception as exc:  # lỗi port tác giả không được chặn cả lượt huấn luyện
                logger.exception("ConAlign random-log training failed; using item-frequency proxy")
                fitted, info = None, {"error": f"{type(exc).__name__}: {exc}"}
            if fitted is not None:
                model, info = fitted
                # Checkpoint chọn theo AUC validation; <= 0.5 nghĩa là tháp unbiased chưa học được gì
                # (có thể vẫn là trạng thái khởi tạo epoch 0) nên không đưa ra phục vụ.
                if info["stage2_best_val_auc"] > MIN_RANDOM_VAL_AUC:
                    return model.to(self.device), "random_log", info
                info = {**info, "skipped": f"val_auc<={MIN_RANDOM_VAL_AUC}"}
            info = info or {"skipped": "Không chia được train/validation có đủ hai nhãn."}
        return self._train_conalign_proxy(*biased, n_users, n_items), "item_frequency_proxy", info

    def _train_conalign_proxy(self, u, i, y, n_users, n_items):
        set_seed(self.seed)
        model = DualTowerMF(n_users, n_items, dim=self.embedding_dim, alignment_weight=0.1).to(self.device)
        # Stage 1: Huấn luyện tháp Biased trên dữ liệu tương tác tự nhiên (MNAR log)
        optimizer_b = torch.optim.Adam(
            [model.user_latent_biased.weight, model.item_latent_biased.weight,
             model.user_bias_biased.weight, model.item_bias_biased.weight],
            lr=self.lr, weight_decay=self.weight_decay)
        criterion = torch.nn.BCEWithLogitsLoss()
        model.train()
        stage1_epochs = max(10, self.epochs // 2)
        for _ in range(stage1_epochs):
            optimizer_b.zero_grad()
            u_b = model.user_latent_biased(u)
            i_b = model.item_latent_biased(i)
            bu_b = model.user_bias_biased(u).squeeze(-1)
            bi_b = model.item_bias_biased(i).squeeze(-1)
            logits_b = torch.sum(u_b * i_b, dim=-1) + bu_b + bi_b
            loss1 = criterion(logits_b, y)
            loss1.backward()
            optimizer_b.step()

        # Stage 2: Sao chép tham số sang tháp Unbiased, đóng băng tháp Biased
        model.copy_biased_to_unbiased()
        for param in model.biased_parameters():
            param.requires_grad = False

        optimizer_ub = torch.optim.Adam(
            filter(lambda p: p.requires_grad, model.parameters()),
            lr=self.lr, weight_decay=self.weight_decay)

        # Trọng số nghịch đảo tần suất vật phẩm làm proxy khử thiên lệch khi online
        inv_p = item_frequency_weights(i, n_items)
        weights = inv_p / (inv_p.mean() + 1e-8)

        stage2_epochs = max(10, self.epochs // 2)
        for _ in range(stage2_epochs):
            optimizer_ub.zero_grad()
            b_probs, ub_probs, align = model(u, i)
            bce_raw = F.binary_cross_entropy(ub_probs, y, reduction="none")
            loss2 = (bce_raw * weights).mean() + model.alignment_weight * align.mean()
            loss2.backward()
            optimizer_ub.step()

        model.eval()
        return model

    def _train_mf(self, u, i, y, n_users, n_items):
        set_seed(self.seed)
        model = MatrixFactorization(n_users, n_items, embedding_dim=self.embedding_dim,
                                    train_global_bias=False, init_scheme="author_uniform").to(self.device)
        optimizer = torch.optim.Adam(model.parameters(), lr=self.lr, weight_decay=self.weight_decay)
        model.train()
        for _ in range(self.epochs):
            optimizer.zero_grad()
            loss = F.mse_loss(model(u, i), y)
            loss.backward()
            optimizer.step()
        model.eval()
        return model

    def _train_cdr(self, u, i, y, n_users, n_items):
        set_seed(self.seed)
        model = ReleasedCDR(n_users, n_items, embedding_dim=4, un_thres=10., dropout_rate=.5).to(self.device)
        inv_p = item_frequency_weights(i, n_items)
        # App has no randomized exposure log: record this serving adaptation.
        x = torch.stack([u, i], 1).detach().cpu().numpy()
        history = fit_released(model, x, y.detach().cpu().numpy(), inv_p, epochs=self.epochs,
                               batch_size=min(128, len(u)), lr=.05, weight_decay=1e-4, G=1,
                               catalog_sampler='replacement')
        info = dict(implementation='cdr_released', embedding_dim=4, un_thres=10.,
                    dropout_rate=.5, lr=.05, weight_decay=1e-4, epochs_run=len(history),
                    propensity='item_frequency_proxy_no_random_log', catalog_sampler='replacement',
                    scope='serving_adaptation_not_paper_experiment')
        model.eval()
        return model, info

    # ------------------------------------------------------------- serving
    def resolve_model(self, requested):
        requested = (requested or "conalign").lower()
        if requested in self.models:
            return requested, None
        if requested == "popularity":
            return "popularity", None
        reason = UNSUPPORTED_MODELS.get(requested)
        if reason is None and requested in self.model_names:
            reason = f"Chưa đủ dữ liệu để huấn luyện '{requested}' (cần >= {self.min_interactions} tương tác, có cả hai nhãn)."
        elif reason is None:
            reason = f"Mô hình '{requested}' không tồn tại."
        fallback = next((m for m in ("conalign", "cdr", "mf") if m in self.models), "popularity")
        return fallback, reason

    def _scores(self, model_name, user_idx):
        if model_name == "popularity" or user_idx is None:
            return self.popularity
        with torch.no_grad():
            logits = self.models[model_name].predict_user_all(torch.tensor([user_idx], device=self.device))
        return torch.sigmoid(logits[0]).cpu().numpy().astype(np.float64)

    def recommend(self, user_id, k=10, model="conalign", filter_rejected=True, exclude_video_ids=(),
                  explore=False):
        with self._lock:
            model_used, reason = self.resolve_model(model)
            user_idx = self.u2idx.get(str(user_id))
            # Người chỉ có lượt xem ngẫu nhiên chỉ được học bởi ConAlign chế độ random_log;
            # các mô hình khác (và ConAlign proxy) coi họ là cold-start.
            learned = str(user_id) in self.normal_users or (
                model_used == "conalign" and self.training_stats.get("conalign_mode") == "random_log")
            cold = user_idx is None or not learned
            if cold and model_used != "popularity":
                model_used, reason = "popularity", "User chưa có lịch sử tương tác (cold-start)."
            scores = self._scores(model_used, user_idx)
            excluded = set(map(str, exclude_video_ids)) | self.watched.get(str(user_id), set())

            def eligible(vid, skip_excluded):
                video = self.snapshot.videos[vid]
                if not video.get("videoUri"):
                    return False
                if filter_rejected:
                    status = str(video.get("moderationStatus", "")).strip().lower()
                    if status != "approved":
                        return False
                return not (skip_excluded and vid in excluded)

            candidates = [j for j, vid in enumerate(self.video_ids) if eligible(vid, True)]
            if not candidates:
                # Đã xem hết: cho phép xem lại thay vì trả về rỗng.
                candidates = [j for j, vid in enumerate(self.video_ids) if eligible(vid, False)]
            candidates = np.asarray(candidates, dtype=np.int64)
            if len(candidates) == 0:
                return [], model_used, cold, reason
            ranked = [int(j) for j in candidates[np.lexsort((candidates, -scores[candidates]))]]
            explore = explore and self.random_rate > 0 and str(user_id) != "guest"
            picks = []  # (chỉ số video, có phải bốc ngẫu nhiên không)
            placed = set()
            next_model = 0
            for _ in range(k):
                while next_model < len(ranked) and ranked[next_model] in placed:
                    next_model += 1
                pool = [int(j) for j in candidates if int(j) not in placed] if explore else []
                if pool and self._rng.random() < self.random_rate:
                    j, is_random = pool[int(self._rng.integers(len(pool)))], True
                elif next_model < len(ranked):
                    j, is_random = ranked[next_model], False
                else:
                    break
                placed.add(j)
                picks.append((j, is_random))
            results = []
            now = time.time()
            for rank, (j, is_random) in enumerate(picks, 1):
                video = dict(self.snapshot.videos[self.video_ids[j]])
                video.pop("_doc_id", None)
                video.update(rank=rank, video_id=video["videoId"],
                             score=None if is_random else round(float(scores[j]), 6),
                             model="random" if is_random else model_used,
                             exposure="random" if is_random else "normal")
                if is_random:
                    self.random_served[(str(user_id), video["videoId"])] = now
                else:
                    # Lần phát thường sau đó thu hồi cờ ngẫu nhiên cũ của cặp này.
                    self.random_served.pop((str(user_id), video["videoId"]), None)
                results.append(video)
            if any(is_random for _, is_random in picks):
                # Dọn các mục quá hạn mỗi lần ghi để dict không phình mãi.
                self.random_served = {key: t for key, t in self.random_served.items()
                                      if now - t <= RANDOM_SERVED_TTL}
            return results, model_used, cold, reason

    def log_interaction(self, user_id, video_id, play_time_ms, is_like, exposure="normal"):
        user_id, video_id = str(user_id), str(video_id)
        label = behavior_label(is_like, play_time_ms)
        start = False
        with self._lock:
            # Chỉ nhận "random" khi cặp thật sự được phát ngẫu nhiên và chưa quá hạn.
            served_at = self.random_served.get((user_id, video_id))
            accepted = "random" if (exposure == "random" and served_at is not None
                                    and time.time() - served_at <= RANDOM_SERVED_TTL) else "normal"
        if accepted == "random":
            if self.random_log is not None:
                self.random_log.append(user_id, video_id, play_time_ms, is_like)
        elif self.interaction_log is not None:
            self.interaction_log.append(user_id, video_id, play_time_ms, is_like)
        with self._lock:
            self.watched.setdefault(user_id, set()).add(video_id)
            known = video_id in self.i2idx
            if known:
                row = {"user_id": user_id, "video_id": video_id, "label": label,
                       "play_time_ms": int(play_time_ms), "is_like": bool(is_like),
                       "source": "api_random" if accepted == "random" else "api_live"}
                (self.pending_random if accepted == "random" else self.pending).append(row)
                self._since_fit += 1
                start = bool(self.retrain_every) and self._since_fit >= self.retrain_every and not self.retraining
                if start and self.background_retrain:
                    self._retrain_thread = threading.Thread(target=self._retrain_safely,
                                                            name="recsys-retrain", daemon=True)
                    self._retrain_thread.start()
        if start and not self.background_retrain:
            self._retrain_safely()
        return {"status": "recorded", "user_id": user_id, "video_id": video_id,
                "is_positive_interaction": bool(label), "known_video": known, "retrain_started": start,
                "exposure": accepted}

    def health(self):
        with self._lock:
            return {"status": "ok", "data_source": self.snapshot.source,
                    "models_available": sorted(self.models) + ["popularity"],
                    "device": str(self.device), "retraining": self.retraining,
                    "last_retrain_error": self.last_retrain_error, **self.training_stats}
