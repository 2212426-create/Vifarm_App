# Thu log ngẫu nhiên cho dịch vụ đề xuất – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dịch vụ tự chèn video ngẫu nhiên có cờ vào `/recommend`, nhận lại phản hồi qua `/interaction`, lưu thành log ngẫu nhiên riêng và huấn luyện ConAlign theo bản cài đặt của tác giả khi log đủ lớn; ứng dụng Flutter giữ cờ và gửi cả lượt xem dưới 3 giây.

**Architecture:** API quyết định vị trí nào là ngẫu nhiên và ghi nhớ cặp (người dùng, video) đã phát ngẫu nhiên; chỉ những cặp này mới được nhận là log ngẫu nhiên, nên ứng dụng không giả được cờ. Log ngẫu nhiên nằm trong một file CSV riêng, nạp thành `Snapshot.random_interactions`. Khi đủ dữ liệu, RecEngine gọi lại `train_conalign` của pipeline nghiên cứu (`src/models/conalign/`) thay cho cách thay thế bằng trọng số tần suất; chưa đủ thì giữ cách hiện tại.

**Tech Stack:** Python 3.12, FastAPI, PyTorch CPU, pandas, unittest (`services/recsys`); Flutter/Dart, package `http` (`apps/mobile-flutter`).

**Spec:** Thiết kế thống nhất trong hội thoại 15/11/2026 (người dùng chọn "Sửa cả API và ứng dụng"), tóm tắt ở mục Thiết kế dưới đây.

## Thiết kế

- `/recommend` (chỉ endpoint này, không áp cho `/compare`, `/items/popular`) đi qua từng vị trí 1..k: với xác suất `random_rate` lấy một video bốc đều trong các video hợp lệ (đã duyệt, có `videoUri`, không nằm trong danh sách loại trừ hoặc đã xem, chưa có trong danh sách đang dựng); còn lại lấy video kế tiếp theo điểm mô hình. Không chèn cho `user_id == "guest"`.
- Mọi phần tử trả về có thêm `exposure` = `"normal"` hoặc `"random"`. Phần tử ngẫu nhiên có `model = "random"`, `score = null`.
- `/interaction` nhận thêm `exposure` (mặc định `"normal"`). Dịch vụ chỉ chấp nhận `"random"` khi cặp (user, video) có trong sổ phát ngẫu nhiên của chính nó (hạn 24 giờ); ngược lại ghi như lượt thường.
- Lượt ngẫu nhiên ghi vào `RECSYS_RANDOM_LOG` (mặc định `data/api/random_log.csv`, cùng định dạng với `interactions_log.csv`), không trộn vào log thường.
- Huấn luyện: khi log ngẫu nhiên ≥ `min_random_interactions` (50) và các phần chia đều có cả hai nhãn, ConAlign của dịch vụ huấn luyện bằng `train_conalign(..., 'coat', ...)` (SGD, dim 10, có cổng, dừng sớm theo AUC validation); nếu không, dùng cách trọng số tần suất hiện tại. `/health` báo `conalign_mode` và `random_interactions`.
- Ứng dụng: `RecSysService` nhớ các `videoId` được trả với `exposure = "random"` và gửi kèm cờ khi ghi tương tác; `VideoPlayerWidget` gửi thêm lượt xem từ 500 ms đến dưới 3 giây khi người dùng rời video.

## Global Constraints

- Không thêm thư viện mới vào `requirements.txt` hay `pubspec.yaml`.
- Không sửa `src/models/conalign/` (pipeline thực nghiệm Chương III); chỉ gọi lại `train_conalign`.
- Hợp đồng JSON chỉ thêm trường: ứng dụng cũ không gửi `exposure` vẫn chạy, mặc định `"normal"`.
- Biến môi trường mới: `RECSYS_RANDOM_RATE` (mặc định `0.1` khi dựng từ môi trường), `RECSYS_RANDOM_LOG`, `RECSYS_MIN_RANDOM` (mặc định `50`). `RecEngine(random_rate=0.0)` mặc định để các test cũ không đổi.
- Ngưỡng nhãn dương giữ nguyên: `is_like` hoặc `play_time_ms >= 3000`.
- Ngưỡng gửi lượt xem ngắn của ứng dụng: `500` ms.
- Chú thích và thông báo lỗi viết tiếng Việt như code hiện có.
- Chạy test Python bằng `python -m unittest tests.test_api -v` trong `services/recsys`.

