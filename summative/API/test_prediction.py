"""API checks for every rubric requirement. Run from summative/:  uv run pytest API -q"""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from prediction import app

client = TestClient(app)
VALID = {
    "source_country": "USA", "destination_country": "GMB", "firm_type": "MTO", "payment_instrument": "CARD",
    "access_point": "ONLINE", "pickup_method": "MOBILE_WALLET", "network_coverage": "HIGH",
    "transparent": "yes", "speed_hours": 1, "year": 2025,
}
NEW_QUARTER = Path(__file__).parent / "data" / "new_quarter_2025Q3.csv"


def test_valid_quote_returns_a_prediction():
    response = client.post("/predict", json=VALID)
    assert response.status_code == 200
    body = response.json()
    assert 0 <= body["total_cost_pct"] <= 40
    assert body["total_cost_bps"] == round(body["total_cost_pct"] * 100)
    assert body["above_sdg_target"] == (body["total_cost_pct"] > 3.0)


def test_lower_case_codes_are_accepted():
    assert client.post("/predict", json={**VALID, "source_country": "usa", "firm_type": "mto"}).status_code == 200


@pytest.mark.parametrize("field, bad_value", [
    ("speed_hours", "fast"),      # wrong type: text instead of a number
    ("speed_hours", "24"),        # wrong type: a number sent as text is rejected too (strict)
    ("year", 2025.5),             # wrong type: not a whole number
    ("speed_hours", 500),         # out of range: more than 168 hours
    ("year", 2010),               # out of range: before the data starts
    ("destination_country", "FRA"),  # not an African destination in the data
    ("firm_type", "CRYPTO_EXCHANGE"),  # unknown category
])
def test_invalid_values_are_rejected(field, bad_value):
    response = client.post("/predict", json={**VALID, field: bad_value})
    assert response.status_code == 422
    assert response.json()["detail"][0]["loc"][-1] == field


def test_missing_field_is_rejected():
    incomplete = {key: value for key, value in VALID.items() if key != "year"}
    response = client.post("/predict", json=incomplete)
    assert response.status_code == 422
    assert response.json()["detail"][0]["type"] == "missing"


def test_unexpected_field_is_rejected():
    assert client.post("/predict", json={**VALID, "firm": "Western Union"}).status_code == 422


def test_cors_allows_listed_origin_only():
    preflight = {"Access-Control-Request-Method": "POST", "Access-Control-Request-Headers": "Content-Type"}
    allowed = client.options("/predict", headers={"Origin": "http://localhost:8080", **preflight})
    blocked = client.options("/predict", headers={"Origin": "https://evil.example", **preflight})
    assert allowed.headers.get("access-control-allow-origin") == "http://localhost:8080"
    assert "access-control-allow-origin" not in blocked.headers
    assert "access-control-allow-credentials" not in allowed.headers


def test_retrain_rejects_csv_with_missing_columns():
    response = client.post("/retrain", files={"file": ("bad.csv", b"year,speed_hours\n2025,1\n", "text/csv")})
    assert response.status_code == 422


def test_retrain_rejects_invalid_rows():
    header = ",".join([*VALID, "total_cost_pct"])
    row = ",".join(str(v) for v in {**VALID, "speed_hours": 999}.values()) + ",5.0"
    response = client.post("/retrain", files={"file": ("bad.csv", f"{header}\n{row}\n".encode(), "text/csv")})
    assert response.status_code == 422
    assert "speed_hours" in str(response.json()["detail"])


def test_retrain_with_new_quarter_updates_the_live_model():
    version_before = client.get("/").json()["model_version"]
    with NEW_QUARTER.open("rb") as handle:
        response = client.post("/retrain", files={"file": ("new_quarter_2025Q3.csv", handle, "text/csv")})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["rows_added"] == 1722
    assert body["model_version"] == version_before + 1
    prediction = client.post("/predict", json=VALID).json()
    assert prediction["model_version"] == version_before + 1
