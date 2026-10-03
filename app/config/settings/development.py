"""
Development settings: a local workstation only, never a deployed container.

Starts with no environment variables at all: DEBUG on, SQLite, a built-in secret
key and localhost allowed. Any of them can still be overridden with the usual
variables (DJANGO_DEBUG=false included, to see how the application behaves with
DEBUG off).
"""

import os

# base.py derives its development fallbacks (secret key, allowed hosts) from
# DEBUG, so the default has to be in the environment before it is imported.
os.environ.setdefault("DJANGO_DEBUG", "true")

from .base import *  # noqa: E402, F403
from .base import DEBUG, INSTALLED_APPS, MIDDLEWARE  # noqa: E402

# Mail is printed to the console rather than sent.
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"

# Reloads the browser when a template or stylesheet changes. It injects a script
# into every response and serves an event-stream endpoint, so it is loaded only
# here and only if installed (requirements/development.txt).
if DEBUG:
    try:
        import django_browser_reload  # noqa: F401
    except ImportError:
        pass
    else:
        INSTALLED_APPS += ["django_browser_reload"]
        MIDDLEWARE += ["django_browser_reload.middleware.BrowserReloadMiddleware"]
