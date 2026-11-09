"""Self-check for the training-only SpecAugment layer.  Run:  python test_train_voice.py"""
import numpy as np
import tensorflow as tf

from train_voice import N_MELS, T_FRAMES, SpecAugment

tf.random.set_seed(0)
x = np.random.default_rng(0).normal(1, 1, (4, T_FRAMES, N_MELS)).astype(np.float32)
aug = SpecAugment()

assert np.array_equal(aug(x, training=False).numpy(), x)   # inference/TFLite path untouched
y = aug(x, training=True).numpy()
changed = y != x
assert changed.any() and np.all(y[changed] == 0), "masks may only blank values"
assert changed.mean() < 0.5, changed.mean()                 # most of each clip survives
print("ok")
