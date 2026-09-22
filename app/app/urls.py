"""URL configuration."""

from django.conf import settings
from django.contrib import admin
from django.urls import include, path

urlpatterns = [
    path("polls/", include("polls.urls")),
    path("admin/", admin.site.urls),
]

# Development-only live reload. Mounted only when its app is installed, which
# settings.py does under DEBUG, so the endpoint does not exist in production.
if "django_browser_reload" in settings.INSTALLED_APPS:
    urlpatterns += [path("__reload__/", include("django_browser_reload.urls"))]
