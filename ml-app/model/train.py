"""
Loan Default Prediction - Model Training Script
Trains a RandomForestClassifier and saves it with MLflow tracking.
"""

import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
import joblib
import json
import os

# Generate synthetic loan dataset
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

# Create target: higher chance of default with low credit score, high loan, low income
default_probability = (
    (800 - data["credit_score"]) / 500
    + (data["loan_amount"] / data["income"]) * 2
    + (data["num_existing_loans"] / 10)
    - (data["employment_years"] / 30)
)
default_probability = (default_probability - default_probability.min()) / (default_probability.max() - default_probability.min())
data["default"] = (default_probability > 0.5).astype(int)

print(f"Dataset shape: {data.shape}")
print(f"Default rate: {data['default'].mean():.2%}")

# Split data
features = ["age", "income", "loan_amount", "credit_score", "employment_years", "num_existing_loans"]
X = data[features]
y = data["default"]
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# Train model
model = RandomForestClassifier(n_estimators=100, max_depth=10, random_state=42)
model.fit(X_train, y_train)

# Evaluate
y_pred = model.predict(X_test)
metrics = {
    "accuracy": round(accuracy_score(y_test, y_pred), 4),
    "precision": round(precision_score(y_test, y_pred), 4),
    "recall": round(recall_score(y_test, y_pred), 4),
    "f1_score": round(f1_score(y_test, y_pred), 4),
}

print("\n=== Model Metrics ===")
for metric, value in metrics.items():
    print(f"  {metric}: {value}")

# Save model and artifacts
os.makedirs("model/artifacts", exist_ok=True)
joblib.dump(model, "model/artifacts/model.joblib")

# Save test data for validation
X_test.to_csv("model/artifacts/test_data.csv", index=False)
y_test.to_csv("model/artifacts/test_labels.csv", index=False)

# Save metrics
with open("model/artifacts/metrics.json", "w") as f:
    json.dump(metrics, f, indent=2)

# Save feature schema (used for input validation in API)
schema = {
    "features": features,
    "dtypes": {col: str(X[col].dtype) for col in features},
    "ranges": {col: {"min": int(X[col].min()), "max": int(X[col].max())} for col in features},
}
with open("model/artifacts/schema.json", "w") as f:
    json.dump(schema, f, indent=2)

print("\nModel and artifacts saved to model/artifacts/")
