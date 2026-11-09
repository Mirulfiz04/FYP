"""
add_my_face.py  —  Add your own selfies to the FER2013 dataset.

What it does
------------
For every image in  training/my_face/<emotion>/  it:
  1. detects the largest face (OpenCV Haar cascade, offline, no downloads),
  2. crops it square with a margin (like your app's face crop),
  3. resizes to 224x224 (the model input size),
  4. splits the SELFIES ~85% train / 15% test by burst order (the last frames
     of each burst are held out, with a small gap), so no photo or near-identical
     neighbouring frame ends up on both sides; byte-identical duplicates are skipped,
  5. makes a few lightly-augmented copies of TRAIN selfies only (test keeps the
     real, un-augmented photos) and writes them into
        fer2013/train/<emotion>/  and  fer2013/test/<emotion>/
     with a  myface_  prefix so you can find/remove them any time.

Folder layout you prepare first (create the ones you want to use):
    training/my_face/happy/      <- drop your happy selfies here
    training/my_face/neutral/
    training/my_face/sad/
    training/my_face/surprise/
    training/my_face/angry/
    training/my_face/fear/
    training/my_face/disgust/

Usage (from the training/ folder, in your Python 3.11 venv):
    python add_my_face.py                 # add faces
    python add_my_face.py --copies 8      # more augmented copies per selfie
    python add_my_face.py --reset         # remove previously added myface_* first
    python add_my_face.py --detector mediapipe   # force MediaPipe crop + eye-align
    python add_my_face.py --detector center       # skip detection, center crop
"""

import argparse
import glob
import hashlib
import os
import random
import re
import sys
import uuid

import cv2
import numpy as np

# Windows consoles default to cp1252 and crash on non-ASCII prints. Force UTF-8.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

EMOTIONS = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]
IMG = 224
MARGIN = 1.4          # padding around the detected face box
VALID_EXT = (".jpg", ".jpeg", ".png", ".bmp", ".webp")

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_SRC = os.path.join(HERE, "my_face")
DEFAULT_DATA = os.path.normpath(os.path.join(HERE, "..", "fer2013_clean"))  # build_clean_dataset.py

def _load_cascade():
    """Find a frontal-face Haar cascade. OpenCV 5 ships an EMPTY data/ folder,
    so we try several locations and return None if none work (caller then falls
    back to a center crop, which is fine for already-centered burst selfies)."""
    name = "haarcascade_frontalface_default.xml"
    candidates = []
    try:
        candidates.append(os.path.join(cv2.data.haarcascades, name))
    except Exception:
        pass
    candidates.append(os.path.join(os.path.dirname(cv2.__file__), "data", name))
    candidates.append(os.path.join(HERE, name))  # a copy you drop next to this script
    for p in candidates:
        if os.path.isfile(p):
            c = cv2.CascadeClassifier(p)
            if not c.empty():
                return c
    return None


_cascade = _load_cascade()


def _load_mediapipe():
    """MediaPipe face detector (best quality, gives eye keypoints for alignment).
    Returns None if mediapipe isn't installed / can't init (e.g. on Python 3.14)."""
    try:
        import mediapipe as mp
        return mp.solutions.face_detection.FaceDetection(
            model_selection=1, min_detection_confidence=0.5)
    except Exception as e:
        print(f"[info] MediaPipe not available ({type(e).__name__}); "
              "will use Haar/center instead.")
        return None


_mp_fd = _load_mediapipe()
if _mp_fd is not None:
    print("[info] Using MediaPipe face detection + eye-alignment.")
elif _cascade is None:
    print(f"[info] No MediaPipe and OpenCV {cv2.__version__} ships no Haar cascade "
          "- using center-crop.\n       Your burst selfies are already centered, so "
          "this works fine.")


def _crop_square(img, cx, cy, side):
    h, w = img.shape[:2]
    x0 = int(max(0, cx - side / 2)); y0 = int(max(0, cy - side / 2))
    x1 = int(min(w, cx + side / 2)); y1 = int(min(h, cy + side / 2))
    crop = img[y0:y1, x0:x1]
    return crop if crop.size else None


