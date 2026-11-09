"""
train_meds.py  —  Retrain the MEDS facial-emotion model on FER2013 (+ your face).

Produces a DROP-IN replacement for your Flutter app:
  * assets/model.tflite   -> 224x224x3 input, normalized to [-1, 1], softmax output
  * assets/labels.txt      -> class order matching the model's output

This matches exactly what lib/services/emotion_classifier.dart already feeds the
model (pixel/127.5 - 1.0), so NO Dart changes are needed — just rebuild the app.

Approach: transfer learning (ImageNet weights).
  Phase 1: freeze the base, train a new 7-class head.
  Phase 2: unfreeze the top layers and fine-tune at a low learning rate.

Accuracy features: choice of backbone (MobileNetV2 / V3), label smoothing for
FER2013's noisy labels, class weighting, augmentation, and test-time augmentation
(flip) at evaluation to match the app. Reports include a confusion matrix,
ROC curves + AUC, top-2 accuracy, before/after vs the old model, own-face
accuracy, and a combined summary dashboard.

Run (from training/, inside the Python 3.11 venv):
  python train_meds.py                       # full run, writes into ../meds_app/assets
  python train_meds.py --safe                # laptop overheating/crashing? use this
  python train_meds.py --threads 4           # cap CPU cores (cooler) at full data
  python train_meds.py --base mobilenetv3large   # more accurate, a bit bigger
  python train_meds.py --subset 0.3          # quick test on 30% of data
"""

import argparse
import os
import sys

# Windows consoles default to cp1252 and crash on non-ASCII prints. Force UTF-8.
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import numpy as np
import tensorflow as tf
from tensorflow import keras
from tensorflow.keras import layers

AUTOTUNE = tf.data.AUTOTUNE
IMG = 224
# image_dataset_from_directory sorts class folders alphabetically -> this order
# becomes the model's output order, so labels.txt must match it exactly.
CLASS_ORDER = ["angry", "disgust", "fear", "happy", "neutral", "sad", "surprise"]

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DATA = os.path.normpath(os.path.join(HERE, "..", "fer2013_clean"))  # build_clean_dataset.py
DEFAULT_OUT = os.path.normpath(os.path.join(HERE, "..", "meds_app", "assets"))
LOCAL_OUT = os.path.join(HERE, "output")


def make_ds(directory, batch, shuffle, subset=1.0, val_split=None):
    """One dataset, or a (train, validation) pair split from the same folder."""
    ds = keras.utils.image_dataset_from_directory(
        directory,
        labels="inferred",
        label_mode="int",
        class_names=CLASS_ORDER,     # force the exact order
        color_mode="rgb",
        image_size=(IMG, IMG),
        batch_size=batch,
        shuffle=shuffle,
        seed=42,
        validation_split=val_split,
        subset="both" if val_split else None,   # one call -> no train/val overlap
    )
    if subset < 1.0:
        cut = lambda d: d.take(max(1, int(d.cardinality().numpy() * subset)))
        ds = tuple(map(cut, ds)) if val_split else cut(ds)
    return ds


def compute_class_weights(data_dir):
    counts = []
    for c in CLASS_ORDER:
        d = os.path.join(data_dir, "train", c)
        counts.append(len(os.listdir(d)) if os.path.isdir(d) else 0)
    counts = np.array(counts, dtype=np.float64)
    counts[counts == 0] = 1
    weights = counts.sum() / (len(counts) * counts)   # inverse-frequency
    return {i: float(w) for i, w in enumerate(weights)}, counts


def build_model(n_classes, base_name="mobilenetv2", dropout=0.3):
    """Transfer-learning model. All supported backbones consume [-1, 1] input,
    so the exported tflite keeps the contract the Flutter app expects.
    MobileNetV3Large is more accurate than V2 (at a slightly larger size)."""
    kw = dict(input_shape=(IMG, IMG, 3), include_top=False, weights="imagenet", pooling="avg")
    name = base_name.lower()
    if name in ("mobilenetv3large", "v3large", "v3"):
        base = keras.applications.MobileNetV3Large(include_preprocessing=False, **kw)
    elif name in ("mobilenetv3small", "v3small"):
        base = keras.applications.MobileNetV3Small(include_preprocessing=False, **kw)
    else:
        base = keras.applications.MobileNetV2(**kw)   # default, smallest, proven
    base.trainable = False
    inputs = keras.Input(shape=(IMG, IMG, 3))   # expects values already in [-1, 1]
    x = base(inputs, training=False)
    x = layers.Dropout(dropout)(x)
    outputs = layers.Dense(n_classes, activation="softmax")(x)
    return keras.Model(inputs, outputs), base


