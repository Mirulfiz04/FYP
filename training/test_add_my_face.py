"""Self-check for the selfie train/test split.  Run:  python test_add_my_face.py"""
import os
import tempfile

from add_my_face import burst_key, split_burst, unique_files

# capture order: first burst, then the browser's "(1)" re-download burst
names = ["happy_0002.jpg", "happy_0001 (1).jpg", "happy_0001.jpg", "happy_0002 (1).jpg"]
assert sorted(names, key=burst_key) == [
    "happy_0001.jpg", "happy_0002.jpg", "happy_0001 (1).jpg", "happy_0002 (1).jpg"]

files = [f"sad_{i:04d}.jpg" for i in range(100, 0, -1)]  # shuffled order on purpose
train, test = split_burst(files, 0.15, gap=3)
assert test == [f"sad_{i:04d}.jpg" for i in range(86, 101)]  # last 15 frames
assert train == [f"sad_{i:04d}.jpg" for i in range(1, 83)]   # 83-85 dropped as gap
assert not set(train) & set(test)

with tempfile.TemporaryDirectory() as d:
    paths = []
    for name, data in (("a.jpg", b"x"), ("a (1).jpg", b"x"), ("b.jpg", b"y")):
        paths.append(os.path.join(d, name))
        with open(paths[-1], "wb") as fh:
            fh.write(data)
    assert unique_files(paths) == [paths[0], paths[2]]

print("ok")
