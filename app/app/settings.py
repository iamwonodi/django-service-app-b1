"""
Django settings.

Every value that differs between environments comes from an environment
variable, so the same image runs in development, staging and production. On the
fleet those variables come from the service's .env file, with secrets resolved
from Secrets Manager just before the container starts (see .env and
docker-compose.yml).

Nothing here has a production default that would be unsafe: a missing secret or
allowed host stops the process with a message that names the cause, rather than
starting an application that is quietly misconfigured.
"""

import os
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent


# -----------------------------------------------------------------------------
# Reading the environment
# -----------------------------------------------------------------------------

def env_bool(name, default=False):
    """True for 1/true/yes/on (any case); anything else set is False."""
    value = os.environ.get(name)
    if value is None or value.strip() == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def env_list(name):
    """A comma-separated variable as a list, ignoring blanks and spaces."""
    return [item.strip() for item in os.environ.get(name, "").split(",") if item.strip()]


# -----------------------------------------------------------------------------
# Core
# -----------------------------------------------------------------------------

DEBUG = env_bool("DJANGO_DEBUG", False)

# Names this service. It is used to build STATIC_URL, so it must match the
# service_name the platform knows the service by.
SERVICE_NAME = os.environ.get("SERVICE_NAME", "app")

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "")

if not SECRET_KEY:
    if DEBUG:
        # Local development only. Never reachable in production, where DEBUG is
        # false and this branch raises instead.
        SECRET_KEY = "insecure-development-key-not-for-production"
    else:
        # An empty key here usually means the __FROM_SECRET__ resolution on the
        # host did not produce a value -- a missing or unreadable APP_SECRET_ARN.
        # Django's own "must not be empty" error would not say that.
        raise ImproperlyConfigured(
            "DJANGO_SECRET_KEY is empty. Check that APP_SECRET_ARN is set in the "
            "service's .env and that the instance role can read that secret."
        )

ALLOWED_HOSTS = env_list("DJANGO_ALLOWED_HOSTS")

if not ALLOWED_HOSTS:
    if DEBUG:
        ALLOWED_HOSTS = ["localhost", "127.0.0.1", "[::1]"]
    else:
        raise ImproperlyConfigured(
            "DJANGO_ALLOWED_HOSTS is empty. Set it to the domain the service is "
            "served on (comma-separated for several)."
        )

CSRF_TRUSTED_ORIGINS = env_list("DJANGO_CSRF_TRUSTED_ORIGINS")


# -----------------------------------------------------------------------------
# Applications
# -----------------------------------------------------------------------------

INSTALLED_APPS = [
    "polls.apps.PollsConfig",
    "django.contrib.admin",
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "tailwind",
    "theme",
]