def make_loss(smoothing, n):
    """Sparse cross-entropy, optionally with label smoothing (helps a lot on the
    noisy FER2013 labels). Keeps integer labels so the eval code is unchanged."""
    if smoothing and smoothing > 0:
        cce = keras.losses.CategoricalCrossentropy(label_smoothing=float(smoothing))

        def loss_fn(y_true, y_pred):
            yt = tf.one_hot(tf.cast(tf.reshape(y_true, [-1]), tf.int32), n)
            return cce(yt, y_pred)
        return loss_fn
    return "sparse_categorical_crossentropy"


# --------------------------------------------------------------------------- #
#  Evaluation & proof-of-training reports                                      #
# --------------------------------------------------------------------------- #

def _mpl():
    """Import matplotlib with a non-GUI backend, or None if unavailable."""
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        return plt
    except Exception as e:
        print(f"      [!] matplotlib not available ({e}) - skipping plots.")
        return None


def merge_histories(h1, h2):
    keys = ["accuracy", "val_accuracy", "loss", "val_loss"]
    merged = {k: list(h1.history.get(k, [])) + list(h2.history.get(k, [])) for k in keys}
    split = len(h1.history.get("accuracy", []))   # epoch where fine-tuning began
    return merged, split


def metrics_from_cm(cm):
    """Per-class precision / recall / F1 / support from a confusion matrix."""
    cm = cm.astype(float)
    tp = np.diag(cm)
    pred_tot = cm.sum(axis=0)
    supp = cm.sum(axis=1)
    precision = np.divide(tp, pred_tot, out=np.zeros_like(tp), where=pred_tot > 0)
    recall = np.divide(tp, supp, out=np.zeros_like(tp), where=supp > 0)
    denom = precision + recall
    f1 = np.divide(2 * precision * recall, denom, out=np.zeros_like(tp), where=denom > 0)
    return precision, recall, f1, supp.astype(int)


def plot_history(history, split, out_path):
    plt = _mpl()
    if plt is None:
        return
    ep = range(1, len(history["accuracy"]) + 1)
    fig, ax = plt.subplots(1, 2, figsize=(11, 4))
    ax[0].plot(ep, history["accuracy"], "-o", ms=3, label="train")
    ax[0].plot(ep, history["val_accuracy"], "-o", ms=3, label="validation")
    ax[0].set_title("Accuracy"); ax[0].set_xlabel("epoch"); ax[0].set_ylabel("accuracy")
    ax[1].plot(ep, history["loss"], "-o", ms=3, label="train")
    ax[1].plot(ep, history["val_loss"], "-o", ms=3, label="validation")
    ax[1].set_title("Loss"); ax[1].set_xlabel("epoch"); ax[1].set_ylabel("loss")
    for a in ax:
        a.grid(alpha=.3); a.legend()
        if split and 0 < split < len(list(ep)):
            a.axvline(split + 0.5, color="gray", ls="--", lw=1)
            a.text(split + 0.6, a.get_ylim()[0], " fine-tune", color="gray", fontsize=8,
                   va="bottom")
    fig.suptitle("MEDS training history (dashed line = start of fine-tuning)")
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def plot_confusion(cm, class_names, out_path, normalize=False):
    plt = _mpl()
    if plt is None:
        return
    data = cm.astype(float)
    if normalize:
        row = data.sum(axis=1, keepdims=True); row[row == 0] = 1; data = data / row
    fig, ax = plt.subplots(figsize=(6.8, 5.8))
    im = ax.imshow(data, cmap="Blues", vmin=0, vmax=data.max() if data.max() else 1)
    ax.set_xticks(range(len(class_names))); ax.set_yticks(range(len(class_names)))
    ax.set_xticklabels(class_names, rotation=45, ha="right"); ax.set_yticklabels(class_names)
    ax.set_xlabel("Predicted"); ax.set_ylabel("True")
    ax.set_title("Confusion matrix " + ("(row-normalized)" if normalize else "(counts)"))
    thresh = data.max() / 2 if data.max() else 0.5
    for i in range(len(class_names)):
        for j in range(len(class_names)):
            txt = f"{data[i, j]:.2f}" if normalize else f"{int(cm[i, j])}"
            ax.text(j, i, txt, ha="center", va="center", fontsize=8,
                    color="white" if data[i, j] > thresh else "black")
    fig.colorbar(im, fraction=0.046, pad=0.04)
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def plot_bars(class_names, values, title, ylabel, out_path):
    plt = _mpl()
    if plt is None:
        return
    fig, ax = plt.subplots(figsize=(7, 4))
    bars = ax.bar(range(len(class_names)), values, color="#4f46e5")
    ax.set_ylim(0, 1.05); ax.set_ylabel(ylabel); ax.set_title(title)
    ax.set_xticks(range(len(class_names)))
    ax.set_xticklabels(class_names, rotation=45, ha="right")
    for b, v in zip(bars, values):
        ax.text(b.get_x() + b.get_width() / 2, v + 0.01, f"{v:.2f}",
                ha="center", va="bottom", fontsize=8)
    ax.grid(axis="y", alpha=.3)
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def predict_dataset(model, ds, tta=True):
    """Predict over a dataset. With tta=True, also classify the horizontally
    flipped image and average — the same trick emotion_classifier.dart uses, so
    the reported numbers reflect what the app actually does. Returns full
    probabilities too (for ROC / top-2)."""
    y_true, probs = [], []
    for x, y in ds:
        p = model.predict(x, verbose=0)
        if tta:
            p = (p + model.predict(tf.image.flip_left_right(x), verbose=0)) / 2.0
        probs.append(p)
        y_true.extend(np.asarray(y).tolist())
    probs = np.concatenate(probs, axis=0) if probs else np.zeros((0, len(CLASS_ORDER)))
    y_pred = np.argmax(probs, axis=1) if len(probs) else np.array([], dtype=int)
    return np.array(y_true), y_pred, probs


