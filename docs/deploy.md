# Deploying this service

## What deploys, and when

| Trigger | What happens |
| --- | --- |
| A `v*` tag is pushed (semantic-release does this after a merge to `main`) | **Build And Push** builds the image for the **lowest** enabled environment; **Deploy** then deploys that tag there |
| A change to `app/docker-compose.yml` or `app/.env` reaches `main` | **Deploy** redeploys the newest release to the lowest environment with the new configuration |
| **Deploy** is run by hand | Any enabled environment, for one tag you choose, with the environment name typed as confirmation |
| **Build And Push** is run by hand | A backfill: chosen tags, one environment or all |

**Promotion.** Above the lowest environment a tag is accepted only after it deployed successfully to the environment just below it, recorded as a GitHub Deployment whose ref is the tag. The check runs *before* the environment's approval, so a reviewer is never asked to approve something the rule would refuse. A deploy builds a missing image itself, so promoting is one step.

## Inside a deploy

The tag's own commit is checked out, so the compose file and `.env` deployed are the ones the image was released with. Then, in order:

1. read the service's config from `/<project>/services/<service>/config`;
2. make sure the image is in ECR (build and push if the tag is new there);
3. **upload the static files** from the image's `/app/staticfiles` to `static/<service>/`, before anything else changes, so a new page never names a file that is not there yet. Nothing is ever deleted: file names carry a content hash, and older releases still running on some hosts, or a rollback, need theirs;
4. fill in the placeholders in `docker-compose.yml` and `.env` and publish both to `<tier>/<service>/` in the deploy bucket;
5. **send the fleet-update document to the tier's hosts and wait**. If any host fails, or none answers, or they are still busy after 15 minutes, the workflow fails;
6. record the deployment.

**No secret value passes through CI.** `.env` holds `__FROM_SECRET__` references; the host resolves them from Secrets Manager just before the container starts, into a scratch file it deletes at once.

## Shared fleet and dedicated hosts

The platform decides, per environment, and the service config says which. The deploy steps are identical; only where the files go and which hosts are told to redeploy differ:

| | Development: `shared` | Staging, production: `dedicated` |
| --- | --- | --- |
| Compose file and `.env` | shared deploy bucket, `<tier>/<service>/` | the service's own bucket, `services/<service>/` |
| Redeploy document | core's `<project>-fleet-update` | the service's own `<project>-<service>-update` |
| Hosts told to redeploy | tagged `Service=<tier>` | tagged `Service=<service>` |

`read-service-config.sh` refuses a deploy prefix that is not this service's own directory in either model, so a wrong config can never publish into another service's.

## The placeholders

`app/docker-compose.yml` and `app/.env` are templates. The pipeline fills in `__IMAGE__`, `__PORT__`, `__SERVICE_NAME__`, `__SERVICE_DOMAIN__`, `__DATABASE_HOST__`, `__DATABASE_PORT__` and `__APP_SECRET_ARN__` from the service config, and fails on any other placeholder left unfilled (rather than start a container whose database host is literally `__DATABASE_HOST__`). A service without a database removes the `DATABASE_*` lines from `.env`.

## First setup

Everything here is per **environment**. Only `development` is enabled until the platform hosts services in the others.

**0. Prerequisites.** `gh` (authenticated), `jq`, `git`, `bash`. The platform must be running, this service's **infrastructure repository must be applied** (it publishes the config this pipeline reads), and you need read access to core's repository.

**1. Set the service's values.**

```bash
scripts/init-app.sh --project acme --service auth --region eu-west-1 --reviewers alice
```

`--project`, `--service` and `--tier` must match what the infrastructure repository deploys with. It writes `deploy.json` and creates the GitHub Environment (deployments from `main` and from `v*` tags, reviewers on every environment above the lowest). Preview with `--dry-run`. Commit `deploy.json`.

**2. Ask core for a role.**

```bash
scripts/print-role-entry.sh
```

Paste the JSON into core's `infrastructure/<env>/data/service-roles.json`, next to the infrastructure repository's own entry (`kind: infra`; this one is `kind: app`), and open a pull request in core. Both entries must share `service_name` and `tier`.

**3. Connect to the role.** After core has applied it:

```bash
scripts/fetch-role-arn.sh --core OWNER/CORE-REPOSITORY --environment development
```

**4. Releases need a token.** `release.yml` needs a `RELEASE_TOKEN` secret (a personal access token that can push tags): tags pushed by the default `GITHUB_TOKEN` do not start other workflows, so without it a release would never be built.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `could not read /<project>/services/<service>/config` | The infrastructure repository has not applied yet, or the role cannot read it |
| `deploy.json says 'X' but the config says 'Y'` | The tier differs between this repository and the infrastructure repository |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | Core has not applied this repository's entry, or `AWS_ROLE_ARN` is missing on the environment |
| `no host answered` | No running host carries the tags `Project=<project>` and `Service=<tier>` (shared fleet) or `Service=<service>` (dedicated) |
| `could not read the database port` | The platform team has not registered the engine yet |
| `has not been deployed successfully to <lower>` | Deploy the tag to the environment below first |
| A tag was pushed but nothing was built | `RELEASE_TOKEN` is missing (the tag was pushed with the default token) |
| A staging or production deploy is refused | Check `.github/environments.json`: it must list the environment |

## Not built yet

- **The service's database and user** are created by its infrastructure repository's apply (core's provisioning), with its agents' logins; nothing is needed here.

