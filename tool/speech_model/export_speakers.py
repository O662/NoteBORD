"""Exports the speaker model Endless uses to tell voices apart.

SpeechBrain's ECAPA-TDNN speaker embedding, trained on VoxCeleb
(speechbrain/spkrec-ecapa-voxceleb on Hugging Face, Apache-2.0), becomes one
ONNX file that takes 16 kHz mono audio and gives a 192-number voice print:

    audio [1, samples] float32  ->  embedding [1, 192] float32

SpeechBrain computes its filterbank features with a complex STFT, which
ONNX can't export, so this script computes the same features with real
matrix products (the DFT as two convolutions) and checks that the result
matches SpeechBrain's own, then that ONNX Runtime matches PyTorch.

Run (Python 3.11, in a fresh virtual environment):

    pip install torch==2.5.1 torchaudio==2.5.1 --index-url https://download.pytorch.org/whl/cpu
    pip install speechbrain==1.0.3 huggingface_hub==0.25.2 requests onnx==1.17.0 onnxruntime==1.20.1
    python tool/speech_model/export_speakers.py --out assets/speech --work <a temp folder>

It downloads the checkpoint at a pinned revision and checks its SHA-256.
"""

import argparse
import hashlib
import math
import os
import sys

import numpy as np
import torch

REPO = 'speechbrain/spkrec-ecapa-voxceleb'
REVISION = '0f99f2d0ebe89ac095bcc5903c4dd8f72b367286'
CHECKPOINT_SHA256 = '0575cb64845e6b9a10db9bcb74d5ac32b326b8dc90352671d345e2ee3d0126a2'