## Review Focus

1. Ứng dụng gửi `exposure: "random"` cho video không được phát ngẫu nhiên: phải ghi như lượt thường (Task 2, `test_unserved_random_claim_is_recorded_as_normal`).
2. Dịch vụ khởi động lại làm mất sổ phát ngẫu nhiên: lượt gửi sau đó được ghi là thường, không lỗi (cùng test trên, sổ rỗng).
3. Thiếu file `random_log.csv` hoặc file `interactions_log.csv` cũ: nạp snapshot vẫn chạy, `random_interactions` rỗng (Task 3, `test_snapshot_without_random_log_is_empty`).
4. Log ngẫu nhiên quá ít hoặc chỉ một nhãn: ConAlign vẫn được huấn luyện bằng cách cũ, `conalign_mode == "item_frequency_proxy"` (Task 4, `test_small_random_log_falls_back_to_proxy`).
5. Khách, hoặc người dùng đã xem hết kho video: khách không nhận phần tử ngẫu nhiên; người đã xem hết vẫn nhận đủ k video theo quy tắc "cho xem lại" hiện có và không có video lặp trong cùng danh sách (Task 1, `test_guest_and_empty_pool_get_no_random_items`).

---

### Task 1: Chèn video ngẫu nhiên vào /recommend

**Files:**
- Modify: `services/recsys/src/api/service.py` (`RecEngine.__init__`, `recommend`)
- Modify: `services/recsys/src/api/app.py` (`build_engine_from_env`, route `/api/v1/recommend`)
- Test: `services/recsys/tests/test_api.py` (lớp mới `RandomExposureTests`)

**Interfaces:**
- Produces: `RecEngine(..., random_rate: float = 0.0, random_seed: int | None = None, ...)`; `RecEngine.recommend(user_id, k=10, model="conalign", filter_rejected=True, exclude_video_ids=(), explore: bool = False) -> (list[dict], str, bool, str | None)`; thuộc tính `RecEngine.random_served: dict[tuple[str, str], float]` (cặp → thời điểm phát, giây); hằng `RANDOM_SERVED_TTL = 24 * 3600`.

- [ ] **Step 1: Viết test hỏng**

```python
class RandomExposureTests(unittest.TestCase):
    def test_explore_marks_random_items(self):
        engine = make_engine(random_rate=1.0, random_seed=0)
        recs, _, _, _ = engine.recommend("u0", k=3, explore=True)
        self.assertEqual([r["exposure"] for r in recs], ["random"] * 3)
        self.assertTrue(all(r["model"] == "random" and r["score"] is None for r in recs))
        self.assertEqual(len({r["videoId"] for r in recs}), 3)
        self.assertTrue(all(("u0", r["videoId"]) in engine.random_served for r in recs))

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
        client = TestClient(create_app(engine=make_engine(random_rate=1.0, random_seed=0)))
        body = client.post("/api/v1/recommend", json={"user_id": "u0", "k": 2}).json()
        self.assertEqual({r["exposure"] for r in body["recommendations"]}, {"random"})
```

`create_app(engine=...)` và cách test HTTP hiện có (lớp `HttpTests`) quyết định cách dựng client; dùng lại đúng cách đó.

- [ ] **Step 2: Chạy test, xác nhận hỏng**

Run: `python -m unittest tests.test_api.RandomExposureTests -v`
Expected: FAIL (`unexpected keyword argument 'random_rate'`).

- [ ] **Step 3: Cài đặt**

