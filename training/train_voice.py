"""
train_voice.py  —  Train the MEDS voice-emotion model (the "Are you OK?" check-in).

Produces for the Flutter app:
  * assets/voice_model.tflite -> input  [1, 48000] float32 = 3 s of 16 kHz mono audio
                                 output [1, 7] softmax, same order as the face model
  * assets/voice_labels.txt

The log-mel front-end is INSIDE the model, so the app only hands over raw samples
after two simple steps (voice_classifier.dart mirrors them — keep them identical):
  1. trim():   cut leading/trailing silence,
  2. prepare(): repeat the trimmed clip until it is exactly 3 s long.

Data (downloaded into ../voice_data/, see README_TRAINING.md):
  ravdess/  RAVDESS speech   24 actors  03-01-EE-II-SS-RR-AA.wav
  cremad/   CREMA-D AudioWAV 91 actors  AAAA_SSS_EEE_LL.wav
  tess/     TESS              2 speakers OAF_word_emotion.wav

Honest evaluation: split by SPEAKER, never by clip, so a test voice is never heard
in training. Test = RAVDESS actors 21-24 + CREMA-D actors with id % 7 == 0.
Validation = RAVDESS 19-20 + CREMA-D id % 7 == 1. Train = the rest + all of TESS
(only 2 speakers, and near-perfect accuracy would flatter the test score).

Run (from training/, in the Python 3.11 venv):
  python train_voice.py
  python train_voice.py --subset 0.3 --epochs 3     # quick trial
"""

import argparse
import glob
import math
import os
import re
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter, resample_poly
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

from train_meds import (CLASS_ORDER, confusion, plot_bars, plot_confusion,
                        plot_history, write_report)

SR = 16000
CLIP = 3 * SR                              # model input length (samples)
N_FFT, HOP, N_MELS = 512, 160, 64          # 32 ms window, 10 ms hop
T_FRAMES = 1 + (CLIP - N_FFT) // HOP
TOP_DB = 30.0                              # trim(): frames this far below the loudest are silence

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DATA = os.path.normpath(os.path.join(HERE, "..", "voice_data"))
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "meds_app", "assets"))
LOCAL_OUT = os.path.join(HERE, "output_voice")

RAVDESS_EMO = {"01": "neutral", "02": "neutral", "03": "happy", "04": "sad",   # 02 = calm
               "05": "angry", "06": "fear", "07": "disgust", "08": "surprise"}
CREMAD_EMO = {"ANG": "angry", "DIS": "disgust", "FEA": "fear", "HAP": "happy",
              "NEU": "neutral", "SAD": "sad"}
TESS_EMO = {"angry": "angry", "disgust": "disgust", "fear": "fear", "happy": "happy",
            "neutral": "neutral", "ps": "surprise", "sad": "sad"}


# --------------------------------------------------------------------------- #
#  Data                                                                        #
# --------------------------------------------------------------------------- #

def parse(path):
    """File name -> (emotion, speaker, split), or None if it isn't a clip we use."""
    name = os.path.basename(path)
    m = re.fullmatch(r"03-01-(\d\d)-\d\d-\d\d-\d\d-(\d\d)\.wav", name)
    if m:
        actor = int(m.group(2))
        split = "test" if actor >= 21 else "val" if actor >= 19 else "train"
        return RAVDESS_EMO.get(m.group(1)), f"ravdess{actor}", split
    m = re.fullmatch(r"(\d{4})_[A-Z]{3}_([A-Z]{3})_[A-Z]{2}\.wav", name)
    if m:
        actor = int(m.group(1))
        split = {0: "test", 1: "val"}.get(actor % 7, "train")
        return CREMAD_EMO.get(m.group(2)), f"cremad{actor}", split
    m = re.fullmatch(r"([OY]AF)_.+_([A-Za-z]+)\.wav", name, re.I)
    if m:
        return TESS_EMO.get(m.group(2).lower()), f"tess{m.group(1).upper()}", "train"
    return None


