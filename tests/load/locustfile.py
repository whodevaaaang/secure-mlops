"""
SecureMLOps Load Testing with Locust
Simulates realistic traffic patterns against the loan prediction API.

Usage:
    # Web UI mode (interactive):
    locust -f tests/load/locustfile.py --host http://localhost:8080

    # Headless mode (CI-friendly):
    locust -f tests/load/locustfile.py --host http://localhost:8080 \
        --headless -u 50 -r 5 -t 60s --csv=tests/load/results/report
"""

import random
from locust import HttpUser, task, between, tag


# Realistic test data ranges based on the training data
SAMPLE_APPLICATIONS = [
    # Low risk profiles
    {"age": 45, "income": 95000, "loan_amount": 10000, "credit_score": 780, "employment_years": 20, "num_existing_loans": 1},
    {"age": 35, "income": 75000, "loan_amount": 15000, "credit_score": 720, "employment_years": 10, "num_existing_loans": 2},
    {"age": 55, "income": 120000, "loan_amount": 20000, "credit_score": 800, "employment_years": 25, "num_existing_loans": 0},
    # Medium risk profiles
    {"age": 28, "income": 45000, "loan_amount": 25000, "credit_score": 650, "employment_years": 3, "num_existing_loans": 4},
    {"age": 32, "income": 38000, "loan_amount": 30000, "credit_score": 620, "employment_years": 5, "num_existing_loans": 5},
    # High risk profiles
    {"age": 22, "income": 25000, "loan_amount": 40000, "credit_score": 520, "employment_years": 1, "num_existing_loans": 8},
    {"age": 19, "income": 18000, "loan_amount": 35000, "credit_score": 480, "employment_years": 0, "num_existing_loans": 10},
]


def random_application():
    """Generate a randomized loan application within valid ranges."""
    return {
        "age": random.randint(18, 80),
        "income": random.randint(15000, 200000),
        "loan_amount": random.randint(1000, 100000),
        "credit_score": random.randint(300, 850),
        "employment_years": random.randint(0, 40),
        "num_existing_loans": random.randint(0, 15),
    }


class MLOpsAPIUser(HttpUser):
    """Simulates a user making requests to the ML prediction API."""
    wait_time = between(0.5, 2.0)

    @tag("health")
    @task(1)
    def health_check(self):
        """GET /health - liveness probe"""
        self.client.get("/health", name="/health")

    @tag("health")
    @task(1)
    def readiness_check(self):
        """GET /ready - readiness probe"""
        self.client.get("/ready", name="/ready")

    @tag("predict")
    @task(5)
    def predict_sample(self):
        """POST /predict with a pre-defined sample application."""
        payload = random.choice(SAMPLE_APPLICATIONS)
        self.client.post("/predict", json=payload, name="/predict (sample)")

    @tag("predict")
    @task(3)
    def predict_random(self):
        """POST /predict with a randomly generated application."""
        payload = random_application()
        self.client.post("/predict", json=payload, name="/predict (random)")

    @tag("info")
    @task(1)
    def model_info(self):
        """GET /model/info - model metadata."""
        self.client.get("/model/info", name="/model/info")

    @tag("docs")
    @task(1)
    def swagger_docs(self):
        """GET /docs - Swagger UI (simulates developer traffic)."""
        self.client.get("/docs", name="/docs")


class HeavyLoadUser(HttpUser):
    """Simulates burst traffic focused on the prediction endpoint."""
    wait_time = between(0.1, 0.5)
    weight = 1  # Lower weight — fewer of these users in the mix

    @task
    def rapid_predictions(self):
        """POST /predict - high-frequency predictions."""
        payload = random_application()
        self.client.post("/predict", json=payload, name="/predict (burst)")
