"""The environment a child Python needs just to start, and nothing more.

Several tests run the settings or migrate.py in a fresh interpreter with a
deliberately minimal environment, so they can prove exactly what happens when a
variable is missing. "Minimal" still has to include what the operating system
itself needs, or the child fails before any of our code runs:

- Windows: without SYSTEMROOT, Winsock cannot load its service providers, and
  importing asyncio fails with "WinError 10106: The requested service provider
  could not be loaded or initialized". Django imports asyncio (through asgiref)
  on every startup.

None of these variables is read by the application, so carrying them over does
not change what the tests prove.
"""

import os

# PATH everywhere; the rest only exist on Windows and are ignored elsewhere.
_OPERATING_SYSTEM_VARIABLES = (
    "PATH",
    "SYSTEMROOT",
    "SYSTEMDRIVE",
    "WINDIR",
    "COMSPEC",
    "PATHEXT",
    "TEMP",
    "TMP",
)


def base_environment():
    """The operating system's own variables, as the current process has them."""
    return {name: os.environ[name] for name in _OPERATING_SYSTEM_VARIABLES if name in os.environ}
