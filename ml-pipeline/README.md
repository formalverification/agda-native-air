# ML Pipeline Project

This project combines a Scala/Spark ETL with PyTorch model training and FastAPI serving.

## 🚀 Project Structure

```
ml-pipeline/
├── etl/            # Scala Spark (sbt project)
├── python/
│   ├── api/        # FastAPI model server
│   └── model/      # PyTorch training/inference + export
├── data/
├── features/       # Processed data
├── models/         # Trained/exported models
└── scripts/        # Shell helpers
```

## 🛠️ Setup Instructions (Ubuntu 24.04+)

### 🔹 1. Install Java and sbt

```bash
sudo apt update
sudo apt install openjdk-17-jdk -y
echo "deb https://repo.scala-sbt.org/scalasbt/debian all main" | sudo tee /etc/apt/sources.list.d/sbt.list
curl -sL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x99E82A75642AC823" | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/sbt.gpg > /dev/null
sudo apt update
sudo apt install sbt -y
```

### 🔹 2. Create a Python virtual environment (PEP 668-safe)

```bash
sudo apt install python3-venv python3-full -y
python3 -m venv ~/venvs/mlpipeline
source ~/venvs/mlpipeline/bin/activate
pip install torch fastapi uvicorn pyarrow pytest
```

## 🧪 Run Components

### 🧱 ETL with Spark (Scala)
```bash
make etl
```

### 🧠 Train & Export Model (PyTorch)
```bash
make train
make export_script
```

### 🌐 Serve API (FastAPI)
```bash
make serve
```

---

## 🧼 Tips

+  Always activate a `venv` before working.

    ```bash
    source ~/venvs/mlpipeline/bin/activate
    ```

+  Deactivate with the command `deactivate`.
    ```

---

## 📦 CI/CD
GitHub Actions workflow is located in `.github/workflows/ci.yml`.

## ✅ Test
```bash
make test
```

Happy hacking! 🎉
