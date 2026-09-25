# Working on this repository

This is a **blueprint**: many services clone it. Never commit anything service- or project-specific; `deploy.json` ships with `CHANGE_ME`.

## Ground rules

- **Never run anything that changes AWS**, and never run `terraform` (there is none here). Read the real files, and the scripts a workflow calls, before proposing a change.
- Ask before building. Classify review findings CRITICAL / HIGH / MEDIUM / LOW / OPTIONAL, say PASS when something is correct, and do not rewrite working code for style.
- Comments explain why, not what. Scripts are exercised against real inputs and their error paths before they are called done.

## Where things live

- `app/`: the Django project. Settings come from environment variables only; a missing secret or allowed host stops startup with a message naming the cause. `migrate.py` migrates under a database lock.
- `app/docker-compose.yml` and `app/.env`: **templates**. Placeholders (`__IMAGE__` ...) are filled by `scripts/ci/render-deploy-files.sh`; `__FROM_SECRET__` is left for the host.
- `scripts/ci/`: everything the workflows call, each with an offline test in `scripts/ci/tests/`. Keep a workflow's `run:` steps to one script call.

## Contracts with the other repositories

- **The infrastructure repository** publishes `/<project>/services/<service>/config` (schema version 1). This repository only reads it (`read-service-config.sh`); changing what it expects means agreeing a new `schema_version`.
- **Core** generates this repository's IAM role (`kind: app`). It can push to `<service>/*` in ECR, publish to `<tier>/<service>/` in the deploy bucket and `static/<service>/` in the assets bucket, send the fleet-update document to the tier's hosts, and read `/<project>/platform/*`, `/<project>/database/*` and `/<project>/services/<service>/*`. Anything else fails with AccessDenied, on purpose.

## Checks before a commit

```bash
(cd app && python manage.py test)
shellcheck -S warning scripts/*.sh scripts/ci/*.sh
bash scripts/ci/tests/run-all.sh
actionlint
```

## Environments and releases

- `.github/environments.json` lists the environments this app deploys to (any of development, staging, production, only ones its infrastructure repository runs), checked by `scripts/ci/enabled-environments.sh` and always used in the platform's order: a release reaches the first automatically, and each later one accepts only a tag that ran in the one before it. `scripts/init-app.sh --environments` sets it.
- Releases are decided from commit messages (semantic-release, angular convention): `feat:` minor, `fix:`/`perf:` patch, a `BREAKING CHANGE:` note major. Every pull request's commits and title are checked (`scripts/ci/check-commit-messages.sh`).

## Open items

- Dedicated hosting has never run: the first staging deploy is the test that its hosts carry `Service=<service>` and answer the service's own document.
- Nothing here has been run against real AWS or GitHub. The tests fake `aws`, `docker` and `gh`; the first real release is the test of the rest.
- The hosting models the service config reports are `shared` and `dedicated`; the old `shared-fleet` is refused on purpose, so a config from an unmigrated service-infra fails loudly instead of deploying to the wrong hosts. Names follow `<project>-<environment>-<service>-<resource>` (the dedicated config bucket is `<project>-<env>-<service>-config`).

