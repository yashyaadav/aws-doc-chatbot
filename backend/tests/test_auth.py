"""Regression test for Cognito ID-token verification.

Hosted-UI implicit-flow ID tokens include an ``at_hash`` claim (an access token
is minted alongside). python-jose rejects such a token unless ``at_hash``
verification is disabled, which manifested as every chat request 401-ing and
redirecting the user back to the login screen.
"""

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jose import jwt

from app import auth, config


@pytest.fixture
def rsa_keys():
    priv = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    priv_pem = priv.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    )
    pub_pem = priv.public_key().public_bytes(
        serialization.Encoding.PEM,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return priv_pem, pub_pem


def _patch(monkeypatch, pub_pem):
    monkeypatch.setattr(config.settings, "aws_region", "us-east-1")
    monkeypatch.setattr(config.settings, "cognito_user_pool_id", "us-east-1_pool")
    monkeypatch.setattr(config.settings, "cognito_app_client_id", "client123")
    # Bypass the JWKS HTTP fetch — hand the verifier the public key directly.
    monkeypatch.setattr(auth, "_key_for", lambda token: pub_pem)


def test_id_token_with_at_hash_is_accepted(monkeypatch, rsa_keys):
    priv_pem, pub_pem = rsa_keys
    _patch(monkeypatch, pub_pem)
    claims = {
        "sub": "u1",
        "aud": "client123",
        "iss": auth._issuer(),
        "token_use": "id",
        "at_hash": "someAccessTokenHash",  # present on Hosted-UI tokens
    }
    token = jwt.encode(claims, priv_pem, algorithm="RS256")
    decoded = auth.verify_token(token)
    assert decoded["sub"] == "u1"


def test_bad_audience_is_rejected(monkeypatch, rsa_keys):
    priv_pem, pub_pem = rsa_keys
    _patch(monkeypatch, pub_pem)
    claims = {"sub": "u1", "aud": "someone-else", "iss": auth._issuer(), "at_hash": "x"}
    token = jwt.encode(claims, priv_pem, algorithm="RS256")
    with pytest.raises(auth.AuthError):
        auth.verify_token(token)