def _mediapipe_crop(img):
    """Detect the largest face, level the eyes (rotate), and return a padded
    square crop. None if no face found."""
    if _mp_fd is None:
        return None
    h, w = img.shape[:2]
    res = _mp_fd.process(cv2.cvtColor(img, cv2.COLOR_BGR2RGB))
    if not res.detections:
        return None
    det = max(res.detections,
              key=lambda d: d.location_data.relative_bounding_box.width *
                            d.location_data.relative_bounding_box.height)
    kp = det.location_data.relative_keypoints          # 0=right eye, 1=left eye
    rex, rey = kp[0].x * w, kp[0].y * h
    lex, ley = kp[1].x * w, kp[1].y * h
    angle = np.degrees(np.arctan2(ley - rey, lex - rex))
    cx, cy = (rex + lex) / 2.0, (rey + ley) / 2.0
    M = cv2.getRotationMatrix2D((cx, cy), angle, 1.0)  # rotate so eyes are level
    rot = cv2.warpAffine(img, M, (w, h), flags=cv2.INTER_LINEAR,
                         borderMode=cv2.BORDER_REFLECT)
    bb = det.location_data.relative_bounding_box
    fcx = (bb.xmin + bb.width / 2) * w
    fcy = (bb.ymin + bb.height / 2) * h
    side = max(bb.width * w, bb.height * h) * MARGIN
    return _crop_square(rot, fcx, fcy, side)


def _haar_crop(img):
    if _cascade is None:
        return None
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    faces = _cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=5,
                                      minSize=(60, 60))
    if len(faces) == 0:
        return None
    x, y, fw, fh = max(faces, key=lambda b: b[2] * b[3])
    side = max(fw, fh) * MARGIN
    return _crop_square(img, x + fw / 2, y + fh / 2, side)


def largest_face_crop(img, detector="auto"):
    """Return a square face crop (BGR). detector: auto|mediapipe|haar|center.
    'auto' tries MediaPipe, then Haar, then a center-square crop."""
    if detector in ("auto", "mediapipe"):
        crop = _mediapipe_crop(img)
        if crop is not None:
            return crop
    if detector in ("auto", "haar"):
        crop = _haar_crop(img)
        if crop is not None:
            return crop
    # fallback: center square
    h, w = img.shape[:2]
    side = min(h, w)
    x0 = (w - side) // 2; y0 = (h - side) // 2
    return img[y0:y0 + side, x0:x0 + side]


def augment(face):
    """One random light augmentation (flip / rotate / brightness / zoom)."""
    out = face.copy()
    if random.random() < 0.5:
        out = cv2.flip(out, 1)
    # rotation
    ang = random.uniform(-12, 12)
    h, w = out.shape[:2]
    M = cv2.getRotationMatrix2D((w / 2, h / 2), ang, 1.0)
    out = cv2.warpAffine(out, M, (w, h), borderMode=cv2.BORDER_REFLECT)
    # brightness / contrast
    alpha = random.uniform(0.85, 1.15)   # contrast
    beta = random.uniform(-18, 18)       # brightness
    out = cv2.convertScaleAbs(out, alpha=alpha, beta=beta)
    # small zoom (crop + resize back)
    if random.random() < 0.6:
        z = random.uniform(0.0, 0.12)
        dx, dy = int(w * z / 2), int(h * z / 2)
        out = out[dy:h - dy, dx:w - dx]
    return out


GAP = 3  # burst frames dropped between train and test: neighbours are near-twins


def burst_key(path):
    """Capture order: happy_0001.jpg .. happy_0167.jpg, then a second burst that
    the browser saved as happy_0001 (1).jpg .. happy_0044 (1).jpg."""
    name = os.path.basename(path)
    m = re.search(r"_(\d+)(?: \((\d+)\))?\.\w+$", name)
    return (int(m.group(2) or 0), int(m.group(1)), name) if m else (0, 0, name)