def _auc_binary(scores, pos):
    """One-vs-rest ROC-AUC via the rank (Mann-Whitney) formula. No sklearn."""
    pos = np.asarray(pos, dtype=bool)
    P, N = int(pos.sum()), int((~pos).sum())
    if P == 0 or N == 0:
        return float("nan")
    order = np.argsort(scores, kind="mergesort")
    ranks = np.empty(len(scores), dtype=float)
    ranks[order] = np.arange(1, len(scores) + 1)
    # average ranks for ties
    s_sorted = scores[order]
    i = 0
    while i < len(s_sorted):
        j = i
        while j + 1 < len(s_sorted) and s_sorted[j + 1] == s_sorted[i]:
            j += 1
        if j > i:
            ranks[order[i:j + 1]] = (i + 1 + j + 1) / 2.0
        i = j + 1
    return (ranks[pos].sum() - P * (P + 1) / 2.0) / (P * N)


def roc_points(scores, pos):
    """FPR, TPR arrays and AUC for one-vs-rest ROC."""
    pos = np.asarray(pos, dtype=bool)
    order = np.argsort(-scores, kind="mergesort")
    pos = pos[order]
    tps = np.cumsum(pos); fps = np.cumsum(~pos)
    P = max(int(pos.sum()), 1); N = max(int((~pos).sum()), 1)
    tpr = np.concatenate([[0.0], tps / P])
    fpr = np.concatenate([[0.0], fps / N])
    # trapezoidal area, computed manually (np.trapz was removed in numpy 2.0)
    auc = float(np.sum(np.diff(fpr) * (tpr[1:] + tpr[:-1]) / 2.0))
    return fpr, tpr, auc


def plot_roc(y_true, probs, class_names, out_path):
    plt = _mpl()
    if plt is None or not len(probs):
        return
    fig, ax = plt.subplots(figsize=(6.6, 5.6))
    aucs = []
    for i, c in enumerate(class_names):
        fpr, tpr, auc = roc_points(probs[:, i], y_true == i)
        aucs.append(auc)
        ax.plot(fpr, tpr, lw=1.6, label=f"{c} (AUC {auc:.2f})")
    ax.plot([0, 1], [0, 1], "k--", lw=1, alpha=.5)
    ax.set_xlabel("False positive rate"); ax.set_ylabel("True positive rate")
    ax.set_title(f"ROC curves (one-vs-rest) - macro AUC {np.nanmean(aucs):.3f}")
    ax.legend(fontsize=8, loc="lower right"); ax.grid(alpha=.3)
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def plot_summary(history, split, cm, class_names, f1, out_path,
                 before_after=None):
    """One paper-ready page: training curves, normalized confusion, per-class F1,
    and (if available) the before/after bars."""
    plt = _mpl()
    if plt is None:
        return
    fig, axes = plt.subplots(2, 2, figsize=(13, 9))

    # (0,0) accuracy history
    ax = axes[0, 0]
    ep = range(1, len(history["accuracy"]) + 1)
    ax.plot(ep, history["accuracy"], "-o", ms=3, label="train")
    ax.plot(ep, history["val_accuracy"], "-o", ms=3, label="validation")
    if split:
        ax.axvline(split + 0.5, color="gray", ls="--", lw=1)
    ax.set_title("Accuracy"); ax.set_xlabel("epoch"); ax.legend(); ax.grid(alpha=.3)

    # (0,1) normalized confusion
    ax = axes[0, 1]
    data = cm.astype(float); rs = data.sum(1, keepdims=True); rs[rs == 0] = 1; data /= rs
    im = ax.imshow(data, cmap="Blues", vmin=0, vmax=1)
    ax.set_xticks(range(len(class_names))); ax.set_yticks(range(len(class_names)))
    ax.set_xticklabels(class_names, rotation=45, ha="right", fontsize=8)
    ax.set_yticklabels(class_names, fontsize=8)
    ax.set_title("Confusion (row-normalized)"); ax.set_xlabel("Predicted"); ax.set_ylabel("True")
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)

    # (1,0) per-class F1
    ax = axes[1, 0]
    ax.bar(range(len(class_names)), list(f1), color="#4f46e5")
    ax.set_xticks(range(len(class_names)))
    ax.set_xticklabels(class_names, rotation=45, ha="right", fontsize=8)
    ax.set_ylim(0, 1.05); ax.set_title("Per-emotion F1"); ax.grid(axis="y", alpha=.3)

    # (1,1) before/after or per-class recall
    ax = axes[1, 1]
    if before_after is not None:
        old_v, new_v, acc_old, acc_new = before_after
        labels = list(class_names) + ["ALL"]
        old = list(old_v) + [acc_old]; new = list(new_v) + [acc_new]
        x = np.arange(len(labels)); w = .38
        ax.bar(x - w / 2, old, w, label="before", color="#9ca3af")
        ax.bar(x + w / 2, new, w, label="after", color="#4f46e5")
        ax.set_xticks(x); ax.set_xticklabels(labels, rotation=45, ha="right", fontsize=8)
        ax.set_ylim(0, 1.08); ax.set_title("Before vs after (recall)"); ax.legend(fontsize=8)
    else:
        _, recall, _, _ = metrics_from_cm(cm)
        ax.bar(range(len(class_names)), list(recall), color="#059669")
        ax.set_xticks(range(len(class_names)))
        ax.set_xticklabels(class_names, rotation=45, ha="right", fontsize=8)
        ax.set_ylim(0, 1.05); ax.set_title("Per-emotion recall")
    ax.grid(axis="y", alpha=.3)

    fig.suptitle("MEDS retraining summary", fontsize=14)
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def confusion(y_true, y_pred, n):
    cm = np.zeros((n, n), dtype=int)
    for t, p in zip(y_true, y_pred):
        cm[t, p] += 1
    return cm


