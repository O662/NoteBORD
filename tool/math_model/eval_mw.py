"""Scores the ONNX model on MathWriting's human-written samples whose symbols
are all in the model's vocabulary, rendering the pen strokes ourselves."""
import glob, sys, time
import numpy as np
import hmer, step, render
from PIL import Image

words = hmer.read_vocab(sys.argv[1])
r = step.onnx_runner(sys.argv[2], sys.argv[3])
files = sorted(glob.glob(sys.argv[4] + '/**/*.inkml', recursive=True))
vocab = set(words)
alias = {'log': '\log', 'sin': '\sin', 'cos': '\cos', 'tan': '\tan', 'lim': '\lim'}
samples = []
for f in files:
    if 'synthetic' in f or 'symbols' in f:
        continue
    label, strokes = render.read_inkml(f)
    if not label:
        continue
    toks = render.tokens(label)
    # MathWriting writes log/sin/lim as letters in normalized labels.
    joined = render.norm(toks)
    if all(t in vocab or t in '{}' for t in toks):
        samples.append((f, label, strokes))
print(len(samples), 'usable samples of', len(files))
configs = [tuple(map(float, c.split(','))) for c in sys.argv[5:]] or [(30, 3)]
for sym, lw in configs:
    ok = 0; t0 = time.time()
    for j, (f, label, strokes) in enumerate(samples):
        img = render.render(strokes, sym, lw)
        if j == 0 and sym == configs[0][0]:
            Image.fromarray((img * 255).astype(np.uint8)).save('mw_sample.png')
        best, _ = step.recognize(r, img[None, None])
        pred = [words[t] for t in best]
        good = render.norm(pred) == render.norm(render.tokens(label))
        ok += good
    print(f'symbol {sym} line {lw}: {ok}/{len(samples)} = {ok / len(samples):.3f}  ({(time.time() - t0) / len(samples):.2f}s each)', flush=True)
