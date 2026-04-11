# SecureMLOps Architecture

## 1. Overall System Architecture

```mermaid
graph TB
    subgraph "Developer Workflow"
        DEV[Developer] -->|git push| GH[GitHub Repository]
        GH -->|webhook| JENKINS[Jenkins CI/CD]
    end

    subgraph "CI/CD Pipeline"
        JENKINS -->|build & test| BUILD[Docker Build]
        JENKINS -->|security scan| SEC[Security Scanning]
        JENKINS -->|deploy| HELM_DEPLOY[Helm Deploy]
    end

    subgraph "Minikube Kubernetes Cluster"
        subgraph "Application Namespace"
            SVC[Service<br/>NodePort:30080] --> POD1[ML API Pod 1<br/>FastAPI + Model]
            SVC --> POD2[ML API Pod 2<br/>FastAPI + Model]
            POD1 -->|writes| PVC_PRED[(Prediction Data<br/>PVC)]
            POD2 -->|writes| PVC_PRED
        end

        subgraph "Monitoring Stack"
            PROM[Prometheus<br/>Metrics Collection] -->|scrapes /metrics| POD1
            PROM -->|scrapes /metrics| POD2
            PROM -->|reads from| PUSHGW[Pushgateway<br/>Batch Metrics]
            GRAFANA[Grafana<br/>NodePort:31000] -->|queries| PROM
            SM[ServiceMonitor] -->|configures| PROM
            NODE_EXP[Node Exporter] -->|system metrics| PROM
            KUBE_STATE[kube-state-metrics] -->|K8s metrics| PROM
        end

        subgraph "Drift Detection"
            CRONJOB[CronJob<br/>Every 6h] -->|reads| PVC_PRED
            CRONJOB -->|reads| CM_REF[ConfigMap<br/>Reference Data]
            CRONJOB -->|runs| EVIDENTLY[Evidently AI<br/>Drift Detector]
            EVIDENTLY -->|pushes metrics| PUSHGW
            EVIDENTLY -->|saves reports| PVC_REPORT[(Drift Reports<br/>PVC)]
        end

        subgraph "Data Layer"
            PG[(PostgreSQL)] -->|backend store| MLFLOW[MLflow<br/>Experiment Tracking]
            MLFLOW -->|tracks experiments| TRAIN[Model Training]
        end
    end

    subgraph "Infrastructure as Code"
        ANSIBLE[Ansible Playbooks] -->|provisions| MINIKUBE[Minikube Cluster]
        ANSIBLE -->|installs| TOOLS[Docker / kubectl / Helm]
        ANSIBLE -->|deploys| HELM_DEPLOY
    end

    HELM_DEPLOY --> SVC
    BUILD -->|image| POD1
    BUILD -->|image| POD2

    USER[API Consumer] -->|POST /predict| SVC

    style PROM fill:#e6522c,color:#fff
    style GRAFANA fill:#f46800,color:#fff
    style EVIDENTLY fill:#6c63ff,color:#fff
    style JENKINS fill:#d33833,color:#fff
    style PG fill:#336791,color:#fff
    style MLFLOW fill:#0194e2,color:#fff
```

## 2. CI/CD Pipeline Flow

```mermaid
graph LR
    subgraph "Stage 1: Source"
        S1[Git Checkout<br/>GitHub Webhook]
    end

    subgraph "Stage 2: Secret Scan"
        S2[Gitleaks<br/>Detect hardcoded<br/>secrets & keys]
    end

    subgraph "Stage 3: SAST"
        S3A[Bandit<br/>Python security<br/>analysis]
        S3B[SonarQube<br/>Code quality &<br/>vulnerability scan]
    end

    subgraph "Stage 4: Unit Tests"
        S4[pytest<br/>7 API tests<br/>health / predict /<br/>validation / model]
    end

    subgraph "Stage 5: Build"
        S5[Docker Build<br/>Multi-stage<br/>non-root image]
    end

    subgraph "Stage 6: Image Scan"
        S6[Trivy<br/>Container image<br/>vulnerability scan]
    end

    subgraph "Stage 7: Deploy"
        S7[Helm Upgrade<br/>Rolling update<br/>zero-downtime]
    end

    subgraph "Stage 8: Verify"
        S8[Health Check<br/>Smoke tests<br/>Rollout status]
    end

    S1 --> S2 --> S3A --> S4
    S3A --> S3B
    S3B --> S4
    S4 --> S5 --> S6 --> S7 --> S8

    S8 -->|failure| ROLLBACK[Helm Rollback<br/>Previous Revision]
    S8 -->|success| DONE[Deploy Complete]

    style S2 fill:#ff6b6b,color:#fff
    style S3A fill:#ff6b6b,color:#fff
    style S3B fill:#ff6b6b,color:#fff
    style S6 fill:#ff6b6b,color:#fff
    style S4 fill:#51cf66,color:#fff
    style S5 fill:#339af0,color:#fff
    style S7 fill:#339af0,color:#fff
    style ROLLBACK fill:#fcc419,color:#000
    style DONE fill:#51cf66,color:#fff
```

### Pipeline Stage Details

