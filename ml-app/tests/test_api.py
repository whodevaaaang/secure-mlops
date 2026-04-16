import os
import sys
import json

import joblib

# Add parent directory to path for api imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

BASE = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MODEL_FILE = os.path.join(BASE, "model", "artifacts", "model.joblib")
SCHEMA_FILE = os.path.join(BASE, "model", "artifacts", "schema.json")

# Set env vars before importing app
os.environ["MODEL_PATH"] = MODEL_FILE
os.environ["SCHEMA_PATH"] = SCHEMA_FILE
os.environ["METRICS_PATH"] = os.path.join(BASE, "model", "artifacts", "metrics.json")

import api.main as main_module  # noqa: E402
from api.main import app  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

# Load model directly (bypass lifespan for test client)
main_module.model = joblib.load(MODEL_FILE)
with open(SCHEMA_FILE) as f:
    main_module.schema = json.load(f)

client = TestClient(app)


def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"


def test_predict_valid_input():
    payload = {
        "age": 35, "income": 75000, "loan_amount": 15000,
        "credit_score": 720, "employment_years": 10, "num_existing_loans": 2,
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["prediction"] in ["DEFAULT", "NO DEFAULT"]
    assert 0 <= data["default_probability"] <= 1
    assert data["risk_level"] in ["LOW", "MEDIUM", "HIGH"]


def test_predict_high_risk():
    payload = {
        "age": 22, "income": 25000, "loan_amount": 45000,
        "credit_score": 350, "employment_years": 1, "num_existing_loans": 8,
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 200
    assert response.json()["risk_level"] in ["MEDIUM", "HIGH"]


def test_predict_low_risk():
    payload = {
        "age": 45, "income": 120000, "loan_amount": 5000,
        "credit_score": 800, "employment_years": 20, "num_existing_loans": 1,
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 200
    assert response.json()["risk_level"] in ["LOW", "MEDIUM"]


def test_predict_invalid_credit_score():
    payload = {
        "age": 30, "income": 50000, "loan_amount": 10000,
        "credit_score": 100, "employment_years": 5, "num_existing_loans": 1,
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 422


def test_predict_missing_field():
    payload = {"age": 30, "income": 50000}
    response = client.post("/predict", json=payload)
    assert response.status_code == 422


def test_model_info():
    response = client.get("/model/info")
    assert response.status_code == 200
    assert response.json()["model_type"] == "RandomForestClassifier"
