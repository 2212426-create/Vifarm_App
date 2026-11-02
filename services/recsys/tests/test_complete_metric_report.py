"""Hand-calculated source auxiliaries and explicit mixed-protocol reporting."""
import unittest
import numpy as np
import torch
from src.causal.cdr.source_protocol import source_metrics
from experiments.workflows.run_all_benchmarks import get_benchmark_tables_data


class Scores(torch.nn.Module):
    def __init__(self):
        super().__init__();self.anchor=torch.nn.Parameter(torch.zeros(1))
    def forward(self,users,items):return (10-items.float())/10 + self.anchor*0


class CompleteMetricTests(unittest.TestCase):
    def test_both_recalls_precision_and_hit_rate_match_hand_calculation(self):
        x=np.array([[u,i] for u in range(3) for i in range(10)])
        y=np.array([1,1,1,1,0,0,1,1,1,1]+[0]*10+[0]*8+[1,1])
        m=source_metrics(Scores(),x,y)
        self.assertAlmostEqual(m['Recall@5'],(.5+1+0)/3)
        self.assertAlmostEqual(m['Recall@5_bounded'],(.8+1+0)/3)
        self.assertAlmostEqual(m['Precision@5'],.8/3)
        self.assertAlmostEqual(m['HitRate@5'],1/3)
        discount=1/np.log2(np.arange(2,7))
        self.assertAlmostEqual(m['NDCG@5'],(discount[:4].sum()/discount.sum()+1)/3)
        local=source_metrics(Scores(),x,y,include_empty=False,bounded=False)
        self.assertAlmostEqual(local['Recall@5'],.25)
        self.assertAlmostEqual(local['Recall@5_bounded'],.4)
        self.assertAlmostEqual(local['Precision@5'],.4)
        self.assertAlmostEqual(local['HitRate@5'],.5)
        self.assertEqual(local['users'],2)

    def test_precision_uses_k_even_if_candidate_pool_is_short(self):
        m=source_metrics(Scores(),np.array([[0,0],[0,1]]),np.array([1,0]))
        self.assertAlmostEqual(m['Precision@5'],.2)
        self.assertEqual(m['Recall@5'],1.)
        self.assertEqual(m['Recall@5_bounded'],1.)
        self.assertEqual(m['HitRate@5'],1.)

    def test_unified_rows_retain_protocol_and_auc_type(self):
        base={'NDCG@5':.3,'Recall@5':.2,'Recall@5_bounded':.4,
              'Precision@5':.1,'HitRate@5':.5}
        results={d:{'MF':dict(base,AUC=.6),'iDCF':dict(base,AUC=.7),'IViDR':dict(base,AUC=.65),
            'DR-BIAS + CDR':dict(base,AUC_global=.8,evaluation_scope='cdr_source_protocol')}
            for d in ('coat','yahoo','kuairand')}
        headers,rows=get_benchmark_tables_data(results)
        self.assertEqual(len(rows),12)
        self.assertEqual(sum(row[1]=='IViDR-approx' for row in rows),3)
        self.assertTrue(all('N/A' not in row for row in rows))
        for row in rows:
            self.assertEqual(len(row),len(headers))
            if row[1]=='DR-BIAS + CDR':
                self.assertIn(row[2],('S-full','S-KR'))
                self.assertEqual(row[-2:],['0.800000','global'])
            else:
                self.assertEqual((row[2],row[-1]),('H30','macro-user'))

    def test_lcdr_and_conalign_rows_keep_their_protocols(self):
        from experiments.workflows.run_all_benchmarks import generate_console_grid_report
        base={'NDCG@5':.3,'Recall@5':.2,'Recall@5_bounded':.4,'Precision@5':.1,'HitRate@5':.5}
        conalign={'NDCG@5':.7,'UNDCG@5':.71,'UAUC':.68,'AUC_global':.75,'Precision@5':.32,
                  'Recall@5_source':.88,'evaluation_scope':'conalign_source_protocol'}
        results={d:{'iDCF':dict(base,AUC=.7),'LCDR':dict(base,AUC=.69),'ConAlign':dict(conalign)}
                 for d in ('coat','yahoo','kuairand')}
        headers,rows=get_benchmark_tables_data(results)
        self.assertEqual([row[1] for row in rows[:3]],['iDCF','LCDR','ConAlign'])
        for row in rows:
            if row[1]=='LCDR':
                self.assertEqual((row[2],row[-1]),('H30','macro-user'))
            if row[1]=='ConAlign':
                self.assertEqual(row[2],'C-src')
                self.assertEqual(row[3:],['0.700000','N/A','0.320000','N/A','0.750000','global'])
        report=generate_console_grid_report(results)
        self.assertIn('ConAlign Coat: UAUC 0.680000 | UNDCG@5 0.710000',report)
        self.assertIn('C-src:',report)


if __name__=='__main__':unittest.main()