| Stage | Tool | Purpose | Failure Action |
|-------|------|---------|---------------|
| 1. Source | Git | Checkout code from GitHub | Abort pipeline |
| 2. Secret Scan | Gitleaks | Detect hardcoded secrets, API keys, passwords | Block merge |
| 3. SAST | Bandit + SonarQube | Static analysis for Python vulnerabilities, code smells | Block merge |
| 4. Unit Tests | pytest | Validate API endpoints, model predictions, input validation | Block merge |
| 5. Build | Docker | Multi-stage build with non-root user | Abort pipeline |
| 6. Image Scan | Trivy | Scan container image for CVEs (HIGH/CRITICAL) | Block deploy |
| 7. Deploy | Helm | Rolling update to Kubernetes (maxSurge=1, maxUnavailable=0) | Rollback |
| 8. Verify | kubectl | Health checks, rollout status, smoke tests | Rollback |

## 3. Monitoring and Drift Detection Flow

```mermaid
graph TB
    subgraph "Data Collection"
        API[FastAPI ML API] -->|POST /predict| PREDICT[Prediction Handler]
        PREDICT -->|1. Serve prediction| RESPONSE[Response to Client]
        PREDICT -->|2. Log input features| CSV[current.csv<br/>on PVC]
        PREDICT -->|3. Record metrics| PROM_CLIENT[prometheus_client]
    end

    subgraph "Prometheus Metrics"
        PROM_CLIENT -->|expose /metrics| SCRAPE[Prometheus Scrape<br/>every 15s]
        SCRAPE --> PROM_DB[(Prometheus TSDB)]

        PROM_DB -->|ml_predictions_total| M1[Prediction counts<br/>by outcome & risk]
        PROM_DB -->|ml_prediction_duration_seconds| M2[Inference latency<br/>p50/p95/p99]
        PROM_DB -->|ml_default_probability| M3[Probability<br/>distribution]
        PROM_DB -->|ml_model_loaded| M4[Model health<br/>status]
        PROM_DB -->|http_requests_total| M5[HTTP request<br/>rate & errors]
        PROM_DB -->|container_cpu/memory| M6[Pod resource<br/>utilization]
    end

    subgraph "Drift Detection Pipeline"
        CRON[K8s CronJob<br/>Every 6 hours] -->|triggers| DETECTOR[Evidently AI<br/>Drift Detector]
        REF[Reference Data<br/>test_data.csv] -->|baseline| DETECTOR
        CSV -->|current window| DETECTOR

        DETECTOR -->|DatasetDriftMetric| D1{Dataset<br/>Drift?}
        DETECTOR -->|ColumnDriftMetric<br/>per feature| D2[Per-Feature<br/>Drift Scores]
        DETECTOR -->|save| HTML[HTML Report]

        D1 -->|drift_share > 0.5| ALERT[Drift Alert]
        D1 -->|no drift| OK[All Clear]

        DETECTOR -->|push metrics| PUSHGW[Pushgateway]
        PUSHGW -->|scraped by| PROM_DB

        PROM_DB -->|ml_drift_dataset_detected| D3[Dataset drift<br/>status]
        PROM_DB -->|ml_drift_feature_score| D4[Feature drift<br/>scores]
        PROM_DB -->|ml_drift_share| D5[Drift share<br/>percentage]
    end

    subgraph "Grafana Dashboards"
        PROM_DB --> G1[API Performance<br/>Request rate, latency,<br/>status codes, errors]
        PROM_DB --> G2[System Resources<br/>CPU, memory, restarts,<br/>replicas, network I/O]
        PROM_DB --> G3[Prediction Metrics<br/>Counts, risk levels,<br/>probability distribution]
        PROM_DB --> G4[Drift Detection<br/>Drift status, feature scores,<br/>drift history timeline]
    end

    subgraph "Remediation"
        ALERT -->|trigger| RETRAIN[Retrain Model<br/>with new data]
        ALERT -->|or| ROLLBACK_2[Rollback to<br/>previous model]
    end

    style ALERT fill:#ff6b6b,color:#fff
    style OK fill:#51cf66,color:#fff
    style G1 fill:#f46800,color:#fff
    style G2 fill:#f46800,color:#fff
    style G3 fill:#f46800,color:#fff
    style G4 fill:#f46800,color:#fff
    style DETECTOR fill:#6c63ff,color:#fff
```

### Metrics Reference

#### Application Metrics (from FastAPI)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `ml_predictions_total` | Counter | prediction, risk_level | Total predictions served |
| `ml_prediction_duration_seconds` | Histogram | - | Model inference time |
| `ml_default_probability` | Histogram | - | Distribution of default probabilities |
| `ml_model_loaded` | Gauge | - | Model load status (1/0) |
| `http_requests_total` | Counter | handler, method, status | HTTP request counts |
| `http_request_duration_seconds` | Histogram | handler | HTTP request latency |

#### Drift Metrics (from Evidently via Pushgateway)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `ml_drift_dataset_detected` | Gauge | - | Dataset-level drift (1/0) |
| `ml_drift_share` | Gauge | - | Fraction of drifted features |
| `ml_drift_columns_count` | Gauge | - | Number of drifted columns |
| `ml_drift_feature_score` | Gauge | feature | Per-feature drift score |
| `ml_drift_feature_detected` | Gauge | feature | Per-feature drift flag (1/0) |
| `ml_drift_last_run_timestamp` | Gauge | - | Last detection run time |

#### System Metrics (from Node Exporter + kube-state-metrics)

| Metric | Type | Description |
|--------|------|-------------|
| `container_cpu_usage_seconds_total` | Counter | Pod CPU usage |
| `container_memory_working_set_bytes` | Gauge | Pod memory usage |
| `kube_pod_container_status_restarts_total` | Counter | Pod restart count |
| `kube_deployment_status_replicas_ready` | Gauge | Ready replicas |
