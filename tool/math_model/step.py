"""The incremental (cached) decoder, exported to ONNX, and the beam search the
app runs (mirrored later in Dart)."""
import math

import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

from hmer import D, H, HD, Model

SOS, EOS = 1, 2


class EncoderExport(nn.Module):
    """img [1, 1, Hi, Wi] -> memK [3, H, T, HD], memV [3, H, T, HD], hw [2]."""

    def __init__(self, m: Model):
        super().__init__()
        self.m = m

    def forward(self, img):
        f = self.m.encoder(img)  # [1, h, w, D]
        h, w = f.shape[1], f.shape[2]
        mem = f.reshape(1, h * w, D)
        ks, vs = [], []
        for layer in self.m.decoder.model.layers:
            W, b = layer.multihead_attn.in_proj_weight, layer.multihead_attn.in_proj_bias
            k = F.linear(mem, W[D:2 * D], b[D:2 * D]).view(-1, H, HD).transpose(0, 1)
            v = F.linear(mem, W[2 * D:], b[2 * D:]).view(-1, H, HD).transpose(0, 1)
            ks.append(k)
            vs.append(v)
        return torch.stack(ks), torch.stack(vs)


class StepExport(nn.Module):
    """One decoding step for B hypotheses.

    tok [B] int64, pos [1] int64, memK/memV [3, H, T, HD], hw [2] int64,
    sk/sv [3, B, H, t, HD] (self-attention keys and values so far),
    cov [2, B, 2H, T] (summed attention of earlier steps, for layers 1 and 2)
    -> logp [B, V], sk', sv' (t + 1), cov'
    """

    def __init__(self, m: Model):
        super().__init__()
        self.m = m

    def forward(self, ctl, memK, memV, grid, sk, sv, cov):
        # ctl: the B tokens, then the B rows of the caches they continue, then the position.
        B = (ctl.shape[0] - 1) // 2
        tok, beam_idx, pos = ctl[:B], ctl[B:2 * B], ctl[2 * B:]
        dec = self.m.decoder
        # The hypotheses continued this step: each one's caches.
        sk = sk.index_select(1, beam_idx)
        sv = sv.index_select(1, beam_idx)
        cov = cov.index_select(1, beam_idx)
        pe = dec.pos_pe.index_select(0, pos)  # [1, D]
        x = dec.norm(dec.word_embed(tok) + pe)  # [B, D]
        nsk, nsv, ncov = [], [], []
        prev = None
        h, w = grid.shape[0], grid.shape[1]
        for i, layer in enumerate(dec.model.layers):
            sa = layer.self_attn
            q, k, v = F.linear(x, sa.in_proj_weight, sa.in_proj_bias).chunk(3, dim=-1)
            q = q.view(B, H, 1, HD) * HD ** -0.5
            K = torch.cat((sk[i], k.view(B, H, 1, HD)), dim=2)
            V = torch.cat((sv[i], v.view(B, H, 1, HD)), dim=2)
            nsk.append(K)
            nsv.append(V)
            a = q @ K.transpose(-1, -2)  # [B, H, 1, t+1]
            # Slot 0 is a dummy, so a cache is never empty: never attended to.
            first = torch.zeros_like(a[..., :1]) - 1e9
            a = torch.cat((a[..., :1] + first, a[..., 1:]), dim=-1).softmax(-1)
            o = (a @ V).reshape(B, D)
            x = layer.norm1(x + sa.out_proj(o))

            ca = layer.multihead_attn
            W, bb = ca.in_proj_weight, ca.in_proj_bias
            q = F.linear(x, W[:D], bb[:D]).view(B, H, 1, HD) * HD ** -0.5
            dots = (q @ memK[i].transpose(-1, -2)[None]).squeeze(2)  # [B, H, T]
            att = dots.softmax(-1)
            if prev is not None:
                c = cov[i - 1]  # [B, 2H, T]: sums of earlier steps
                T = c.shape[-1]
                x4 = c.reshape(B, 2 * H, h, w)
                arm = dec.model.arm
                y = arm.proj(F.relu(arm.conv(x4)))
                bn = arm.post_norm.bn
                y = (y - bn.running_mean[None, :, None, None]) / torch.sqrt(bn.running_var[None, :, None, None] + bn.eps)
                y = y * bn.weight[None, :, None, None] + bn.bias[None, :, None, None]
                covv = y.reshape(B, H, T)
                ncov.append(c + torch.cat((prev, att), dim=1))
                att = (dots - covv).softmax(-1)
            prev = att
            o = (att.unsqueeze(2) @ memV[i][None]).reshape(B, D)
            x = layer.norm2(x + ca.out_proj(o))
            x = layer.norm3(x + layer.linear2(F.relu(layer.linear1(x))))
        logp = F.log_softmax(dec.proj(x), dim=-1)
        return logp, torch.stack(nsk), torch.stack(nsv), torch.stack(ncov)


