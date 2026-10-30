# -*- coding: utf-8 -*-
"""
Sinh notebook Google Colab 'TopTop_RecSys_Colab_API.ipynb'.
Notebook không tự định nghĩa mô hình: nó cài repo và chạy src.api (MF / DR-BIAS+CDR
huấn luyện thật trên tương tác TopTop), mở Cloudflare Tunnel rồi ghi URL lên Firebase.

    venv\\Scripts\\python.exe notebooks\\build_notebook.py
"""

import json
from pathlib import Path

REPO_URL = "https://github.com/HubertPhung/agri-behavioral-recsys.git"
TARGET = Path(__file__).resolve().parent / "TopTop_RecSys_Colab_API.ipynb"


def make_cell(cell_type, source):
    cell = {"cell_type": cell_type, "metadata": {}, "source": source.strip("\n").splitlines(keepends=True)}
    if cell_type == "code":
        cell.update(execution_count=None, outputs=[])
    return cell


cells = [
    make_cell("markdown", r"""
# TopTop RecSys API trên Google Colab

Chạy **Runtime → Run all**. Notebook:
1. Cài repo `agri-behavioral-recsys` và thư viện API.
2. Nạp video từ Firestore, tương tác từ `toptop_interactions.csv` (nếu tải lên) và lượt like RTDB.
3. Huấn luyện thật **MF** và **DR-BIAS + CDR** trên tương tác TopTop (nhãn dương: like hoặc xem ≥ 3 giây).
4. Mở Cloudflare Tunnel và ghi URL vào `server_config/recsys_url` để app tự kết nối.

User chưa có lịch sử nhận gợi ý theo độ phổ biến. App gửi `model="ividr"`: dữ liệu TopTop chưa có đặc trưng user
để làm biến công cụ/proxy cho IViDR, nên API chọn mô hình khả dụng và trả `fallback_reason` trong phản hồi.
Benchmark mặc định chỉ chạy MF/iDCF/CDR; IViDR-approx chỉ chạy khi yêu cầu riêng và chưa đúng paper. MF dùng MSE; CDR dùng BCE và huấn luyện độc lập. Đọc docs/CURRENT_STATE.md ở đúng revision repo đang chạy.
"""),
    make_cell("code", f"""
# 1. Cài repo, thư viện API và cloudflared
!git clone -q {REPO_URL} /content/agri-behavioral-recsys 2>/dev/null || git -C /content/agri-behavioral-recsys pull -q
%cd /content/agri-behavioral-recsys
!pip install -q fastapi uvicorn httpx
!wget -q -nc https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O cloudflared && chmod +x cloudflared
"""),
    make_cell("code", """
# 2. (Tùy chọn) Tải lên toptop_interactions.csv từ data/firebase_export của dự án.
#    Bỏ qua cell này thì API chỉ dùng lượt like trong RTDB và tương tác app gửi về.
import os
from pathlib import Path
export_dir = Path("/content/data/firebase_export")
export_dir.mkdir(parents=True, exist_ok=True)
try:
    from google.colab import files
    for name, content in files.upload().items():
        (export_dir / name).write_bytes(content)
except Exception as exc:
    print("Bỏ qua tải file:", exc)
os.environ["RECSYS_EXPORT_DIR"] = str(export_dir)
os.environ["RECSYS_DATA_SOURCE"] = "auto"
print(sorted(p.name for p in export_dir.iterdir()))
"""),
    make_cell("code", """
# 3. Chạy API + Cloudflare Tunnel ở tiến trình nền, chờ URL công khai
import subprocess, sys, time
server = subprocess.Popen([sys.executable, "-m", "src.api.tunnel", "--port", "8000", "--cloudflared", "./cloudflared"],
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=os.environ.copy())
PUBLIC_URL = None
deadline = time.time() + 180
while time.time() < deadline and PUBLIC_URL is None:
    line = server.stdout.readline()
    if not line and server.poll() is not None:
        break
    print(line, end="")
    if line.startswith("Public URL:"):
        PUBLIC_URL = line.split()[2]
print("\\nPUBLIC_URL =", PUBLIC_URL)
"""),
    make_cell("code", """
# 4. Kiểm thử nhanh qua cổng nội bộ
import requests
BASE = "http://127.0.0.1:8000"
health = requests.get(f"{BASE}/health", timeout=10).json()
print(health)
rec = requests.post(f"{BASE}/api/v1/recommend",
                    json={"user_id": "guest", "k": 5, "model": "mf", "filter_rejected": False}, timeout=10).json()
print(rec["model_used"], rec["fallback_reason"], [r["videoId"] for r in rec["recommendations"]])
"""),
]

notebook = {
    "nbformat": 4,
    "nbformat_minor": 2,
    "metadata": {"colab": {"name": TARGET.name, "provenance": []},
                 "kernelspec": {"name": "python3", "display_name": "Python 3"},
                 "language_info": {"name": "python"}},
    "cells": cells,
}

if __name__ == "__main__":
    TARGET.write_text(json.dumps(notebook, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Đã tạo {TARGET}")
