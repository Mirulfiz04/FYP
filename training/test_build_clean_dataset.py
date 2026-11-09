"""Self-check for the dedupe rules.  Run:  python test_build_clean_dataset.py"""
import numpy as np

from build_clean_dataset import CROSS, EXACT, normalise, plan

rng = np.random.default_rng(0)
face, other, amb = rng.normal(0, 1, (3, 256))
noisy = lambda v, s: v + rng.normal(0, s, 256)

rows = [  # (split, label, vector) - test rows first, as main() orders them
    ("test", "happy", face),
    ("test", "happy", noisy(face, 0.05)),      # re-saved copy inside test -> dropped
    ("test", "angry", amb),
    ("train", "happy", noisy(face, 0.40)),     # similar to a test face -> dropped (leak guard)
    ("train", "sad", other),
    ("train", "sad", noisy(other, 0.40)),      # similar but not a copy, same split -> kept
    ("train", "fear", noisy(amb, 0.05)),       # copy of a test face with another label
]
X = normalise(np.stack([v for _, _, v in rows]).astype(np.float32))
assert CROSS <= X[0] @ X[3] < EXACT and CROSS <= X[4] @ X[5] < EXACT  # test data is what it claims

keep, conflicts = plan(X, [s for s, _, _ in rows], [l for _, l, _ in rows])
assert keep.tolist() == [True, False, False, False, True, True, False], keep
assert conflicts == 1   # the ambiguous angry/fear face is dropped from test AND train
print("ok")