def load_wav(path):
    """Any PCM/float wav -> float32 mono at 16 kHz."""
    sr, x = wavfile.read(path)
    if x.dtype.kind == "i":
        x = x / float(np.iinfo(x.dtype).max)
    elif x.dtype.kind == "u":
        x = (x.astype(np.float32) - 128) / 128.0
    x = np.asarray(x, np.float32)
    if x.ndim > 1:
        x = x.mean(axis=1)
    if sr != SR:
        g = math.gcd(sr, SR)
        x = resample_poly(x, SR // g, sr // g).astype(np.float32)
    return x


def trim(x):
    """Cut leading/trailing silence: keep from the first to the last frame whose
    RMS is within TOP_DB of the loudest frame."""
    if len(x) < N_FFT:
        return x
    frames = np.lib.stride_tricks.sliding_window_view(x, N_FFT)[::HOP]
    rms = np.sqrt(np.mean(frames.astype(np.float64) ** 2, axis=1))
    loud = np.nonzero(rms >= rms.max() * 10 ** (-TOP_DB / 20))[0]
    return x[loud[0] * HOP: loud[-1] * HOP + N_FFT]


def prepare(x, offset=0):
    """Trimmed clip -> exactly CLIP samples by repeating it (no silent padding).
    The app always uses offset 0; training uses random offsets."""
    if len(x) == 0:
        return np.zeros(CLIP, np.float32)
    reps = -(-(offset + CLIP) // len(x))
    return np.tile(x, reps)[offset:offset + CLIP].astype(np.float32)


def load_dataset(root, cache):
    """Trimmed int16 clips + labels/speakers/splits, cached after the first run."""
    if os.path.isfile(cache):
        z = np.load(cache)
        clips = np.split(z["audio"], z["ends"][:-1])
        print(f"[data] loaded {len(clips)} clips from cache {cache}")
        return clips, z["labels"], z["speakers"], z["splits"]

    clips, labels, speakers, splits, bad = [], [], [], [], 0
    files = sorted(glob.glob(os.path.join(root, "**", "*.wav"), recursive=True))
    for n, f in enumerate(files):
        meta = parse(f)
        if not meta or meta[0] is None:
            continue
        try:
            x = trim(load_wav(f))
        except Exception:
            bad += 1   # e.g. a git-lfs pointer instead of real audio
            continue
        peak = float(np.abs(x).max()) if len(x) else 0.0
        if peak == 0.0:
            bad += 1
            continue
        clips.append((x / peak * 32767).astype(np.int16))   # model peak-normalises anyway
        labels.append(CLASS_ORDER.index(meta[0]))
        speakers.append(meta[1])
        splits.append(meta[2])
        if n % 2000 == 0:
            print(f"[data] {n}/{len(files)} files read", flush=True)
    if not clips:
        raise SystemExit(f"[ERROR] no usable .wav files under {root} - see README_TRAINING.md")
    print(f"[data] {len(clips)} clips ({bad} unreadable/silent skipped)")
    np.savez(cache, audio=np.concatenate(clips), ends=np.cumsum([len(c) for c in clips]),
             labels=np.array(labels), speakers=np.array(speakers), splits=np.array(splits))
    return clips, np.array(labels), np.array(speakers), np.array(splits)


def augment(x, rng):
    """Random start point, and half the time a different 'microphone' (spectral
    tilt) and background noise (5-30 dB SNR) - phones are not studio mics."""
    x = prepare(x, offset=int(rng.integers(len(x))))
    if rng.random() < 0.5:
        x = lfilter([1.0, -rng.uniform(-0.3, 0.7)], [1.0], x).astype(np.float32)
    if rng.random() < 0.5:
        rms = np.sqrt(np.mean(x ** 2))
        x = x + rng.normal(0, 1, len(x)).astype(np.float32) * rms / 10 ** (rng.uniform(5, 30) / 20)
    return x.astype(np.float32)


def to_float(c):
    return c.astype(np.float32) / 32767.0


# --------------------------------------------------------------------------- #
#  Model                                                                       #
# --------------------------------------------------------------------------- #

def mel_matrix(fmin=50.0, fmax=SR / 2):
    """(N_FFT/2+1, N_MELS) triangular HTK mel filterbank."""
    hz2mel = lambda f: 2595 * np.log10(1 + f / 700)
    mel2hz = lambda m: 700 * (10 ** (m / 2595) - 1)
    edges = mel2hz(np.linspace(hz2mel(fmin), hz2mel(fmax), N_MELS + 2))
    bins = np.fft.rfftfreq(N_FFT, 1 / SR)
    lo, mid, hi = edges[:-2, None], edges[1:-1, None], edges[2:, None]
    fb = np.maximum(0, np.minimum((bins - lo) / (mid - lo), (hi - bins) / (hi - mid)))
    return fb.T.astype(np.float32)


class LogMel(layers.Layer):
    """Raw audio -> log-mel spectrogram inside the model, built only from
    conv / matmul / log ops so it converts to TFLite with no custom ops."""

    def __init__(self, **kw):
        super().__init__(trainable=False, **kw)
        n, k = np.arange(N_FFT), np.arange(N_FFT // 2 + 1)
        win = 0.5 - 0.5 * np.cos(2 * np.pi * n / N_FFT)          # periodic Hann
        ang = 2 * np.pi * np.outer(n, k) / N_FFT
        self.cos = tf.constant((np.cos(ang) * win[:, None])[:, None, :], tf.float32)
        self.sin = tf.constant((np.sin(ang) * win[:, None])[:, None, :], tf.float32)
        self.mel = tf.constant(mel_matrix())

    def call(self, x):
        x = x / (tf.reduce_max(tf.abs(x), axis=1, keepdims=True) + 1e-6)   # mic gain doesn't matter
        x = x[:, :, None]
        re_ = tf.nn.conv1d(x, self.cos, stride=HOP, padding="VALID")       # (B, T, bins) = DFT
        im_ = tf.nn.conv1d(x, self.sin, stride=HOP, padding="VALID")
        power = tf.reshape(tf.square(re_) + tf.square(im_), [-1, N_FFT // 2 + 1])
        mel = tf.reshape(tf.matmul(power, self.mel), [-1, T_FRAMES, N_MELS])
        logmel = tf.math.log(mel + 1e-6)
        return logmel - tf.reduce_mean(logmel, axis=[1, 2], keepdims=True)  # loudness-free


class SpecAugment(layers.Layer):
    """Training only: blank n random mel bands (<= freq wide) and n time spans
    (<= time frames) so the model can't lean on one cue. Identity at inference,
    so the TFLite export and the app see exactly the same model as before."""

    def __init__(self, freq=8, time=30, n=2, **kw):
        super().__init__(**kw)
        self.freq, self.time, self.n = freq, time, n

    def call(self, x, training=None):
        if not training:
            return x
        b = tf.shape(x)[0]
        for axis, width in ((2, self.freq), (1, self.time)) * self.n:
            size = tf.shape(x)[axis]
            w = tf.random.uniform([b, 1], 0, width + 1, tf.int32)
            start = tf.random.uniform([b, 1], 0, size - width, tf.int32)
            pos = tf.range(size)[None, :]
            hit = (pos >= start) & (pos < start + w)                        # (B, size)
            hit = hit[:, None, :] if axis == 2 else hit[:, :, None]
            x = tf.where(hit, tf.zeros_like(x), x)   # 0 = the clip's mean log-mel
        return x


def build_model(dropout=0.3):
    inp = keras.Input((CLIP,), name="audio")
    x = LogMel(name="logmel")(inp)
    x = SpecAugment(name="specaugment")(x)
    x = layers.Reshape((T_FRAMES, N_MELS, 1))(x)
    x = layers.BatchNormalization()(x)
    for f in (32, 64, 128, 128):
        x = layers.Conv2D(f, 3, padding="same", use_bias=False)(x)
        x = layers.BatchNormalization()(x)
        x = layers.ReLU()(x)
        x = layers.MaxPooling2D(2)(x)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(dropout)(x)
    out = layers.Dense(len(CLASS_ORDER), activation="softmax", name="emotion")(x)
    return keras.Model(inp, out, name="meds_voice")


def tflite_predict(tfl_bytes, X):
    interp = tf.lite.Interpreter(model_content=tfl_bytes)
    interp.allocate_tensors()
    i, o = interp.get_input_details()[0]["index"], interp.get_output_details()[0]["index"]
    probs = []
    for x in X:
        interp.set_tensor(i, x[None])
        interp.invoke()
        probs.append(interp.get_tensor(o)[0])
    return np.array(probs)


# --------------------------------------------------------------------------- #
#  Main                                                                        #
# --------------------------------------------------------------------------- #

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=DEFAULT_DATA)
    ap.add_argument("--out", default=DEFAULT_OUT, help="app assets folder to write into")
    ap.add_argument("--epochs", type=int, default=60)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--subset", type=float, default=1.0, help="fraction of TRAIN clips (quick trials)")
    ap.add_argument("--dropout", type=float, default=0.3)
    args = ap.parse_args()

    os.makedirs(LOCAL_OUT, exist_ok=True)
    reports = os.path.join(LOCAL_OUT, "reports")
    os.makedirs(reports, exist_ok=True)

    clips, labels, speakers, splits = load_dataset(args.data, os.path.join(args.data, "cache_16k.npz"))
    idx = {s: np.nonzero(splits == s)[0] for s in ("train", "val", "test")}
    rng = np.random.default_rng(42)
    if args.subset < 1.0:
        idx["train"] = rng.choice(idx["train"], max(1, int(len(idx["train"]) * args.subset)), replace=False)
    for s, ii in idx.items():
        print(f"[data] {s:5s}: {len(ii):5d} clips, {len(set(speakers[ii])):3d} speakers  "
              + " ".join(f"{c}={int((labels[ii] == k).sum())}" for k, c in enumerate(CLASS_ORDER)))
    assert not set(speakers[idx["train"]]) & set(speakers[idx["test"]]), "speaker leak train/test"
    assert not set(speakers[idx["val"]]) & set(speakers[idx["test"]]), "speaker leak val/test"

    counts = np.bincount(labels[idx["train"]], minlength=len(CLASS_ORDER)).astype(float)
    class_weight = {k: float(counts.sum() / (len(counts) * c)) if c else 0.0 for k, c in enumerate(counts)}

    def train_gen():
        g = np.random.default_rng(0)
        while True:
            for i in g.permutation(idx["train"]):
                yield augment(to_float(clips[i]), g), labels[i]

    train_ds = tf.data.Dataset.from_generator(
        train_gen, output_signature=(tf.TensorSpec((CLIP,), tf.float32), tf.TensorSpec((), tf.int64))
    ).batch(args.batch).prefetch(2)
    X_val = np.stack([prepare(to_float(clips[i])) for i in idx["val"]])
    X_test = np.stack([prepare(to_float(clips[i])) for i in idx["test"]])
    y_val, y_test = labels[idx["val"]], labels[idx["test"]]

    model = build_model(args.dropout)
    steps = math.ceil(len(idx["train"]) / args.batch)
    # Smooth cosine decay instead of plateau drops: val accuracy swung 17%-61%
    # between epochs, so the "best epoch" pick was mostly luck.
    lr = keras.optimizers.schedules.CosineDecay(1e-3, decay_steps=steps * args.epochs, alpha=0.01)
    model.compile(optimizer=keras.optimizers.Adam(lr),
                  loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    ckpt = os.path.join(LOCAL_OUT, "best_voice.weights.h5")
    hist = model.fit(
        train_ds, steps_per_epoch=steps,
        validation_data=(X_val, y_val), epochs=args.epochs, class_weight=class_weight,
        callbacks=[
            keras.callbacks.ModelCheckpoint(ckpt, monitor="val_accuracy", save_best_only=True,
                                            save_weights_only=True, verbose=1),
            keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=15,
                                          restore_best_weights=True),
            keras.callbacks.CSVLogger(os.path.join(reports, "history.csv")),
        ])
    model.load_weights(ckpt)

    print("\n[eval] test set (speakers never heard in training)")
    plot_history(hist.history, None, os.path.join(reports, "training_history.png"))
    probs = model.predict(X_test, batch_size=64, verbose=0)
    y_pred = probs.argmax(1)
    acc = float((y_pred == y_test).mean())
    cm = confusion(y_test, y_pred, len(CLASS_ORDER))
    np.savetxt(os.path.join(reports, "confusion_matrix.csv"), cm, fmt="%d", delimiter=",",
               header=",".join(CLASS_ORDER), comments="")
    plot_confusion(cm, CLASS_ORDER, os.path.join(reports, "confusion_matrix.png"))
    plot_confusion(cm, CLASS_ORDER, os.path.join(reports, "confusion_matrix_normalized.png"),
                   normalize=True)
    f1, recall = write_report(cm, CLASS_ORDER, acc, os.path.join(reports, "classification_report.txt"),
                              y_true=y_test, probs=probs, title="MEDS Voice-Emotion Model")
    plot_bars(CLASS_ORDER, list(recall), "Voice: per-emotion recall (detection rate)", "recall",
              os.path.join(reports, "per_class_recall.png"))
    for ds in ("ravdess", "cremad"):
        sel = np.char.startswith(speakers[idx["test"]].astype(str), ds)
        if sel.any():
            print(f"      {ds:8s} test accuracy: {(y_pred[sel] == y_test[sel]).mean() * 100:.1f}% "
                  f"({int(sel.sum())} clips)")

    print("\n[export] converting to TFLite...")
    # Plain float32 on purpose: Optimize.DEFAULT quantises the raw audio feeding
    # the built-in DFT to 8 bits, which wiped out quiet speech (54% -> 15%).
    tfl = tf.lite.TFLiteConverter.from_keras_model(model).convert()
    tfl_acc = float((tflite_predict(tfl, X_test).argmax(1) == y_test).mean())
    print(f"      TFLite test accuracy: {tfl_acc * 100:.2f}% (Keras {acc * 100:.2f}%)")
    with open(os.path.join(reports, "classification_report.txt"), "a", encoding="utf-8") as f:
        f.write(f"TFLite (what the app runs) accuracy: {tfl_acc * 100:.2f}%\n")

    for out_dir in {LOCAL_OUT, args.out}:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, "voice_model.tflite"), "wb") as f:
            f.write(tfl)
        with open(os.path.join(out_dir, "voice_labels.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(CLASS_ORDER) + "\n")
    print(f"\n[done] voice_model.tflite ({len(tfl) / 1e6:.1f} MB) + voice_labels.txt -> {args.out}")


if __name__ == "__main__":
    main()
