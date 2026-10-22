import unittest

from release_version import release_version


class ReleaseVersionTest(unittest.TestCase):
    def test_release_matches_version_and_android_build(self):
        self.assertEqual(
            release_version('name: simplerunning\nversion: 1.3.4+12\n', {'.': '1.3.4'}, 'v1.3.4'),
            ('1.3.4', 12),
        )

    def test_ci_allows_unreleased_version(self):
        self.assertEqual(release_version('version: 1.3.4+11', {'.': '1.3.3'}), ('1.3.4', 11))

    def test_rejects_wrong_tag_or_manifest(self):
        for manifest, tag in [({'.': '1.3.4'}, 'v1.3.3'), ({'.': '1.3.3'}, 'v1.3.4'),
                              ({'.': '1.3.4'}, 'main'), ({'.': '1.3.4'}, 'v1.3.4;echo bad')]:
            with self.subTest(manifest=manifest, tag=tag), self.assertRaises(ValueError):
                release_version('version: 1.3.4+12', manifest, tag)

    def test_rejects_invalid_android_versions(self):
        for version in ['1.3.4', '1.3.4+0', '1.3.4+-1', '1.3.4+2100000001',
                        '1.3.4-beta+12', '01.3.4+12']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                release_version(f'version: {version}', {})


if __name__ == '__main__':
    unittest.main()
