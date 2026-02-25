import os

os.environ["MODEL_PATH"] = os.path.join(os.path.dirname(__file__), "..", "model", "artifacts", "model.joblib")
os.environ["SCHEMA_PATH"] = os.path.join(os.path.dirname(__file__), "..", "model", "artifacts", "schema.json")
os.environ["METRICS_PATH"] = os.path.join(os.path.dirname(__file__), "..", "model", "artifacts", "metrics.json")
