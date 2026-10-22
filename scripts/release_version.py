"""Validate Android release metadata before building or accessing signing keys."""

import json
import os
from pathlib import Path
import re


def release_version(pubspec, manifest, tag=''):
    match = re.search(
        r'^version: (0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\+([1-9][0-9]*)$',
        pubspec,
        re.MULTILINE,
    )
    if not match:
        raise ValueError('pubspec.yaml must have a stable version and positive Android build number.')
    version = '.'.join(match.group(1, 2, 3))
    build = int(match.group(4))
    if build > 2100000000:
        raise ValueError('Android build number exceeds the supported versionCode limit.')
    if tag:
        if tag != f'v{version}':
            raise ValueError('Release tag must match the pubspec.yaml version.')
        if manifest.get('.') != version:
            raise ValueError('Release Please manifest must match the release version.')
    return version, build


if __name__ == '__main__':
    version, build = release_version(
        Path('pubspec.yaml').read_text(),
        json.loads(Path('.github/release-please-manifest.json').read_text()),
        os.environ.get('RELEASE_TAG', ''),
    )
    print(f'version={version}')
    print(f'build-number={build}')
