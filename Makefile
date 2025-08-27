SHELL := /bin/bash

.PHONY: setup test lint run
setup:
	python -m pip install -r requirements.txt

test:
	pytest -q

run-onboard:
	python -m src.lifecycle onboard --csv data/users.csv --idp okta --dry-run

run-offboard:
	python -m src.lifecycle offboard --csv data/users.csv --idp okta --apply
