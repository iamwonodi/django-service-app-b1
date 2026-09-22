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
app/                      the Django project, its Dockerfile, and the deployment templates
  docker-compose.yml        the service's fleet deployment (a template)
  .env                      its configuration (a template of placeholders and secret references)
deploy.json               this service's project, name and tier
.github/
  environments.json         the enabled environments, lowest first
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
pip install -r requirements-dev.txt
DJANGO_DEBUG=true python manage.py migrate
DJANGO_DEBUG=true python manage.py runserver
```

`python manage.py test` runs the suite. `docker build -t service app` builds the production image.

## Testing

| What | How |
| --- | --- |
| The application, its settings and the migration lock | `python manage.py test` in `app/` |
| The pipeline's scripts | `bash scripts/ci/tests/run-all.sh` (bash, git, jq; `aws`, `docker` and `gh` are faked) |

The scripts' tests prove their own logic. They do not prove AWS's or Docker's behaviour: the first real deploy does.
