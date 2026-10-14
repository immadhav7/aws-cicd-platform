import os

from flask import Flask, jsonify

app = Flask(__name__)

# Injected at build time (Docker build arg) or at runtime. In the pipeline this is the commit SHA.
BUILD_ID = os.environ.get("BUILD_ID", "dev")
APP_ENV = os.environ.get("APP_ENV", "local")
# Rollback demo only: when set to 1 the home page returns HTTP 500 while /health stays green,
# the way a real bug passes health checks but fails real requests. Off by default.
SIMULATE_FAULT = os.environ.get("SIMULATE_FAULT", "0") == "1"


@app.get("/health")
def health():
    """Used by the ALB target group and ECS health checks."""
    return jsonify(status="ok"), 200


@app.get("/version")
def version():
    """Shows which build is live; used to verify deploys and rollbacks."""
    return jsonify(build_id=BUILD_ID, environment=APP_ENV), 200


@app.get("/")
def index():
    if SIMULATE_FAULT:
        return jsonify(error="simulated fault", build_id=BUILD_ID), 500
    return jsonify(service="aws-cicd-app", build_id=BUILD_ID), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
