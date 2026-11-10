"""Release regression checks; use only temporary Git repositories and a fake gh."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='macpad-release-test-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.origin = self.base / 'origin.git'
        self.repo = self.base / 'checkout'
        self.run_cmd(['git', 'init', '--bare', str(self.origin)], self.base)
        self.run_cmd(['git', 'clone', str(self.origin), str(self.repo)], self.base)
        self.git('checkout', '-b', 'main')
        self.git('config', 'user.email', 'release-test@example.invalid')
        self.git('config', 'user.name', 'Release test')
        self.git('commit', '--allow-empty', '-m', 'First build')
        self.sha = self.git('rev-parse', 'HEAD').strip()
        self.git('push', 'origin', 'main')
        self.git('commit', '--allow-empty', '-m', 'Newer build')
        self.next_sha = self.git('rev-parse', 'HEAD').strip()
        self.git('push', 'origin', 'HEAD:refs/heads/future')
        self.git('checkout', '--detach', self.sha)
        (self.repo / 'Tools').mkdir()
        for name in ['release-guard.sh', 'publish-release.sh']:
            shutil.copy2(ROOT / 'Tools' / name, self.repo / 'Tools' / name)
        (self.repo / 'dist').mkdir()
        self.artifact = 'MacPad-0.1.2-' + self.sha[:7]
        self.payload = b'the checked current build\x00\xff'
        (self.repo / 'dist' / (self.artifact + '.dmg')).write_bytes(self.payload)
        self.log = self.base / 'calls.jsonl'
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        mock = self.bin / 'gh'
        mock.write_text('#!' + sys.executable + '\n' + r'''
import hashlib,json,os,pathlib,subprocess,sys
a=sys.argv[1:]
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps(a)+'\n')
mode=os.environ.get('MOCK_MODE','')
if a[:2]==['release','list']:sys.exit(0)
if a[:2]==['release','create']:
 if mode=='upload_failure':sys.exit(7)
 if mode=='superseded_during_upload':
  subprocess.run(['git','--git-dir',os.environ['MOCK_ORIGIN'],'update-ref','refs/heads/main',os.environ['MOCK_NEXT_SHA']],check=True)
 if mode=='remote_failure_after_upload':
  subprocess.run(['git','remote','set-url','origin','/nonexistent/macpad-test-origin'],check=True)
 sys.exit(0)
if a[:2]==['release','view']:
 print('123');sys.exit(0)
if a[0]=='api' and a[1].endswith('/latest'):
 print('v0.1.2');sys.exit(0)
if a[0]=='api':
 assets=[]
 for p in sorted(pathlib.Path('dist').iterdir()):
  if mode=='missing_alias' and p.name=='MacPad.dmg':continue
  data=p.read_bytes();digest='sha256:'+hashlib.sha256(data).hexdigest()
  if mode=='bad_digest' and p.name=='MacPad.dmg':digest='sha256:'+'0'*64
  assets.append({'name':p.name,'state':'uploaded','size':len(data),'digest':digest})
 print(json.dumps({'tag_name':'v0.1.2','draft':True,'assets':assets}));sys.exit(0)
if a[:2]==['release','edit']:sys.exit(0)
raise SystemExit('unexpected gh invocation: '+repr(a))
''')
        mock.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        GITHUB_SHA=self.sha, GITHUB_REPOSITORY='example/macpad',
                        DEFAULT_BRANCH='main', VERSION='0.1.2', ARTIFACT_NAME=self.artifact,
                        MOCK_LOG=str(self.log), MOCK_ORIGIN=str(self.origin), MOCK_NEXT_SHA=self.next_sha)

    def run_cmd(self, args, cwd):
        return subprocess.run(args, cwd=cwd, text=True, capture_output=True, check=True).stdout

    def git(self, *args):
        return self.run_cmd(['git', *args], self.repo)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def publish(self, mode=''):
        return subprocess.run(['bash', 'Tools/publish-release.sh'], cwd=self.repo,
                              env=dict(self.env, MOCK_MODE=mode), text=True, capture_output=True)

    def assert_not_promoted(self, result, *, skipped=False):
        self.assertEqual(result.returncode == 0, skipped, result.stdout + result.stderr)
        self.assertFalse(any(c[:2] == ['release', 'edit'] for c in self.calls()))

    def test_current_build_promotes_verified_assets(self):
        result = self.publish()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((self.repo / 'dist/MacPad.dmg').read_bytes(), self.payload)
        expected = hashlib.sha256(self.payload).hexdigest() + '  MacPad.dmg\n'
        self.assertEqual((self.repo / 'dist/MacPad.dmg.sha256').read_text(), expected)
        calls = self.calls()
        create = next(i for i, c in enumerate(calls) if c[:2] == ['release', 'create'])
        verify = next(i for i, c in enumerate(calls) if c[0] == 'api')
        promote = next(i for i, c in enumerate(calls) if c[:2] == ['release', 'edit'])
        self.assertLess(create, verify)
        self.assertLess(verify, promote)
        self.assertIn('--draft', calls[create])
        self.assertIn('--latest', calls[promote])
        self.assertIn('--draft=false', calls[promote])
        self.assertTrue(calls[-1][1].endswith('/latest'))

    def test_obsolete_commit_is_skipped_before_upload(self):
        self.run_cmd(['git', '--git-dir', str(self.origin), 'update-ref', 'refs/heads/main', self.next_sha], self.base)
        self.assert_not_promoted(self.publish(), skipped=True)
        self.assertEqual(self.calls(), [])

    def test_remote_failure_is_closed(self):
        self.git('remote', 'set-url', 'origin', '/nonexistent/macpad-test-origin')
        self.assert_not_promoted(self.publish())
        self.assertEqual(self.calls(), [])

    def test_new_head_during_upload_leaves_draft(self):
        self.assert_not_promoted(self.publish('superseded_during_upload'), skipped=True)

    def test_remote_failure_after_upload_leaves_draft(self):
        self.assert_not_promoted(self.publish('remote_failure_after_upload'))

    def test_failed_upload_is_not_published(self):
        self.assert_not_promoted(self.publish('upload_failure'))

    def test_missing_stable_asset_is_not_published(self):
        self.assert_not_promoted(self.publish('missing_alias'))

    def test_bad_uploaded_digest_is_not_published(self):
        self.assert_not_promoted(self.publish('bad_digest'))

    def test_retained_old_artifact_is_rejected(self):
        (self.repo / 'dist/MacPad-0.1.1-old.dmg').write_bytes(b'old build')
        self.assert_not_promoted(self.publish())
        self.assertEqual(self.calls(), [])

    def test_artifact_version_must_match_plan(self):
        self.env['ARTIFACT_NAME'] = self.artifact.replace('0.1.2', '0.1.1')
        self.assert_not_promoted(self.publish())
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
