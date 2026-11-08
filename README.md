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

Data: *The World Bank, Remittance Prices Worldwide, available at remittanceprices.worldbank.org.*
