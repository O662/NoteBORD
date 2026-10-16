# The handwritten math model

Math mode reads handwriting with **CoMER** (Zhao and Gao, ECCV 2022), run on the device by ONNX Runtime. It needs no network and no account, and there is nothing to pay for. The app ships it as `assets/math/encoder.onnx` and `assets/math/decoder.onnx` (7.3 MB together).

These scripts rebuild those files from the published checkpoint, and measure the model. They are only for whoever maintains the model; the app doesn't run them.

## How the app uses it

1. **Draw** (`lib/math/ink_image.dart`, ported from `render.py`). The pen strokes are drawn the way CROHME's training images look: white ink on black, 3 px lines, writing about 30 px tall, at most 256 × 1024 px.
2. **Encode** (`encoder.onnx`). `img [1, 1, H, W]` becomes the attention keys and values for each of the decoder's 3 layers: `memK`, `memV [3, 8, T, 32]`, where T = ⌈H/16⌉·⌈W/16⌉.
3. **Decode, one token at a time** (`decoder.onnx`).
   - **Input `ctl`:** the tokens, the cache row each continues, and the position.
   - **Input `grid`:** a zero tensor whose shape is the feature map's, ⌈H/16⌉ × ⌈W/16⌉.
   - **The caches:** `sk`/`sv` (self-attention) and `cov` (CoMER's coverage), which go back in on the next step. They stay as native tensors and the model reorders them itself, so only the log-probabilities come back to Dart.
   - **Cache slot 0:** a dummy that is never attended to, so no tensor is ever empty.
4. **Search** (`lib/math/decoder.dart`, ported from `step.py`).
   - Beam search (10 wide) runs left-to-right and right-to-left in the same steps.
   - The other direction rescores each answer, as in the paper.
   - Tokens become LaTeX in `lib/math/latex.dart`.

## Accuracy

These figures were measured with `eval_crohme.py` and `eval_mw.py`; ExpRate means the whole expression is right.

| Test | ExpRate |
|---|---|
| CROHME 2014, all 986 expressions, full-precision ONNX | 62.9% (the paper: 59.3%) |
| CROHME 2014, 300 expressions, 8-bit model (as shipped) | 62.0% (full precision: 62.3%) |
| MathWriting excerpt, real pen strokes drawn by `render.py`, 89 expressions in the model's symbols | 36% |

MathWriting is much harder than everyday notes: long Wikipedia formulas, words like `mod`, and p/P, c/C and l/1 that only context tells apart.

The model knows CROHME's 101 symbols:
- the digits and Latin letters (but not every capital: no D, J, K, O, Q, U, W or Z);
- the Greek letters α β γ θ λ μ π σ φ Δ Π;
- `\frac`, `\sqrt`, `\int`, `\sum` and `\lim`, `\sin` `\cos` `\tan` `\log`, `\infty`, `\rightarrow`, `\leq` `\geq` `\neq` `\pm` `\times` `\div`, `\exists` `\forall` `\in`;
- brackets.

There are no matrices, and no ω, ρ, τ or ∂. Those are typed with the math keyboard.

## Licence: personal, non-commercial use

The CoMER repository has no licence file, and its checkpoint was trained on CROHME, which is CC BY-NC-SA 3.0. Every openly available handwritten-math model checked (CoMER, TAMER, PosFormer, BTTR's data) has the same restriction. See `assets/math/NOTICE.txt`.

Before Endless is sold, replace the model with one trained on data whose licence allows it. The app only needs two ONNX files with the inputs and outputs above, and the vocabulary in `lib/math/decoder.dart`. A model with a different vocabulary also needs that list changed, and `mathModelVersion` in `lib/math/onnx_math.dart` bumped.

## Rebuilding the model

You need Python 3.11 with `torch` (CPU is enough), `onnx`, `onnxruntime`, `numpy` and `pillow`. On Windows, make the virtual environment in a short path (for example `%TEMP%\hm`): some of torch's file paths are too long otherwise.

```sh
git clone --depth 1 https://github.com/Green-Wood/CoMER.git
python export.py "CoMER/lightning_logs/version_0/checkpoints/epoch=151-step=57151-val_ExpRate=0.6365.ckpt" \
                 CoMER/comer/datamodule/dictionary.txt out
cp out/encoder.onnx out/decoder.onnx ../../assets/math/
```

`hmer.py` is a fresh implementation of the network, inference only. It loads the checkpoint with `torch.load(weights_only=True)`, so no code in the downloaded file runs, and nothing from the CoMER repository is imported.

## Measuring

```sh
python eval_crohme.py <ckpt> <dictionary.txt> CoMER/data.zip 986 onnx out/encoder.onnx out/decoder.onnx
python eval_mw.py <dictionary.txt> out/encoder.onnx out/decoder.onnx <mathwriting-2024-excerpt> 30,3
```

The MathWriting excerpt (1.5 MB) is at <https://storage.googleapis.com/mathwriting_data/mathwriting-2024-excerpt.tgz>; it is CC BY-NC-SA 4.0.

## Test fixtures

`make_fixtures.py` writes `test/fixtures/math/ink_samples.json`. For six MathWriting samples, it holds:
- the pen strokes;
- the picture `render.py` draws, as packed bits;
- what the model reads.

`test/math/math_engine_test.dart` checks the Dart renderer against those pictures, pixel for pixel. `integration_test/math_model_test.dart` checks that the shipped model, run through the Flutter plugin, reads them the same way:

```sh
flutter test integration_test/math_model_test.dart -d windows
```
