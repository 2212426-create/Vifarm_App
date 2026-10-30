"""Source-default dispatch, scientific metric boundaries and serving adaptation."""
import unittest
from unittest.mock import patch
import numpy as np
import torch
from src.causal.cdr.released import ReleasedCDR,fit_released
from src.causal.cdr.source_protocol import source_metrics
from src.training.config import released_cdr_config,released_tuning_grids


class SourceDefaultTests(unittest.TestCase):
    def test_source_metrics_keep_empty_users_bounded_recall_and_global_auc(self):
        model=ReleasedCDR(2,3)
        with torch.no_grad():
            for p in model.parameters(): p.zero_()
        x=np.array([[u,i] for u in range(2) for i in range(3)])
        y=np.array([1,1,0,0,0,0])
        source=source_metrics(model,x,y,k=1)
        self.assertEqual(source['users'],2)
        self.assertEqual(source['NDCG@5'],1.)
        self.assertEqual(source['Recall@5_bounded'],1.)
        self.assertEqual(source['AUC_global'],.5)
        local=source_metrics(model,x,y,k=1,include_empty=False,bounded=False)
        self.assertEqual(local['users'],1)
        self.assertEqual(local['Recall@5'],.5)

    def test_all_source_defaults_and_tuning_grids_use_released_estimator(self):
        for dataset in ('coat','yahoo','kuairand'):
            cfg=released_cdr_config(dataset)
            self.assertEqual((cfg['epochs'],cfg['embedding_dim'],cfg['un_thres']),(1000,4,10.))
            grid=released_tuning_grids(dataset)['cdr']
            self.assertEqual(len(grid),1120)
            self.assertFalse(any('ips_weighting' in row for row in grid))
            self.assertEqual(grid[0]['dropout_rate'],.7 if dataset=='yahoo' else .5)

    def test_source_checkpoint_does_not_enter_shared_paired_test(self):
        from experiments.workflows.run_all_benchmarks import paired_significance
        with patch('experiments.workflows.run_all_benchmarks.evaluate_popularity',return_value={}), \
                patch('experiments.workflows.run_all_benchmarks.evaluate_checkpoint') as evaluate:
            result=paired_significance({'DR-BIAS + CDR':dict(checkpoint_path='source.pt',
                evaluation_scope='cdr_source_protocol')},{})
        evaluate.assert_not_called()
        self.assertEqual(result,{})

    def test_serving_sampler_handles_more_events_than_catalog_pairs(self):
        model=ReleasedCDR(2,2)
        x=np.tile(np.array([[0,0],[1,1]]),(4,1));y=np.tile([0,1],4)
        history=fit_released(model,x,y,torch.ones(8),epochs=1,batch_size=4,G=1,
                             catalog_sampler='replacement')
        self.assertTrue(np.isfinite(history[0]['rec_loss']))


if __name__=='__main__':unittest.main()
