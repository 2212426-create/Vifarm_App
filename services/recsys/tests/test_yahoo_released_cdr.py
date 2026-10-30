"""Yahoo ID/proxy integrity and numerical parity with pinned upstream CDR."""
import ast
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from src.data_pipeline.yahoo_dataset import load_yahoo_processed, subset_yahoo_users, YAHOO_PREFIX
from src.causal.cdr.released import ReleasedCDR, fit_released, released_inverse_propensity
from src.utils.artifacts import data_signature, evaluate_checkpoint


def yahoo_fixture(folder):
    train=np.array([[u,i,5 if i==1 else 1] for u in range(1,7) for i in [1,2]])
    random=np.array([[u,i,5 if i==3 else 1] for u in range(1,5) for i in [1,2,3,4]])
    survey=np.array([[5,4,3,2,1,5,2]]*4)
    for key,array in [('train',train),('test',random),('survey-answers',survey)]:
        np.savetxt(Path(folder)/f'{YAHOO_PREFIX}{key}.txt',array,fmt='%d',delimiter='\t')
    return load_yahoo_processed(data_dir=folder)


class YahooDataTests(unittest.TestCase):
    def test_one_based_ids_survey_rows_and_missing_users_align(self):
        with tempfile.TemporaryDirectory() as folder:
            data=yahoo_fixture(folder)
        self.assertEqual((data['n_users'],data['n_items']), (6,4))
        self.assertEqual((data['train_u'].min(),data['train_u'].max()),(0,5))
        self.assertEqual(data['user_features'].shape,(6,39))
        self.assertEqual(data['user_feature_info']['missing_proxy_users'],2)
        np.testing.assert_array_equal(data['user_features'][4],data['user_features'][5])
        self.assertFalse(np.array_equal(data['user_features'][0],data['user_features'][4]))
        self.assertFalse(set(data['val_candidates']) & set(data['test_candidates']))
        self.assertTrue(all(len(items)==4 for items in data['test_candidates'].values()))

    def test_proxies_do_not_depend_on_random_ratings_and_affect_data_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            data=yahoo_fixture(folder)
            path=Path(folder)/f'{YAHOO_PREFIX}test.txt'
            values=np.loadtxt(path,dtype=int); values[:,2]=np.where(values[:,2]==5,4,2)
            np.savetxt(path,values,fmt='%d')
            changed=load_yahoo_processed(data_dir=folder)
        np.testing.assert_array_equal(data['user_features'],changed['user_features'])
        before=data_signature(data)['sha256']
        data['user_features']=data['user_features'].copy();data['user_features'][0,0]=1
        self.assertNotEqual(before,data_signature(data)['sha256'])

    def test_smoke_remaps_users_and_preserves_survey_alignment(self):
        with tempfile.TemporaryDirectory() as folder:
            data=yahoo_fixture(folder)
        subset=subset_yahoo_users(data,4)
        self.assertEqual(subset['n_users'],4)
        self.assertLess(subset['train_u'].max(),4)
        for new,old in enumerate(subset['split_info']['original_user_ids']):
            np.testing.assert_array_equal(subset['user_features'][new],data['user_features'][old])


class ReleasedCDRParityTests(unittest.TestCase):
    def test_three_cpu_epochs_match_upstream_parameters_exactly(self):
        folder=Path(__file__).resolve().parents[1]/'docs/archive/2026-10-20/cdr_followup_audit/runners_and_source.zip'
        namespace=dict(np=np,torch=torch,nn=nn,F=F)
        with zipfile.ZipFile(folder) as z:
            for file,names in [('utils.py',{'McDropout'}),('MF_mcdropout.py',
                    {'generate_total_sample','MF_BaseModel','MF_McdropoutModel','MF_DR_BIAS_MCDROPOUT'})]:
                tree=ast.parse(z.read('original/'+file).decode('utf-8'))
                nodes=[n for n in tree.body if isinstance(n,(ast.ClassDef,ast.FunctionDef)) and n.name in names]
                self.assertEqual({n.name for n in nodes},names)
                exec(compile(ast.Module(body=nodes,type_ignores=[]),file,'exec'),namespace)
        x=np.array([[0,0],[0,2],[1,1],[1,3],[2,0],[2,4],[3,1],[3,5]])
        y=np.array([0,1,1,0,0,1,1,0]); calibration=np.array([1,0,0,1])
        np.random.seed(42);torch.manual_seed(42)
        reference=namespace['MF_DR_BIAS_MCDROPOUT'](4,6)
        with contextlib.redirect_stdout(io.StringIO()):
            reference.fit(x,y,calibration,num_epoch=3,batch_size=2,lr=.05,lamb=.001,G=1,stop=999)
        np.random.seed(42);torch.manual_seed(42)
        port=ReleasedCDR(4,6)
        w,_=released_inverse_propensity(x,y,calibration)
        fit_released(port,x,y,w,epochs=3,batch_size=2,lr=.05,weight_decay=.001,G=1,stop=999)
        for branch,old in [('rec_model','prediction_model'),('imp_model','imputation')]:
            for matrix in ['W','H']:
                torch.testing.assert_close(port.state_dict()[f'{branch}.{matrix}.weight'],
                    reference.state_dict()[f'{old}.{matrix}.weight'],rtol=0,atol=0)

    def test_yahoo_three_models_train_without_test_selection_and_released_checkpoint_reloads(self):
        from src.baselines.train_mf import train_baseline_mf
        from src.causal.idcf.train_idcf import fit_idcf_pipeline
        from src.causal.cdr.train_released_cdr import train_released_cdr
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            data=yahoo_fixture(folder)
            for name,run in [('mf',lambda:train_baseline_mf('yahoo',data_dict=data,epochs=1,batch_size=2,
                    checkpoint_dir=folder,evaluate_test=False)),
                    ('idcf',lambda:fit_idcf_pipeline(data,'yahoo',epochs=1,ivae_epochs=2,checkpoint_dir=folder,
                    train_overrides={'batch_size':2},evaluate_test=False)),
                    ('cdr',lambda:train_released_cdr('yahoo',data,epochs=1,batch_size=2,checkpoint_dir=folder,
                    evaluate_test=False))]:
                with self.subTest(model=name):
                    result=run()
                    self.assertTrue(np.isfinite(result['best_val_ndcg']))
                    if name=='cdr':
                        self.assertFalse(result['metadata']['config']['propensity_calibration']['test_labels_used'])
                        scored=evaluate_checkpoint(result['checkpoint_path'],data)
                        self.assertEqual(scored['objective_revision'],'cdr_released_v1')


if __name__=='__main__': unittest.main()