def grid_for(img):
    """The encoder's feature map is ceil(H/16) x ceil(W/16)."""
    H_, W_ = img.shape[2], img.shape[3]
    return np.zeros((-(-H_ // 16), -(-W_ // 16)), np.float32)


# ----------------------------------------------------------------------------
# Beam search over a step function (numpy in / out), as the app does it: the
# caches are opaque handles passed back in, reordered by beam_idx.

NAMES = ['ctl', 'memK', 'memV', 'grid', 'sk', 'sv', 'cov']


class Runner:
    def __init__(self, enc, step):
        self.encode, self.run = enc, step


def torch_runner(m):
    e, s = EncoderExport(m), StepExport(m)

    def enc(img):
        with torch.no_grad():
            k, v = e(torch.from_numpy(img))
        return k.numpy(), v.numpy(), grid_for(img)

    def step(tok, pos, bidx, *rest):
        ctl = np.concatenate([tok, bidx, pos]).astype(np.int64)
        with torch.no_grad():
            out = s(*[torch.from_numpy(x) for x in (ctl, *rest)])
        return [o.numpy() for o in out]

    return Runner(enc, step)


def onnx_runner(enc_path, step_path, threads=4):
    import onnxruntime as ort
    so = ort.SessionOptions()
    so.intra_op_num_threads = threads
    e = ort.InferenceSession(enc_path, so, providers=['CPUExecutionProvider'])
    s = ort.InferenceSession(step_path, so, providers=['CPUExecutionProvider'])

    def enc(img):
        k, v = e.run(None, {'img': img})
        return k, v, grid_for(img)

    def step(tok, pos, bidx, *rest):
        ctl = np.concatenate([tok, bidx, pos]).astype(np.int64)
        return s.run(None, dict(zip(NAMES, (ctl, *rest))))

    return Runner(enc, step)


def empty_caches(T):
    """One dummy slot (never attended to), one hypothesis."""
    return (np.zeros((3, 1, H, 1, HD), np.float32), np.zeros((3, 1, H, 1, HD), np.float32),
            np.zeros((2, 1, 2 * H, T), np.float32))


def beam(runner, k, v, grid, start, stop, beam_size=10, max_len=200, banned=None, alpha=1.0):
    """Beam search from [start] until [stop]. Returns [(tokens, score)], best
    first, score = sum log p (with the stop token) / (len + 1) ** alpha, as CoMER."""
    T = k.shape[2]
    sk, sv, cov = empty_caches(T)
    seqs = [[]]
    scores = np.zeros(1, np.float32)
    tok = np.array([start], np.int64)
    bidx = np.zeros(1, np.int64)
    done = []
    for t in range(max_len):
        logp, sk, sv, cov = runner.run(tok, np.array([t], np.int64), bidx, k, v, grid, sk, sv, cov)
        if banned is not None:
            logp[:, banned] = -1e9
        V = logp.shape[1]
        flat = (scores[:, None] + logp).reshape(-1)
        order = np.argsort(-flat, kind='stable')[: 2 * beam_size]
        keep_b, keep_t, keep_s = [], [], []
        for rank, idx in enumerate(order):
            b, tk = divmod(int(idx), V)
            if tk == stop:
                if rank < beam_size:
                    done.append((seqs[b], float(flat[idx]) / (len(seqs[b]) + 1) ** alpha))
            else:
                keep_b.append(b)
                keep_t.append(tk)
                keep_s.append(float(flat[idx]))
            if len(keep_b) == beam_size:
                break
        done.sort(key=lambda x: -x[1])
        done = done[:beam_size]
        # Stop once enough are finished and no live one can beat the worst of them.
        if len(done) >= beam_size and max(keep_s) / (t + 1) ** alpha <= done[-1][1]:
            break
        seqs = [seqs[b] + [tk] for b, tk in zip(keep_b, keep_t)]
        scores = np.array(keep_s, np.float32)
        tok = np.array(keep_t, np.int64)
        bidx = np.array(keep_b, np.int64)
    if not done:
        done = [(s_, float(sc) / (len(s_) + 1) ** alpha) for s_, sc in zip(seqs, scores)]
    done.sort(key=lambda x: -x[1])
    return done


def rate(runner, k, v, grid, seqs, start, stop, alpha=1.0):
    """Teacher-forced score of each sequence, normalised like beam()."""
    if not seqs:
        return []
    T = k.shape[2]
    B = len(seqs)
    L = max(len(s_) for s_ in seqs) + 1
    sk, sv, cov = empty_caches(T)
    total = np.zeros(B, np.float64)
    tok = np.full(B, start, np.int64)
    bidx = np.zeros(B, np.int64)  # every hypothesis starts from the one empty cache
    for t in range(L):
        logp, sk, sv, cov = runner.run(tok, np.array([t], np.int64), bidx, k, v, grid, sk, sv, cov)
        bidx = np.arange(B, dtype=np.int64)
        nxt = np.zeros(B, np.int64)
        for b, s_ in enumerate(seqs):
            if t <= len(s_):
                nxt[b] = s_[t] if t < len(s_) else stop
                total[b] += logp[b, nxt[b]]
        tok = nxt
    return [float(total[b] / (len(s_) + 1) ** alpha) for b, s_ in enumerate(seqs)]


def recognize(runner, img, beam_size=10, bidirectional=True, banned=None):
    k, v, grid = runner.encode(img)
    l2r = beam(runner, k, v, grid, SOS, EOS, beam_size, banned=banned)
    if not bidirectional:
        return l2r[0][0], l2r
    r2l = beam(runner, k, v, grid, EOS, SOS, beam_size, banned=banned)
    r2l = [(list(reversed(s_)), sc) for s_, sc in r2l]
    # Each hypothesis is also scored by the other direction (CoMER's bi-directional rescoring).
    rev_l = rate(runner, k, v, grid, [list(reversed(s_)) for s_, _ in l2r], EOS, SOS)
    rev_r = rate(runner, k, v, grid, [s_ for s_, _ in r2l], SOS, EOS)
    allh = [(s_, sc + rr) for (s_, sc), rr in zip(l2r, rev_l)] + [(s_, sc + rr) for (s_, sc), rr in zip(r2l, rev_r)]
    allh.sort(key=lambda x: -x[1])
    return allh[0][0], allh
