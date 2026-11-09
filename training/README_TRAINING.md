# Retraining the MEDS Face-Emotion Model

Everything here rebuilds `assets/model.tflite` for the Flutter app, trained on
FER2013 **plus your own face**. The output is a drop-in replacement — the app's
code (`lib/services/emotion_classifier.dart`) already feeds the model
`224×224` RGB normalized to `[-1, 1]`, which is exactly what these scripts produce.

> **Folder layout.** The scripts expect `MEDS/training`, `MEDS/meds_app`,
> `MEDS/fer2013_clean` and `MEDS/voice_data` side by side. The datasets and
> `my_face/` selfies are not in the git repo (size, licences, privacy), so
> download them as described below.

## 0. One-time setup (use Python 3.11 — TensorFlow does NOT support 3.14)

Open **PowerShell** in this `training/` folder and run:

```powershell
py -3.11 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
```

> If `Activate.ps1` is blocked, run once:
> `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`

## 1. Capture your face

Open **`webcam_burst.html`** by double-clicking it (Chrome or Edge). For each
emotion: pick it in the dropdown, make the face, and **hold "Capture"** while
slowly moving your head. Aim for **~150–250 shots per emotion**. Click
**Download** — files save as `happy_0001.jpg`, etc.

Then sort the downloaded files into these folders (create only the ones you did):

```
training/my_face/happy/
training/my_face/neutral/
training/my_face/sad/
training/my_face/surprise/
training/my_face/angry/
training/my_face/fear/
training/my_face/disgust/
```

