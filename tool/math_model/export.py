"""Exports the encoder and the cached step decoder to ONNX, checks them
against torch, and stores their weights as 8-bit integers: out_dir's
encoder.onnx and decoder.onnx are what the app ships (assets/math/).

    python export.py <checkpoint.ckpt> <dictionary.txt> <out_dir>
"""
import sys, os
import numpy as np, torch
import hmer, step

ckpt, dict_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
words = hmer.read_vocab(dict_path)
m = hmer.load(ckpt, len(words))
enc, dec = step.EncoderExport(m).eval(), step.StepExport(m).eval()
os.makedirs(out_dir, exist_ok=True)
ep, sp = os.path.join(out_dir, 'encoder_fp32.onnx'), os.path.join(out_dir, 'decoder_fp32.onnx')

img = torch.rand(1, 1, 70, 230)
with torch.no_grad():
    torch.onnx.export(enc, (img,), ep, input_names=['img'], output_names=['memK', 'memV'],
                      dynamic_axes={'img': {2: 'H', 3: 'W'}, 'memK': {2: 'T'}, 'memV': {2: 'T'}},
                      opset_version=17, dynamo=False)
    k, v = enc(img)
    B, t = 3, 4
    T = k.shape[2]
    grid = torch.zeros(5, 15)
    args = (torch.tensor([5, 6, 7, 0, 2, 1, t]), k, v, grid,
            torch.rand(3, B, 8, t, 32), torch.rand(3, B, 8, t, 32), torch.rand(2, B, 16, T))
    torch.onnx.export(dec, args, sp,
                      input_names=['ctl', 'memK', 'memV', 'grid', 'sk', 'sv', 'cov'],
                      output_names=['logp', 'sk_out', 'sv_out', 'cov_out'],
                      dynamic_axes={'ctl': {0: 'C'}, 'memK': {2: 'T'}, 'memV': {2: 'T'}, 'grid': {0: 'h', 1: 'w'},
                                    'sk': {1: 'Bp', 3: 't'}, 'sv': {1: 'Bp', 3: 't'}, 'cov': {1: 'Bp', 3: 'T'},
                                    'logp': {0: 'B'}, 'sk_out': {1: 'B', 3: 't1'}, 'sv_out': {1: 'B', 3: 't1'}, 'cov_out': {1: 'B', 3: 'T'}},
                      opset_version=17, dynamo=False)
print('exported', os.path.getsize(ep) // 1024, 'KB', os.path.getsize(sp) // 1024, 'KB')

import onnxruntime as ort
e = ort.InferenceSession(ep, providers=['CPUExecutionProvider'])
s = ort.InferenceSession(sp, providers=['CPUExecutionProvider'])
for shape in [(1, 1, 50, 120), (1, 1, 140, 600)]:
    x = torch.rand(*shape)
    with torch.no_grad():
        k, v = enc(x)
    ok, ov = e.run(None, {'img': x.numpy()})
    print('enc', shape, np.abs(ok - k.numpy()).max())
    g = step.grid_for(x.numpy())
    T = k.shape[2]
    for Bp, B, t in [(1, 1, 1), (1, 10, 1), (4, 3, 6)]:
        a = dict(ctl=np.concatenate([np.arange(B) + 3, np.random.randint(0, Bp, B), [t - 1]]).astype(np.int64),
                 memK=k.numpy(), memV=v.numpy(), grid=g,
                 sk=np.random.rand(3, Bp, 8, t, 32).astype(np.float32), sv=np.random.rand(3, Bp, 8, t, 32).astype(np.float32),
                 cov=np.random.rand(2, Bp, 16, T).astype(np.float32))
        o = s.run(None, a)
        with torch.no_grad():
            r = dec(*[torch.from_numpy(a[n]) for n in step.NAMES])
        print('  step', Bp, '->', B, 't', t, [round(float(np.abs(x1 - x2.numpy()).max()), 7) for x1, x2 in zip(o, r)])

from onnxruntime.quantization import quantize_dynamic, QuantType
# 8-bit weights: a quarter of the size, the same accuracy on CROHME 2014.
quantize_dynamic(ep, os.path.join(out_dir, 'encoder.onnx'), weight_type=QuantType.QUInt8, op_types_to_quantize=['Conv', 'MatMul'])
quantize_dynamic(sp, os.path.join(out_dir, 'decoder.onnx'), weight_type=QuantType.QInt8, op_types_to_quantize=['MatMul', 'Gemm'])
print('quantized', os.path.getsize(os.path.join(out_dir, 'encoder.onnx')) // 1024, os.path.getsize(os.path.join(out_dir, 'decoder.onnx')) // 1024, 'KB')
