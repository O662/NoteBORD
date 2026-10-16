"""Pen-stroke samples for the app's tests: strokes, the picture our renderer
draws (as packed bits) and what the ONNX model reads."""
import base64, glob, json, sys
import numpy as np
import hmer, step, render

words = hmer.read_vocab(sys.argv[1])
r = step.onnx_runner(sys.argv[2], sys.argv[3])
out_path = sys.argv[5]
vocab = set(words)
picked = []
for f in sorted(glob.glob(sys.argv[4] + '/**/*.inkml', recursive=True)):
    if 'synthetic' in f or 'symbols' in f: continue
    label, strokes = render.read_inkml(f)
    toks = render.tokens(label)
    if not all(t in vocab or t in '{}' for t in toks) or len(toks) > 14: continue
    img = render.render(strokes)
    best, allh = step.recognize(r, img[None, None])
    pred = [words[t] for t in best]
    if render.norm(pred) != render.norm(toks): continue
    bits = np.packbits(img.astype(np.uint8).reshape(-1))
    picked.append({
        'label': label,
        'strokes': [[[round(x, 2), round(y, 2)] for x, y in s] for s in strokes],
        'width': int(img.shape[1]), 'height': int(img.shape[0]),
        'bits': base64.b64encode(bits.tobytes()).decode(),
        'read': pred,
        'score': float(allh[0][1]),
    })
    if len(picked) == 6: break
json.dump(picked, open(out_path, 'w'), indent=0)
for p in picked: print(p['label'], '|', ' '.join(p['read']), p['width'], p['height'], len(p['strokes']))
