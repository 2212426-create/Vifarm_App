"""Uniform sampling of catalog pairs without materializing the dense catalog."""
import torch


class CounterfactualSampler:
    def __init__(self, num_users, num_items, train_u, train_i, pool="all", device="cpu"):
        if pool not in ("all", "unobserved"):
            raise ValueError("counterfactual_pool must be all or unobserved")
        self.num_items, self.device = num_items, torch.device(device)
        self.size = num_users * num_items
        self.observed_offsets = None
        if pool == "unobserved":
            users = torch.as_tensor(train_u, dtype=torch.long, device=self.device)
            items = torch.as_tensor(train_i, dtype=torch.long, device=self.device)
            observed = torch.unique(users * num_items + items, sorted=True)
            self.size -= len(observed)
            # Map a rank in the missing pairs to a flattened catalog ID. Equal
            # offsets represent consecutive observed IDs and require right=True.
            self.observed_offsets = observed - torch.arange(len(observed), device=self.device)
        if self.size < 1:
            raise ValueError("Counterfactual candidate pool is empty")

    def sample(self, count):
        ids = torch.randint(self.size, (count,), device=self.device)
        if self.observed_offsets is not None:
            ids = ids + torch.searchsorted(self.observed_offsets, ids, right=True)
        return ids // self.num_items, ids % self.num_items
