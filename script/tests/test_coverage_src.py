import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "coverage-src.py"
spec = importlib.util.spec_from_file_location("coverage_src", SCRIPT)
coverage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(coverage)


def record(path, found=10, hit=5):
    return f"SF:{path}\nLF:{found}\nLH:{hit}\nBRF:0\nBRH:0\nFNF:1\nFNH:1\nend_of_record\n"


class SourceCoverageTest(unittest.TestCase):
    def test_only_repository_src_is_included(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report = "".join(record(path) for path in [
                "src/A.sol", str(root / "src/libraries/B.sol"), "test/A.t.sol",
                "script/Deploy.s.sol", "dependencies/vendor/src/C.sol", "../src/Outside.sol",
            ])
            records = coverage.source_records(report, root)
            self.assertEqual([name for name, _, _ in records], ["src/A.sol", "src/libraries/B.sol"])

    def test_totals_are_weighted_and_output_contains_only_src(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "raw.lcov"
            output = Path(directory) / "src.lcov"
            source.write_text(record("src/A.sol", 100, 50) + record("src/B.sol", 1, 1)
                              + record("script/Deploy.s.sol", 1000, 0))
            result = subprocess.run(["python3", str(SCRIPT), str(source), "--output", str(output)],
                                    check=True, text=True, capture_output=True)
            self.assertIn("50.50% (51/101)", result.stdout)
            self.assertNotIn("script/", output.read_text())
            self.assertEqual(output.read_text().count("end_of_record"), 2)

    def test_empty_and_duplicate_reports_are_rejected(self):
        for report in [record("test/A.t.sol"), record("src/A.sol") * 2]:
            with self.assertRaises(ValueError):
                coverage.source_records(report)

    def test_invalid_counters_are_rejected(self):
        with self.assertRaises(ValueError):
            coverage.source_records(record("src/A.sol", 1, 2))


if __name__ == "__main__":
    unittest.main()
