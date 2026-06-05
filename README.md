taxi-tips-mlops/
├── .github/
│   └── workflows/      # CI/CD GitHub Actions (Phase C)
├── infra/              # Terraform configurations (Phase B)
├── notebooks/          # Jupyter notebooks for initial XGBoost model (Phase D)
├── pipelines/          # Vertex AI KFP pipeline definitions (Phase E)
├── src/                # Application code
│   ├── proxy/          # Cloud Run FastAPI app (We will put A3 here)
│   │   └── main.py        # FastAPI app code
│   │   └── requirements.txt  # Python dependencies for the FastAPI app
│   └── sampler/        # Drift simulator script (Phase E)
├── .gitignore
└── README.md