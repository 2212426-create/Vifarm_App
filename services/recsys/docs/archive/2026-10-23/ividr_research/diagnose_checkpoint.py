"""Read-only, exposure-based IViDR diagnostics; never select on test scores."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT))
import numpy as np
from scipy import sparse
import torch
from src.models.ividr.ividr_reference import PaperExposureIVAE
from src.utils.artifacts import source_signature


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


torch.set_num_threads(2)
report_path = ROOT/'results/benchmark_coat_all_02b9e8eb46_20261022_073711_146173c9_v4.json'
report = json.loads(report_path.read_text(encoding='utf-8'))
result = report['coat']['IViDR']
path = Path(result['confounder_info']['checkpoint_path'])
before = digest(path)
checkpoint = torch.load(path, map_location='cpu', weights_only=True)
state = checkpoint['model_state_dict']
exposure = state['iv.exposure_t'].to_dense().T.numpy()
features = state['iv.features'].numpy()
model = PaperExposureIVAE(**checkpoint['model_config'],
    item_embeddings=state['iv.treatment'].numpy(), exposure=sparse.csr_matrix(exposure), instruments=features)
model.load_state_dict(state)
model.eval()


def norm(x):
    return float(torch.linalg.vector_norm(x))


def stats(x):
    return dict(min=float(x.min()), mean=float(x.mean()), max=float(x.max()), std=float(x.std()))


with torch.no_grad():
    a, w = torch.tensor(exposure), torch.tensor(features)
    t, fitted, residual, af, ar = model.iv.components()
    xre = model.reconstructed_input(a)
    m1,l1,m2,l2 = model.posteriors(a,w)
    ranks = {str(rank):len(items) for rank,items in model.iv.rank_groups}
    mean,std = model.confounders(a,w)
    perturbation = xre-a
    diagnostics = dict(
        exposure_shape=list(a.shape), raw_feature_shape=list(w.shape),
        instrument_rank_counts=ranks,
        fitted_norm_over_t=norm(fitted)/norm(t), residual_norm_over_t=norm(residual)/norm(t),
        gate_fitted=stats(af), gate_residual=stats(ar),
        reconstruction_delta=stats(perturbation),
        reconstruction_delta_norm_over_exposure=norm(perturbation)/norm(a),
        reconstruction_user_delta_norm_over_exposure_percentiles=np.percentile(
            (perturbation.norm(dim=1)/a.norm(dim=1)).numpy(),[0,10,50,90,100]).tolist(),
        branch_mean_relative_difference=norm(m1-m2)/max(norm(m2),1e-12),
        branch_mean_cosine=float(torch.nn.functional.cosine_similarity(m1.flatten(),m2.flatten(),dim=0)),
        branch_original_mean=stats(m2), branch_reconstructed_mean=stats(m1),
        merged_mean=stats(mean), merged_std=stats(std),
        cached_mean_exact=torch.equal(mean,checkpoint['confounder_mean']),
        cached_std_exact=torch.equal(std,checkpoint['confounder_std']),
        cached_mean_max_abs_difference=float((mean-checkpoint['confounder_mean']).abs().max()),
        cached_std_max_abs_difference=float((std-checkpoint['confounder_std']).abs().max()))
after = digest(path)
assert before == after
output = dict(checked_at_utc=datetime.now(timezone.utc).isoformat(),
    scope='read_only_coat_biased_exposure_checkpoint_diagnostics_no_retraining_no_test_predictions',
    diagnostic_source_sha256=source_signature(), training_source_sha256=checkpoint['code_sha256'],
    reference_report=report_path.relative_to(ROOT).as_posix(), reference_report_sha256=digest(report_path),
    checkpoint_path=path.relative_to(ROOT).as_posix(), checkpoint_sha256_before=before,
    checkpoint_sha256_after=after, diagnostics=diagnostics,
    optimization_claim='No measured quality improvement; diagnostics only',
    conclusions_require_validation_ablation=True)
with (ROOT/'results/ividr_research_diagnostics_20261023.json').open('x',encoding='utf-8') as f:
    json.dump(output,f,indent=2);f.write('\n')
print(json.dumps(diagnostics,indent=2))