def write_report(cm, class_names, acc, out_path, y_true=None, probs=None,
                 title="MEDS Facial-Emotion Model"):
    precision, recall, f1, supp = metrics_from_cm(cm)
    macro_f1 = float(np.mean(f1))
    weighted_f1 = float(np.average(f1, weights=supp)) if supp.sum() else 0.0

    # extras from probabilities (optional)
    aucs = None
    top2 = None
    if y_true is not None and probs is not None and len(probs):
        aucs = np.array([_auc_binary(probs[:, i], y_true == i) for i in range(len(class_names))])
        top2i = np.argsort(-probs, axis=1)[:, :2]
        top2 = float(np.mean([yt in row for yt, row in zip(y_true, top2i)]))

    lines = []
    lines.append(f"{title} - Test Evaluation")
    lines.append("=" * 60)
    lines.append(f"Overall accuracy : {acc * 100:.2f}%")
    if top2 is not None:
        lines.append(f"Top-2 accuracy   : {top2 * 100:.2f}%")
    lines.append(f"Macro F1         : {macro_f1:.3f}")
    lines.append(f"Weighted F1      : {weighted_f1:.3f}")
    if aucs is not None:
        lines.append(f"Macro ROC-AUC    : {np.nanmean(aucs):.3f}")
    lines.append(f"Test samples     : {int(supp.sum())}")
    lines.append("")
    head = f"{'class':10s} {'precision':>9s} {'recall':>7s} {'f1':>6s} {'support':>8s}"
    if aucs is not None:
        head += f" {'auc':>6s}"
    lines.append(head)
    lines.append("-" * len(head))
    for i, c in enumerate(class_names):
        row = f"{c:10s} {precision[i]:9.3f} {recall[i]:7.3f} {f1[i]:6.3f} {supp[i]:8d}"
        if aucs is not None:
            row += f" {aucs[i]:6.3f}"
        lines.append(row)
    text = "\n".join(lines)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print("\n" + text)
    return f1, recall


def clean_labels(lines):
    """Normalize a labels.txt into lowercase emotion names (drops a leading index
    like Teachable Machine's '0 happy', and fixes the 'suprise' typo)."""
    out = []
    for ln in lines:
        ln = ln.strip()
        if not ln:
            continue
        parts = ln.split()
        if len(parts) >= 2 and parts[0].isdigit():
            ln = " ".join(parts[1:])
        ln = ln.strip().lower()
        if ln == "suprise":
            ln = "surprise"
        out.append(ln)
    return out


