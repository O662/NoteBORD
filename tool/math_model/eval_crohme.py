"""Scores a model on a CROHME test year from CoMER's data.zip (images only)."""
import io, sys, time, zipfile
import numpy as np
import torch
from PIL import Image
import hmer, step

def load_set(zip_path, year):
    z = zipfile.ZipFile(zip_path)
    out = []
    for line in z.read(f'data/{year}/caption.txt').decode().splitlines():
        parts = line.split()
        if not parts: continue
        im = Image.open(io.BytesIO(z.read(f'data/{year}/img/{parts[0]}.bmp'))).convert('L')
        out.append((parts[0], np.asarray(im, np.float32)[None, None] / 255.0, parts[1:]))
    return out

if __name__ == '__main__':
    ckpt, dict_path, zip_path, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    mode = sys.argv[5] if len(sys.argv) > 5 else 'torch'
    words = hmer.read_vocab(dict_path)
    m = hmer.load(ckpt, len(words))
    if mode == 'torch':
        r = step.torch_runner(m)
    else:
        r = step.onnx_runner(sys.argv[6], sys.argv[7])
    data = load_set(zip_path, '2014')
    rng = np.random.default_rng(0)
    idx = rng.permutation(len(data))[:n]
    ok_bi = ok_l2r = 0
    t0 = time.time()
    for j, i in enumerate(idx):
        name, img, truth = data[i]
        best, allh = step.recognize(r, img)
        l2r_best = step.beam(r, *r.encode(img), step.SOS, step.EOS)[0][0]
        pred = [words[t] for t in best]
        ok_bi += pred == truth
        ok_l2r += [words[t] for t in l2r_best] == truth
    dt = time.time() - t0
    print(f'{n} images: bi ExpRate {ok_bi / n:.3f}, l2r-only {ok_l2r / n:.3f}, {dt / n:.2f}s/img')
