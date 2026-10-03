from django.utils.http import url_has_allowed_host_and_scheme


def safe_next_url(request, fallback, param="next"):
    """The ``next`` target of a redirect, or `fallback` when it could leave the site.

    An unchecked ``?next=https://evil.example`` turns a login or logout page into
    an open redirect. The host is compared with the request's own, and https is
    required when the request itself arrived over https (behind the load balancer
    that is known through SECURE_PROXY_SSL_HEADER).
    """
    target = request.POST.get(param) or request.GET.get(param)
    if target and url_has_allowed_host_and_scheme(
        target, allowed_hosts={request.get_host()}, require_https=request.is_secure()
    ):
        return target
    return fallback
