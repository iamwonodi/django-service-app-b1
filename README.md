# Django service: application blueprint

A Django service, its container, and the pipeline that releases and deploys it onto the platform that [core](https://github.com/iamwonodi/aws-core-infra-b1) runs. It is one half of a service. The other half is the **infrastructure repository** ([aws-service-infra-b1](https://github.com/iamwonodi/aws-service-infra-b1)), which creates the service's cloud resources.

```text
   this repository                            service-infra
   (build and deploy)                         (creates the resources)
        |                                           |
        | reads                                     | writes
        v                                           v
   /<project>/services/<service>/config  <---------+
        |
        | tells this repository where to push the image, where to publish files,
        | which document redeploys, the port, the domain, the secret
        v
   ECR  ·  static/<service>/ (CloudFront)  ·  <tier>/<service>/ (deploy bucket)  ·  the tier's hosts
```

The two repositories have separate IAM roles, and neither can do the other's job: this one can push an image, publish files and trigger a redeploy, and **can create or change no resource**. Core generates both roles from a `service-roles.json` entry for each.

## What is here

```text
app/                      the Django project, its Dockerfile, and the deployment templates (the build context)
  config/                   the project package: urls, wsgi, asgi, and settings/ (base, development, staging, production)
  apps/                     the Django apps: core (shared base model, mixins, health middleware),
                            users (custom user, login, profile), polls (the worked example; delete it)
  theme/                    the Tailwind build app (not business logic)
  templates/                the project-wide layout: base.html, partials/, errors/404 and 500
  requirements/             base, production (the image), development, staging
  docker-compose.yml        the service's fleet deployment (a template)
  .env                      its configuration (a template of placeholders and secret references)
  .env.example              the variables for local development only
deploy.json               this service's project, name and tier
.github/
  environments.json         the environments this app deploys to (checked; always development, staging, production order)
  workflows/                release, build-and-push, deploy, tests
  actions/ensure-image/     build and push an image if the tag is not already in ECR
scripts/                  init-app, print-role-entry, fetch-role-arn
scripts/ci/               what the workflows call, with offline tests
docs/deploy.md            the pipeline, setup, and how to promote
```

## The release flow

1. **Merge to `main`.** `release.yml` runs semantic-release, which tags `vX.Y.Z` from the commit messages.
2. **The tag is built.** `build-and-push.yml` builds the image and pushes it to the development ECR repository.
3. **Development deploys automatically.** `deploy.yml` uploads the static files, publishes the compose file and `.env`, redeploys the tier's hosts, and **waits for every host to report success**.
4. **Staging and production are deliberate.** Run the Deploy workflow by hand with a tag. It is accepted only if that tag already deployed successfully to the environment below.

## Getting started

```bash
scripts/init-app.sh --project acme --service auth --region eu-west-1 --reviewers alice
```

then follow [docs/deploy.md](docs/deploy.md).

## Local development

```bash
cd app
python -m venv .venv && . .venv/bin/activate
pip install -r requirements/development.txt
python manage.py migrate
python manage.py runserver
```

`manage.py` uses `config.settings.development` (DEBUG on, SQLite, console email), which starts with no environment variables; `.env.example` lists the ones you can set. `python manage.py test` runs the suite. `docker build -t service app` builds the production image.

### Settings modules

| Module | Used by |
| --- | --- |
| `config.settings.production` | **every deployed container**, in every environment. The image sets it, and it refuses to start with `DJANGO_DEBUG=true` |
| `config.settings.development` | a local workstation only |
| `config.settings.staging` | nothing, until a service needs a staging-only difference: it is production plus a place to put it |

The image is built once and promoted from one environment to the next, so the environments differ by their variables, never by their code. All three read the same environment variables through `base.py`.

### Adding an app

```bash
cd app
python manage.py startapp orders apps/orders
```

then set `name = "apps.orders"` in `apps/orders/apps.py` and add `"apps.orders"` to `INSTALLED_APPS` in `config/settings/base.py`. Keep an app's tests in `apps/orders/tests/`. An app that stores a user reference points at `settings.AUTH_USER_MODEL`.

The user model is `apps.users.User`, a plain `AbstractUser` swapped in before any migration exists, since it cannot be replaced afterwards. `polls` is the demo of an app's shape; a service deletes it (its folder, its `INSTALLED_APPS` entry and its URL in `config/urls.py`) before its first release, while no table exists.

## Testing

| What | How |
| --- | --- |
| The application, its settings and the migration lock | `python manage.py test` in `app/` (the production requirements first, then the development ones) |
| The models and migrations agree | `python manage.py makemigrations --check --dry-run` in `app/` |
| The pipeline's scripts | `bash scripts/ci/tests/run-all.sh` (bash, git, jq; `aws`, `docker` and `gh` are faked) |

The scripts' tests prove their own logic. They do not prove AWS's or Docker's behaviour: the first real deploy does.
