# IAM Automation Suite (Okta‑focused)
End‑to‑end IAM engineering automation you can run locally or in CI.

## What this does
- **Identity Lifecycle Automation**: Onboard/offboard/update users from an HR CSV into Okta.
- **RBAC Grouping**: Map `department/role` → Okta groups.
- **MFA Audit**: Report users missing MFA enrollment.
- **SSO Helpers**: Tiny SAML/OIDC helpers for labs.
- **DevX**: Dockerfile, Makefile, unit tests, GitHub Actions, `.env.example`.

> Works with Okta by default; Azure AD stubs are included so you can extend with Microsoft Graph later.

---

## Quick start
1) **Python 3.10+** and **pip** installed.
2) Copy `.env.example` → `.env` and set your values.
3) (Optional) Create/adjust `data/users.csv`.
4) Install & run:
```bash
pip install -r requirements.txt

# Dry-run onboarding (no writes to Okta) — add --apply to execute
python -m src.lifecycle onboard --csv data/users.csv --idp okta --dry-run

# Offboard terminations (deactivate in Okta)
python -m src.lifecycle offboard --csv data/users.csv --idp okta --apply

# Audit MFA and export a report
python -m src.audit mfa --idp okta --out mfa-report.csv
```

### Environment (.env)
```
OKTA_DOMAIN=dev-XXXXX.okta.com
OKTA_API_TOKEN=your_api_token_here
# Optional defaults
DEFAULT_OKTA_GROUP_ID=00gXXXXXXXXXXXXXXX
```

> Get an **API token** in Okta: *Security → API → Tokens*.

---

## CSV format (`data/users.csv`)
Required headers (feel free to add more):
```
employee_id,first_name,last_name,email,department,role,status
```
- `status`: `active` or `terminated`
- Example rows are included.

---

## Group mapping
Edit `src/config.py` → `GROUP_RULES` to map `(department, role)` to group IDs.

---

## Azure AD note
A minimal `AzureADClient` stub exists. Add your `CLIENT_ID`, `TENANT_ID`, `CLIENT_SECRET`, then implement calls with Microsoft Graph if you want both IdPs.

---

## Testing
```bash
python -m pytest -q
```

## Docker
```bash
docker build -t iam-automation .
docker run --env-file .env -v $PWD/data:/app/data iam-automation \
  python -m src.lifecycle onboard --csv data/users.csv --idp okta --dry-run
```

## CI
A simple GitHub Actions workflow runs lint & tests on pushes/PRs.

---

## What you can say in interviews
- Built a production‑style lifecycle pipeline (CSV → Okta REST API) with idempotent writes, retry/backoff on 429, logging, and unit tests.
- Implemented MFA compliance reporting and RBAC group assignment via rules.
- Containerized the tool and wired CI for repeatable automation.
