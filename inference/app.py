"""
Credit Risk Prediction API
FastAPI inference service for EKS deployment.
"""
import json
import logging
import os
import time
import uuid
from contextlib import asynccontextmanager
from math import isfinite
from typing import List, Optional

import numpy as np
from fastapi import FastAPI, HTTPException, Request, Response
from pydantic import BaseModel, Field, field_validator
from prometheus_fastapi_instrumentator import Instrumentator

from model_loader import MODEL_PATH, ModelLoadError, load_model

# ── Structured JSON logging ─────────────────────────────────────────
class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": "credit-risk-api",
            "environment": os.getenv("ENVIRONMENT", "unknown"),
        }
        if record.exc_info:
            log_entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(log_entry)

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger("credit-risk-api")

EXPECTED_FEATURES = int(os.getenv("EXPECTED_FEATURES", "20"))


# ── Lifespan (replaces deprecated @app.on_event) ────────────────────
# FIX: Use lifespan context manager (FastAPI >= 0.93) instead of
#      deprecated on_event("startup").
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Starting up — preloading model", extra={"model_path": MODEL_PATH})
    try:
        load_model()
        logger.info("Model loaded successfully")
    except ModelLoadError as exc:
        logger.error("Failed to preload model", extra={"error": str(exc)})
        raise
    yield
    logger.info("Shutting down")


app = FastAPI(
    title="Credit Risk Prediction API",
    version="1.0.0",
    description="FastAPI service for credit risk inference",
    lifespan=lifespan,
)

Instrumentator().instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


# ── Request / Response models ────────────────────────────────────────
class PredictRequest(BaseModel):
    features: List[float] = Field(
        ..., description=f"Feature vector with exactly {EXPECTED_FEATURES} values"
    )
    request_id: Optional[str] = Field(
        default=None, description="Optional idempotency / tracing key"
    )

    @field_validator("features")
    @classmethod
    def validate_features(cls, values: List[float]) -> List[float]:
        if len(values) != EXPECTED_FEATURES:
            raise ValueError(f"Expected {EXPECTED_FEATURES} features, got {len(values)}")
        if not all(isfinite(v) for v in values):
            raise ValueError("All feature values must be finite numbers")
        return values


class PredictResponse(BaseModel):
    prediction: int = Field(..., ge=0, le=1)
    probability: float = Field(..., ge=0.0, le=1.0)
    request_id: str
    latency_ms: float


# ── Middleware: request ID propagation ──────────────────────────────
@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-ID", str(uuid.uuid4()))
    start = time.perf_counter()
    response: Response = await call_next(request)
    latency = (time.perf_counter() - start) * 1000
    response.headers["X-Request-ID"] = request_id
    response.headers["X-Response-Time-Ms"] = f"{latency:.2f}"
    return response


# ── Health endpoint ──────────────────────────────────────────────────
@app.get("/health")
def health() -> dict:
    try:
        load_model()
        # FIX: Don't expose internal model path in response (info leak)
        return {"status": "ok", "model_loaded": True}
    except ModelLoadError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


# ── Predict endpoint ─────────────────────────────────────────────────
@app.post("/predict", response_model=PredictResponse)
def predict(payload: PredictRequest, request: Request) -> PredictResponse:
    request_id = payload.request_id or request.headers.get("X-Request-ID", str(uuid.uuid4()))
    start = time.perf_counter()

    logger.info("Prediction request", extra={"request_id": request_id})

    try:
        model = load_model()
        features = np.array(payload.features, dtype=np.float64).reshape(1, -1)

        prediction = int(model.predict(features)[0])

        if hasattr(model, "predict_proba"):
            probability = float(model.predict_proba(features)[0][1])
        else:
            # FIX: Raise instead of silently returning misleading 0.0/1.0
            raise HTTPException(
                status_code=500,
                detail="Model does not support probability estimates (predict_proba missing)"
            )

        latency_ms = (time.perf_counter() - start) * 1000
        logger.info(
            "Prediction complete",
            extra={
                "request_id": request_id,
                "prediction": prediction,
                "probability": round(probability, 4),
                "latency_ms": round(latency_ms, 2),
            },
        )

        return PredictResponse(
            prediction=prediction,
            probability=probability,
            request_id=request_id,
            latency_ms=round(latency_ms, 2),
        )

    except ModelLoadError as exc:
        logger.error("Model load error", extra={"request_id": request_id, "error": str(exc)})
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=f"Invalid input: {exc}") from exc
    except HTTPException:
        raise
    except Exception as exc:
        logger.error("Unexpected inference error", extra={"request_id": request_id, "error": str(exc)})
        raise HTTPException(status_code=500, detail="Inference failed") from exc
