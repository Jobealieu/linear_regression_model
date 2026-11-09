"""ENTROPY API: predicts the all-in cost (%) of sending USD 200 into an African country.

Run locally:  uv run uvicorn prediction:app --reload   (from summative/API)
"""

import math
import threading
import time
from pathlib import Path
from typing import Literal

import joblib
import pandas as pd
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError, field_validator
from sklearn.base import clone
from sklearn.metrics import mean_squared_error, r2_score

HERE = Path(__file__).parent
MODEL_PATH = HERE / "best_model.pkl"
TRAIN_PATH = HERE / "data" / "train.csv.gz"
TEST_PATH = HERE / "data" / "test.csv.gz"
TARGET = "total_cost_pct"
SDG_TARGET_PCT = 3.0  # UN SDG 10.c: remittance costs below 3%
MAX_PLAUSIBLE_COST = 40.0  # same cleaning rule as the notebook

SourceCountry = Literal[
    "AGO", "ARE", "AUS", "BEL", "BHR", "CAN", "CIV", "CMR", "DEU", "ESP", "FRA", "GBR", "GHA", "ISR", "ITA",
    "JOR", "KEN", "KWT", "NGA", "NLD", "PRT", "QAT", "RWA", "SAU", "SEN", "SWE", "TZA", "USA", "ZAF",
]
DestinationCountry = Literal[
    "AGO", "BEN", "BWA", "CIV", "CMR", "COD", "COM", "CPV", "DZA", "EGY", "ERI", "ETH", "GHA", "GMB", "KEN",
    "LBR", "LSO", "MAR", "MDG", "MLI", "MOZ", "MWI", "NAM", "NGA", "RWA", "SDN", "SEN", "SLE", "SOM", "SSD",
    "SWZ", "TGO", "TUN", "TZA", "UGA", "ZAF", "ZMB", "ZWE",
]


class Quote(BaseModel):
    """One remittance service profile: the 10 inputs the model needs."""

    model_config = ConfigDict(extra="forbid", json_schema_extra={"examples": [{
        "source_country": "USA", "destination_country": "GMB", "firm_type": "MTO",
        "payment_instrument": "CARD", "access_point": "ONLINE", "pickup_method": "MOBILE_WALLET",
        "network_coverage": "HIGH", "transparent": "yes", "speed_hours": 1, "year": 2025,
    }]})

    source_country: SourceCountry = Field(description="ISO3 code of the sending country, e.g. USA, GBR, ZAF")
    destination_country: DestinationCountry = Field(description="ISO3 code of the African receiving country")
    firm_type: Literal["BANK", "MTO", "MOBILE_OPERATOR", "POST", "NON_BANK_FI", "MULTI"] = Field(
        description="Provider type (MTO = money transfer operator)")
    payment_instrument: Literal["CASH", "BANK_ACCOUNT", "CARD", "MOBILE_MONEY", "MULTI"] = Field(
        description="How the sender pays")
    access_point: Literal["AGENT", "ONLINE", "BRANCH", "CALL_CENTER", "POST_OFFICE", "MOBILE_APP", "MULTI"] = Field(
        description="Where the sender starts the transfer")
    pickup_method: Literal["CASH", "BANK_ACCOUNT", "MOBILE_WALLET"] = Field(description="How the receiver gets the money")
    network_coverage: Literal["HIGH", "MEDIUM", "LOW"] = Field(description="Provider's pickup network in the receiving country")
    transparent: Literal["yes", "no"] = Field(description="Does the provider disclose its exchange rate?")
    speed_hours: int = Field(ge=1, le=168, strict=True, description="Hours until the money is available (1 to 168)")
    year: int = Field(ge=2016, le=2030, strict=True, description="Year of the quote (2016 to 2030)")

    @field_validator("source_country", "destination_country", "firm_type", "payment_instrument",
                     "access_point", "pickup_method", "network_coverage", mode="before")
    @classmethod
    def upper_case_codes(cls, value):
        return value.strip().upper() if isinstance(value, str) else value

    @field_validator("transparent", mode="before")
    @classmethod
    def lower_case_flag(cls, value):
        return value.strip().lower() if isinstance(value, str) else value


class LabelledQuote(Quote):
    """A training row: the 10 inputs plus the observed cost."""

    total_cost_pct: float = Field(ge=0, le=MAX_PLAUSIBLE_COST, description="Observed all-in cost in %")


class Prediction(BaseModel):
    total_cost_pct: float = Field(description="Predicted all-in cost of sending USD 200, in % of the amount")
    total_cost_bps: int = Field(description="The same cost in basis points (1 bp = 0.01%)")
    sdg_gap_pct_points: float = Field(description="Predicted cost minus the 3% SDG 10.c target")
    above_sdg_target: bool
    expected_error_pct_points: float = Field(description="Model's typical error on the test set (RMSE)")
    model: str
    model_version: int
    inference_ms: float


FEATURES = list(Quote.model_fields)
labelled_rows = TypeAdapter(list[LabelledQuote])


def predict_total_cost(features: dict, model=None) -> float:
    # Same function as notebook section 10: predicted all-in cost (%) for one quote.
    model = model if model is not None else joblib.load(MODEL_PATH)
    return round(float(model.predict(pd.DataFrame([features], columns=FEATURES))[0]), 2)


