import app as app_module
from app import app


def test_health_returns_ok():
    client = app.test_client()
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}


def test_version_returns_build_id_and_environment():
    client = app.test_client()
    resp = client.get("/version")
    assert resp.status_code == 200
    body = resp.get_json()
    assert "build_id" in body
    assert "environment" in body


def test_index_returns_service_name():
    client = app.test_client()
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.get_json()["service"] == "aws-cicd-app"


def test_simulated_fault_breaks_home_page_but_not_health(monkeypatch):
    monkeypatch.setattr(app_module, "SIMULATE_FAULT", True)
    client = app.test_client()
    assert client.get("/").status_code == 500
    # the load balancer health check and /version stay up, like a bug that only shows under real traffic
    assert client.get("/health").status_code == 200
    assert client.get("/version").status_code == 200
