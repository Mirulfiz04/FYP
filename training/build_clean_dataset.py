"""
build_clean_dataset.py  —  Make a leak-free copy of fer2013/ in fer2013_clean/.

Why: fer2013/ merges several downloads of FER2013 (Training_N / PublicTest_N /
PrivateTest_N, N.jpg, imN.png, ...), so the same face appears many times —
including in BOTH train and test. Testing on faces the model trained on makes
the accuracy look better than it really is.

What it does (the original fer2013/ is never modified):
  * compares every image with every other one (16x16 grey pixel correlation),
    so exact, re-saved (jpg/png) and resized copies of a face are grouped,
  * keeps ONE copy per face,
  * a face that appears in test is kept ONLY in test (all train copies dropped),
  * drops faces whose copies carry different emotion labels, and blank images,
  * skips myface_* files — run  add_my_face.py --reset  afterwards.

Usage (from training/):
    python build_clean_dataset.py                  # fer2013 -> fer2013_clean
    python build_clean_dataset.py --src X --dst Y
"""

import argparse
import os
import shutil
import sys
from collections import Counter

import numpy as np
from PIL import Image

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.normpath(os.path.join(HERE, "..", "fer2013"))
DEFAULT_DST = os.path.normpath(os.path.join(HERE, "..", "fer2013_clean"))
SIZE = 16
# Pixel correlation thresholds, checked by eye on this dataset: pairs >= 0.927
# were the same photo, pairs at 0.904 / 0.914 were different people.
CROSS = 0.90   # train image this close to a test face is dropped (leak guard; erring low only costs train images)
EXACT = 0.97   # re-saved / resized copy of the same photo (same-split dedupe, label conflicts)
BLANK_STD = 2.0   # pixel std below this = blank / solid image, not a face


def load_vec(path):
    img = Image.open(path).convert("L").resize((SIZE, SIZE), Image.BILINEAR)
    return np.asarray(img, np.float32).ravel()


def normalise(X):
    """Mean-centre + L2-normalise rows, so X @ X.T is the pixel correlation."""
    X = X - X.mean(1, keepdims=True)
    return X / np.maximum(np.linalg.norm(X, axis=1, keepdims=True), 1e-6)


def plan(X, splits, labels, chunk=500):
    """Walk the rows in order (put test rows first so test copies win). Each row
    still kept drops every LATER row that matches it: corr >= CROSS when one is
    train and the other test, >= EXACT within the same split. A kept row whose
    exact copies carry another label is dropped too (ambiguous label).
    Only direct matches count: chaining A~B~C merged thousands of faces.
    Returns (keep mask, number of label conflicts)."""
    n = len(X)
    splits, labels = np.asarray(splits), np.asarray(labels)
    removed, conflicts = np.zeros(n, bool), 0
    for c in range(0, n, chunk):
        S = X[c:c + chunk] @ X[c:].T          # rows c.. vs rows c.. (upper triangle used)
        for a in range(len(S)):
            i = c + a
            if removed[i]:
                continue
            k = np.nonzero(S[a, a + 1:] >= CROSS)[0]
            js, sims = i + 1 + k, S[a, a + 1 + k]
            need = np.where(splits[js] != splits[i], CROSS, EXACT)
            hit = (sims >= need) & ~removed[js]
            js, sims = js[hit], sims[hit]
            removed[js] = True
            if np.any((labels[js] != labels[i]) & (sims >= EXACT)):
                removed[i] = True
                conflicts += 1
    return ~removed, conflicts


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEFAULT_SRC)
    ap.add_argument("--dst", default=DEFAULT_DST)
    args = ap.parse_args()
    if os.path.exists(args.dst):
        raise SystemExit(f"[ERROR] {args.dst} already exists - delete it first to rebuild.")

    records, vecs, unreadable = [], [], 0
    for split in ("test", "train"):   # test first: plan() keeps the earliest copy
        for emo in sorted(os.listdir(os.path.join(args.src, split))):
            d = os.path.join(args.src, split, emo)
            for f in os.listdir(d):
                if f.startswith("myface_"):
                    continue
                p = os.path.join(d, f)
                try:
                    vecs.append(load_vec(p))
                    records.append((split, emo, p))
                except Exception:
                    unreadable += 1
            print(f"[load] {split}/{emo}", flush=True)

    X = np.stack(vecs)
    blank = X.std(1) < BLANK_STD
    faces = [r for r, b in zip(records, blank) if not b]
    print(f"[match] comparing {len(faces)} images (this takes a minute)...", flush=True)
    mask, conflicts = plan(normalise(X[~blank]), [r[0] for r in faces], [r[1] for r in faces])
    keep = [r for r, k in zip(faces, mask) if k]

    for split, emo, p in keep:
        out = os.path.join(args.dst, split, emo)
        os.makedirs(out, exist_ok=True)
        shutil.copy2(p, out)

    before = Counter((s, e) for s, e, _ in records)
    after = Counter((s, e) for s, e, _ in keep)
    print(f"\n{'':10s}{'train before':>14s}{'after':>8s}{'test before':>14s}{'after':>8s}")
    for emo in sorted({e for _, e in before}):
        print(f"{emo:10s}{before['train', emo]:14d}{after['train', emo]:8d}"
              f"{before['test', emo]:14d}{after['test', emo]:8d}")
    print(f"\n[done] {len(records)} images -> {len(keep)} unique faces in {args.dst}")
    print(f"       dropped {int(blank.sum())} blank images, {conflicts} faces with "
          f"conflicting labels, {unreadable} unreadable files")
    print("       Next:  python add_my_face.py --reset   then   python train_meds.py")


if __name__ == "__main__":
    main()
