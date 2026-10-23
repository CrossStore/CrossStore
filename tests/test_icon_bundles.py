import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('icon_catalog', ROOT / 'scripts/build.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class IconBundleTest(unittest.TestCase):
    def package(self, root):
        folder = root / 'example'
        (folder / 'assets').mkdir(parents=True)
        manifest = {'schema': 1, 'api': 2, 'id': 'example', 'version': '1.0.0',
                    'name': {'en': 'Example', 'zh': '示例'}, 'description': {'en': 'Test', 'zh': '测试'},
                    'runtime': 'crossmux-lua54', 'entry': 'main.lua', 'memory_bytes': 65536,
                    'requires': [], 'permissions': [], 'status': 'ready', 'license': 'MIT', 'assets': []}
        for i, (levels, size, length) in enumerate(catalog.ICON_VARIANTS):
            asset = f'assets/icon-g{levels}-{size}.bin'
            manifest['assets'].append(asset)
            (folder / asset).write_bytes(bytes([i]) * length)
        (folder / 'main.lua').write_text('return {}')
        (folder / 'LICENSE').write_text('MIT')
        (folder / 'manifest.json').write_text(json.dumps(manifest))
        return folder, manifest

    def test_fixed_offsets_and_content_address(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder, manifest = self.package(root)
            expected = b'CSI1\0\0\0\0' + b''.join(bytes([i]) * size for i, (_, _, size) in enumerate(catalog.ICON_VARIANTS))
            first = catalog.make_icon_bundle(folder, manifest)
            self.assertEqual(first, expected)
            self.assertEqual(len(first), 7048)
            self.assertEqual(first, catalog.make_icon_bundle(folder, manifest))
            rows = catalog.build(root, root / 'dist')
            icon = rows[0]['icon']
            self.assertEqual(icon['bytes'], 7048)
            self.assertEqual(icon['sha256'], hashlib.sha256(first).hexdigest())
            self.assertEqual((root / 'dist' / icon['artifact']).read_bytes(), first)

    def test_legacy_partial_set_omits_preview(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            folder, manifest = self.package(root)
            manifest['assets'].pop()
            self.assertIsNone(catalog.make_icon_bundle(folder, manifest))
            manifest['assets'] = []
            self.assertIsNone(catalog.make_icon_bundle(folder, manifest))

    def test_malformed_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder, manifest = self.package(Path(temporary))
            asset = folder / manifest['assets'][0]
            asset.write_bytes(b'bad')
            with self.assertRaises(ValueError):
                catalog.make_icon_bundle(folder, manifest)
            asset.unlink()
            asset.symlink_to(folder / manifest['assets'][1])
            with self.assertRaises(ValueError):
                catalog.make_icon_bundle(folder, manifest)

    def test_real_catalog_fits_budget_and_matches_package_icons(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            rows = catalog.build(ROOT / 'packages', output)
            for page in [output / 'index.json', *output.glob('page-*.json')]:
                self.assertLessEqual(page.stat().st_size, 24576)
            for row in rows:
                self.assertIn('icon', row, row['id'])
                bundle = (output / row['icon']['artifact']).read_bytes()
                offset = 8
                for levels, size, length in catalog.ICON_VARIANTS:
                    asset = ROOT / 'packages' / row['id'] / f'assets/icon-g{levels}-{size}.bin'
                    self.assertEqual(bundle[offset:offset + length], asset.read_bytes())
                    offset += length


if __name__ == '__main__':
    unittest.main()
