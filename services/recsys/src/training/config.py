"""Effective defaults shared by benchmark, tuning and seed workflows.

MF/iDCF use the iDCF author's initialization and squared-error feedback model.
CDR is trained independently with BCE and a dot-product backbone. All dataset
benchmark defaults use RELEASED_CDR_CONFIG; CDR_CONFIG names the Eq. (7) variant.
These method definitions do not imply identical data protocols across papers.
"""
from copy import deepcopy
from itertools import product

MF_CONFIG = {
    "yahoo": dict(embedding_dim=64, epochs=100, lr=5e-4, weight_decay=1e-6,
                  batch_size=2048, patience=5),
    "coat": dict(embedding_dim=64, epochs=100, lr=5e-4, weight_decay=1e-6,
                 batch_size=512, patience=5),
    "kuairand": dict(embedding_dim=64, epochs=100, lr=5e-5, weight_decay=1e-6,
                     batch_size=2048, patience=5),
}
CDR_CONFIG = {
    "yahoo": dict(embedding_dim=4, epochs=100, lr=.05,batch_size=2048,patience=5,
        un_thres=.1,weight_decay=1e-4,filter_mode="cv",ips_weighting="paper",counterfactual_pool="all",
        mc_samples=10,training_profile="paper",backbone="paper_dot",scheduler_name="none",
        propensity_mode="naive_bayes_validation"),
    # Selected from a limited paper-range search using mean validation over
    # seeds 42/43/44. This is not a completed 1,120-configuration search.
    "coat": dict(embedding_dim=4, epochs=100, lr=0.1, batch_size=512,
                 patience=20, un_thres=0.1, max_inverse_propensity=None, weight_decay=1e-4,
                 filter_mode="cv", ips_weighting="paper", counterfactual_pool="all", mc_samples=10,
                 training_profile="paper", backbone="paper_dot", scheduler_name="none",
                 propensity_mode="naive_bayes_validation"),
    "kuairand": dict(embedding_dim=4, epochs=100, lr=0.05, batch_size=2048,
                     patience=5, un_thres=0.1, filter_mode="cv", weight_decay=1e-4,
                     ips_weighting="paper", counterfactual_pool="all", mc_samples=10,
                     training_profile="paper", backbone="paper_dot", scheduler_name="none"),
}

RELEASED_CDR_CONFIG = {
    "coat": dict(embedding_dim=4,epochs=1000,lr=.05,weight_decay=.001,batch_size=128,
                 un_thres=10.,dropout_rate=.5,G=4),
    "yahoo": dict(embedding_dim=4,epochs=1000,lr=.05,weight_decay=.0001,batch_size=2048,
                  un_thres=10.,dropout_rate=.7,G=1),
    "kuairand": dict(embedding_dim=4,epochs=1000,lr=.05,weight_decay=.0001,batch_size=2048,
                     un_thres=10.,dropout_rate=.5,G=1),
}


def released_cdr_config(dataset, **overrides):
    config = deepcopy(RELEASED_CDR_CONFIG[dataset])
    config.update({k:v for k,v in overrides.items() if v is not None})
    return config


def mf_config(dataset, **overrides):
    config = dict(deepcopy(MF_CONFIG[dataset]), loss_name="mse", decay_scope="all",
                  scheduler_name="none", train_global_bias=False, init_scheme="author_uniform")
    config.update({k: v for k, v in overrides.items() if v is not None})
    return config


def cdr_config(dataset, **overrides):
    config = deepcopy(CDR_CONFIG[dataset])
    config.update({k: v for k, v in overrides.items() if v is not None})
    return config


def tuning_grids(dataset):
    """Baseline first, then the Cartesian search ranges published by each paper.

    MF: iDCF MF.py; CDR: CDR paper section 4.1 (1,120 configurations).
    This does not reuse selected hyperparameters from a different method.
    """
    mf = mf_config(dataset)
    cdr = cdr_config(dataset)
    for config in (mf, cdr):
        config.pop("epochs")
        config.pop("patience")
    mf_trials = [dict(mf, lr=lr, weight_decay=wd) for lr, wd in
                 product((5e-5, 1e-5, 1e-3, 5e-4, 1e-4), (1e-5, 1e-6))]
    batches = ((128,256,512,1024,2048) if dataset == "coat" else
               (1024,2048,4096,8192,16384) if dataset == "yahoo" else (2048,4096,8192,16384,32768))
    cdr_trials = [dict(cdr, lr=lr, weight_decay=wd, un_thres=eta, batch_size=batch)
        for lr, wd, eta, batch in product((.005, .01, .05, .1),
            (1e-5, 5e-5, 1e-4, 5e-4, 1e-3, 5e-3, 1e-2),
            (.1, .5, 1, 3, 5, 7, 10, 50), batches)]
    return {"mf": [mf] + [trial for trial in mf_trials if trial != mf],
            "cdr": [cdr] + [trial for trial in cdr_trials if trial != cdr]}


def released_tuning_grids(dataset):
    """Published Cartesian ranges applied to the released estimator/variance."""
    grids = tuning_grids(dataset)
    base = released_cdr_config(dataset)
    base.pop("epochs")
    trials = [dict(base, **{key:trial[key] for key in ("lr","weight_decay","un_thres","batch_size")})
              for trial in grids["cdr"]]
    grids["cdr"] = [base] + [trial for trial in trials if trial != base]
    return grids
