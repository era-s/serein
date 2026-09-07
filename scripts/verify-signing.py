#!/usr/bin/env python3
"""Verify certificate-bound rebuilds using only Serein's existing local identity.

All app fixtures stay in a temporary directory and are never launched. The only
keychain mutations are performed by sign-app.py itself. No private material,
certificate fingerprints, requirements or keychain paths are printed.
"""
import os
from pathlib import Path
import plistlib
import re
import shlex
import shutil
import subprocess
import sys
import tempfile


PROJECT = Path(__file__).resolve().parent.parent
SIGNER = PROJECT / 'scripts/sign-app.py'
IDENTITY = Path.home() / 'Library/Application Support/SereinDevelopmentSigning/identity'
SECURITY = '/usr/bin/security'
CODESIGN = '/usr/bin/codesign'
CLANG = '/usr/bin/clang'
ASSERTIONS = 0
ENVIRONMENT = {key: value for key, value in os.environ.items()
               if key not in {'SEREIN_SIGN_IDENTITY', 'SEREIN_SIGN_KEYCHAIN'}}


def check(condition, description):
    global ASSERTIONS
    if not condition:
        raise RuntimeError(description)
    ASSERTIONS += 1


def execute(arguments, *, label, expected_success=True):
    result = subprocess.run([str(argument) for argument in arguments],
                            capture_output=True, text=True, env=ENVIRONMENT)
    if expected_success and result.returncode:
        # Signing tools may include sensitive arguments in their diagnostics.
        raise RuntimeError(f'{label} failed; command output was withheld')
    return result


def keychain_configuration():
    search = execute([SECURITY, 'list-keychains', '-d', 'user'], label='Read keychain search list')
    default = execute([SECURITY, 'default-keychain', '-d', 'user'], label='Read default keychain')
    return shlex.split(search.stdout), default.stdout.strip()


def sign_and_check_configuration(app, label, *, should_succeed=True):
    before = keychain_configuration()
    try:
        result = execute([sys.executable, SIGNER, app], label=label, expected_success=False)
    finally:
        after = keychain_configuration()
        check(after[0] == before[0], f'{label}: user keychain search list changed')
        check(after[1] == before[1], f'{label}: default keychain changed')
    check((result.returncode == 0) == should_succeed, f'{label}: unexpected signing outcome')


def make_app(directory, name, bundle_id, version, *, executable=True):
    app = directory / f'{name}.app'
    contents = app / 'Contents'
    macos = contents / 'MacOS'
    macos.mkdir(parents=True)
    with (contents / 'Info.plist').open('wb') as output:
        plistlib.dump({
            'CFBundleExecutable': 'SigningProbe',
            'CFBundleIdentifier': bundle_id,
            'CFBundleName': name,
            'CFBundlePackageType': 'APPL',
            'CFBundleVersion': str(version),
            'CFBundleShortVersionString': f'1.{version}',
        }, output)
    if executable:
        source = directory / f'{name}.c'
        source.write_text(f'int main(void) {{ return {version}; }}\n')
        execute([CLANG, source, '-o', macos / 'SigningProbe'], label='Compile temporary native fixture')
    return app


def designated_requirement(app):
    result = execute([CODESIGN, '-d', '-r-', app], label='Read designated requirement')
    for line in (result.stdout + result.stderr).splitlines():
        if line.startswith('designated => '):
            return line.removeprefix('designated => ')
    raise RuntimeError('Signed fixture has no designated requirement')


def code_directory_hash(app):
    result = execute([CODESIGN, '-d', '--verbose=4', app], label='Read code directory hash')
    match = re.search(r'^CDHash=([0-9a-fA-F]+)$', result.stdout + result.stderr, re.MULTILINE)
    if not match:
        raise RuntimeError('Signed fixture has no code directory hash')
    return match.group(1)


def satisfies(app, requirement=None):
    arguments = [CODESIGN, '--verify', '--deep', '--strict']
    if requirement is not None:
        arguments += ['-R', '=' + requirement]
    arguments.append(app)
    return execute(arguments, label='Verify temporary fixture', expected_success=False).returncode == 0


