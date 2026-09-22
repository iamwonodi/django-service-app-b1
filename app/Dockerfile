# syntax=docker/dockerfile:1

# ==============================================================================
# Three stages:
#   1. tailwind  compiles the CSS with Node, which the final image does not carry
#   2. builder   installs the Python dependencies into a virtual environment
#   3. final     the runtime image
#
# The context is the app/ directory (the folder holding this file).
# ==============================================================================


# ------------------------------------------------------------------------------
# 1. Tailwind
#
# django-tailwind's compiled stylesheet is a build artifact and is not committed,
# so it is produced here. The templates are copied in because Tailwind scans them
# for the class names to keep (see the @source lines in theme/static_src/src/styles.css).
# ------------------------------------------------------------------------------
FROM node:24-slim AS tailwind

WORKDIR /build/theme/static_src

# Dependencies first, so this layer is cached until package-lock.json changes.
COPY theme/static_src/package.json theme/static_src/package-lock.json ./
RUN npm ci

COPY . /build
RUN npm run build


# ------------------------------------------------------------------------------
# 2. Python dependencies
# ------------------------------------------------------------------------------
FROM python:3.14-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

COPY requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt


# ------------------------------------------------------------------------------
# 3. Runtime
# ------------------------------------------------------------------------------
FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:${PATH}"

# A fixed, unprivileged user. The compose file also drops every capability.
RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
COPY --chown=app:app . /app

# Belt and braces with .gitattributes: a script checked out with Windows line
# endings has a carriage return in its interpreter path, and the container then
# fails to start with "no such file or directory".
RUN sed -i 's/\r$//' /app/entrypoint.prod.sh && chmod +x /app/entrypoint.prod.sh
COPY --from=tailwind --chown=app:app /build/theme/static/css/dist /app/theme/static/css/dist

# Collect the static files into /app/staticfiles. The pipeline copies that folder
# out of the image and uploads it. The key is a throwaway used only by this step:
# collectstatic needs settings to import, but reads no secret and stores nothing.
RUN DJANGO_SECRET_KEY=build-time-only-not-a-secret \
    DJANGO_ALLOWED_HOSTS=build \
    python manage.py collectstatic --noinput \
 && chown -R app:app /app/staticfiles

USER app

EXPOSE 8000

ENTRYPOINT ["/app/entrypoint.prod.sh"]
