"""Gunicorn settings. Read by the entrypoint with --config."""

import multiprocessing
import os

bind = "0.0.0.0:8000"

# Two workers per core plus one is gunicorn's rule of thumb, capped because the
# database connections multiply by the worker count. Override with
# GUNICORN_WORKERS.
workers = int(os.environ.get("GUNICORN_WORKERS") or min(multiprocessing.cpu_count() * 2 + 1, 4))

timeout = int(os.environ.get("GUNICORN_TIMEOUT", "30"))
graceful_timeout = 30

# A tmpfs, so a worker's heartbeat file never touches the disk. In a container the
# default (/tmp on the overlay filesystem) can stall workers under load.
worker_tmp_dir = "/dev/shm"

accesslog = "-"
errorlog = "-"
loglevel = os.environ.get("GUNICORN_LOG_LEVEL", "info")

# Gunicorn 26 opens a control socket for its management CLI, by default in
# $HOME/.gunicorn/. In the container the app user has no home directory and the
# root filesystem is mounted read-only, so the default path cannot be created.
# Nothing here uses the control CLI, so it is turned off; point
# GUNICORN_CONTROL_SOCKET at a writable path (such as /tmp) to use it instead.
control_socket_disable = not os.environ.get("GUNICORN_CONTROL_SOCKET")

if os.environ.get("GUNICORN_CONTROL_SOCKET"):
    control_socket = os.environ["GUNICORN_CONTROL_SOCKET"]
