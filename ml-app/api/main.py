"""
Loan Default Prediction API
FastAPI application serving the trained model.
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
import joblib
import json
import time
import os
import numpy as np
import pandas as pd

app = FastAPI(
    title="SecureMLOps - Loan Default Prediction API",
    description="Predicts whether a loan applicant is likely to default",
    version="1.0.0",
)

# Load model and schema at startup
_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_PATH = os.getenv("MODEL_PATH", os.path.join(_dir, "model", "artifacts", "model.joblib"))
SCHEMA_PATH = os.getenv("SCHEMA_PATH", os.path.join(_dir, "model", "artifacts", "schema.json"))

model = None
schema = None

@app.on_event("startup")
def load_model():
    global model, schema
    if os.path.exists(MODEL_PATH):
        model = joblib.load(MODEL_PATH)
        print(f"Model loaded from {MODEL_PATH}")
    else:
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

    return PredictionResponse(
        prediction="DEFAULT" if prediction == 1 else "NO DEFAULT",
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
