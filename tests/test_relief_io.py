"""Generated snapshots survive transient file-watcher locks without truncation."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from relief_core import write_bytes

class ReliefIOTests(unittest.TestCase):
    def temporary(self):
        folder=ROOT/'.godot-local-profile';folder.mkdir(exist_ok=True)
        return tempfile.TemporaryDirectory(dir=folder)

    def test_unchanged_snapshot_is_not_rewritten(self):
        with self.temporary() as directory:
            path=Path(directory)/'sample.bin'
            write_bytes(path,b'unchanged\x00snapshot')
            timestamp=path.stat().st_mtime_ns
            with patch.object(Path,'replace',side_effect=AssertionError('Unchanged snapshot must remain untouched')):
                write_bytes(path,b'unchanged\x00snapshot')
            self.assertEqual(timestamp,path.stat().st_mtime_ns)
            self.assertFalse(path.with_name(path.name+'.writing').exists())

    def test_transient_lock_preserves_valid_previous_snapshot(self):
        with self.temporary() as directory:
            path=Path(directory)/'sample.bin';path.write_bytes(b'previous-valid-data')
            original=Path.replace;calls=[]
            def replace(p,target):
                calls.append(p)
                if len(calls)<3:
                    self.assertEqual(path.read_bytes(),b'previous-valid-data')
                    raise OSError(22,'Simulated temporary watcher lock')
                return original(p,target)
            with patch.object(Path,'replace',replace),patch('relief_core.time.sleep'):
                write_bytes(path,b'complete-new-data')
            self.assertEqual(path.read_bytes(),b'complete-new-data')
            self.assertEqual(len(calls),3)
            self.assertFalse(path.with_name(path.name+'.writing').exists())

if __name__=='__main__':unittest.main()
