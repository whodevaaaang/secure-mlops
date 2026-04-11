"""
Loan Default Prediction API
FastAPI application serving the trained model.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Counter, Histogram, Gauge
import csv
import joblib
import json
import logging
import time
import os
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

app = FastAPI(
    title="SecureMLOps - Loan Default Prediction API",
    description="Predicts whether a loan applicant is likely to default",
    version="1.0.0",
)

# Prometheus metrics
PREDICTION_COUNT = Counter(
    "ml_predictions_total",
    "Total number of predictions",
    ["prediction", "risk_level"],
)
PREDICTION_LATENCY = Histogram(
    "ml_prediction_duration_seconds",
    "Time spent processing prediction requests",
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0],
)
DEFAULT_PROBABILITY = Histogram(
    "ml_default_probability",
    "Distribution of predicted default probabilities",
    buckets=[0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0],
)
MODEL_LOADED = Gauge(
    "ml_model_loaded",
    "Whether the ML model is loaded (1=yes, 0=no)",
)

# Instrument FastAPI with default HTTP metrics + expose /metrics endpoint
Instrumentator(
    should_group_status_codes=True,
    should_ignore_untemplated=True,
    excluded_handlers=["/health", "/ready", "/metrics"],
).instrument(app).expose(app, include_in_schema=False)

# Load model and schema at startup
_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH = os.getenv("MODEL_PATH", os.path.join(_dir, "model", "artifacts", "model.joblib"))
SCHEMA_PATH = os.getenv("SCHEMA_PATH", os.path.join(_dir, "model", "artifacts", "schema.json"))

model = None
schema = None

# Prediction logging for drift detection
PREDICTION_LOG_DIR = os.getenv("PREDICTION_LOG_DIR", os.path.join(_dir, "data", "predictions"))
PREDICTION_LOG_FIELDS = ["age", "income", "loan_amount", "credit_score", "employment_years", "num_existing_loans"]


def log_prediction(input_data: dict):
    """Append prediction input to CSV for drift detection."""
    try:
        os.makedirs(PREDICTION_LOG_DIR, exist_ok=True)
        log_path = os.path.join(PREDICTION_LOG_DIR, "current.csv")
        file_exists = os.path.exists(log_path)
        with open(log_path, "a", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=PREDICTION_LOG_FIELDS)
            if not file_exists:
                writer.writeheader()
            writer.writerow({k: input_data[k] for k in PREDICTION_LOG_FIELDS})
    except Exception as e:
        logger.warning("Failed to log prediction for drift detection: %s", e)

@app.on_event("startup")
def load_model():
    global model, schema
    if os.path.exists(MODEL_PATH):
        model = joblib.load(MODEL_PATH)
        MODEL_LOADED.set(1)
        print(f"Model loaded from {MODEL_PATH}")
    else:
        MODEL_LOADED.set(0)
        print(f"WARNING: Model not found at {MODEL_PATH}")

    if os.path.exists(SCHEMA_PATH):
        with open(SCHEMA_PATH) as f:
            schema = json.load(f)
        print(f"Schema loaded from {SCHEMA_PATH}")


class LoanApplication(BaseModel):
    """Input schema for loan prediction"""
    age: int = Field(..., ge=18, le=100, description="Applicant age")
    income: int = Field(..., ge=0, description="Annual income in USD")
    loan_amount: int = Field(..., ge=0, description="Requested loan amount in USD")
    credit_score: int = Field(..., ge=300, le=850, description="Credit score")
    employment_years: int = Field(..., ge=0, le=50, description="Years of employment")
    num_existing_loans: int = Field(..., ge=0, le=20, description="Number of existing loans")


class PredictionResponse(BaseModel):
    """Output schema for loan prediction"""
    prediction: str
    default_probability: float
    risk_level: str
    inference_time_ms: float


@app.get("/health")
def health_check():
    """Health check endpoint for liveness probe"""
    return {
        "status": "healthy",
        "model_loaded": model is not None,
        "version": "1.0.0",
    }


@app.get("/ready")
def readiness_check():
    """Readiness check endpoint for K8s readiness probe"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")
    return {"status": "ready"}


@app.post("/predict", response_model=PredictionResponse)
def predict(application: LoanApplication):
    """Predict loan default probability"""
    if model is None:
        raise HTTPException(status_code=503, detail="Model not loaded")

    start_time = time.time()

    # Prepare input
    input_data = pd.DataFrame([{
        "age": application.age,
        "income": application.income,
        "loan_amount": application.loan_amount,
        "credit_score": application.credit_score,
        "employment_years": application.employment_years,
        "num_existing_loans": application.num_existing_loans,
    }])

    # Predict
    prediction = model.predict(input_data)[0]
    probability = model.predict_proba(input_data)[0]

    default_prob = round(float(probability[1]), 4)
    inference_time = round((time.time() - start_time) * 1000, 2)

    # Determine risk level
    if default_prob < 0.3:
        risk_level = "LOW"
    elif default_prob < 0.6:
        risk_level = "MEDIUM"
    else:
        risk_level = "HIGH"

    prediction_label = "DEFAULT" if prediction == 1 else "NO DEFAULT"

    # Log input for drift detection
    log_prediction(input_data.iloc[0].to_dict())

    # Record custom Prometheus metrics
    PREDICTION_COUNT.labels(prediction=prediction_label, risk_level=risk_level).inc()
    PREDICTION_LATENCY.observe(inference_time / 1000)  # convert ms to seconds
    DEFAULT_PROBABILITY.observe(default_prob)

    return PredictionResponse(
        prediction=prediction_label,
        default_probability=default_prob,
        risk_level=risk_level,
        inference_time_ms=inference_time,
    )


@app.get("/model/info")
def model_info():
    """Return model metadata"""
    metrics_path = os.getenv("METRICS_PATH", os.path.join(_dir, "model", "artifacts", "metrics.json"))
    metrics = {}
    if os.path.exists(metrics_path):
        with open(metrics_path) as f:
            metrics = json.load(f)

    return {
        "model_type": "RandomForestClassifier",
        "features": schema["features"] if schema else [],
        "metrics": metrics,
        "version": "1.0.0",
    }