MIDDLEWARE = [
    # First: answers the load balancer's health check before any host validation.
    "app.middleware.HealthCheckMiddleware",
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

TAILWIND_APP_NAME = "theme"

# Development tooling. It injects a script into every response and serves an
# event-stream endpoint, so it is loaded only in DEBUG and only if installed
# (requirements-dev.txt); the production image does not contain it.
if DEBUG:
    try:
        import django_browser_reload  # noqa: F401
    except ImportError:
        pass
    else:
        INSTALLED_APPS += ["django_browser_reload"]
        MIDDLEWARE += ["django_browser_reload.middleware.BrowserReloadMiddleware"]

ROOT_URLCONF = "app.urls"
WSGI_APPLICATION = "app.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]


# -----------------------------------------------------------------------------
# Proxy and transport security
# -----------------------------------------------------------------------------
# TLS terminates at CloudFront and the ALB, so the application always sees plain
# HTTP. Without this header mapping request.is_secure() is False, secure cookies
# are never set, and Django builds http:// URLs that break login flows.
#
# SECURE_SSL_REDIRECT stays off: CloudFront already redirects HTTP to HTTPS at the
# edge, and a second redirect inside the origin would only add a hop.
#
# HSTS is off by default because it cannot be undone for the period it names.
# Set DJANGO_SECURE_HSTS_SECONDS once the domain is committed to HTTPS.
# -----------------------------------------------------------------------------

SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

SESSION_COOKIE_SECURE = not DEBUG
CSRF_COOKIE_SECURE = not DEBUG

SECURE_HSTS_SECONDS = int(os.environ.get("DJANGO_SECURE_HSTS_SECONDS", "0"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = SECURE_HSTS_SECONDS > 0
SECURE_CONTENT_TYPE_NOSNIFF = True


# -----------------------------------------------------------------------------
# Static files
# -----------------------------------------------------------------------------
# Served by CloudFront from S3, never by this application. Each service owns the
# prefix static/<service>/ in the shared assets bucket, and CloudFront's single
# /static/* behaviour routes to it, so STATIC_URL names the service:
#
#     /static/<service>/polls/style.<hash>.css
#
# collectstatic runs at image build time; the deploy pipeline uploads the result
# to that prefix. Manifest storage gives every file a hashed name, so a long
# CloudFront TTL is safe and a rollback still finds the files of the older
# release: hashed names are never overwritten.
# -----------------------------------------------------------------------------

STATIC_URL = f"/static/{SERVICE_NAME}/"
STATIC_ROOT = BASE_DIR / "staticfiles"

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "django.contrib.staticfiles.storage.ManifestStaticFilesStorage",
    },
}


# -----------------------------------------------------------------------------
# Database
# -----------------------------------------------------------------------------
# The engine names the platform uses (postgres, mysql) differ from Django's
# backend module names, so both are accepted.
# -----------------------------------------------------------------------------

DATABASE_BACKENDS = {
    "postgres": "postgresql",
    "postgresql": "postgresql",
    "mysql": "mysql",
    "sqlite3": "sqlite3",
    "sqlite": "sqlite3",
}

_engine = os.environ.get("DATABASE_ENGINE", "sqlite3").strip().lower()

if _engine not in DATABASE_BACKENDS:
    raise ImproperlyConfigured(
        f"DATABASE_ENGINE '{_engine}' is not supported. Use one of: "
        + ", ".join(sorted(DATABASE_BACKENDS))
    )

_backend = DATABASE_BACKENDS[_engine]

if _backend == "sqlite3":
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": os.environ.get("DATABASE_NAME", str(BASE_DIR / "db.sqlite3")),
        }
    }
else:
    _missing = [
        name
        for name in ("DATABASE_HOST", "DATABASE_PORT", "DATABASE_NAME", "DATABASE_USERNAME", "DATABASE_PASSWORD")
        if not os.environ.get(name)
    ]
    if _missing:
        raise ImproperlyConfigured(
            f"DATABASE_ENGINE is {_engine} but these are not set: {', '.join(_missing)}. "
            "The name, user and password come from the service's secret "
            "(__FROM_SECRET__ in .env); the host and port from the platform."
        )

    DATABASES = {
        "default": {
            "ENGINE": f"django.db.backends.{_backend}",
            "NAME": os.environ["DATABASE_NAME"],
            "USER": os.environ["DATABASE_USERNAME"],
            "PASSWORD": os.environ["DATABASE_PASSWORD"],
            "HOST": os.environ["DATABASE_HOST"],
            "PORT": os.environ["DATABASE_PORT"],
            # The database host is reached over the network, so a new connection
            # per request is real latency. Keep this below the database's own
            # idle timeout.
            "CONN_MAX_AGE": int(os.environ.get("DATABASE_CONN_MAX_AGE", "60")),
            # Bound every connection attempt. Without it, a database whose
            # security group DROPS packets -- which is what a missing rule does --
            # blocks each attempt for the operating system's TCP timeout (about two
            # minutes on Linux): a request hangs instead of failing, and
            # migrate.py cannot honour MIGRATE_DB_WAIT, since it can only check
            # its deadline between attempts. Both PostgreSQL's and MySQL's
            # drivers take the same key, in seconds.
            "OPTIONS": {
                "connect_timeout": int(os.environ.get("DATABASE_CONNECT_TIMEOUT", "5")),
            },
        }
    }

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"


# -----------------------------------------------------------------------------
# Auth, localisation
# -----------------------------------------------------------------------------

AUTH_PASSWORD_VALIDATORS = [
    {"NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator"},
    {"NAME": "django.contrib.auth.password_validation.MinimumLengthValidator"},
    {"NAME": "django.contrib.auth.password_validation.CommonPasswordValidator"},
    {"NAME": "django.contrib.auth.password_validation.NumericPasswordValidator"},
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True


# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
# With DEBUG off and no handler configured, unhandled exceptions produce almost
# nothing on stdout, so nothing useful would reach the container's logs.
# -----------------------------------------------------------------------------

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
    },
    "root": {
        "handlers": ["console"],
        "level": os.environ.get("DJANGO_LOG_LEVEL", "INFO"),
    },
    "loggers": {
        "django.request": {
            "handlers": ["console"],
            "level": "ERROR",
            "propagate": False,
        },
    },
}