Trong `RecEngine`: lưu `random_rate`, tạo `self._rng = np.random.default_rng(random_seed)`, `self.random_served = {}`. Trong `recommend`: giữ nguyên phần chấm điểm; nếu `explore and random_rate > 0 and str(user_id) != "guest"`, dựng danh sách theo thiết kế (bốc đều bằng `self._rng.choice` trong tập hợp lệ còn lại; tập rỗng thì lấy video của mô hình). Mọi phần tử có `exposure`; phần tử ngẫu nhiên có `model="random"`, `score=None`. Ghi `random_served[(user, vid)] = time.time()` và xóa mục quá `RANDOM_SERVED_TTL` mỗi lần ghi. Trường hợp "đã xem hết" hiện có (cho xem lại) áp dụng chung cho cả tập bốc ngẫu nhiên. Trong `app.py`: route `/recommend` gọi `recommend(..., explore=True)`; `build_engine_from_env` đọc `RECSYS_RANDOM_RATE` (mặc định `"0.1"`).

- [ ] **Step 4: Chạy lại toàn bộ test API**

Run: `python -m unittest tests.test_api -v`
Expected: PASS, kể cả các test cũ (`test_recommendation_is_deterministic`, `test_recommend_contract_matches_flutter_client`).

- [ ] **Step 5: Commit**

```bash
git add services/recsys/src/api/service.py services/recsys/src/api/app.py services/recsys/tests/test_api.py
git commit -m "feat(recsys): chèn video ngẫu nhiên có cờ vào /recommend"
```

### Task 2: Nhận cờ ở /interaction và ghi log ngẫu nhiên riêng

**Files:**
- Modify: `services/recsys/src/api/schemas.py` (`InteractionRequest`)
- Modify: `services/recsys/src/api/service.py` (`RecEngine.__init__`, `log_interaction`)
- Modify: `services/recsys/src/api/app.py` (route `/api/v1/interaction`, `build_engine_from_env`)
- Test: `services/recsys/tests/test_api.py` (`RandomExposureTests`)

**Interfaces:**
- Consumes: `RecEngine.random_served`, `RANDOM_SERVED_TTL` (Task 1).
- Produces: `InteractionRequest.exposure: Literal["normal", "random"] = "normal"`; `RecEngine(..., random_log: InteractionLog | None = None)`; `RecEngine.pending_random: list[dict]` (cùng khóa với `pending`, `source="api_random"`); `log_interaction(user_id, video_id, play_time_ms, is_like, exposure="normal") -> dict` có thêm khóa `"exposure"` là giá trị đã chấp nhận.

- [ ] **Step 1: Viết test hỏng**

```python
    def test_served_random_interaction_goes_to_random_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            rlog = InteractionLog(Path(tmp) / "random.csv")
            engine = make_engine(random_rate=1.0, random_seed=0, random_log=rlog, retrain_every=0)
            vid = engine.recommend("u0", k=1, explore=True)[0][0]["videoId"]
            out = engine.log_interaction("u0", vid, 800, False, exposure="random")
            self.assertEqual(out["exposure"], "random")
            self.assertEqual(len(engine.pending_random), 1)
            self.assertEqual(engine.pending_random[0]["label"], 0.0)
            self.assertEqual(len(pd.read_csv(rlog.path)), 1)

    def test_unserved_random_claim_is_recorded_as_normal(self):
        engine = make_engine(random_rate=0.0, retrain_every=0)
        out = engine.log_interaction("u0", "v3", 800, False, exposure="random")
        self.assertEqual(out["exposure"], "normal")
        self.assertEqual(engine.pending_random, [])

    def test_http_interaction_accepts_exposure_field(self):
        # Dựng client và header token giả lập y như AuthHttpTests.test_interaction_is_recorded_for_token_owner
        resp = client.post("/api/v1/interaction", headers=headers,
                           json={"video_id": "v3", "play_time_ms": 800, "is_like": False, "exposure": "random"})
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["exposure"], "normal")
```

- [ ] **Step 2: Chạy test, xác nhận hỏng**

Run: `python -m unittest tests.test_api.RandomExposureTests -v`
Expected: FAIL (`unexpected keyword argument 'random_log'` / `'exposure'`).

- [ ] **Step 3: Cài đặt**

