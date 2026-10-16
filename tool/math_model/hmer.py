"""A from-scratch re-implementation of the CoMER architecture (also TAMER's,
which shares it), for inference only, without padding masks (one image at a
time). Loads the published weights with torch's safe, tensors-only loader.

Two forms:
  * Model.encode(img) -> memory [1, T, D], (h, w)
  * Model.decode_full(memory, hw, tokens [B, L]) -> logits [B, L, V]   (reference)
  * Step decoder (StepDecoder) with caches, for export and beam search.
"""
import math
import os

import torch
import torch.nn as nn
import torch.nn.functional as F

D, H, HD, DC = 256, 8, 32, 32


class Bottleneck(nn.Module):
    def __init__(self, c, g):
        super().__init__()
        self.bn1 = nn.BatchNorm2d(4 * g)
        self.conv1 = nn.Conv2d(c, 4 * g, 1, bias=False)
        self.bn2 = nn.BatchNorm2d(g)
        self.conv2 = nn.Conv2d(4 * g, g, 3, padding=1, bias=False)

    def forward(self, x):
        out = F.relu(self.bn1(self.conv1(x)))
        out = F.relu(self.bn2(self.conv2(out)))
        return torch.cat((x, out), 1)


class Transition(nn.Module):
    def __init__(self, c, o):
        super().__init__()
        self.bn1 = nn.BatchNorm2d(o)
        self.conv1 = nn.Conv2d(c, o, 1, bias=False)

    def forward(self, x):
        return F.avg_pool2d(F.relu(self.bn1(self.conv1(x))), 2, ceil_mode=True)


class DenseNet(nn.Module):
    def __init__(self, g=24, n=16):
        super().__init__()
        c = 2 * g
        self.conv1 = nn.Conv2d(1, c, 7, padding=3, stride=2, bias=False)
        self.norm1 = nn.BatchNorm2d(c)
        self.dense1 = nn.Sequential(*[Bottleneck(c + i * g, g) for i in range(n)])
        c += n * g
        o = c // 2
        self.trans1 = Transition(c, o)
        c = o
        self.dense2 = nn.Sequential(*[Bottleneck(c + i * g, g) for i in range(n)])
        c += n * g
        o = c // 2
        self.trans2 = Transition(c, o)
        c = o
        self.dense3 = nn.Sequential(*[Bottleneck(c + i * g, g) for i in range(n)])
        self.out_channels = c + n * g
        self.post_norm = nn.BatchNorm2d(self.out_channels)

    def forward(self, x):
        x = F.relu(self.norm1(self.conv1(x)))
        x = F.max_pool2d(x, 2, ceil_mode=True)
        x = self.trans1(self.dense1(x))
        x = self.trans2(self.dense2(x))
        return self.post_norm(self.dense3(x))


def img_pos(h, w, d=D):
    """ImgPosEnc(normalize=True) for an unpadded h x w feature map: [h, w, d]."""
    half = d // 2
    ys = torch.arange(1, h + 1, dtype=torch.float32)
    xs = torch.arange(1, w + 1, dtype=torch.float32)
    ys = ys / (ys[-1] + 1e-6) * 2 * math.pi
    xs = xs / (xs[-1] + 1e-6) * 2 * math.pi
    dim_t = torch.arange(0, half, 2, dtype=torch.float32)
    inv = 1.0 / (10000.0 ** (dim_t / half))
    px = xs[:, None] * inv[None, :]  # [w, 64]
    py = ys[:, None] * inv[None, :]  # [h, 64]
    px = torch.stack((px.sin(), px.cos()), dim=2).flatten(1)  # [w, 128]
    py = torch.stack((py.sin(), py.cos()), dim=2).flatten(1)  # [h, 128]
    return torch.cat((px[None, :, :].expand(h, w, half), py[:, None, :].expand(h, w, half)), dim=2)


class Encoder(nn.Module):
    def __init__(self):
        super().__init__()
        self.model = DenseNet()
        self.feature_proj = nn.Conv2d(self.model.out_channels, D, 1)
        self.norm = nn.LayerNorm(D)

    def forward(self, img):
        f = self.feature_proj(self.model(img))  # [1, D, h, w]
        h, w = f.shape[2], f.shape[3]
        f = f.permute(0, 2, 3, 1) + img_pos(h, w)[None]
        return self.norm(f)  # [1, h, w, D]


class MHA(nn.Module):
    def __init__(self):
        super().__init__()
        self.in_proj_weight = nn.Parameter(torch.empty(3 * D, D))
        self.in_proj_bias = nn.Parameter(torch.empty(3 * D))
        self.out_proj = nn.Linear(D, D)


class BN1(nn.Module):
    def __init__(self):
        super().__init__()
        self.bn = nn.BatchNorm1d(H)


class ARM(nn.Module):
    def __init__(self):
        super().__init__()
        self.conv = nn.Conv2d(2 * H, DC, 5, padding=2)
        self.proj = nn.Conv2d(DC, H, 1, bias=False)
        self.post_norm = BN1()

    def coverage(self, cov_in, h, w):
        """cov_in: [N, 2H, T] summed attention -> [N, H, T]."""
        n = cov_in.shape[0]
        x = cov_in.reshape(n, 2 * H, h, w)
        x = self.proj(F.relu(self.conv(x)))
        bn = self.post_norm.bn
        x = (x - bn.running_mean[None, :, None, None]) / torch.sqrt(bn.running_var[None, :, None, None] + bn.eps)
        x = x * bn.weight[None, :, None, None] + bn.bias[None, :, None, None]
        return x.reshape(n, H, h * w)


