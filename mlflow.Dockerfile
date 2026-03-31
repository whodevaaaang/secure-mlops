FROM python:3.10-slim
RUN pip install mlflow==2.9.2 psycopg2-binary --no-cache-dir
EXPOSE 5000
CMD ["mlflow", "server", "--backend-store-uri", "postgresql://mlflow:mlflow123@postgres:5432/mlflow_db", "--default-artifact-root", "/mlflow/artifacts", "--host", "0.0.0.0", "--port", "5000"]
