"""
Model loader with S3 fallback, caching, and structured error handling.
The model is downloaded by the init container to MODEL_PATH.
This module simply loads it into memory on first call and caches it.
"""
import logging
import os
from functools import lru_cache
from pathlib import Path

import joblib

logger = logging.getLogger("credit-risk-api.model_loader")

# MODEL_PATH is populated by the init container downloading from S3.
# The path is mounted from an emptyDir shared volume.
MODEL_PATH = os.getenv("MODEL_PATH", "/app/model/model.pkl")


class ModelLoadError(RuntimeError):
    """Raised when the model cannot be loaded from disk."""


@lru_cache(maxsize=1)
def load_model(model_path: str = MODEL_PATH):
    """
    Load the scikit-learn model from MODEL_PATH.
    Result is cached in-process — subsequent calls return the cached object.
    Cache is intentionally not invalidated during runtime; a pod restart
    triggers the init container to re-download the latest model from S3.
    """
    path = Path(model_path)

    if not path.exists():
        raise ModelLoadError(
            f"Model file not found at {path}. "
            "Ensure the init container completed successfully and the "
            "model-volume is correctly mounted."
        )

    try:
        model = joblib.load(path)
    except Exception as exc:
        raise ModelLoadError(f"Failed to deserialise model from {path}: {exc}") from exc

    if not hasattr(model, "predict"):
        raise ModelLoadError(
            "Loaded object does not implement .predict() — "
            "ensure it is a valid scikit-learn estimator."
        )

    if not hasattr(model, "predict_proba"):
        raise ModelLoadError(
            "Loaded model does not implement .predict_proba() — "
            "required for probability output. Use a classifier that supports it."
        )

    logger.info("Model loaded successfully", extra={"model_path": str(path)})
    return model