class TFLiteRunner:
    """Runs a .tflite model (given as bytes) on batches of [-1, 1] RGB images.
    Used to score the OLD model for the before/after comparison."""

    def __init__(self, model_bytes):
        self.interp = tf.lite.Interpreter(model_content=model_bytes)
        self.inp = self.interp.get_input_details()[0]
        self.out = self.interp.get_output_details()[0]
        self._n = None

    def _resize(self, n):
        if self._n != n:
            self.interp.resize_tensor_input(self.inp["index"],
                                            [n] + list(self.inp["shape"][1:]))
            self.interp.allocate_tensors()
            self._n = n

    def _run(self, X, chunk):
        outs = []
        for i in range(0, len(X), chunk):
            xb = np.asarray(X[i:i + chunk], dtype=self.inp["dtype"])
            self._resize(len(xb))
            self.interp.set_tensor(self.inp["index"], xb)
            self.interp.invoke()
            outs.append(self.interp.get_tensor(self.out["index"]).copy())
        return np.concatenate(outs, axis=0)

    def predict(self, X):
        try:
            return self._run(X, 128)                 # fast: batched
        except Exception as e:                       # some models are batch-1 only
            print(f"      [info] batched TFLite not supported ({e}); per-image mode.")
            self._n = None
            return self._run(X, 1)


def _old_to_class_indexer(old_labels, class_order):
    """Map the old model's output index -> our class-order index (returns -1 for
    any label that doesn't match, so the caller can bail out)."""
    return np.array([class_order.index(n) if n in class_order else -1
                     for n in (old_labels or [])])


def capture_baseline(model_path, labels_path):
    """Read the currently-installed (old) model + labels into memory BEFORE
    training overwrites them, so we can compare old vs new at the end."""
    if not model_path or not os.path.isfile(model_path):
        print(f"      [!] baseline model not found ({model_path}) - before/after skipped.")
        return None, None
    with open(model_path, "rb") as f:
        data = f.read()
    labels = None
    if labels_path and os.path.isfile(labels_path):
        with open(labels_path, "r", encoding="utf-8") as f:
            labels = clean_labels(f.readlines())
    print(f"      Baseline captured for before/after: {os.path.basename(model_path)} "
          f"({len(data) / 1e6:.1f} MB), old label order = {labels}")
    return data, labels


def plot_before_after(class_names, old_vals, new_vals, acc_old, acc_new, out_path, title):
    plt = _mpl()
    if plt is None:
        return
    labels = list(class_names) + ["OVERALL"]
    old = list(old_vals) + [acc_old]
    new = list(new_vals) + [acc_new]
    x = np.arange(len(labels)); w = 0.38
    fig, ax = plt.subplots(figsize=(9.6, 4.7))
    b1 = ax.bar(x - w / 2, old, w, label="before (old model)", color="#9ca3af")
    b2 = ax.bar(x + w / 2, new, w, label="after (retrained)", color="#4f46e5")
    ax.set_xticks(x); ax.set_xticklabels(labels, rotation=45, ha="right")
    ax.set_ylim(0, 1.08); ax.set_ylabel("accuracy / recall"); ax.set_title(title)
    ax.legend()
    for bars in (b1, b2):
        for b in bars:
            ax.text(b.get_x() + b.get_width() / 2, b.get_height() + 0.01,
                    f"{b.get_height():.2f}", ha="center", va="bottom", fontsize=7)
    ax.grid(axis="y", alpha=.3)
    fig.tight_layout(); fig.savefig(out_path, dpi=150); plt.close(fig)
    print(f"      saved {os.path.basename(out_path)}")


def compare_baseline_testset(baseline_bytes, old_labels, val_ds, new_recall, acc_new,
                             class_order, out_dir):
    """Run the OLD model on the same test set and chart old-vs-new per emotion."""
    indexer = _old_to_class_indexer(old_labels, class_order)
    if len(indexer) != len(class_order) or (indexer < 0).any():
        print("      [!] old labels don't map to the class set - before/after skipped.")
        return None
    print("      Running the OLD model on the test set for before/after...")
    runner = TFLiteRunner(baseline_bytes)
    y_true, y_old = [], []
    for x, y in val_ds:
        xb = x.numpy()
        probs = runner.predict(xb)
        probs = (probs + runner.predict(xb[:, :, ::-1, :])) / 2.0   # flip TTA, like the app
        y_old.extend(indexer[np.argmax(probs, axis=1)].tolist())
        y_true.extend(np.argmax(np.asarray(y), axis=1).tolist()
                      if np.asarray(y).ndim > 1 else np.asarray(y).tolist())
    y_true = np.array(y_true); y_old = np.array(y_old)
    cm_old = confusion(y_true, y_old, len(class_order))
    _, recall_old, _, _ = metrics_from_cm(cm_old)
    acc_old = float((y_old == y_true).mean())

    plot_before_after(class_order, recall_old, new_recall, acc_old, acc_new,
                      os.path.join(out_dir, "before_after_testset.png"),
                      "Before vs after retraining - test set (per-emotion recall)")
    lines = ["Before/After on the TEST SET (detection rate = recall)",
             "=" * 60,
             f"OVERALL accuracy:  before {acc_old * 100:6.2f}%   "
             f"after {acc_new * 100:6.2f}%   change {(acc_new - acc_old) * 100:+.2f}%",
             "",
             f"{'emotion':10s} {'before':>8s} {'after':>8s} {'change':>8s}",
             "-" * 38]
    for i, c in enumerate(class_order):
        lines.append(f"{c:10s} {recall_old[i] * 100:7.1f}% {new_recall[i] * 100:7.1f}% "
                     f"{(new_recall[i] - recall_old[i]) * 100:+7.1f}%")
    txt = "\n".join(lines)
    with open(os.path.join(out_dir, "before_after_testset.txt"), "w", encoding="utf-8") as f:
        f.write(txt + "\n")
    print("\n" + txt)
    return recall_old, acc_old