(Tip: the files are already named by emotion, so they're easy to sort.)
You don't need all 7 — even just `happy / neutral / sad / surprise` helps a lot.

## 1b. Build the leak-free dataset (once)

```powershell
python build_clean_dataset.py
```

`../fer2013` merges several downloads of FER2013, so the same face appears many
times — and ~75% of its test images also sit in train. This writes
`../fer2013_clean` with one copy per face, every test face removed from train,
and blank / conflicting-label images dropped. `../fer2013` is left untouched.
Both scripts below use `../fer2013_clean` by default.

## 2. Add your face to the dataset

```powershell
python add_my_face.py
```

This detects & crops your face, resizes to 224×224, and files them into
`../fer2013_clean/train` and `../fer2013_clean/test` with a `myface_` prefix. The split is
done per selfie in capture order (the last ~15% of each burst is test, with a
3-frame gap), duplicate files are skipped, and only train selfies get augmented
copies — so the test set holds real photos the model has never seen.
Re-run with `--reset` to redo it cleanly, or `--copies 8` for more copies.

**Face detector:** by default (`--detector auto`) it uses **MediaPipe** — which
also *aligns* the face by leveling the eyes (a real accuracy boost for emotion
models) — then falls back to Haar, then a center crop. Force one with
`--detector mediapipe|haar|center`. MediaPipe needs the 3.11 venv (`pip install
-r requirements.txt`); if you run this on plain Python 3.14 it will fall back to
center-crop, which is fine for the centered burst selfies.

## 3. Retrain

```powershell
python train_meds.py
```

- Writes `model.tflite` + `labels.txt` straight into `../meds_app/assets/`
  (and a backup in `training/output/`).
- Prints the test accuracy at the end.
- Quick trial run first: `python train_meds.py --subset 0.3 --epochs-head 3 --epochs-fine 3`

### Knobs to push accuracy higher

| Flag | Effect |
|---|---|
| `--base mobilenetv3large` | Stronger backbone than the default MobileNetV2 (more accurate, a bit bigger `.tflite`). Also `mobilenetv3small`. All keep the `[-1,1]` input the app needs. |
| `--label-smoothing 0.1` | On by default — softens the noisy FER2013 labels so the model generalizes better. Set `0` to disable. |
| `--fine-tune-layers 60` | Unfreeze more of the backbone during phase 2 (default 40). More capacity to adapt; watch for overfitting. |
| `--epochs-head` / `--epochs-fine` | Train longer. Early-stopping restores the best epoch, so higher is usually safe. |
| `--dropout 0.4` | More regularization if train ≫ test accuracy. |
| `--no-tta` | Turn off test-time flip averaging in the reports (it's on by default — matches what the app does at inference). |

Evaluation uses **test-time augmentation** (averages the image with its mirror),
the same trick `emotion_classifier.dart` uses, so the reported numbers reflect
the real app.

### Proof-of-training reports (great for your paper)

After training, `training/output/reports/` will contain:

| File | What it shows |
|---|---|
| `training_history.png` | Accuracy & loss per epoch (train vs validation — 10% held out of train; the test set is only used for the final report), with a marker where fine-tuning starts — proves the model actually learned and converged. |
| `confusion_matrix.png` | Raw counts: which emotion got predicted as which. |
| `confusion_matrix_normalized.png` | Row-normalized (diagonal = recall per emotion) — the clearest "how good per class" picture. |
| `confusion_matrix.csv` | The same matrix as numbers, to drop into Excel/LaTeX. |
| `classification_report.txt` | Overall accuracy, **top-2 accuracy**, macro/weighted F1, **macro ROC-AUC**, and precision/recall/F1/**AUC** per emotion. |
| `roc_curves.png` | One-vs-rest ROC curve per emotion with AUC — a standard paper figure. |
| `per_class_f1.png`, `per_class_recall.png` | Bar charts per emotion. |
| `before_after_testset.png` + `.txt` | **Before vs after retraining** on the same test set: old model vs new, per emotion + overall, with the change. The key "it got better" figure. |
| `before_after_myface.png` | Before vs after on **your own** face, per emotion (if you added `myface_*` images). |
| `myface_accuracy.png` | New-model accuracy on your own face (shown instead of the before/after version when no baseline is available). |
| `summary_dashboard.png` | **One page** combining training curves, confusion matrix, per-class F1, and before/after — drop this straight into your report. |

**How the before/after works:** at the start of the run the script reads the
`model.tflite` currently in `meds_app/assets` (your *old* model) into memory
*before* it gets overwritten, runs it on the same test set, and handles its
different label order automatically. Options:
- `--no-baseline` — skip the comparison.
- `--baseline path\to\old.tflite --baseline-labels path\to\labels.txt` — compare
  against a specific model instead. To always compare against your *original*
  model (useful on the 2nd+ retrain, since the default compares against whatever
  is currently installed), point at the backups made for you:
  `--baseline output_model_backup_20260827.tflite --baseline-labels output_labels_backup_20260827.txt`

> **Speed:** on a CPU this can take a while (large dataset). If it's too slow,
> use `--subset 0.5`, or train on Google Colab's free GPU (upload the dataset as
> a zip, run the same script).

### ⚠️ Laptop crashing / freezing / shutting off during training?

That's almost always **overheating**, not a bug: training pins all your CPU
cores at 100% for a long time and the laptop thermally shuts down. Fixes:

- **Use the safe preset** (recommended first try) — caps CPU to 4 threads, uses a
  quarter of the data, fewer epochs, so it runs cool and finishes quickly:
  ```
  python train_meds.py --safe
  ```
- **Cap threads only**, keep all the data (slower but cooler than default):
  ```
  python train_meds.py --threads 4
  ```
- Keep the laptop on a hard, flat surface (not a bed/lap), plugged into power,
  and let it cool between runs.
- **Best option for a full-quality run: Google Colab's free GPU** — it never
  touches your laptop's heat/CPU and trains far faster. Ask me and I'll hand you
  a ready Colab notebook.

Do a `--safe` run first to confirm the whole pipeline works end-to-end on your
machine before attempting anything heavier.

## 4. Put it in the app

The scripts already copy the files into `meds_app/assets/`. Just rebuild:

```powershell
cd ..\meds_app
flutter clean
flutter pub get
flutter run
```

## 5. Voice model (the "Are you OK?" check-in)

During a live session the mic button asks "Are you OK?", records a 3-second
answer, and judges the *tone* (not the words, so Malay or English both work).
The result is blended into the face emotion for ~20 s, and if the face looks
fine but the voice sounds clearly negative the live insight says so.

**Data** (free for non-commercial use), unpacked into `../voice_data/`:

| Folder | Dataset | Clips | Licence |
|---|---|---|---|
| `ravdess/` | RAVDESS speech audio (zenodo.org/records/1188976) | 1,440, 24 actors | CC BY-NC-SA 4.0 |
| `cremad/AudioWAV/` | CREMA-D (github.com/CheyneyComputerScience/CREMA-D, git-lfs) | 7,442, 91 actors | ODbL |
| `tess/` | TESS (borealisdata.ca, doi:10.5683/SP2/E8H2MF) | 2,800, 2 speakers | CC BY-NC-ND 4.0 |

```powershell
python train_voice.py                              # ~1 h on CPU
python train_voice.py --subset 0.3 --epochs 3      # quick trial
```

Writes `voice_model.tflite` + `voice_labels.txt` into `../meds_app/assets/`
and reports into `output_voice/reports/`. The test set is **different
speakers** from training (RAVDESS actors 21–24, CREMA-D actors with id % 7 == 0),
so the score shows how it does on a voice it has never heard. The first run
caches the audio in `../voice_data/cache_16k.npz`; delete it after adding data.

`trim()` / `prepare()` in `train_voice.py` must stay identical to
`trimSilence()` / `fitToClip()` in `meds_app/lib/services/voice_classifier.dart`
(`test/voice_check_in_test.dart` checks they agree).

## Notes
- **No Dart changes needed.** Input size (224), normalization (`[-1,1]`), and
  softmax output all match the existing `emotion_classifier.dart`.
- `labels.txt` is rewritten in the model's real output order
  (`angry, disgust, fear, happy, neutral, sad, surprise`). Keep both files together.
- To undo your face additions later: `python add_my_face.py --reset`
- Your old model is at `meds_app/assets/model.tflite` — back it up first if you
  want to keep it (`copy ..\meds_app\assets\model.tflite model_backup.tflite`).
