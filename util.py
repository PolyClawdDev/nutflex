"""Shared utilities."""

from __future__ import annotations

from typing import Any

import urllib.error
import urllib.parse
import urllib.request


class _SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Redirect handler that only allows http/https schemes."""

    def redirect_request(
        self,
        req: urllib.request.Request,
        fp: Any,
        code: int,
        msg: str,
        headers: Any,
        newurl: str,
    ) -> urllib.request.Request | None:
        parsed = urllib.parse.urlparse(newurl)
        if parsed.scheme not in ("http", "https"):
            raise urllib.error.URLError(f"Unsafe redirect scheme: {parsed.scheme}")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


_DEFAULT_USER_AGENT = "VLC/3.0.20 LibVLC/3.0.20"


def safe_urlopen(url: str, timeout: int = 30, user_agent: str | None = None) -> Any:
    """Open URL with safe redirect handling.

    Args:
        url: URL to open
        timeout: Request timeout in seconds
        user_agent: User-Agent header to send. If None, uses a default VLC User-Agent
            to avoid being blocked by providers that reject Python's default.
    """
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise urllib.error.URLError(f"Unsafe URL scheme: {parsed.scheme}")
    ua = user_agent if user_agent else _DEFAULT_USER_AGENT
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    opener = urllib.request.build_opener(_SafeRedirectHandler())
    return opener.open(req, timeout=timeout)
