"""
Production settings: what every deployed container runs, whatever the environment.

Images are built once and promoted by tag, so development, staging and production
all run this module. What differs between them is the environment's variables,
never the code. The hardening below therefore does not depend on a variable.
"""

import os

from django.core.exceptions import ImproperlyConfigured

from .base import *  # noqa: F403
from .base import DEBUG as _DEBUG_FROM_ENVIRONMENT

# A container that was started with DJANGO_DEBUG=true would serve tracebacks and
# settings to the internet. Stop it rather than quietly ignore the variable.
if _DEBUG_FROM_ENVIRONMENT:
    raise ImproperlyConfigured(
        "DJANGO_DEBUG is true, but config.settings.production never runs with DEBUG on. "
        "Unset it; for a local workstation use config.settings.development."
    )

DEBUG = False


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

SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

SECURE_HSTS_SECONDS = int(os.environ.get("DJANGO_SECURE_HSTS_SECONDS", "0"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = SECURE_HSTS_SECONDS > 0
SECURE_CONTENT_TYPE_NOSNIFF = True
