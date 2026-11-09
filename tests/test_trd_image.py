import sys
import unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from trd_image import IMAGE_SIZE, LOAD_ADDRESS, basic_loader, build_trd, verify_trd

class TrdTests(unittest.TestCase):
    def test_basic_loader(self):
        data, n = basic_loader()
        self.assertEqual(data[n:], b"\x80\xaa\x0a\x00")
        self.assertIn(b"P127BOOT", data)
        self.assertIn(b"24576", data)
    def test_image_and_directory(self):
        code = b"\xc3\x09\x60" + bytes(range(64))
        image = build_trd(code)
        self.assertEqual(len(image), IMAGE_SIZE)
        self.assertEqual(image[:9], b"BOOT    B")
        self.assertEqual(image[16:25], b"P127BOOTC")
        self.assertEqual(int.from_bytes(image[25:27], "little"), LOAD_ADDRESS)
        self.assertEqual(int.from_bytes(image[27:29], "little"), len(code))
        verify_trd(image, code)
    def test_reject_empty_and_oversized_code(self):
        with self.assertRaises(ValueError):
            build_trd(b"")
        with self.assertRaises(ValueError):
            build_trd(b"x" * 65536)

if __name__ == "__main__":
    unittest.main()
