"""Request middleware for load-balancer integration."""

from django.http import HttpResponse


class HealthCheckMiddleware:
    """
    Answer the load balancer's health check before host validation runs.

    The ALB checks targets by private IP, so the Host header carries an
    instance IP that cannot be in ALLOWED_HOSTS -- it differs per
    instance and changes on every replacement. Django would reject it
    with DisallowedHost (400), the target would never go healthy, and the
    ASG would replace the instance in a loop.

    Note this is specifically the ALB's check. The container's own
    healthcheck uses localhost, which IS in ALLOWED_HOSTS -- so without
    this middleware Docker reports the container healthy while the ALB
    reports the target unhealthy.

    request.path is safe to read here; it does not call get_host().

    Must be FIRST in MIDDLEWARE: SecurityMiddleware and CommonMiddleware
    both call get_host() and would trigger the same rejection if they ran
    ahead of this.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path == "/health":
            return HttpResponse("ok", content_type="text/plain")
        return self.get_response(request)