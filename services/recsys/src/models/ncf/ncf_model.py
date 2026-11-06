"""GMF, MLP and NeuMF in PyTorch, following the author's Keras code.

Reference: X. He et al., "Neural Collaborative Filtering", WWW 2017,
github.com/hexiangnan/neural_collaborative_filtering @ 4aab159, files GMF.py, MLP.py, NeuMF.py.
"""
import math

import numpy as np
import torch
import torch.nn as nn

VARIANTS = ("gmf", "mlp", "neumf")


class NCF(nn.Module):
    """One class for the three NCF models.

    embedding_dim is the author's num_factors (GMF part). layers[0] is the size of the concatenated MLP input,
    so each MLP embedding has layers[0] // 2 entries, and Dense layers follow layers[1:] with ReLU.
    The output is a logit; the author's sigmoid is applied inside the loss.
    """

    def __init__(self, num_users, num_items, variant="neumf", embedding_dim=8, layers=(64, 32, 16, 8)):
        super().__init__()
        if variant not in VARIANTS:
            raise ValueError(f"variant must be one of {VARIANTS}")
        layers = tuple(int(size) for size in layers)
        if variant != "gmf" and (len(layers) < 2 or layers[0] % 2):
            raise ValueError("layers needs an even input size and at least one hidden layer")
        self.variant, self.embedding_dim, self.layers = variant, int(embedding_dim), layers
        predictive = 0
        if variant in ("gmf", "neumf"):
            self.gmf_user = nn.Embedding(num_users, self.embedding_dim)
            self.gmf_item = nn.Embedding(num_items, self.embedding_dim)
            predictive += self.embedding_dim
        if variant in ("mlp", "neumf"):
            self.mlp_user = nn.Embedding(num_users, layers[0] // 2)
            self.mlp_item = nn.Embedding(num_items, layers[0] // 2)
            self.mlp_layers = nn.ModuleList(nn.Linear(a, b) for a, b in zip(layers[:-1], layers[1:]))
            predictive += layers[-1]
        self.prediction = nn.Linear(predictive, 1)
        self.reset_parameters()

    def reset_parameters(self):
        for module in self.modules():
            if isinstance(module, nn.Embedding):
                nn.init.normal_(module.weight, mean=0.0, std=0.01)  # init_normal: scale 0.01
        for layer in getattr(self, "mlp_layers", ()):
            nn.init.xavier_uniform_(layer.weight)  # Keras 1 Dense default init: glorot_uniform
            nn.init.zeros_(layer.bias)
        bound = math.sqrt(3.0 / self.prediction.in_features)  # init='lecun_uniform'
        nn.init.uniform_(self.prediction.weight, -bound, bound)
        nn.init.zeros_(self.prediction.bias)

    def features(self, users, items):
        parts = []
        if self.variant in ("gmf", "neumf"):
            parts.append(self.gmf_user(users) * self.gmf_item(items))
        if self.variant in ("mlp", "neumf"):
            vector = torch.cat([self.mlp_user(users), self.mlp_item(items)], dim=-1)
            for layer in self.mlp_layers:
                vector = torch.relu(layer(vector))
            parts.append(vector)
        return torch.cat(parts, dim=-1)

    def forward(self, users, items):
        return self.prediction(self.features(users, items)).squeeze(-1)

    def predict(self, user, items, device=None):
        device = device or self.prediction.weight.device
        items = torch.as_tensor(np.asarray(items), dtype=torch.long, device=device)
        users = torch.full_like(items, int(user))
        with torch.no_grad():
            return self(users, items).cpu().numpy()

    def load_pretrained(self, gmf, mlp, alpha=0.5):
        """NeuMF.load_pretrain_model: copy both towers, prediction = [alpha h_gmf, (1 - alpha) h_mlp]."""
        if self.variant != "neumf" or gmf.variant != "gmf" or mlp.variant != "mlp":
            raise ValueError("Pre-training loads a GMF and an MLP into a NeuMF")
        if gmf.embedding_dim != self.embedding_dim or mlp.layers != self.layers:
            raise ValueError("Pre-trained models must use the same sizes as NeuMF")
        with torch.no_grad():
            for name in ("gmf_user", "gmf_item"):
                getattr(self, name).weight.copy_(getattr(gmf, name).weight)
            for name in ("mlp_user", "mlp_item"):
                getattr(self, name).weight.copy_(getattr(mlp, name).weight)
            for target, source in zip(self.mlp_layers, mlp.mlp_layers):
                target.weight.copy_(source.weight)
                target.bias.copy_(source.bias)
            self.prediction.weight.copy_(torch.cat([alpha * gmf.prediction.weight,
                                                    (1 - alpha) * mlp.prediction.weight], dim=1))
            self.prediction.bias.copy_(alpha * gmf.prediction.bias + (1 - alpha) * mlp.prediction.bias)
        return self