def verify():
    # Do not let the test create an identity, silently rotate one, or select an
    # unrelated certificate from the user's normal keychains.
    required = ['keychain-password', 'identity-sha1', 'certificate.pem', 'signing.keychain-db']
    if not all((IDENTITY / name).is_file() for name in required):
        raise RuntimeError('An existing Serein local signing identity is required; run the normal build setup first')
    initial_configuration = keychain_configuration()
    try:
        with tempfile.TemporaryDirectory(prefix='serein-signing-check-') as temporary:
            directory = Path(temporary)
            bundle_id = 'studio.serein.signing-verification'
            first = make_app(directory, 'BuildOne', bundle_id, 1)
            second = make_app(directory, 'BuildTwo', bundle_id, 2)
            sign_and_check_configuration(first, 'First build')
            sign_and_check_configuration(second, 'Second build')
            first_requirement = designated_requirement(first)
            second_requirement = designated_requirement(second)
            check(code_directory_hash(first) != code_directory_hash(second), 'Changed native builds must have different code directory hashes')
            check(first_requirement == second_requirement, 'Rebuilt app must retain the same designated requirement')
            check(bool(re.fullmatch(r'identifier "' + re.escape(bundle_id) + r'" and certificate leaf = H"[0-9a-fA-F]{40}"', first_requirement)),
                  'Local requirement must bind both the exact bundle ID and the signing certificate')
            check(satisfies(first), 'First build signature must verify')
            check(satisfies(second), 'Second build signature must verify')
            check(satisfies(second, first_requirement), 'Second build must satisfy the first build identity')

            tampered = directory / 'Tampered.app'
            shutil.copytree(second, tampered)
            with (tampered / 'Contents/Info.plist').open('rb') as source:
                info = plistlib.load(source)
            info['CFBundleVersion'] = 'tampered'
            with (tampered / 'Contents/Info.plist').open('wb') as output:
                plistlib.dump(info, output)
            check(not satisfies(tampered), 'Tampering with sealed app metadata must invalidate the signature')
            check(not satisfies(tampered, first_requirement), 'Tampered app must fail the original identity requirement')

            other = make_app(directory, 'DifferentIdentifier', bundle_id + '.other', 3)
            sign_and_check_configuration(other, 'Different bundle identifier')
            check(satisfies(other), 'Different bundle fixture must be validly signed before testing its identity')
            check(not satisfies(other, first_requirement), 'The same certificate must not authorize another bundle identifier')

            adhoc = make_app(directory, 'AdHoc', bundle_id, 4)
            execute([CODESIGN, '--force', '--sign', '-', adhoc], label='Sign ad-hoc negative fixture')
            check(satisfies(adhoc), 'Ad-hoc fixture must have a valid self-contained signature')
            check(not satisfies(adhoc, first_requirement), 'Ad-hoc signing with the same identifier must not satisfy certificate-bound identity')

            incomplete = make_app(directory, 'UnwritableSignatureDirectory', bundle_id, 5)
            # A regular file at the reserved signature-directory path makes
            # codesign fail after the helper has opened its dedicated keychain.
            (incomplete / 'Contents/_CodeSignature').write_bytes(b'not a directory')
            sign_and_check_configuration(incomplete, 'Failed signing cleanup', should_succeed=False)
    finally:
        final_configuration = keychain_configuration()
        check(final_configuration[0] == initial_configuration[0], 'Full verification changed the user keychain search list')
        check(final_configuration[1] == initial_configuration[1], 'Full verification changed the default keychain')
    print(f'Verified {ASSERTIONS} stable signing assertions: rebuild identity, tamper and impersonation rejection, and keychain configuration preservation.')
    print('Temporary native apps were never launched. Existing identity reused; no private signing material printed.')


if __name__ == '__main__':
    try:
        verify()
    except (OSError, RuntimeError) as error:
        print(f'Signing verification failed: {error}', file=sys.stderr)
        sys.exit(1)
