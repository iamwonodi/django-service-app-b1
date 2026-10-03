from django.http import HttpResponseNotFound, HttpResponseServerError
from django.template import loader


def not_found(request, exception):
    return HttpResponseNotFound(loader.render_to_string("errors/404.html", request=request))


def server_error(request):
    # No request: the context processors read the session and the user, and the
    # error being handled may well be the database. Django's own 500 view does the same.
    return HttpResponseServerError(loader.render_to_string("errors/500.html"))
