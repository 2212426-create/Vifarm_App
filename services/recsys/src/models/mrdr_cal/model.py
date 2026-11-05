"""NeuMF and Platt scaling of Hu et al., "Uncertainty Calibration for Counterfactual Propensity Estimation in
Recommendation", IEEE TKDE 2025. Re-implemented from sunxin000/uncertainty4recsys @ 36dc7c6 (model/neumf.py,
model/layers.py, utils/platt.py); no file is copied.
"""
import torch
import torch.nn as nn
import torch.nn.functional as F


class MLPLayers(nn.Module):
    """model/layers.py (RecBole): [Dropout, Linear, ReLU] per layer, xavier_uniform weights, zero biases."""

    def __init__(self, layers, dropout=0.0):
        super().__init__()
        modules = []
        for input_size, output_size in zip(layers[:-1], layers[1:]):
            modules += [nn.Dropout(p=dropout), nn.Linear(input_size, output_size), nn.ReLU()]
        self.mlp_layers = nn.Sequential(*modules)
        for module in self.modules():
            if isinstance(module, nn.Linear):
                nn.init.xavier_uniform_(module.weight.data)
                module.bias.data.fill_(0.0)

    def forward(self, x):
        return self.mlp_layers(x)


class NeuMF(nn.Module):
    """model/neumf.py: separate GMF and MLP embeddings, dropout on all four embeddings, one prediction layer."""

    def __init__(self, num_users, num_items, mf_emb_size, mlp_emb_size, mlp_hidden_size, dropout=0.0,
                 output_logits=False):
        super().__init__()
        self.num_users, self.num_items = num_users, num_items
        self.mf_emb_size, self.mlp_emb_size, self.mlp_hidden_size = mf_emb_size, mlp_emb_size, list(mlp_hidden_size)
        self.dropout, self.output_logits = dropout, output_logits
        self.user_mf_embedding = nn.Embedding(num_users, mf_emb_size)
        self.item_mf_embedding = nn.Embedding(num_items, mf_emb_size)
        self.user_mlp_embedding = nn.Embedding(num_users, mlp_emb_size)
        self.item_mlp_embedding = nn.Embedding(num_items, mlp_emb_size)
        self.dropout_layer = nn.Dropout(p=dropout)
        self.mlp_layers = MLPLayers([2 * mlp_emb_size] + self.mlp_hidden_size, dropout)
        self.predict_layer = nn.Linear(mf_emb_size + self.mlp_hidden_size[-1], 1)
        for module in self.modules():
            if isinstance(module, nn.Embedding):
                nn.init.normal_(module.weight.data, mean=0.0, std=0.01)

    def forward(self, user, item):
        d = self.dropout_layer
        mf = torch.mul(d(self.user_mf_embedding(user)), d(self.item_mf_embedding(item)))
        mlp = self.mlp_layers(torch.cat((d(self.user_mlp_embedding(user)), d(self.item_mlp_embedding(item))), -1))
        logits = self.predict_layer(torch.cat((mf, mlp), -1)).squeeze(-1)
        return logits if self.output_logits else torch.sigmoid(logits)


class Platt(nn.Module):
    """utils/platt.py ModelWithPlatt: calibrated logit = a * logit + b, a = 0.6 and b = 0 at start,
    fitted with LBFGS (lr 0.01, max_iter 1000) on BCE-with-logits."""

    def __init__(self):
        super().__init__()
        self.a = nn.Parameter(torch.FloatTensor([0.6]))
        self.b = nn.Parameter(torch.FloatTensor([0.0]))

    def forward(self, logits):
        return torch.mul(logits, self.a) + self.b

    def fit(self, logits, labels, lr=0.01, max_iter=1000):
        logits, labels = logits.detach(), labels.float()
        optimizer = torch.optim.LBFGS([self.a, self.b], lr=lr, max_iter=max_iter)

        def closure():
            optimizer.zero_grad()
            loss = F.binary_cross_entropy_with_logits(self(logits), labels)
            loss.backward()
            return loss

        optimizer.step(closure)
        return {"a": float(self.a), "b": float(self.b),
                "nll_after": float(F.binary_cross_entropy_with_logits(self(logits), labels))}
