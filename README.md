# 🔐 IAM Automation Suite (Okta‑focused)

> End-to-end identity lifecycle automation — onboard, offboard, update users from a CSV/HRIS source into Okta, audit MFA compliance, and enforce least privilege.

[![CI](https://github.com/mraaron360/iam-automation-suite/actions/workflows/ci.yml/badge.svg)](https://github.com/mraaron360/iam-automation-suite/actions)
[![Python: 3.11+](https://img.shields.io/badge/Python-3.11%2B-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![IdP: Okta](https://img.shields.io/badge/IdP-Okta-00297A.svg)](https://developer.okta.com/)

---

## 📋 Table of Contents

- [What This Does](#what-this-does)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Lifecycle Commands](#lifecycle-commands)
- [MFA Audit](#mfa-audit)
- [Role → Group Mapping](#role--group-mapping)
- [Running Tests](#running-tests)
- [Docker](#docker)
- [CI/CD](#cicd)
- [Design Decisions](#design-decisions)

---

## What This Does

| Module | File | Description |
|---|---|---|
| **Okta API Client** | `src/okta_client.py` | Authenticated wrapper for Okta Users, Groups, Factors, and Sessions APIs |
| **Identity Lifecycle** | `src/lifecycle.py` | Joiner / Mover / Leaver workflows with dry-run support |
| **MFA Audit** | `src/audit.py` | Enumerate users, flag missing/weak MFA, export CSV report, optional enforce |
| **Config & Mapping** | `src/config.py` | Role-to-group rules, SLA settings, env var loading |

**Key engineering properties:**
- **Dry-run by default** — safe to run without `--apply`; shows exactly what would change
- **Idempotent** — re-running onboard on an existing ACTIVE user skips cleanly
- **Least-privilege enforcement** — Mover reconciles group memberships (adds new, removes stale)
- **Error isolation** — one failed user doesn't stop the batch; errors are logged and reported in summary
- **Rate-limit aware** — respects Okta's `X-Rate-Limit-Reset` header with automatic backoff

---

## Repository Structure

```
iam-automation-suite/
├── src/
│   ├── __init__.py
│   ├── okta_client.py      # Okta REST API wrapper
│   ├── lifecycle.py        # Joiner / Mover / Leaver CLI
│   ├── audit.py            # MFA audit + enforce CLI
│   └── config.py           # GROUP_RULES, env config
├── tests/
│   ├── __init__.py
│   ├── test_lifecycle.py   # Unit tests — lifecycle flows
│   └── test_audit.py       # Unit tests — MFA audit logic
├── data/
│   └── users.csv           # Sample HR data (edit or replace with HRIS export)
├── .github/
│   └── workflows/
│       └── ci.yml          # GitHub Actions — lint + test on push/PR
├── .env.example            # Environment variable template
├── requirements.txt
├── Dockerfile
├── Makefile
└── README.md
```

---

## Prerequisites

- Python 3.11+
- An Okta developer tenant ([free at developer.okta.com](https://developer.okta.com/signup/))
- An Okta API token with permissions to manage users and groups

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/mraaron360/iam-automation-suite.git
cd iam-automation-suite

# 2. Install
pip install -r requirements.txt

# 3. Configure
cp .env.example .env
# Edit .env with your OKTA_DOMAIN and OKTA_API_TOKEN

# 4. Dry-run onboarding (no writes to Okta)
python -m src.lifecycle onboard --csv data/users.csv --idp okta

# 5. When ready, apply
python -m src.lifecycle onboard --csv data/users.csv --idp okta --apply
```

---

## Configuration

Copy `.env.example` to `.env` and set:

```env
OKTA_DOMAIN=dev-XXXXX.okta.com
OKTA_API_TOKEN=your_okta_api_token_here

# Group every new hire is added to (e.g., "All Staff")
DEFAULT_OKTA_GROUP_ID=00gXXXXXXXXXXXXXXX

# Fallback group if no role rule matches
FALLBACK_OKTA_GROUP_ID=00gXXXXXXXXXXXXXXX

# true = hard delete on offboard | false = deactivate only (default)
HARD_DELETE_ON_OFFBOARD=false

LOG_LEVEL=INFO
```

> Get your API token in Okta: **Security → API → Tokens → Create Token**

---

## Lifecycle Commands

### CSV Format

```
employee_id,first_name,last_name,email,department,role,status
EMP-001,Ada,Lovelace,ada.lovelace@example.com,Engineering,Dev,active
EMP-002,Grace,Hopper,grace.hopper@example.com,Security,Analyst,terminated
```

`status` values: `active` (Joiner/Mover) | `terminated` (Leaver)

---

### Joiner — Onboard new hires

Processes all rows with `status=active`. Creates new users, skips existing ACTIVE users, reactivates DEPROVISIONED users.

```bash
# Dry-run (default — safe, no Okta writes)
python -m src.lifecycle onboard --csv data/users.csv --idp okta

# Apply
python -m src.lifecycle onboard --csv data/users.csv --idp okta --apply
```

**What it does:**
1. Checks if user already exists in Okta (idempotent)
2. Creates user with activation email
3. Assigns groups based on `department` + `role` mapping
4. Logs all actions + prints summary

---

### Leaver — Offboard terminated users

Processes all rows with `status=terminated`. Revokes sessions, deactivates (or hard-deletes) the Okta account.

```bash
# Dry-run
python -m src.lifecycle offboard --csv data/users.csv --idp okta

# Apply
python -m src.lifecycle offboard --csv data/users.csv --idp okta --apply
```

**What it does:**
1. Revokes all active SSO sessions (T+0)
2. Deactivates Okta account (or hard-deletes if `HARD_DELETE_ON_OFFBOARD=true`)
3. Skips already-deactivated/deprovisioned accounts cleanly

---

### Mover — Update role changers

Processes all `active` rows. Updates profile attributes and **reconciles group memberships** — adds new role groups, removes stale ones.

```bash
# Dry-run
python -m src.lifecycle update --csv data/users.csv --idp okta

# Apply
python -m src.lifecycle update --csv data/users.csv --idp okta --apply
```

---

### Summary Output

Every run prints a summary:

```
── Lifecycle Summary ─────────────────────────────
  created                        3
  skipped_already_active         1
  dry_run_create                 2
  error                          1
  TOTAL                          7
──────────────────────────────────────────────────

── Errors ────────────────────────────────────────
  bad.user@example.com: Okta API 404
──────────────────────────────────────────────────
```

---

## MFA Audit

Enumerate all ACTIVE users, check MFA factor enrollment, classify compliance, and export a CSV report.

**Compliance levels:**
- `COMPLIANT` — enrolled in at least one strong factor (TOTP, FIDO2/WebAuthn, Okta Push, hardware token)
- `WEAK_MFA` — enrolled in only weak factors (e.g., SMS OTP)
- `NO_MFA` — no enrolled factors

```bash
# Audit only — report, no changes
python -m src.audit mfa --idp okta --out mfa-report.csv

# Enforce — reset MFA for non-compliant users (forces re-enrollment)
python -m src.audit mfa --idp okta --out mfa-report.csv --enforce
```

**Report columns:** `employee_id`, `email`, `department`, `title`, `okta_status`, `enrolled_factors`, `compliance`, `action_taken`

---

## Role → Group Mapping

Edit `src/config.py` → `GROUP_RULES` to map `(department, role)` tuples to Okta group IDs:

```python
GROUP_RULES: dict[tuple[str, str], list[str]] = {
    ("engineering", "dev"):        ["00gENGDEV000000000", "00gALL000000000000"],
    ("engineering", "senior dev"): ["00gENGSENIOR000000", "00gALL000000000000"],
    ("security",    "analyst"):    ["00gSECURITY0000000", "00gALL000000000000"],
    ("it",          "admin"):      ["00gITADMIN00000000", "00gALL000000000000"],
    # Add more rules here...
}
```

Matching is case-insensitive. If no rule matches, the user is assigned `FALLBACK_OKTA_GROUP_ID`.

---

## Running Tests

Tests use `unittest.mock` — no real Okta connection required.

```bash
# Run all tests
python -m pytest tests/ -v

# With coverage
pip install pytest-cov
python -m pytest tests/ -v --cov=src --cov-report=term-missing

# Via Makefile
make test
```

**Test coverage includes:**
- CSV loading and validation (missing columns, empty email handling)
- Group resolution (known roles, unknown roles, case-insensitivity)
- Onboard: new user, existing active user (skip), deprovisioned user (reactivate), API error handling
- Offboard: active user deactivation, already-deprovisioned skip, user-not-found handling
- Mover: group reconciliation (add new, remove stale)
- MFA audit: compliant, no-MFA, weak-MFA, inactive factor, enforce mode, error handling

---

## Docker

```bash
# Build
docker build -t iam-automation-suite .

# Dry-run onboard
docker run --env-file .env -v $(pwd)/data:/app/data iam-automation-suite

# Custom command
docker run --env-file .env -v $(pwd)/data:/app/data iam-automation-suite \
  python -m src.audit mfa --idp okta --out mfa-report.csv
```

---

## CI/CD

GitHub Actions runs on every push and PR to `main`:

```
.github/workflows/ci.yml
  ├── Python 3.11 matrix
  ├── Python 3.12 matrix
  ├── pip install -r requirements.txt
  ├── Syntax check (py_compile)
  └── pytest tests/ -v
```

---

## Design Decisions

**Why dry-run by default?**
IAM changes are high-blast-radius. Deactivating the wrong user is immediately visible to that person and their team. Default-safe means you always review the plan before applying it.

**Why idempotency on onboard?**
HR systems sometimes re-send the same record. An idempotent onboard means running the job twice doesn't create duplicate users or throw errors — it just skips.

**Why deactivate instead of delete on offboard?**
Most compliance frameworks (SOC 2, HIPAA) require retaining account records for audit purposes. Deactivation preserves the record while removing access. Hard-delete is opt-in via `HARD_DELETE_ON_OFFBOARD`.

**Why reconcile groups on Mover instead of just adding new ones?**
Not removing old groups is how privilege creep happens. The Mover workflow computes a delta (desired vs. actual) and removes stale entitlements — this is the least-privilege enforcement point.

---

## License

[MIT](LICENSE) © Aaron Agyapong
---