def evaluate_myface(model, data_dir, class_names, out_dir,
                    baseline_bytes=None, old_labels=None):
    """If your own face images (myface_*) are in the test set, score them
    separately so you can see how well the model learned YOUR face per emotion.
    If a baseline model is given, also chart old-vs-new for your face."""
    import glob
    paths, labels = [], []
    for idx, c in enumerate(class_names):
        for p in glob.glob(os.path.join(data_dir, "test", c, "myface_*")):
            paths.append(p); labels.append(idx)
    if not paths:
        print("      (no myface_* images in the test set - skipping own-face report)")
        return
    X = np.stack([
        keras.utils.img_to_array(keras.utils.load_img(p, target_size=(IMG, IMG))) / 127.5 - 1.0
        for p in paths
    ])
    y = np.array(labels)
    Xf = X[:, :, ::-1, :]   # horizontally-flipped copy for TTA
    p_new = (model.predict(X, verbose=0) + model.predict(Xf, verbose=0)) / 2.0
    pred = np.argmax(p_new, axis=1)
    overall = float((pred == y).mean())

    # optional: old model on the same face images (with the same flip TTA)
    old_pred = None
    indexer = _old_to_class_indexer(old_labels, class_names)
    if baseline_bytes is not None and len(indexer) == len(class_names) and not (indexer < 0).any():
        r = TFLiteRunner(baseline_bytes)
        p_old = (r.predict(X) + r.predict(Xf)) / 2.0
        old_pred = indexer[np.argmax(p_old, axis=1)]

    tag = f"{overall * 100:.2f}%"
    if old_pred is not None:
        tag += f"  (old model: {float((old_pred == y).mean()) * 100:.2f}%)"
    print(f"\n      >>> Accuracy on YOUR OWN face ({len(y)} imgs): {tag}")

    per_new, per_old, present = [], [], []
    for idx, c in enumerate(class_names):
        mask = y == idx
        if not mask.sum():
            continue
        a = float((pred[mask] == y[mask]).mean())
        per_new.append(a); present.append(c)
        line = f"          {c:10s}: new {a * 100:5.1f}%"
        if old_pred is not None:
            o = float((old_pred[mask] == y[mask]).mean()); per_old.append(o)
            line += f"   old {o * 100:5.1f}%"
        line += f"   ({int(mask.sum())} imgs)"
        print(line)

    if not present:
        return
    if per_old:
        plot_before_after(present, per_old, per_new,
                          float((old_pred == y).mean()), overall,
                          os.path.join(out_dir, "before_after_myface.png"),
                          "Before vs after - YOUR OWN face (accuracy)")
    else:
        plot_bars(present, per_new, f"Accuracy on your own face (overall {overall * 100:.1f}%)",
                  "accuracy", os.path.join(out_dir, "myface_accuracy.png"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=DEFAULT_DATA)
    ap.add_argument("--out", default=DEFAULT_OUT, help="app assets folder to write into")
    ap.add_argument("--batch", type=int, default=64)
    ap.add_argument("--epochs-head", type=int, default=8)
    ap.add_argument("--epochs-fine", type=int, default=12)
    ap.add_argument("--fine-tune-layers", type=int, default=40)
    ap.add_argument("--subset", type=float, default=1.0)
    ap.add_argument("--val-split", type=float, default=0.1,
                    help="fraction of TRAIN held out for validation (test stays untouched)")
    ap.add_argument("--base", default="mobilenetv2",
                    choices=["mobilenetv2", "mobilenetv3large", "mobilenetv3small"],
                    help="backbone; mobilenetv3large is more accurate (bigger)")
    ap.add_argument("--label-smoothing", type=float, default=0.1,
                    help="0 to disable; helps with FER2013's noisy labels")
    ap.add_argument("--dropout", type=float, default=0.3)
    ap.add_argument("--no-tta", action="store_true",
                    help="disable test-time augmentation in the evaluation reports")
    ap.add_argument("--baseline", default=None,
                    help="old .tflite to compare against (default: the model.tflite "
                         "currently in --out, captured before it is overwritten)")
    ap.add_argument("--baseline-labels", default=None,
                    help="labels.txt for the baseline model (default: labels.txt in --out)")
    ap.add_argument("--no-baseline", action="store_true",
                    help="skip the before/after comparison")
    ap.add_argument("--threads", type=int, default=0,
                    help="cap CPU threads (0 = use all cores). Lower (e.g. 4) runs "
                         "much cooler - use this if your laptop overheats/crashes.")
    ap.add_argument("--safe", action="store_true",
                    help="low-heat laptop preset: 4 threads, batch 16, 25%% of the "
                         "data, fewer epochs. Prevents overheating/freezing.")
    args = ap.parse_args()

    # Low-resource preset for laptops that overheat or freeze during training.
    if args.safe:
        args.batch = min(args.batch, 16)
        if args.subset >= 1.0:
            args.subset = 0.25
        if args.threads <= 0:
            args.threads = 4
        args.epochs_head = min(args.epochs_head, 4)
        args.epochs_fine = min(args.epochs_fine, 5)
        print("[safe] low-heat preset: batch=%d subset=%.2f threads=%d epochs=%d/%d"
              % (args.batch, args.subset, args.threads, args.epochs_head, args.epochs_fine))

    # Cap CPU threads so training doesn't pin every core at 100% (the usual cause
    # of laptop thermal shutdowns). Must run before any TF ops are built.
    if args.threads and args.threads > 0:
        try:
            tf.config.threading.set_intra_op_parallelism_threads(args.threads)
            tf.config.threading.set_inter_op_parallelism_threads(min(2, args.threads))
            os.environ["OMP_NUM_THREADS"] = str(args.threads)
            print(f"      CPU threads capped at {args.threads} (cooler, a bit slower).")
        except Exception as e:
            print(f"      [!] could not cap threads: {e}")

    train_dir = os.path.join(args.data, "train")
    test_dir = os.path.join(args.data, "test")
    for d in (train_dir, test_dir):
        if not os.path.isdir(d):
            raise SystemExit(f"[ERROR] not found: {d}")

    os.makedirs(LOCAL_OUT, exist_ok=True)
    os.makedirs(args.out, exist_ok=True)

    # Capture the OLD model NOW, before training overwrites assets/model.tflite.
    if args.no_baseline:
        baseline_bytes, baseline_labels = None, None
    else:
        base_model = args.baseline or os.path.join(args.out, "model.tflite")
        base_labels = args.baseline_labels or os.path.join(args.out, "labels.txt")
        baseline_bytes, baseline_labels = capture_baseline(base_model, base_labels)

    print("[1/5] Loading datasets...")
    # Validation (early stopping / best-epoch pick / LR schedule) comes out of TRAIN,
    # so the test set is used exactly once: the final report.
    # shortcut: myface_* augmented copies are split at random, so one selfie's copies
    # can sit in both train and val; this only nudges the epoch pick, never the test score.
    train_ds, val_ds = make_ds(train_dir, args.batch, shuffle=True, subset=args.subset,
                               val_split=args.val_split)
    test_ds = make_ds(test_dir, args.batch, shuffle=False, subset=args.subset)

    # Augmentation (train only) + normalize to [-1, 1] in the data pipeline so the
    # exported model's input contract stays [-1, 1] with no extra layers.
    aug = keras.Sequential([
        layers.RandomFlip("horizontal"),
        layers.RandomRotation(0.06, fill_mode="nearest"),
        layers.RandomZoom(0.10, fill_mode="nearest"),
        layers.RandomContrast(0.10),
    ], name="augment")
    scale = lambda x: x / 127.5 - 1.0

    # When threads are capped (laptop/thermal mode) also bound the data pipeline,
    # otherwise AUTOTUNE spins up its own worker threads and re-saturates the CPU.
    par = args.threads if (args.threads and args.threads > 0) else AUTOTUNE
    train_ds = train_ds.map(lambda x, y: (scale(aug(x, training=True)), y),
                            num_parallel_calls=par).prefetch(par)
    val_ds = val_ds.map(lambda x, y: (scale(x), y),
                        num_parallel_calls=par).prefetch(par)
    test_ds = test_ds.map(lambda x, y: (scale(x), y),
                          num_parallel_calls=par).prefetch(par)

    class_weight, counts = compute_class_weights(args.data)
    print("      Train images per class:",
          {c: int(n) for c, n in zip(CLASS_ORDER, counts)})

    print(f"      Backbone: {args.base} | label-smoothing: {args.label_smoothing} | "
          f"TTA: {not args.no_tta}")
    model, base = build_model(len(CLASS_ORDER), base_name=args.base, dropout=args.dropout)
    loss = make_loss(args.label_smoothing, len(CLASS_ORDER))
    metric = keras.metrics.SparseCategoricalAccuracy(name="accuracy")

    # Weights-only checkpoint so a custom (label-smoothing) loss never blocks
    # save/load. EarlyStopping tracks the best within a phase; the checkpoint
    # holds the global best, which we load back before evaluating/exporting.
    ckpt = os.path.join(LOCAL_OUT, "best.weights.h5")
    callbacks = [
        keras.callbacks.ModelCheckpoint(ckpt, monitor="val_accuracy",
                                        save_best_only=True, save_weights_only=True,
                                        verbose=1),
        keras.callbacks.EarlyStopping(monitor="val_accuracy", patience=5,
                                      restore_best_weights=True),
        keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5,
                                          patience=2, min_lr=1e-6, verbose=1),
    ]

    # ---- Phase 1: train the head ----
    print("\n[2/5] Phase 1: training the classifier head (base frozen)...")
    model.compile(optimizer=keras.optimizers.Adam(1e-3), loss=loss, metrics=[metric])
    hist1 = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_head,
                      class_weight=class_weight, callbacks=callbacks)

    # ---- Phase 2: fine-tune the top of the base ----
    print(f"\n[3/5] Phase 2: fine-tuning top {args.fine_tune_layers} layers...")
    base.trainable = True
    for layer in base.layers[:-args.fine_tune_layers]:
        layer.trainable = False
    model.compile(optimizer=keras.optimizers.Adam(1e-5), loss=loss,
                  metrics=[keras.metrics.SparseCategoricalAccuracy(name="accuracy")])
    hist2 = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs_fine,
                      class_weight=class_weight, callbacks=callbacks)

    # ---- Evaluate best + generate proof-of-training reports ----
    print("\n[4/5] Evaluating best checkpoint on the test set...")
    model.load_weights(ckpt)   # global-best weights captured during training
    tta = not args.no_tta

    reports = os.path.join(LOCAL_OUT, "reports")
    os.makedirs(reports, exist_ok=True)

    # 1) training curves
    history, split = merge_histories(hist1, hist2)
    plot_history(history, split, os.path.join(reports, "training_history.png"))

    # 2) predictions (with TTA) -> confusion matrix + per-class metrics
    print(f"      Running predictions over the test set (TTA={tta})...")
    y_true, y_pred, probs = predict_dataset(model, test_ds, tta=tta)
    acc = float((y_true == y_pred).mean())
    print(f"      Test accuracy: {acc * 100:.2f}%")
    cm = confusion(y_true, y_pred, len(CLASS_ORDER))
    np.savetxt(os.path.join(reports, "confusion_matrix.csv"), cm, fmt="%d", delimiter=",",
               header=",".join(CLASS_ORDER), comments="")
    plot_confusion(cm, CLASS_ORDER, os.path.join(reports, "confusion_matrix.png"))
    plot_confusion(cm, CLASS_ORDER, os.path.join(reports, "confusion_matrix_normalized.png"),
                   normalize=True)

    # 3) precision / recall / F1 (+ top-2, ROC-AUC) table + bar charts + ROC
    f1, recall = write_report(cm, CLASS_ORDER, acc,
                              os.path.join(reports, "classification_report.txt"),
                              y_true=y_true, probs=probs)
    plot_bars(CLASS_ORDER, list(f1), "Per-emotion F1 score", "F1",
              os.path.join(reports, "per_class_f1.png"))
    plot_bars(CLASS_ORDER, list(recall), "Per-emotion recall (detection rate)", "recall",
              os.path.join(reports, "per_class_recall.png"))
    plot_roc(y_true, probs, CLASS_ORDER, os.path.join(reports, "roc_curves.png"))

    # 4) before vs after retraining: run the OLD model on the same test set
    ba = None
    if baseline_bytes:
        ba_res = compare_baseline_testset(baseline_bytes, baseline_labels, test_ds, recall, acc,
                                          CLASS_ORDER, reports)
        if ba_res is not None:
            recall_old, acc_old = ba_res
            ba = (recall_old, recall, acc_old, acc)

    # 5) how well did it learn YOUR face specifically (new, and old-vs-new)?
    evaluate_myface(model, args.data, CLASS_ORDER, reports, baseline_bytes, baseline_labels)

    # 6) one combined paper-ready summary page
    plot_summary(history, split, cm, CLASS_ORDER, f1,
                 os.path.join(reports, "summary_dashboard.png"), before_after=ba)

    print(f"\n      All charts + reports saved to: {reports}")

    # ---- Export TFLite (dynamic-range quantized: smaller, float in/out) ----
    print("\n[5/5] Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite = converter.convert()

    for out_dir in {LOCAL_OUT, args.out}:
        with open(os.path.join(out_dir, "model.tflite"), "wb") as f:
            f.write(tflite)
        with open(os.path.join(out_dir, "labels.txt"), "w", encoding="utf-8") as f:
            f.write("\n".join(CLASS_ORDER) + "\n")

    size_mb = len(tflite) / 1e6
    print(f"\n[done] Wrote model.tflite ({size_mb:.1f} MB) + labels.txt to:")
    print(f"       {args.out}   (your Flutter app)")
    print(f"       {LOCAL_OUT} (local backup)")
    print("\nNext: rebuild the app.  cd ../meds_app && flutter clean && flutter run")


if __name__ == "__main__":
    main()