def unique_files(files):
    """Drop byte-identical copies (e.g. the same burst downloaded twice)."""
    seen, out = set(), []
    for f in files:
        with open(f, "rb") as fh:
            h = hashlib.md5(fh.read()).hexdigest()
        if h not in seen:
            seen.add(h)
            out.append(f)
    return out


def split_burst(files, test_frac, gap=GAP):
    """Hold out the LAST test_frac of the burst (in capture order) as test.
    A random split would put near-identical consecutive frames on both sides
    and inflate the test score."""
    files = sorted(files, key=burst_key)
    n_test = round(len(files) * test_frac)
    cut = len(files) - n_test
    return files[:max(0, cut - gap)], files[cut:]


def remove_existing(data_dir):
    n = 0
    for split in ("train", "test"):
        for emo in EMOTIONS:
            for p in glob.glob(os.path.join(data_dir, split, emo, "myface_*")):
                os.remove(p); n += 1
    print(f"[clean] Removed {n} previously added myface_* files.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=DEFAULT_SRC, help="folder with my_face/<emotion>/")
    ap.add_argument("--data", default=DEFAULT_DATA, help="fer2013 root (train/ + test/)")
    ap.add_argument("--copies", type=int, default=5,
                    help="augmented copies saved per selfie (extra to the original)")
    ap.add_argument("--test-frac", type=float, default=0.15)
    ap.add_argument("--detector", default="auto",
                    choices=["auto", "mediapipe", "haar", "center"],
                    help="face crop method (auto = mediapipe -> haar -> center)")
    ap.add_argument("--no-detect", action="store_true",
                    help="alias for --detector center")
    ap.add_argument("--reset", action="store_true",
                    help="delete previously added myface_* files first")
    args = ap.parse_args()
    detector = "center" if args.no_detect else args.detector

    if not os.path.isdir(args.data):
        raise SystemExit(f"[ERROR] dataset not found: {args.data}\n"
                         "        Run  python build_clean_dataset.py  first.")
    if args.reset:
        remove_existing(args.data)

    random.seed(42)
    grand_train = grand_test = 0

    for emo in EMOTIONS:
        src_dir = os.path.join(args.src, emo)
        if not os.path.isdir(src_dir):
            continue
        all_files = [f for f in glob.glob(os.path.join(src_dir, "*"))
                     if f.lower().endswith(VALID_EXT)]
        files = unique_files(sorted(all_files, key=burst_key))  # keep originals, not "(1)" copies
        if not files:
            continue
        if len(files) < len(all_files):
            print(f"   [i] {emo}: skipped {len(all_files) - len(files)} duplicate files")

        os.makedirs(os.path.join(args.data, "train", emo), exist_ok=True)
        os.makedirs(os.path.join(args.data, "test", emo), exist_ok=True)

        train_files, test_files = split_burst(files, args.test_frac)
        made = {"train": 0, "test": 0}
        for split, group in (("train", train_files), ("test", test_files)):
            for f in group:
                img = cv2.imread(f)
                if img is None:
                    print(f"   [!] could not read {f}"); continue
                face = largest_face_crop(img, detector=detector)
                variants = [cv2.resize(face, (IMG, IMG))]
                if split == "train":  # test keeps only the real photos
                    for _ in range(args.copies):
                        variants.append(cv2.resize(augment(face), (IMG, IMG)))

                for v in variants:
                    name = f"myface_{emo}_{uuid.uuid4().hex[:12]}.jpg"
                    cv2.imwrite(os.path.join(args.data, split, emo, name), v,
                                [cv2.IMWRITE_JPEG_QUALITY, 92])
                made[split] += len(variants)

        grand_train += made["train"]
        grand_test += made["test"]
        print(f"[ok] {emo:9s}: {len(train_files):4d} train / {len(test_files):3d} test "
              f"selfies -> +{made['train']} train / +{made['test']} test images")

    if grand_train + grand_test == 0:
        print("\n[!] Nothing added. Did you put selfies in training/my_face/<emotion>/ ?")
    else:
        print(f"\n[done] Added {grand_train} train + {grand_test} test images.")
        print("       Now retrain:  python train_meds.py")


if __name__ == "__main__":
    main()
