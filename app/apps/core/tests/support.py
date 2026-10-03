"""Shared by the tests of pages that load static files."""

# The production storage hashes names from a manifest that only collectstatic
# writes, so a page that names a static file cannot render in a test without
# this override (override_settings(STORAGES=PLAIN_STATIC)).
PLAIN_STATIC = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}