Chỉ video có trong catalog mới vào `pending_random`, giống quy tắc `known` của `pending`. `log_interaction` xác định `accepted = "random"` chỉ khi `exposure == "random"` và cặp có trong `random_served` chưa quá hạn. Lượt ngẫu nhiên: ghi `random_log` (nếu có) và `pending_random`; lượt thường: giữ nguyên đường cũ. Cả hai loại đều thêm vào `watched` và tăng bộ đếm huấn luyện lại. Route truyền `req.exposure`; `build_engine_from_env` tạo `InteractionLog` cho `RECSYS_RANDOM_LOG` (mặc định `PROJECT_ROOT / "data" / "api" / "random_log.csv"`). `refresh` cắt `pending_random` theo cùng quy tắc với `pending`.

- [ ] **Step 4: Chạy lại toàn bộ test API**

Run: `python -m unittest tests.test_api -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/recsys/src/api/schemas.py services/recsys/src/api/service.py services/recsys/src/api/app.py services/recsys/tests/test_api.py
git commit -m "feat(recsys): /interaction nhận cờ exposure và ghi log ngẫu nhiên riêng"
```

### Task 3: Nạp log ngẫu nhiên vào snapshot

**Files:**
- Modify: `services/recsys/src/api/firebase_bridge.py` (`Snapshot`, `load_snapshot`)
- Modify: `services/recsys/src/api/app.py` (`build_engine_from_env` truyền `random_log`)
- Test: `services/recsys/tests/test_api.py` (`BridgeTests`)

**Interfaces:**
- Produces: `Snapshot.random_interactions: pd.DataFrame` (cột `INTERACTION_COLUMNS`, mặc định rỗng); `load_snapshot(source="auto", export_dir=None, interaction_log=None, random_log=None) -> Snapshot`.

- [ ] **Step 1: Viết test hỏng**

```python
    def test_snapshot_reads_random_log_separately(self):
        # Dựng export_dir và interaction_log y như test_export_snapshot_merges_log_and_drops_unknown_videos;
        # rpath là CSV cùng định dạng InteractionLog, 2 dòng: (u9, v1, 0, 800) với v1 có trong export, (u9, vX, 1, 9000) với vX không có
        snap = load_snapshot("export", export_dir=export_dir, interaction_log=log_path, random_log=rpath)
        self.assertEqual(len(snap.random_interactions), 1)
        self.assertEqual(set(snap.random_interactions["source"]), {"api_random"})
        self.assertNotIn(("u9", "v1"), set(zip(snap.interactions.user_id, snap.interactions.video_id)))

    def test_snapshot_without_random_log_is_empty(self):
        snap = load_snapshot("export", export_dir=export_dir, interaction_log=log_path, random_log=Path(tmp) / "missing.csv")
        self.assertEqual(list(snap.random_interactions.columns), INTERACTION_COLUMNS)
        self.assertEqual(len(snap.random_interactions), 0)
```

- [ ] **Step 2: Chạy test, xác nhận hỏng**

Run: `python -m unittest tests.test_api.BridgeTests -v`
Expected: FAIL (`unexpected keyword argument 'random_log'`).

- [ ] **Step 3: Cài đặt**

Tách phần lọc theo catalog và gộp cặp trùng (`groupby` lấy max) thành một hàm dùng chung cho cả hai frame; `random_interactions` đọc bằng `read_interactions_csv(random_log, "api_random")`.

- [ ] **Step 4: Chạy lại toàn bộ test API**

Run: `python -m unittest tests.test_api -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add services/recsys/src/api/firebase_bridge.py services/recsys/src/api/app.py services/recsys/tests/test_api.py
git commit -m "feat(recsys): nạp log ngẫu nhiên vào Snapshot.random_interactions"
```

### Task 4: Huấn luyện ConAlign bằng log ngẫu nhiên khi đủ dữ liệu

**Files:**
- Create: `services/recsys/src/api/conalign_random.py`
- Modify: `services/recsys/src/api/service.py` (`__init__`, `_interactions`, `_train_state`, `_train_conalign`)
- Modify: `services/recsys/src/api/app.py` (`RECSYS_MIN_RANDOM`)
- Test: `services/recsys/tests/test_api.py` (`RandomTrainingTests`)

