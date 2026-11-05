"""Neighbourhood and non-personalised baselines after Dacrema et al., RecSys 2019."""
from src.models.neighborhood.recommenders import ItemKNNCF, TopPop

__all__ = ["ItemKNNCF", "TopPop"]
