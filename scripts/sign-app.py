#!/usr/bin/env python3
"""Sign development builds with a persistent identity, without installing a trust root.

SEREIN_SIGN_IDENTITY (and optional SEREIN_SIGN_KEYCHAIN) selects an existing Apple
identity. Otherwise the app's dedicated local development identity is reused.
Private material lives outside the repository and is never printed.
"""
import fcntl
import json
import os
from pathlib import Path
import plistlib
import secrets
import shlex
import subprocess
import sys
import tempfile

os.umask(0o077)
SECURITY = '/usr/bin/security'
OPENSSL = '/usr/bin/openssl'
CODESIGN = '/usr/bin/codesign'
ROOT = Path.home() / 'Library/Application Support/SereinDevelopmentSigning'


def run(args, *, env=None):
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True, env=env)
    if result.returncode:
        # Do not include argv: security/openSSL commands can contain a passphrase.
        raise RuntimeError(f'{Path(args[0]).name}: {result.stderr.strip() or "operation failed"}')
    return result.stdout.strip()


def search_list():
    return shlex.split(run([SECURITY, 'list-keychains', '-d', 'user']))


def remove_from_search_list(path):
    # Preserve any concurrent additions; remove only our temporary keychain.
    current = search_list()
    if str(path) in current:
        run([SECURITY, 'list-keychains', '-d', 'user', '-s', *[p for p in current if p != str(path)]])


def create_identity(destination):
    with tempfile.TemporaryDirectory(prefix='.creating-', dir=ROOT) as temp:
        work = Path(temp)
        identity = work / 'identity'
        identity.mkdir(mode=0o700)
        keychain = identity / 'signing.keychain-db'
        password = secrets.token_urlsafe(48)
        (identity / 'keychain-password').write_text(password)
        config = work / 'certificate.conf'
        config.write_text('''[req]
prompt = no
distinguished_name = name
x509_extensions = extensions
[name]
CN = Serein Local Development
[extensions]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
''')
        certificate = identity / 'certificate.pem'
        private_key = work / 'private-key.pem'
        run([OPENSSL, 'req', '-new', '-newkey', 'rsa:3072', '-x509', '-nodes', '-days', '3650',
             '-config', config, '-keyout', private_key, '-out', certificate])
        fingerprint = run([OPENSSL, 'x509', '-in', certificate, '-noout', '-fingerprint', '-sha1']).split('=')[-1].replace(':', '').strip()
        if len(fingerprint) != 40 or any(c not in '0123456789abcdefABCDEF' for c in fingerprint):
            raise RuntimeError('Invalid certificate fingerprint')
        (identity / 'identity-sha1').write_text(fingerprint)
        p12 = work / 'identity.p12'
        environment = dict(os.environ, SEREIN_P12_PASSWORD=password)
        run([OPENSSL, 'pkcs12', '-export', '-inkey', private_key, '-in', certificate,
             '-name', 'Serein Local Development', '-out', p12, '-passout', 'env:SEREIN_P12_PASSWORD'], env=environment)
        try:
            run([SECURITY, 'create-keychain', '-p', password, keychain])
            run([SECURITY, 'unlock-keychain', '-p', password, keychain])
            run([SECURITY, 'import', p12, '-k', keychain, '-P', password, '-T', CODESIGN])
            run([SECURITY, 'set-keychain-settings', '-l', '-u', '-t', '3600', keychain])
            run([SECURITY, 'lock-keychain', keychain])
        finally:
            try:
                if keychain.exists():
                    run([SECURITY, 'lock-keychain', keychain])
            finally:
                remove_from_search_list(keychain)
        identity.rename(destination)


def sign(app):
    with (app / 'Contents/Info.plist').open('rb') as info:
        bundle_id = plistlib.load(info)['CFBundleIdentifier']
    configured = os.environ.get('SEREIN_SIGN_IDENTITY')
    local_fingerprint = None
    if configured:
        if configured == '-':
            raise RuntimeError('Ad-hoc signing cannot preserve calendar permission across builds. Select a certificate identity.')
        args = [CODESIGN, '--force', '--sign', configured]
        if os.environ.get('SEREIN_SIGN_KEYCHAIN'):
            args += ['--keychain', os.environ['SEREIN_SIGN_KEYCHAIN']]
        run([*args, app])
    else:
        ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(ROOT, 0o700)
        with (ROOT / 'build.lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            identity = ROOT / 'identity'
            if not identity.exists():
                create_identity(identity)
            required = ['keychain-password', 'identity-sha1', 'certificate.pem', 'signing.keychain-db']
            if not all((identity / name).is_file() for name in required):
                raise RuntimeError('The local signing identity is incomplete. Restore its backup; do not silently replace it.')
            password = (identity / 'keychain-password').read_text().strip()
            fingerprint = (identity / 'identity-sha1').read_text().strip()
            local_fingerprint = fingerprint.lower()
            keychain = identity / 'signing.keychain-db'
            added_to_search = str(keychain) not in search_list()
            try:
                # codesign also resolves the certificate chain through the
                # search list, even when --keychain selects the identity.
                if added_to_search:
                    run([SECURITY, 'list-keychains', '-d', 'user', '-s', *search_list(), keychain])
                run([SECURITY, 'unlock-keychain', '-p', password, keychain])
                run([CODESIGN, '--force', '--sign', fingerprint, '--keychain', keychain, '--timestamp=none', app])
            finally:
                try:
                    run([SECURITY, 'lock-keychain', keychain])
                finally:
                    if added_to_search:
                        remove_from_search_list(keychain)
    run([CODESIGN, '--verify', '--deep', '--strict', app])
    result = subprocess.run([CODESIGN, '-d', '-r-', str(app)], capture_output=True, text=True)
    requirement = result.stdout + result.stderr
    if result.returncode or 'designated =>' not in requirement or 'identifier ' not in requirement or not any(x in requirement for x in ['anchor ', 'certificate ']):
        raise RuntimeError('The signed app has no stable certificate-bound designated requirement.')
    if local_fingerprint:
        expected = f'identifier {json.dumps(bundle_id)} and certificate leaf = H"{local_fingerprint}"'
        actual = next((line.removeprefix('designated => ') for line in requirement.splitlines() if line.startswith('designated => ')), '')
        if actual != expected:
            raise RuntimeError('The local designated requirement must bind the exact bundle ID and saved certificate.')
        run([CODESIGN, '--verify', '--strict', '-R', '=' + expected, app])
    print('Signed with a persistent certificate identity; signature verified.')


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2 or not Path(sys.argv[1]).is_dir():
            raise RuntimeError('Usage: sign-app.py /path/to/Application.app')
        sign(Path(sys.argv[1]).resolve())
    except (RuntimeError, OSError) as error:
        print(f'Signing failed: {error}', file=sys.stderr)
        sys.exit(1)