**Interfaces:**
- Consumes: `Snapshot.random_interactions` (Task 3), `RecEngine.pending_random` (Task 2), `src.models.conalign.train.train_conalign(data, dataset, seed=0, device=None, overrides=None, checkpoint_dir=None, verbose=True) -> dict` (có `checkpoint_path`, `stage1`, `stage2`).
- Produces: `fit_conalign_with_random_log(biased: tuple[Tensor, Tensor, Tensor], random: tuple[Tensor, Tensor, Tensor], n_users: int, n_items: int, seed: int) -> tuple[DualTowerMF, dict] | None`; `RecEngine(..., min_random_interactions: int = 50)`; `training_stats["conalign_mode"] in {"random_log", "item_frequency_proxy", None}`, `training_stats["random_interactions"]: int`.

- [ ] **Step 1: Viết test hỏng**

```python
def make_random_snapshot(n_random):
    snap = make_snapshot()
    # Duyệt u0..u3 (ngoài), v0..v5 (trong); nhãn 1 nếu video thuộc nhóm "liked" của user trong make_snapshot,
    # ngược lại 0; lấy n_random dòng đầu (24 = đủ mọi cặp; 4 = bốn video đầu của u0, nhãn 1,1,1,0).
    snap.random_interactions = pd.DataFrame(rows[:n_random], columns=INTERACTION_COLUMNS)  # source="api_random"
    return snap

class RandomTrainingTests(unittest.TestCase):
    def test_enough_random_log_trains_author_conalign(self):
        engine = RecEngine(lambda: make_random_snapshot(24), epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "random_log")
        self.assertEqual(engine.training_stats["random_interactions"], 24)
        self.assertEqual(engine.models["conalign"].user_latent_unbiased.embedding_dim, 10)
        recs, used, _, _ = engine.recommend("u0", k=3, model="conalign")
        self.assertEqual(used, "conalign")

    def test_small_random_log_falls_back_to_proxy(self):
        engine = RecEngine(lambda: make_random_snapshot(4), epochs=50, min_interactions=5,
                           min_random_interactions=12)
        self.assertEqual(engine.training_stats["conalign_mode"], "item_frequency_proxy")
        self.assertIn("conalign", engine.models)

    def test_split_without_both_labels_returns_none(self):
        # biased: u,i,y lấy từ make_snapshot().interactions (đã map chỉ số); random_all_positive: 6 dòng nhãn 1
        self.assertIsNone(fit_conalign_with_random_log(biased, random_all_positive, 4, 8, seed=42))
```

Tên thuộc tính embedding (`user_latent_unbiased`) lấy theo `DualTowerMF` hiện có.

- [ ] **Step 2: Chạy test, xác nhận hỏng**

Run: `python -m unittest tests.test_api.RandomTrainingTests -v`
Expected: FAIL (`No module named 'src.api.conalign_random'`).

- [ ] **Step 3: Cài đặt `fit_conalign_with_random_log` trong `src/api/conalign_random.py`**

Chia phân tầng theo nhãn bằng hoán vị có seed: với log ngẫu nhiên, mỗi nhãn lấy `max(1, round(n/6))` dòng làm validation (tỷ lệ 50:10 của tác giả), còn lại làm train; với log thường, mỗi nhãn lấy `max(1, round(n/8))` dòng (tỷ lệ 70:10). Trả `None` khi một nhãn có ít hơn 2 dòng trong log ngẫu nhiên hoặc log thường, vì khi đó không chia được train và validation đều có cả hai nhãn. Dựng dict `train_biased`, `val_biased`, `test_biased` (= `val_biased`), `train_unbiased`, `val_unbiased`, `test_unbiased` (= `val_unbiased`) bằng `torch.sparse_coo_tensor` kích thước `(n_users, n_items)` và `info` (`protocol="serving_random_log_v1"`, số dòng mỗi phần). Gọi `train_conalign(data, "coat", seed=seed, device="cpu", checkpoint_dir=<thư mục tạm>, verbose=False)`, nạp `model_state_dict` vào `DualTowerMF(n_users, n_items, dim=10, alignment_weight=0.2)`. `info` trả về gồm `implementation="conalign_author_port"`, `config="coat"`, số dòng mỗi phần, `best_epoch` của hai giai đoạn và `best_val_auc` của giai đoạn 2.

