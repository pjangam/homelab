#!/usr/bin/env python3
"""Writes a self-signed cert expiring a given number of days from now.

Used only by scripts/test_cert_expiry_check.sh. `openssl req -x509` cannot do
this: it has only -days (positive integers), and the -not_after flag that would
allow a backdated cert does not exist in OpenSSL 3.0.x, which is what xero has.

Usage: make_test_cert.py <out.crt> <out.key> <days_until_expiry>
       days_until_expiry may be negative, to produce an already-expired cert.
"""
import datetime
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

crt_path, key_path, days = sys.argv[1], sys.argv[2], int(sys.argv[3])

key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
now = datetime.datetime.now(datetime.timezone.utc)
name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "test-cert")])

cert = (
    x509.CertificateBuilder()
    .subject_name(name)
    .issuer_name(name)
    .public_key(key.public_key())
    .serial_number(x509.random_serial_number())
    # Backdate not_valid_before so an "expired" cert is genuinely expired
    # rather than not-yet-valid.
    .not_valid_before((now - datetime.timedelta(days=400)).replace(tzinfo=None))
    # +12h so the checker's floor() lands on exactly `days`. Without it a cert
    # minted "5 days out" reads as 4d, because a fraction of a second elapses
    # before the check runs. Flooring is correct for the checker (it must never
    # overstate remaining time), so the fixture absorbs the difference.
    .not_valid_after((now + datetime.timedelta(days=days, hours=12)).replace(tzinfo=None))
    .sign(key, hashes.SHA256())
)

with open(crt_path, "wb") as f:
    f.write(cert.public_bytes(serialization.Encoding.PEM))
with open(key_path, "wb") as f:
    f.write(key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption(),
    ))
