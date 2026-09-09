"""
Simple ML API — used as the sample application for the Helm chart demo.

This is intentionally minimal. In real usage, replace this with your actual
model inference endpoint. The Helm chart is completely decoupled from this code.
"""

from fastapi import FastAPI
from pydantic import BaseModel
import os

app = FastAPI(
    title="ML API",
    description="Sample ML model serving API",
    version=os.getenv("APP_VERSION", "1.0.0"),
)


class PredictionResponse(BaseModel):
    message: str
    environment: str
    version: str


@app.get("/", response_model=PredictionResponse)
def root():
    return PredictionResponse(
        message="Hello World from ML API",
        environment=os.getenv("ENVIRONMENT", "unknown"),
        version=os.getenv("APP_VERSION", "1.0.0"),
    )


@app.get("/health")
def health():
    """Liveness probe endpoint."""
    return {"status": "healthy"}


@app.get("/ready")
def ready():
    """Readiness probe endpoint."""
    return {"status": "ready"}


@app.get("/predict")
def predict(input: str = "default"):
    """
    Stub prediction endpoint.
    Replace this with actual model inference logic.
    """
    return {
        "input": input,
        "prediction": "This is a stub. Swap in your model here.",
        "environment": os.getenv("ENVIRONMENT", "unknown"),
    }
