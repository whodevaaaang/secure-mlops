import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
import joblib
import json
import os
import mlflow
import mlflow.sklearn

mlflow.set_tracking_uri(os.getenv("MLFLOW_TRACKING_URI", "http://localhost:5000"))
mlflow.set_experiment("loan-default-prediction")

np.random.seed(42)
n_samples = 5000

data = pd.DataFrame({
    "age": np.random.randint(21, 65, n_samples),
    "income": np.random.randint(20000, 150000, n_samples),
    "loan_amount": np.random.randint(1000, 50000, n_samples),
    "credit_score": np.random.randint(300, 850, n_samples),
    "employment_years": np.random.randint(0, 30, n_samples),
    "num_existing_loans": np.random.randint(0, 10, n_samples),
})

default_probability = (
    (800 - data["credit_score"]) / 500
    + (data["loan_amount"] / data["income"]) * 2
    + (data["num_existing_loans"] / 10)
    - (data["employment_years"] / 30)
)
default_probability = (default_probability - default_probability.min()) / (default_probability.max() - default_probability.min())
data["default"] = (default_probability > 0.5).astype(int)

features = ["age", "income", "loan_amount", "credit_score", "employment_years", "num_existing_loans"]
X = data[features]
y = data["default"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

with mlflow.start_run(run_name="random_forest_v1"):
    params = {"n_estimators": 100, "max_depth": 10, "random_state": 42}
    mlflow.log_params(params)
    mlflow.log_param("n_samples", n_samples)
    mlflow.log_param("n_features", len(features))

    model = RandomForestClassifier(**params)
    model.fit(X_train, y_train)

    y_pred = model.predict(X_test)
    metrics = {
        "accuracy": round(accuracy_score(y_test, y_pred), 4),
        "precision": round(precision_score(y_test, y_pred), 4),
        "recall": round(recall_score(y_test, y_pred), 4),
        "f1_score": round(f1_score(y_test, y_pred), 4),
    }

    mlflow.log_metrics(metrics)

    os.makedirs("model/artifacts", exist_ok=True)
    joblib.dump(model, "model/artifacts/model.joblib")
    with open("model/artifacts/metrics.json", "w") as f:
        json.dump(metrics, f, indent=2)

    print("\n=== MLflow Run Complete ===")
    print(f"Run ID: {mlflow.active_run().info.run_id}")
    for metric, value in metrics.items():
        print(f"  {metric}: {value}")
    print("\nView at: http://localhost:5000")