- [ ] **Step 4: Nối vào `RecEngine`**

`_train_state` gộp `snapshot.random_interactions` với `pending_random` (cùng cách gộp với log thường); `u2idx` lấy hợp người dùng của cả hai frame. Khi log ngẫu nhiên ≥ `min_random_interactions` và có cả hai nhãn, thử `fit_conalign_with_random_log`; nhận `None` hoặc chưa đủ thì dùng `_train_conalign` hiện tại. Ghi `conalign_mode`, `random_interactions` và `conalign_random` (info) vào `training_stats`. `build_engine_from_env` đọc `RECSYS_MIN_RANDOM` (mặc định `"50"`).

- [ ] **Step 5: Chạy toàn bộ test API**

Run: `python -m unittest tests.test_api -v`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add services/recsys/src/api/conalign_random.py services/recsys/src/api/service.py services/recsys/src/api/app.py services/recsys/tests/test_api.py
git commit -m "feat(recsys): huấn luyện ConAlign bằng log ngẫu nhiên khi đủ dữ liệu"
```

### Task 5: Ứng dụng giữ cờ ngẫu nhiên và gửi lượt xem ngắn

**Files:**
- Modify: `apps/mobile-flutter/lib/features/video_feed/services/recsys_service.dart` (`getRecommendations`, `_sendInteractionAsync`)
- Modify: `apps/mobile-flutter/lib/features/video_feed/widgets/video_player_widget.dart` (nhánh mất hiển thị trong `onVisibilityChanged`)
- Modify: `apps/mobile-flutter/lib/core/constants/app_constants.dart` (`recsysMinExposureMs = 500`)
- Test: `apps/mobile-flutter/test/features/video_feed/recsys_random_exposure_test.dart`

**Interfaces:**
- Consumes: hợp đồng JSON của Task 1–2 (`recommendations[].exposure`, body `/interaction` có `exposure`).
- Produces: `RecSysService.isRandomExposure(String videoId) -> bool`.

- [ ] **Step 1: Viết test hỏng**

```dart
test('gửi exposure random cho video được phát ngẫu nhiên', () async {
  final sent = <Map<String, dynamic>>[];
  final client = MockClient((req) async {
    if (req.url.path == '/health') return http.Response('{"status":"ok"}', 200);
    if (req.url.path == '/api/v1/recommend') {
      return http.Response(jsonEncode({'recommendations': [
        {'videoId': 'a', 'exposure': 'random'}, {'videoId': 'b', 'exposure': 'normal'}]}), 200);
    }
    sent.add(jsonDecode(req.body) as Map<String, dynamic>);
    return http.Response('{}', 200);
  });
  final service = RecSysService(client: client, idTokenProvider: () async => 't');
  // trỏ service tới http://test bằng cách mà recsys_api_integration_test dùng (RECSYS_API_URL)
  await service.getRecommendations(userId: 'u', limit: 2);
  service.logInteraction(userId: 'u', videoId: 'a', playTimeMs: 800, isLike: false);
  service.logInteraction(userId: 'u', videoId: 'b', playTimeMs: 800, isLike: false);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  expect(sent.map((b) => b['exposure']), ['random', 'normal']);
});
```

- [ ] **Step 2: Chạy test, xác nhận hỏng**

Run: `flutter test test/features/video_feed/recsys_random_exposure_test.dart` (trong `apps/mobile-flutter`)
Expected: FAIL (`exposure` là null).

- [ ] **Step 3: Cài đặt**

`RecSysService` giữ `Set<String>` các `videoId` có `exposure == "random"` (thêm khi parse, không xóa khi nhận danh sách mới để lượt thích muộn vẫn mang cờ); `_sendInteractionAsync` thêm `'exposure'`. Trong `VideoPlayerWidget`, khi video mất hiển thị mà `_startTime` vẫn còn (chưa ghi lượt ≥ 3 giây) và thời gian xem tính bằng mili giây từ `AppConstants.recsysMinExposureMs` tới dưới 3000, gọi `logRecSysInteraction(playTimeMs: <ms>, isLike: false)` rồi đặt `_startTime = null`. Không gọi `markVideoAsWatched` hay `recordInterest` cho lượt ngắn.

- [ ] **Step 4: Chạy test và phân tích tĩnh**

Run: `flutter test test/features/video_feed/recsys_random_exposure_test.dart && flutter analyze lib/features/video_feed`
Expected: PASS, không có lỗi mới.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-flutter/lib/features/video_feed/services/recsys_service.dart apps/mobile-flutter/lib/features/video_feed/widgets/video_player_widget.dart apps/mobile-flutter/lib/core/constants/app_constants.dart apps/mobile-flutter/test/features/video_feed/recsys_random_exposure_test.dart
git commit -m "feat(mobile-flutter): gửi cờ exposure và lượt xem dưới 3 giây cho RecSys"
```

