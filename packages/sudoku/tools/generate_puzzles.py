#!/usr/bin/env python3
"""Generate the original, reproducible seed bank offline; never solve on an ESP32.

Easy: naked singles suffice (43 clues). Medium: hidden singles are required
(35 clues). Hard: neither naked nor hidden singles suffice (29 clues). This
is a reproducible grading rule, not a claim of a universal Sudoku rating.
Every seed is independently checked for exactly one solution. Digit/row/column
symmetries used by main.lua preserve both uniqueness and these solver grades.
"""
import random
from pathlib import Path

UNITS = ([list(range(r * 9, r * 9 + 9)) for r in range(9)] +
         [[r * 9 + c for r in range(9)] for c in range(9)] +
         [[(br + r) * 9 + bc + c for r in range(3) for c in range(3)]
          for br in (0, 3, 6) for bc in (0, 3, 6)])
PEERS = [set().union(*(set(u) for u in UNITS if i in u)) - {i} for i in range(81)]
DIGITS = set(range(1, 10))


def candidates(board, i):
    return DIGITS - {board[j] for j in PEERS[i]}


def solutions(board, limit=2):
    choices = [(candidates(board, i), i) for i, v in enumerate(board) if not v]
    if not choices:
        return 1 if all(set(board[i] for i in unit) == DIGITS for unit in UNITS) else 0
    options, index = min(choices, key=lambda item: len(item[0]))
    total = 0
    for value in sorted(options):
        board[index] = value
        total += solutions(board, limit - total)
        board[index] = 0
        if total >= limit:
            break
    return total


def singles(board, hidden=False):
    board = board[:]
    while True:
        options = {i: candidates(board, i) for i, v in enumerate(board) if not v}
        if not options:
            return True
        move = next(((i, next(iter(values))) for i, values in options.items() if len(values) == 1), None)
        if move is None and hidden:
            for unit in UNITS:
                for digit in range(1, 10):
                    positions = [i for i in unit if i in options and digit in options[i]]
                    if len(positions) == 1:
                        move = positions[0], digit
                        break
                if move:
                    break
        if move is None:
            return False
        board[move[0]] = move[1]


def grade(board):
    return 1 if singles(board) else 2 if singles(board, True) else 3


def generate():
    rng = random.Random(20261023)
    found = {1: [], 2: [], 3: []}
    attempts = 0
    while min(map(len, found.values())) < 3:
        attempts += 1
        digits = list(range(1, 10)); rng.shuffle(digits)
        bands, stacks = [0, 1, 2], [0, 1, 2]
        rng.shuffle(bands); rng.shuffle(stacks)
        rows, cols = [], []
        for band in bands:
            parts = [0, 1, 2]; rng.shuffle(parts)
            rows.extend(band * 3 + part for part in parts)
        for stack in stacks:
            parts = [0, 1, 2]; rng.shuffle(parts)
            cols.extend(stack * 3 + part for part in parts)
        solution = [digits[(r * 3 + r // 3 + c) % 9] for r in rows for c in cols]
        puzzle = solution[:]
        order = list(range(81)); rng.shuffle(order)
        clues = 81
        for i in order:
            old = puzzle[i]; puzzle[i] = 0
            if solutions(puzzle[:]) != 1:
                puzzle[i] = old
                continue
            clues -= 1
            tier = {43: 1, 35: 2, 29: 3}.get(clues)
            if tier and len(found[tier]) < 3 and grade(puzzle) == tier:
                found[tier].append((''.join(map(str, puzzle)), ''.join(map(str, solution))))
        if attempts > 20000:
            raise RuntimeError('seed search exhausted')
    return found, attempts


if __name__ == '__main__':
    bank, attempts = generate()
    destination = Path(__file__).resolve().parents[1] / 'assets/puzzles.txt'
    destination.write_text(''.join(puzzle + solution + '\n' for tier in (1, 2, 3) for puzzle, solution in bank[tier]))
    print(f'{destination}: 9 unique puzzles, {attempts} attempts')