class Layer(nn.Module):
    def __init__(self):
        super().__init__()
        self.self_attn = MHA()
        self.multihead_attn = MHA()
        self.linear1 = nn.Linear(D, 1024)
        self.linear2 = nn.Linear(1024, D)
        self.norm1 = nn.LayerNorm(D)
        self.norm2 = nn.LayerNorm(D)
        self.norm3 = nn.LayerNorm(D)


class TD(nn.Module):
    def __init__(self):
        super().__init__()
        self.layers = nn.ModuleList([Layer() for _ in range(3)])
        self.arm = ARM()


class Decoder(nn.Module):
    def __init__(self, vocab_size):
        super().__init__()
        self.word_embed = nn.Sequential(nn.Embedding(vocab_size, D), nn.LayerNorm(D))
        pe = torch.zeros(500, D)
        position = torch.arange(0, 500, dtype=torch.float)
        div = 1.0 / (10000.0 ** (torch.arange(0, D, 2, dtype=torch.float) / D))
        f = position[:, None] * div[None, :]
        pe[:, 0::2] = f.sin()
        pe[:, 1::2] = f.cos()
        self.pos_pe = pe  # also stored in the checkpoint as pos_enc.pe
        self.norm = nn.LayerNorm(D)
        self.model = TD()
        self.proj = nn.Linear(D, vocab_size)


class Model(nn.Module):
    def __init__(self, vocab_size):
        super().__init__()
        self.encoder = Encoder()
        self.decoder = Decoder(vocab_size)

    # ---- reference full-sequence decoder (teacher forced) ----
    def decode_full(self, mem, hw, tokens):
        """mem [1, T, D]; tokens [B, L] -> logits [B, L, V]."""
        h, w = hw
        dec = self.decoder
        B, L = tokens.shape
        x = dec.norm(dec.word_embed(tokens) + dec.pos_pe[:L][None])
        causal = torch.ones(L, L, dtype=torch.bool).triu(1)
        prev = None
        for i, layer in enumerate(dec.model.layers):
            sa = layer.self_attn
            q, k, v = F.linear(x, sa.in_proj_weight, sa.in_proj_bias).chunk(3, dim=-1)
            q = q.view(B, L, H, HD).transpose(1, 2) * HD ** -0.5
            k = k.view(B, L, H, HD).transpose(1, 2)
            v = v.view(B, L, H, HD).transpose(1, 2)
            a = (q @ k.transpose(-1, -2)).masked_fill(causal, float('-inf')).softmax(-1)
            o = (a @ v).transpose(1, 2).reshape(B, L, D)
            x = layer.norm1(x + sa.out_proj(o))

            ca = layer.multihead_attn
            W, bb = ca.in_proj_weight, ca.in_proj_bias
            q = F.linear(x, W[:D], bb[:D]).view(B, L, H, HD).transpose(1, 2) * HD ** -0.5
            k = F.linear(mem, W[D:2 * D], bb[D:2 * D]).view(1, -1, H, HD).transpose(1, 2)
            v = F.linear(mem, W[2 * D:], bb[2 * D:]).view(1, -1, H, HD).transpose(1, 2)
            dots = q @ k.transpose(-1, -2)  # [B, H, L, T]
            att = dots.softmax(-1)
            if prev is not None:
                both = torch.cat((prev, att), dim=1)  # [B, 2H, L, T]
                both = both.cumsum(dim=2) - both
                T = both.shape[-1]
                cin = both.permute(0, 2, 1, 3).reshape(B * L, 2 * H, T)
                cov = dec.model.arm.coverage(cin, h, w).reshape(B, L, H, T).permute(0, 2, 1, 3)
                att = (dots - cov).softmax(-1)
            prev = att
            o = (att @ v).transpose(1, 2).reshape(B, L, D)
            x = layer.norm2(x + ca.out_proj(o))
            x = layer.norm3(x + layer.linear2(F.relu(layer.linear1(x))))
        return dec.proj(x)


def load(path, vocab_size):
    class _Callback:
        pass

    with torch.serialization.safe_globals([(_Callback, 'pytorch_lightning.callbacks.model_checkpoint.ModelCheckpoint')]):
        state = torch.load(path, map_location='cpu', weights_only=True)
    sd = state['state_dict']
    prefix = next(p for p in ('comer_model.', 'tamer_model.') if any(k.startswith(p) for k in sd))
    sd = {k[len(prefix):]: v for k, v in sd.items() if k.startswith(prefix)}
    sd = {k: v for k, v in sd.items() if 'struct_sim' not in k}
    pe = sd.pop('decoder.pos_enc.pe', None)
    m = Model(vocab_size)
    missing, unexpected = m.load_state_dict(sd, strict=False)
    missing = [k for k in missing if 'num_batches_tracked' not in k]
    assert not missing and not unexpected, (missing, unexpected)
    if pe is not None:
        m.decoder.pos_pe = pe
    m.eval()
    return m


def read_vocab(dict_path):
    words = ['<pad>', '<sos>', '<eos>']
    with open(dict_path, encoding='utf-8') as f:
        lines = f.read().splitlines()
    if lines and lines[-1] == '':
        lines = lines[:-1]
    words += [l.strip() for l in lines]
    return words
