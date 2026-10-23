"""Verify the shipped Sudoku bank independently of the on-device transforms."""
import importlib.util
import unittest
from pathlib import Path

PACKAGE = Path(__file__).resolve().parents[1] / 'packages/sudoku'
spec = importlib.util.spec_from_file_location('sudoku_seed_generator', PACKAGE / 'tools/generate_puzzles.py')
seeds = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seeds)


class SudokuBankTest(unittest.TestCase):
    def test_unique_solutions_and_declared_grade(self):
        data = (PACKAGE / 'assets/puzzles.txt').read_bytes()
        self.assertEqual(len(data), 9 * 163)
        self.assertEqual(len(set(data.splitlines())), 9)
        for row, record in enumerate(data.decode('ascii').splitlines()):
            with self.subTest(record=row):
                puzzle, solution = [int(v) for v in record[:81]], [int(v) for v in record[81:]]
                tier = row // 3 + 1
                self.assertEqual(sum(v != 0 for v in puzzle), (43, 35, 29)[tier - 1])
                self.assertEqual(seeds.solutions(puzzle[:]), 1)
                self.assertEqual(seeds.solutions(solution[:]), 1)
                self.assertEqual(seeds.grade(puzzle), tier)
                self.assertTrue(all(p == 0 or p == s for p, s in zip(puzzle, solution)))

    def test_symmetries_preserve_solution_and_grade(self):
        # Reverse bands/stacks and transpose, as the downloaded game can do.
        mapping = [8, 7, 6, 2, 1, 0, 5, 4, 3]
        for row, record in enumerate((PACKAGE / 'assets/puzzles.txt').read_text().splitlines()):
            puzzle = [int(v) for v in record[:81]]
            transformed = [10 - puzzle[mapping[c] * 9 + mapping[r]] if puzzle[mapping[c] * 9 + mapping[r]] else 0
                           for r in range(9) for c in range(9)]
            self.assertEqual(seeds.solutions(transformed[:]), 1)
            self.assertEqual(seeds.grade(transformed), row // 3 + 1)


if __name__ == '__main__':
    unittest.main()
