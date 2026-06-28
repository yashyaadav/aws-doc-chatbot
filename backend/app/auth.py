"""Cognito JWT verification (in-handler, since Function URLs have no JWT authorizer).

Validates the RS256 signature against the user pool's JWKS, plus issuer and
audience. Disabled when ``AUTH_ENABLED=false`` (local dev).
"""

import functools
import json
import urllib.request

from jose import jwt

from .config import settings


class AuthError(Exception):
    pass


def _issuer() -> str:
    return (
        f"https://cognito-idp.{settings.aws_region}.amazonaws.com/{settings.cognito_user_pool_id}"
    )


@functools.lru_cache(maxsize=1)
def _jwks() -> dict:
    url = f"{_issuer()}/.well-known/jwks.json"
    with urllib.request.urlopen(url, timeout=5) as resp:  # noqa: S310 (trusted AWS URL)
        return json.loads(resp.read())


def _key_for(token: str) -> dict:
    kid = jwt.get_unverified_header(token)["kid"]
    for key in _jwks()["keys"]:
        if key["kid"] == kid:
            return key
    raise AuthError("signing key not found for token")


def verify_token(token: str) -> dict:
    """Return the decoded claims, or raise AuthError. Accepts a Cognito ID token."""
    try:
        return jwt.decode(
            token,
            _key_for(token),
            algorithms=["RS256"],
            audience=settings.cognito_app_client_id,
            issuer=_issuer(),
            # Hosted-UI implicit-flow ID tokens carry an `at_hash` claim (an access
            # token is issued alongside). We only have the ID token here, so skip the
            # at_hash check — otherwise python-jose rejects it with "No access_token
            # provided to compare against at_hash claim." Signature/aud/iss/exp still verified.
            options={"verify_at_hash": False},
        )
    except AuthError:
        raise
    except Exception as exc:  # jose raises several subtypes
        raise AuthError(f"invalid token: {exc}") from exc
