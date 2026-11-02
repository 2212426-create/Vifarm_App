"""Canonical published-source CDR workflow (also used by benchmark and seeds)."""
import argparse
from src.models.cdr.source_protocol import run_source, source_metrics

def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dataset",choices=["coat","yahoo","kuairand"],required=True)
    p.add_argument("--epochs",type=int,default=1000)
    p.add_argument("--seed",type=int,default=2020)
    p.add_argument("--threads",type=int,default=2)
    p.add_argument("--device",choices=["cpu","cuda"],default="cpu")
    p.add_argument("--data-dir",default=None)
    p.add_argument("--smoke-users",type=int,default=None,help="KuaiRand local smoke subset")
    a=p.parse_args(argv)
    run_source(a.dataset,a.epochs,a.seed,a.threads,data_dir=a.data_dir,smoke_users=a.smoke_users,device=a.device)

if __name__=="__main__": main()