### Task 6: Tài liệu repo, kiểm chứng cuối và chạy thử đầu cuối

**Files:**
- Modify: `services/recsys/docs/CURRENT_STATE.md` (mục API trong "Cấu hình mặc định", mục "Kiểm chứng")
- Modify: `services/recsys/docs/api/colab_api_guide.md` (trường `exposure`, ba biến môi trường mới)
- Modify: `services/recsys/docs/state_snapshot.json` (mốc kiểm chứng mới, theo `docs/MAINTENANCE.md`)
- Modify: `chay_thu/1_api_du_lieu_cu.bat`, `chay_thu/2_api_du_lieu_hien_tai.bat` (thêm `set RECSYS_RANDOM_RATE=0.1`)

- [ ] **Step 1: Chạy toàn bộ bộ kiểm thử của dự án**

Run: `python -m unittest discover -s tests -v` (trong `services/recsys`)
Expected: mọi ca đạt, ngoài ca CUDA bị bỏ qua; ghi lại tổng số ca và số ca của `tests/test_api.py` để cập nhật báo cáo.

- [ ] **Step 2: Cập nhật tài liệu và kiểm tra**

Run: `python docs/check_docs.py` và `ruff check src experiments tests`
Expected: không lỗi.

- [ ] **Step 3: Chạy thử đầu cuối**

Khởi động API bằng `2_api_du_lieu_hien_tai.bat`, mở ứng dụng ở cổng 5000 và đăng nhập. Mong đợi: phản hồi `/recommend` (DevTools → Network) có phần tử `exposure: "random"`; lướt qua video đó dưới 3 giây làm xuất hiện một dòng mới trong `data/api/random_log.csv`; `/health` có `conalign_mode`.

- [ ] **Step 4: Commit và cập nhật graph**

```bash
graphify update .
git add services/recsys/docs chay_thu graphify-out
git commit -m "docs(recsys): ghi trạng thái log ngẫu nhiên và mốc kiểm chứng"
```

### Task 7: Cập nhật báo cáo đồ án

Sau khi Task 6 xong, sửa `D:\University\DoAnChuyenNganh\29_BaoCao_...docx` (sao lưu trước khi ghi):
- IV.2 và Bảng 4.1: `/recommend` có chèn video ngẫu nhiên; `/interaction` nhận `exposure`.
- IV.3: hai chế độ của ConAlign trong dịch vụ (`random_log` khi đủ log ngẫu nhiên, trọng số tần suất khi chưa đủ).
- IV.4: ứng dụng gửi cả lượt xem từ 500 ms đến dưới 3 giây, kèm cờ.
- IV.6 và Bảng 4.2: số ca kiểm thử mới từ Task 6 Step 1.
- Phụ lục B: thêm trường `exposure` vào ví dụ yêu cầu và phản hồi.
- V.2 và V.3: bỏ hạn chế "ứng dụng không gửi nhãn âm"; giữ ý lượng log ngẫu nhiên thực tế còn nhỏ.
