FROM python:3.10-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY drift_detector.py .

# Reference data is mounted via volume
ENTRYPOINT ["python", "drift_detector.py"]