class Features(torch.nn.Module):
    """SpeechBrain's Fbank (n_fft 400, hop 160, Hamming, centred with zeros,
    80 mel bands, power in dB with top_db 80) without complex numbers,
    followed by the sentence mean normalisation the model expects."""

    def __init__(self, fbank):
        super().__init__()
        stft = fbank.compute_STFT
        n_fft, self.hop = stft.n_fft, stft.hop_length
        win = stft.window.float()
        if win.numel() < n_fft:  # a shorter window is centred in the frame
            left = (n_fft - win.numel()) // 2
            win = torch.nn.functional.pad(win, (left, n_fft - win.numel() - left))
        k = torch.arange(n_fft // 2 + 1).float()[:, None]
        n = torch.arange(n_fft).float()[None, :]
        angle = 2 * math.pi * k * n / n_fft
        self.register_buffer('cos', (torch.cos(angle) * win)[:, None, :])
        self.register_buffer('sin', (-torch.sin(angle) * win)[:, None, :])
        self.pad = n_fft // 2
        fb = fbank.compute_fbanks
        self.register_buffer('mel', self._mel_matrix(fb).float())
        self.multiplier = float(fb.multiplier)
        self.amin = float(fb.amin)
        self.ref = float(fb.ref_value)
        self.top_db = float(fb.top_db)

    @staticmethod
    def _mel_matrix(fb):
        # The filterbank matrix as SpeechBrain builds it in forward().
        f_central_mat = fb.f_central.repeat(fb.all_freqs_mat.shape[1], 1).transpose(0, 1)
        band_mat = fb.band.repeat(fb.all_freqs_mat.shape[1], 1).transpose(0, 1)
        return fb._create_fbank_matrix(f_central_mat, band_mat)

    def forward(self, wav):  # [1, T]
        x = torch.nn.functional.pad(wav[:, None, :], (self.pad, self.pad))
        re = torch.nn.functional.conv1d(x, self.cos, stride=self.hop)
        im = torch.nn.functional.conv1d(x, self.sin, stride=self.hop)
        power = (re * re + im * im).transpose(1, 2)  # [1, frames, bins]
        mel = torch.matmul(power, self.mel)
        db = self.multiplier * torch.log10(torch.clamp(mel, min=self.amin))
        db = db - self.multiplier * math.log10(max(self.amin, self.ref))
        floor = db.amax(dim=(1, 2), keepdim=True) - self.top_db
        db = torch.maximum(db, floor)
        return db - db.mean(dim=1, keepdim=True)


class SpeakerPrint(torch.nn.Module):
    def __init__(self, enc):
        super().__init__()
        self.features = Features(enc.mods.compute_features)
        self.model = enc.mods.embedding_model

    def forward(self, wav):
        return self.model(self.features(wav)).squeeze(1)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', required=True)
    ap.add_argument('--work', required=True)
    args = ap.parse_args()

    from speechbrain.inference.speaker import EncoderClassifier

    src = os.path.join(args.work, 'ecapa_src')
    enc = EncoderClassifier.from_hparams(source=REPO, savedir=src, revision=REVISION, run_opts={'device': 'cpu'})
    ckpt = os.path.join(src, 'embedding_model.ckpt')
    got = sha256(os.path.realpath(ckpt))
    if got != CHECKPOINT_SHA256:
        sys.exit(f'embedding_model.ckpt has SHA-256 {got}, expected {CHECKPOINT_SHA256}')
    enc.eval()

    cf = enc.mods.compute_features
    assert not cf.deltas and not cf.context, 'unexpected feature settings'
    norm = enc.mods.mean_var_norm
    assert norm.norm_type == 'sentence' and not norm.std_norm, 'unexpected normalisation'

    torch.manual_seed(0)
    model = SpeakerPrint(enc).eval()
    # Speech-like test audio: noise shaped by a few formants, 3 s.
    t = torch.arange(48000) / 16000
    wav = (0.1 * torch.randn(1, 48000) + 0.2 * torch.sin(2 * math.pi * 180 * t) * torch.sin(2 * math.pi * 3 * t)).float()
    with torch.no_grad():
        ours = model.features(wav)
        theirs = norm(cf(wav), torch.ones(1))
        diff = (ours - theirs).abs().max().item()
        print(f'features: max difference {diff:.2e}')
        assert diff < 1e-3, 'features differ from SpeechBrain'
        ref = enc.encode_batch(wav).squeeze(1)
        mine = model(wav)
        cos = torch.nn.functional.cosine_similarity(ref, mine).item()
        print(f'embedding: cosine with SpeechBrain {cos:.6f}')
        assert cos > 0.9999

    os.makedirs(args.out, exist_ok=True)
    fp32 = os.path.join(args.work, 'speakers_fp32.onnx')
    torch.onnx.export(
        model, (wav,), fp32, input_names=['audio'], output_names=['embedding'],
        dynamic_axes={'audio': {1: 'samples'}}, opset_version=17, do_constant_folding=True)

    import onnxruntime as ort
    from onnxruntime.quantization import QuantType, quantize_dynamic

    out = os.path.join(args.out, 'speakers.onnx')
    # Only the network's weights become 8-bit; the features (the DFT and the
    # mel filters) stay exact.
    import onnx
    keep = [n.name for n in onnx.load(fp32).graph.node if n.name.startswith('/features/')]
    quantize_dynamic(fp32, out, weight_type=QuantType.QUInt8, nodes_to_exclude=keep)

    for path, label in [(fp32, 'fp32'), (out, 'int8')]:
        sess = ort.InferenceSession(path, providers=['CPUExecutionProvider'])
        for n in (16000, 48000, 160000):
            w = wav[:, :n] if n <= wav.shape[1] else wav.repeat(1, math.ceil(n / wav.shape[1]))[:, :n]
            with torch.no_grad():
                expect = model(w).numpy()
            got = sess.run(None, {'audio': w.numpy()})[0]
            c = float(np.dot(expect[0], got[0]) / (np.linalg.norm(expect[0]) * np.linalg.norm(got[0])))
            print(f'{label} onnx, {n / 16000:.0f} s: cosine with PyTorch {c:.5f}')
            assert c > (0.9999 if label == 'fp32' else 0.98)

    print(f'{out}: {os.path.getsize(out) / 1e6:.1f} MB, SHA-256 {sha256(out)}')


if __name__ == '__main__':
    main()
