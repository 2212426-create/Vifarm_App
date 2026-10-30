"""Progress observation must not change optimization or stopping decisions."""
import unittest
import numpy as np
import torch
from src.causal.cdr.released import ReleasedCDR,fit_released
from src.causal.idcf.ivae import train_exposure_ivae


class TrainingProgressTests(unittest.TestCase):
    def test_cdr_progress_preserves_parameters_history_and_train_loss_stop(self):
        x=np.array([[0,0],[0,2],[1,1],[1,3],[2,0],[2,4],[3,1],[3,5]])
        y=np.array([0,1,1,0,0,1,1,0])
        seen=[]
        def observer(epoch,stats):
            seen.append(epoch)
            stats['rec_loss']=-999  # Callback receives an observational copy.
        results=[]
        for callback in (None,observer):
            np.random.seed(42);torch.manual_seed(42)
            model=ReleasedCDR(4,6)
            history=fit_released(model,x,y,torch.ones(8),epochs=20,batch_size=2,G=1,
                tol=1.,stop=0,on_progress=callback)
            results.append((model.state_dict(),history))
        self.assertLess(len(results[0][1]),20)
        self.assertEqual(seen,list(range(1,len(results[1][1])+1)))
        self.assertEqual(results[0][1],results[1][1])
        for key in results[0][0]:
            torch.testing.assert_close(results[0][0][key],results[1][0][key],rtol=0,atol=0)

    def test_ivae_progress_preserves_latents_and_checkpoint_selection(self):
        rng=np.random.RandomState(7)
        a=(rng.rand(12,8)>.6).astype(np.float32)
        w=rng.rand(12,3).astype(np.float32)
        seen=[]
        def observer(epoch,stats):
            self.assertTrue(np.isfinite(stats['train_loss']))
            seen.append(epoch)
        options=dict(latent_dim=2,hidden_dim=4,n_layers=2,epochs=6,batch_size=4,
                     patience=2,seed=42,device='cpu',validation_samples=2)
        plain=train_exposure_ivae(a,w,**options)
        logged=train_exposure_ivae(a,w,**options,on_progress=observer)
        torch.testing.assert_close(plain[0],logged[0],rtol=0,atol=0)
        torch.testing.assert_close(plain[1],logged[1],rtol=0,atol=0)
        self.assertEqual(plain[2],logged[2])
        self.assertEqual(seen,list(range(1,logged[2]['epochs_run']+1)))


if __name__=='__main__':unittest.main()
