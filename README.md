# ENTROPY

```
root@entropy:~# infer --target total_cost_pct --corridor *>AFRICA
>> predicting the hidden cost of sending money home
```

## Mission and problem

**Mission:** make money movement in Africa transparent, cheap and open to everyone, using decentralised financial rails that bypass the barriers keeping remittances expensive.
**Problem:** sending USD 200 into Africa costs **7.7% on average**, more than double the UN's 3% target (SDG 10.c), and much of it is hidden in the exchange rate.
ENTROPY predicts that all-in cost for any corridor and service profile, so fintech builders know the price to beat and regulators know where to look.

## Dataset

**World Bank, [Remittance Prices Worldwide](https://datacatalog.worldbank.org/search/dataset/0037898/remittance-prices-worldwide)** (CC BY 4.0). Every quarter the World Bank mystery-shops real remittance providers and records the fee and exchange-rate margin they charge.
ENTROPY uses every quote sent **into an African country** from Q2 2016 to Q3 2025: **52,892 quotes, 47 columns** (15 numeric, 32 categorical), covering 38 African destinations, 29 sending countries and 247 providers.
The target is `cc1 total cost %`, the all-in cost of sending USD 200, as a percentage of the amount sent.

## API (Swagger UI)

**Public Swagger UI: https://entropy-remit-api.onrender.com/docs**

The API runs on Render's free tier, so after 15 minutes without traffic the first request can take up to a minute while the service wakes up.

| Route | Method | What it does |
|---|---|---|
| `/predict` | POST | Takes the 10 inputs and returns the predicted cost (% and basis points), the gap to the 3% SDG target and the model's typical error |
| `/retrain` | POST | Upload a CSV with the 10 inputs plus `total_cost_pct`. The model retrains on original + new rows and goes live immediately |
| `/docs` | GET | Swagger UI |
| `/` | GET | Model info: type, version, training rows, test MSE / RMSE / R2 |

To try retraining, upload [`summative/API/data/new_quarter_2025Q3.csv`](summative/API/data/new_quarter_2025Q3.csv), the World Bank's newest quarter, which the model never saw.

## Repository layout

```
linear_regression_model/
├── README.md
└── summative/
    ├── pyproject.toml, uv.lock        # uv-managed environment
    ├── linear_regression/
    │   ├── multivariate.ipynb         # data, EDA, models
    │   └── data/                      # Africa slice of the World Bank dataset
    ├── API/                           # FastAPI service
    └── FlutterApp/                    # mobile app
```

## Run the notebook

```bash
cd summative
uv sync
uv run jupyter nbconvert --to notebook --execute --inplace linear_regression/multivariate.ipynb
```

## Run the API locally

```bash
cd summative
uv sync
uv run pytest API -q                                   # 15 checks: validation, CORS, retraining
cd API && uv run uvicorn prediction:app --reload       # then open http://127.0.0.1:8000/docs
```

Data: *The World Bank, Remittance Prices Worldwide, available at remittanceprices.worldbank.org.*
