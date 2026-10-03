"""The project's URLs plus a view that fails, for the 500 page test."""

from django.urls import path

from config.urls import *  # noqa: F403 - urlpatterns and the error handlers
from config.urls import urlpatterns as project_urlpatterns


def boom(request):
    raise RuntimeError("raised on purpose by a test")


urlpatterns = [*project_urlpatterns, path("boom/", boom)]
