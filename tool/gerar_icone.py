#!/usr/bin/env python3
"""Gera os PNGs do ícone do Risca a partir de assets/icon/risca.png.

No risca.png os dois checks e as duas linhas são um RECORTE transparente no
quadrado verde (e há um halo claro desfocado atrás). Daqui sai:

  risca_fg.png      adaptativo, primeiro plano: só o glifo, branco puro, dentro da
                    zona segura (círculo de 66 dp numa tela de 108 dp)
  risca_bg.png      adaptativo, fundo: gradiente verde que preenche TUDO, verde escuro
                    no canto superior direito, sem borda nem halo
  risca_legacy.png  ícone "normal" (Android < 8 e fallback): quadrado arredondado
                    verde com o glifo branco, sem o círculo claro

Rodar: python3 tool/gerar_icone.py   (precisa de Pillow e numpy). Os PNGs gerados ficam
no repositório; o CI só roda o flutter_launcher_icons.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

RAIZ = Path(__file__).resolve().parent.parent
PASTA = RAIZ / "assets" / "icon"
TAM = 1024

# Gradiente medido no risca.png: lima embaixo à esquerda → verde escuro em cima à direita.
PARADAS = [(0.0, (183, 229, 4)), (0.5, (118, 200, 52)), (1.0, (42, 148, 80))]

# Zona segura do ícone adaptativo: círculo de 66 dp numa tela de 108 dp.
RAIO_SEGURO = TAM * 66 / 108 / 2
FOLGA = 0.93  # o ponto mais longe do glifo fica a 93% do raio seguro


def glifo_do_png():
    """Cobertura (0..1) do glifo: o quanto cada pixel é recorte dentro do quadrado."""
    im = np.array(Image.open(PASTA / "risca.png").convert("RGBA")).astype(float)
    cov = 1.0 - im[..., 3] / 255.0
    janela = np.zeros(cov.shape, bool)
    janela[130:380, 140:380] = True  # só o miolo do quadrado: fora dele é halo/canto
    cov = np.where(janela, cov, 0.0)
    ys, xs = np.where(cov > 0.5)
    y0, y1, x0, x1 = ys.min() - 4, ys.max() + 5, xs.min() - 4, xs.max() + 5
    return cov[y0:y1, x0:x1]


def suavizar(c):
    """Afina a borda depois do upscale (smoothstep) para não ficar borrada."""
    t = np.clip((c - 0.3) / 0.4, 0.0, 1.0)
    return t * t * (3 - 2 * t)


def glifo_branco(cov, largura_alvo):
    """Glifo branco puro (RGBA) com `largura_alvo` px de largura, borda nítida."""
    h, w = cov.shape
    escala = largura_alvo / w
    alvo = (round(w * escala), round(h * escala))
    sup = (alvo[0] * 2, alvo[1] * 2)  # supersample 2x e depois reduz: borda sem serrilhado
    img = Image.fromarray((cov * 255).astype(np.uint8)).resize(sup, Image.BICUBIC)
    a = suavizar(np.array(img).astype(float) / 255.0)
    img = Image.fromarray((a * 255).astype(np.uint8)).resize(alvo, Image.LANCZOS)
    rgba = np.zeros((alvo[1], alvo[0], 4), np.uint8)
    rgba[..., :3] = 255
    rgba[..., 3] = np.array(img)
    return Image.fromarray(rgba)


def gradiente(w, h):
    x = np.linspace(0, 1, w)[None, :]
    y = np.linspace(0, 1, h)[:, None]
    t = np.clip((x + (1 - y)) / 2, 0, 1)  # 0 no canto inferior esquerdo, 1 no superior direito
    out = np.zeros((h, w, 3))
    ts = [p[0] for p in PARADAS]
    for c in range(3):
        out[..., c] = np.interp(t, ts, [p[1][c] for p in PARADAS])
    return Image.fromarray(out.round().astype(np.uint8)).convert("RGBA")


def centralizar(glifo, tela=TAM):
    """Coloca o glifo (centro do retângulo dele) no centro de uma tela transparente."""
    base = Image.new("RGBA", (tela, tela), (0, 0, 0, 0))
    base.alpha_composite(glifo, ((tela - glifo.width) // 2, (tela - glifo.height) // 2))
    return base


def largura_para_zona_segura(cov):
    """Largura do glifo que deixa o pixel mais distante a FOLGA do raio seguro."""
    h, w = cov.shape
    ys, xs = np.where(cov > 0.5)
    d = np.hypot(xs - (w - 1) / 2, ys - (h - 1) / 2).max()
    return w * (RAIO_SEGURO * FOLGA) / d


def main():
    cov = glifo_do_png()

    fg = centralizar(glifo_branco(cov, largura_para_zona_segura(cov)))
    fg.save(PASTA / "risca_fg.png")

    gradiente(TAM, TAM).convert("RGB").save(PASTA / "risca_bg.png")

    # Ícone normal: quadrado arredondado (proporção do original: glifo = 63% do quadrado).
    margem = round(TAM * 0.03)
    lado = TAM - 2 * margem
    sup = 4
    mascara = Image.new("L", (TAM * sup, TAM * sup), 0)
    ImageDraw.Draw(mascara).rounded_rectangle(
        (margem * sup, margem * sup, (TAM - margem) * sup - 1, (TAM - margem) * sup - 1),
        radius=round(lado * 0.24) * sup,
        fill=255,
    )
    mascara = mascara.resize((TAM, TAM), Image.LANCZOS)
    legado = gradiente(TAM, TAM)
    legado.putalpha(mascara)
    legado.alpha_composite(centralizar(glifo_branco(cov, lado * 0.63)))
    legado.save(PASTA / "risca_legacy.png")

    print("ok:", ", ".join(sorted(p.name for p in PASTA.glob("risca*.png"))))


if __name__ == "__main__":
    main()
