import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('catalog', ROOT/'scripts/build.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class CatalogTest(unittest.TestCase):
    def package(self, root, ident='example'):
        folder = root/ident; folder.mkdir()
        manifest = {'schema':1,'api':1,'id':ident,'version':'1.0.0',
                    'name':{'en':'Example','zh':'示例'},'description':{'en':'Test','zh':'测试'},
                    'runtime':'crossmux-lua54','entry':'main.lua','memory_bytes':65536,
                    'requires':['wifi'],'status':'ready','license':'MIT'}
        (folder/'manifest.json').write_text(json.dumps(manifest))
        (folder/'main.lua').write_text('return {on_start=function() app.row("Hello") end}')
        (folder/'LICENSE').write_text('MIT')
        return folder, manifest

    def test_reproducible_complete_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); folder, manifest = self.package(root)
            first = catalog.make_package(folder, manifest)
            self.assertEqual(first, catalog.make_package(folder, manifest))
            output = root/'site'; rows = catalog.build(root, output)
            artifact = output/rows[0]['artifact']
            self.assertEqual(hashlib.sha256(artifact.read_bytes()).hexdigest(), rows[0]['sha256'])
            self.assertEqual(artifact.stat().st_size, rows[0]['bytes'])
            with zipfile.ZipFile(artifact) as package:
                self.assertEqual(set(package.namelist()), {'manifest.json','main.lua','LICENSE'})
                self.assertEqual(json.loads(package.read('manifest.json'))['requires'], ['wifi'])

    def test_missing_unknown_and_duplicate_capabilities_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder, manifest = self.package(Path(temporary))
            for bad in (None, ['unknown'], ['wifi','wifi']):
                manifest['requires'] = bad
                with self.assertRaises(ValueError): catalog.validate(manifest, folder)

    def test_bytecode_oversize_and_escape_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder, manifest = self.package(Path(temporary))
            for bad in (b'\x1bLua', b'x'*32769, b'return {}\0'):
                (folder/'main.lua').write_bytes(bad)
                with self.assertRaises(ValueError): catalog.make_package(folder, manifest)
            (folder/'main.lua').write_text('return {}')
            manifest['assets'] = ['assets/../../outside']
            with self.assertRaises(ValueError): catalog.make_package(folder, manifest)

    def test_unported_sources_are_not_installable(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary); folder,manifest=self.package(root)
            manifest['status']='porting'
            (folder/'manifest.json').write_text(json.dumps(manifest))
            output=root/'site'; self.assertEqual(catalog.build(root,output),[])
            self.assertEqual(json.loads((output/'migration.json').read_text())[0]['status'],'porting')

    def test_pagination_uses_static_relative_pages(self):
        with tempfile.TemporaryDirectory() as temporary:
            root=Path(temporary)
            for i in range(17): self.package(root, f'app_{i}')
            output=root/'site'; catalog.build(root,output)
            first=json.loads((output/'index.json').read_text())
            second=json.loads((output/first['next']).read_text())
            self.assertEqual((len(first['packages']), len(second['packages'])), (16,1))
            self.assertEqual(second['next'],'')

    def test_api2_permissions_and_psram_budget(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder, manifest = self.package(Path(temporary))
            manifest.update(api=2, memory_bytes=131072, requires=['psram'], permissions=['sound'])
            catalog.validate(manifest, folder)
            manifest['requires'] = []
            with self.assertRaises(ValueError): catalog.validate(manifest, folder)
            manifest['requires'] = ['psram']
            for bad in (['unknown'], ['sound','sound'], 'sound'):
                manifest['permissions'] = bad
                with self.assertRaises(ValueError): catalog.validate(manifest, folder)

    def test_all_submitted_manifests(self):
        for path in (ROOT/'packages').glob('*/manifest.json'):
            manifest=catalog.validate(json.loads(path.read_text()),path.parent)
            if manifest['status']=='ready': catalog.make_package(path.parent,manifest)


if __name__ == '__main__': unittest.main()
