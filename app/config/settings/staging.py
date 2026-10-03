"""
Staging settings: identical to production.

Images are built once and promoted by tag, so staging runs the very image
production will run and must not differ in code. This module exists only so a
service can select it with DJANGO_SETTINGS_MODULE=config.settings.staging if it
ever needs a difference that really is staging-only (a sandbox payment key
endpoint, say). Until then nothing selects it.
"""

from .production import *  # noqa: F403
