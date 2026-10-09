import os

from flask import Flask, jsonify

app = Flask(__name__)

# Injected at build time (Docker build arg) or at runtime. In the pipeline this is the commit SHA.
BUILD_ID = os.environ.get("BUILD_ID", "dev")
APP_ENV = os.environ.get("APP_ENV", "local")


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
    return jsonify(service="aws-cicd-app", build_id=BUILD_ID), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