def score(model, test: pd.DataFrame) -> dict:
    predictions = model.predict(test[FEATURES])
    test_mse = mean_squared_error(test[TARGET], predictions)
    return {"test_mse": round(test_mse, 3), "test_rmse": round(math.sqrt(test_mse), 3),
            "test_r2": round(r2_score(test[TARGET], predictions), 3)}


def load_model(path: Path):
    model = joblib.load(path)
    # ponytail: Render's free tier has 0.1 CPU, so extra worker threads only add overhead. Use n_jobs=-1 on bigger hosts.
    if "model__n_jobs" in model.get_params():
        model.set_params(model__n_jobs=1)
    return model


# The live model sits in memory. /retrain swaps it in place, so /predict uses the new one without a redeploy.
# Render's free disk is wiped on restart, so a restart reloads best_model.pkl from the repository.
state = {"model": load_model(MODEL_PATH), "version": 1,
         "train": pd.read_csv(TRAIN_PATH), "test": pd.read_csv(TEST_PATH)}
state["metrics"] = score(state["model"], state["test"])
retrain_lock = threading.Lock()

app = FastAPI(
    title="ENTROPY API",
    version="1.0.0",
    description="Predicts the all-in cost (fee + FX margin) of sending USD 200 into an African country, "
                "from the World Bank's Remittance Prices Worldwide data. The SDG 10.c target is 3%.",
)

# CORS controls which WEBSITES (browser origins) may call this API from JavaScript.
# Allowed: this service's own Render origin (its Swagger UI page) and the Flutter web debug server
#   (flutter run -d chrome --web-port 8080). Origins are listed one by one; there is no "*" wildcard,
#   so a page on any other site cannot call the API through a visitor's browser.
# Restricted: only GET (service info) and POST (predict, retrain) are allowed, and only the Content-Type and
#   Accept headers the clients actually send. Credentials are off because the API uses no cookies or auth
#   headers, so a page can never make a browser attach a visitor's cookies to a request.
# The Flutter mobile app is not a browser, so CORS does not apply to it.
ALLOWED_ORIGINS = [
    "https://entropy-remit-api.onrender.com",
    "http://localhost:8080",
    "http://127.0.0.1:8080",
]
app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST"],
    allow_headers=["Content-Type", "Accept"],
    allow_credentials=False,
)


@app.get("/", summary="Service and model info")
def info():
    return {"service": "ENTROPY", "docs": "/docs", "model": type(state["model"][-1]).__name__,
            "model_version": state["version"], "training_rows": len(state["train"]),
            **state["metrics"], "sdg_target_pct": SDG_TARGET_PCT, "inputs": FEATURES}


@app.post("/predict", response_model=Prediction, summary="Predict the all-in cost of a remittance")
def predict(quote: Quote) -> Prediction:
    started = time.perf_counter()
    model = state["model"]
    cost = predict_total_cost(quote.model_dump(), model)
    return Prediction(
        total_cost_pct=cost,
        total_cost_bps=round(cost * 100),
        sdg_gap_pct_points=round(cost - SDG_TARGET_PCT, 2),
        above_sdg_target=cost > SDG_TARGET_PCT,
        expected_error_pct_points=state["metrics"]["test_rmse"],
        model=type(model[-1]).__name__,
        model_version=state["version"],
        inference_ms=round((time.perf_counter() - started) * 1000, 1),
    )


@app.post("/retrain", summary="Upload new labelled quotes; the model retrains and goes live immediately")
def retrain(file: UploadFile = File(description="CSV with the 10 input columns plus total_cost_pct")):
    try:
        new_rows = pd.read_csv(file.file)
    except Exception:
        raise HTTPException(status_code=400, detail="The file could not be read as CSV.")
    missing = [column for column in FEATURES + [TARGET] if column not in new_rows.columns]
    if missing:
        raise HTTPException(status_code=422, detail=f"Missing columns: {missing}")
    if new_rows.empty:
        raise HTTPException(status_code=422, detail="The CSV has no rows.")
    try:
        validated = labelled_rows.validate_python(new_rows[FEATURES + [TARGET]].to_dict("records"))
    except ValidationError as error:
        problems = [f"row {e['loc'][0] + 2}, {e['loc'][-1]}: {e['msg']}" for e in error.errors()[:5]]
        raise HTTPException(status_code=422, detail={"invalid_rows": error.error_count(), "first_errors": problems})

    if not retrain_lock.acquire(blocking=False):
        raise HTTPException(status_code=409, detail="A retrain is already running. Try again shortly.")
    try:
        started = time.perf_counter()
        before = state["metrics"]
        # The best model is a RandomForest, so it is refit on the original training data plus the new rows.
        # (An SGDRegressor would instead continue training on the new rows only, with partial_fit.)
        combined = pd.concat([state["train"], pd.DataFrame([row.model_dump() for row in validated])],
                             ignore_index=True)
        model = clone(state["model"]).fit(combined[FEATURES], combined[TARGET])
        after = score(model, state["test"])
        state.update(model=model, train=combined, metrics=after, version=state["version"] + 1)
    finally:
        retrain_lock.release()

    return {"status": "retrained and live", "model_version": state["version"], "rows_added": len(validated),
            "training_rows": len(combined), "test_mse_before": before["test_mse"],
            "test_mse_after": after["test_mse"], "test_r2_after": after["test_r2"],
            "seconds": round(time.perf_counter() - started, 1)}
