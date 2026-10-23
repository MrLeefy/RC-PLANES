#!/usr/bin/env python3
"""Rebuild the APK signing keystore from a secret seed.

Android only installs an update if it is signed with the same certificate as the
installed app. CI has no persistent storage, so instead of keeping a keystore file
anywhere, the RSA key and its self-signed certificate are derived deterministically
from one secret (the RC_SIGNING_SEED repository secret). Same seed -> byte-identical
certificate -> every build can update the previous one.

Usage: RC_SIGNING_SEED=... make_keystore.py OUT.p12 STORE_PASSWORD
"""
import datetime
import hashlib
import hmac
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

KEY_BITS = 3072
E = 65537


class Drbg:
    """HMAC-SHA256 counter-mode byte stream keyed by the seed."""

    def __init__(self, seed: bytes, label: bytes):
        self.key = hashlib.pbkdf2_hmac("sha256", seed, b"rcpark-signing/" + label, 200_000)
        self.counter = 0

    def bytes(self, n: int) -> bytes:
        out = b""
        while len(out) < n:
            out += hmac.new(self.key, self.counter.to_bytes(8, "big"), hashlib.sha256).digest()
            self.counter += 1
        return out[:n]

    def int_bits(self, bits: int) -> int:
        return int.from_bytes(self.bytes((bits + 7) // 8), "big") >> ((8 - bits % 8) % 8)


SMALL_PRIMES = [p for p in range(3, 2000) if all(p % d for d in range(2, int(p ** 0.5) + 1))]


def is_probable_prime(n: int, rng: Drbg) -> bool:
    for p in SMALL_PRIMES:
        if n % p == 0:
            return n == p
    d, r = n - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for _ in range(40):
        a = 2 + rng.int_bits(n.bit_length()) % (n - 3)
        x = pow(a, d, n)
        if x in (1, n - 1):
            continue
        for _ in range(r - 1):
            x = pow(x, 2, n)
            if x == n - 1:
                break
        else:
            return False
    return True


def gen_prime(bits: int, rng: Drbg) -> int:
    while True:
        cand = rng.int_bits(bits) | (0b11 << (bits - 2)) | 1   # top two bits set -> n has full length
        if (cand - 1) % E != 0 and is_probable_prime(cand, rng):
            return cand


def derive_key(seed: bytes) -> rsa.RSAPrivateKey:
    rng = Drbg(seed, b"rsa")
    p = gen_prime(KEY_BITS // 2, rng)
    q = gen_prime(KEY_BITS // 2, rng)
    while q == p:
        q = gen_prime(KEY_BITS // 2, rng)
    n = p * q
    d = pow(E, -1, (p - 1) * (q - 1))
    numbers = rsa.RSAPrivateNumbers(
        p, q, d, d % (p - 1), d % (q - 1), pow(q, -1, p), rsa.RSAPublicNumbers(E, n)
    )
    return numbers.private_key()


def build_cert(key: rsa.RSAPrivateKey, seed: bytes) -> x509.Certificate:
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "RC Park"), x509.NameAttribute(NameOID.ORGANIZATION_NAME, "RC Park")])
    serial = int.from_bytes(Drbg(seed, b"serial").bytes(16), "big") >> 1
    # fixed dates + PKCS#1 v1.5 (deterministic) signature -> identical certificate every run
    return (
        x509.CertificateBuilder()
        .subject_name(name)
        .issuer_name(name)
        .public_key(key.public_key())
        .serial_number(serial)
        .not_valid_before(datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
        .not_valid_after(datetime.datetime(2080, 1, 1, tzinfo=datetime.timezone.utc))
        .sign(key, hashes.SHA256())
    )


def main() -> None:
    seed = os.environ.get("RC_SIGNING_SEED", "").encode()
    if len(seed) < 16:
        sys.exit("RC_SIGNING_SEED must be set and at least 16 characters long")
    out, password = sys.argv[1], sys.argv[2].encode()
    key = derive_key(seed)
    cert = build_cert(key, seed)
    data = pkcs12.serialize_key_and_certificates(
        b"rcpark", key, cert, None, serialization.BestAvailableEncryption(password)
    )
    with open(out, "wb") as f:
        f.write(data)
    print("signing certificate SHA-256:", cert.fingerprint(hashes.SHA256()).hex(":"))


if __name__ == "__main__":
    main()
