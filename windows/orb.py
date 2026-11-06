"""Software renderer for the Prisma orb on Windows.

The geometry follows PrismaBeam and SiriLiquidGlassOrbView in
app/Sources/Prisma/OverlayView.swift. The macOS app draws those layers with
SwiftUI and a native backdrop blur; this module rebuilds them with Pillow so
the Windows overlay can show the same light without the AppKit stack.

Everything is drawn on a transparent canvas. The caller composites the result
on a per-pixel-alpha layered window, so edges and the outer aura stay smooth.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Callable, Sequence

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ORB_DIAMETER = 198
CANVAS = 220
MARGIN = (CANVAS - ORB_DIAMETER) // 2
SUPERSAMPLE = 2
SAMPLES = 144

# Voice weight at which the moving light is fully the voice pose. Below it the
# loop and voice paths are crossfaded so the geometry swap is not a jump.
LIGHT_CROSSFADE = 0.06

THEME_TITLES = {
    'prisma': 'Prisma Original (Ámbar y Zafiro)',
    'aurora': 'Aurora Boreal (Esmeralda y Violeta)',
    'oceano': 'Océano Abisal (Cian y Cobalto)',
    'nebula': 'Nebulosa Cósmica (Magenta y Cian)',
    'solar': 'Fulgor Solar (Oro y Carmesí)',
    'amatista': 'Amatista Real (Violeta y Rosa)',
    'esmeralda': 'Bosque Bioluminiscente (Jade y Oro)',
    'artico': 'Cristal Ártico (Hielo y Plata)',
    'atardecer': 'Atardecer (Coral e Índigo)',
    'platino': 'Luz de Luna (Platino y Perla)',
}

PALETTES = {
    'prisma': {
        'upperDeep': (0.88, 0.30, 0.12),
        'upperBright': (1.00, 0.46, 0.12),
        'upperMid': (1.00, 0.66, 0.24),
        'upperHighlight': (1.00, 0.96, 0.84),
        'lowerDeep': (0.18, 0.44, 0.92),
        'lowerBright': (0.18, 0.62, 1.00),
        'lowerMid': (0.35, 0.95, 1.00),
        'lowerHighlight': (0.90, 0.97, 1.00),
        'coreTint': (1.00, 0.94, 0.72),
        'idlePrimary': (0.24, 0.61, 0.94),
        'idleSecondary': (0.05, 0.23, 0.56),
    },
    'aurora': {
        'upperDeep': (0.62, 0.20, 0.96),
        'upperBright': (0.82, 0.36, 1.00),
        'upperMid': (0.95, 0.48, 0.92),
        'upperHighlight': (0.96, 0.88, 1.00),
        'lowerDeep': (0.06, 0.64, 0.50),
        'lowerBright': (0.12, 0.86, 0.66),
        'lowerMid': (0.36, 1.00, 0.82),
        'lowerHighlight': (0.86, 1.00, 0.95),
        'coreTint': (0.84, 1.00, 0.92),
        'idlePrimary': (0.14, 0.84, 0.66),
        'idleSecondary': (0.30, 0.12, 0.58),
    },
    'oceano': {
        'upperDeep': (0.18, 0.28, 0.95),
        'upperBright': (0.32, 0.50, 1.00),
        'upperMid': (0.28, 0.70, 1.00),
        'upperHighlight': (0.84, 0.94, 1.00),
        'lowerDeep': (0.04, 0.64, 0.82),
        'lowerBright': (0.10, 0.84, 0.96),
        'lowerMid': (0.36, 0.98, 0.96),
        'lowerHighlight': (0.88, 1.00, 1.00),
        'coreTint': (0.80, 0.98, 1.00),
        'idlePrimary': (0.12, 0.78, 0.94),
        'idleSecondary': (0.06, 0.20, 0.62),
    },
    'nebula': {
        'upperDeep': (0.92, 0.12, 0.56),
        'upperBright': (1.00, 0.24, 0.72),
        'upperMid': (1.00, 0.50, 0.86),
        'upperHighlight': (1.00, 0.88, 0.97),
        'lowerDeep': (0.26, 0.34, 0.96),
        'lowerBright': (0.20, 0.70, 1.00),
        'lowerMid': (0.28, 0.95, 1.00),
        'lowerHighlight': (0.88, 0.98, 1.00),
        'coreTint': (0.98, 0.88, 1.00),
        'idlePrimary': (0.84, 0.22, 0.74),
        'idleSecondary': (0.14, 0.32, 0.72),
    },
    'solar': {
        'upperDeep': (0.86, 0.12, 0.16),
        'upperBright': (1.00, 0.28, 0.14),
        'upperMid': (1.00, 0.54, 0.12),
        'upperHighlight': (1.00, 0.92, 0.76),
        'lowerDeep': (0.92, 0.48, 0.08),
        'lowerBright': (1.00, 0.68, 0.16),
        'lowerMid': (1.00, 0.86, 0.36),
        'lowerHighlight': (1.00, 0.97, 0.84),
        'coreTint': (1.00, 0.94, 0.70),
        'idlePrimary': (0.96, 0.52, 0.16),
        'idleSecondary': (0.58, 0.12, 0.08),
    },
    'amatista': {
        'upperDeep': (0.90, 0.28, 0.60),
        'upperBright': (1.00, 0.46, 0.76),
        'upperMid': (1.00, 0.66, 0.88),
        'upperHighlight': (1.00, 0.92, 0.97),
        'lowerDeep': (0.44, 0.18, 0.88),
        'lowerBright': (0.62, 0.34, 1.00),
        'lowerMid': (0.78, 0.58, 1.00),
        'lowerHighlight': (0.93, 0.88, 1.00),
        'coreTint': (0.96, 0.88, 1.00),
        'idlePrimary': (0.64, 0.34, 0.94),
        'idleSecondary': (0.30, 0.10, 0.56),
    },
    'esmeralda': {
        'upperDeep': (0.86, 0.60, 0.10),
        'upperBright': (1.00, 0.78, 0.20),
        'upperMid': (0.84, 0.94, 0.30),
        'upperHighlight': (0.96, 1.00, 0.82),
        'lowerDeep': (0.05, 0.58, 0.34),
        'lowerBright': (0.12, 0.82, 0.46),
        'lowerMid': (0.34, 0.98, 0.62),
        'lowerHighlight': (0.86, 1.00, 0.90),
        'coreTint': (0.90, 1.00, 0.78),
        'idlePrimary': (0.18, 0.82, 0.48),
        'idleSecondary': (0.06, 0.36, 0.22),
    },
    'artico': {
        'upperDeep': (0.48, 0.64, 0.86),
        'upperBright': (0.68, 0.82, 0.98),
        'upperMid': (0.82, 0.92, 1.00),
        'upperHighlight': (0.96, 0.99, 1.00),
        'lowerDeep': (0.18, 0.50, 0.92),
        'lowerBright': (0.32, 0.74, 1.00),
        'lowerMid': (0.58, 0.92, 1.00),
        'lowerHighlight': (0.92, 0.98, 1.00),
        'coreTint': (0.90, 0.97, 1.00),
        'idlePrimary': (0.42, 0.76, 0.98),
        'idleSecondary': (0.14, 0.32, 0.60),
    },
    'atardecer': {
        'upperDeep': (0.94, 0.24, 0.30),
        'upperBright': (1.00, 0.42, 0.36),
        'upperMid': (1.00, 0.66, 0.42),
        'upperHighlight': (1.00, 0.90, 0.82),
        'lowerDeep': (0.32, 0.20, 0.84),
        'lowerBright': (0.50, 0.34, 0.96),
        'lowerMid': (0.68, 0.52, 1.00),
        'lowerHighlight': (0.90, 0.84, 1.00),
        'coreTint': (1.00, 0.90, 0.82),
        'idlePrimary': (0.88, 0.38, 0.52),
        'idleSecondary': (0.26, 0.14, 0.58),
    },
    'platino': {
        'upperDeep': (0.72, 0.68, 0.62),
        'upperBright': (0.88, 0.84, 0.78),
        'upperMid': (0.94, 0.91, 0.85),
        'upperHighlight': (1.00, 0.99, 0.96),
        'lowerDeep': (0.50, 0.58, 0.72),
        'lowerBright': (0.68, 0.76, 0.88),
        'lowerMid': (0.82, 0.88, 0.96),
        'lowerHighlight': (0.96, 0.98, 1.00),
        'coreTint': (0.98, 0.98, 0.95),
        'idlePrimary': (0.68, 0.74, 0.86),
        'idleSecondary': (0.28, 0.32, 0.42),
    },
}


def palette(theme: str) -> dict:
    return PALETTES.get(theme, PALETTES['prisma'])


def ring_stops(pal: dict) -> list[tuple[float, float, float]]:
    """Seven-stop closed loop, matching Palette.ringStops on macOS."""
    return [
        pal['lowerBright'], pal['lowerMid'], pal['lowerHighlight'],
        pal['upperHighlight'], pal['upperMid'], pal['upperDeep'],
        pal['lowerBright'],
    ]


def clamp(value: float, low: float = 0.0, high: float = 1.0) -> float:
    return max(low, min(high, value))


def smoothstep(edge0: float, edge1: float, value: float) -> float:
    t = clamp((value - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)


def sinc(value: float) -> float:
    return 1 - value * value / 6 if abs(value) < 1e-4 else math.sin(value) / value


def mix(a: Sequence[float], b: Sequence[float], t: float) -> tuple[float, ...]:
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def color_rgba(rgb: Sequence[float], alpha: float) -> tuple[int, int, int, int]:
    return (
        round(clamp(rgb[0]) * 255),
        round(clamp(rgb[1]) * 255),
        round(clamp(rgb[2]) * 255),
        round(clamp(alpha) * 255),
    )


@dataclass
class OrbFrame:
    """One instant of the animation, in the same units as macOS OrbFrame."""

    time: float
    voice: float = 1.0
    idle: float = 0.0
    thinking: float = 0.0
    speaking: float = 0.0
    spin: float = 0.0
    sweep: float = 0.0
    idle_phase: float = 0.0
    theme: str = 'prisma'

    @property
    def energy(self) -> float:
        t = self.time
        talking = 0.10 + 0.06 * math.sin(t * 3.8)
        voice = 0.05 * (0.5 + 0.5 * math.sin(t * 1.4))
        voice += (talking - voice) * clamp(self.speaking)
        thinking = 0.20 + 0.10 * math.sin(t * 1.65)
        waiting = 0.16 + 0.06 * math.sin((t + self.idle_phase) * 0.9)
        return voice * self.voice + thinking * self.thinking + waiting * self.idle


@dataclass
class Band:
    lift: float
    arch: float
    thickness: float
    phase: float
    stops: list[tuple[float, tuple[float, float, float], float]]


def _stop(location: float, rgb: Sequence[float], alpha: float) -> tuple[float, tuple[float, float, float], float]:
    return (location, tuple(rgb), alpha)


def _clear(location: float) -> tuple[float, tuple[float, float, float], float]:
    return (location, (0.0, 0.0, 0.0), 0.0)


def bloom_bands(pal: dict, energy: float) -> list[Band]:
    spread = 1.0 + energy * 1.15
    return [
        Band(10.0 * spread - 0.4, -1.0, 22.0 + 20.0 * energy, 0.0, [
            _clear(0.02),
            _stop(0.20, pal['lowerDeep'], 0.38 + 0.25 * energy),
            _stop(0.50, pal['lowerBright'], 0.78 + 0.20 * energy),
            _stop(0.80, pal['lowerDeep'], 0.38 + 0.25 * energy),
            _clear(0.98),
        ]),
        Band(-5.5 * spread - 0.4, 0.5, 13.0 + 12.0 * energy, 0.45, [
            _clear(0.05),
            _stop(0.24, pal['upperDeep'], 0.45 + 0.25 * energy),
            _stop(0.50, pal['upperBright'], 0.78 + 0.20 * energy),
            _stop(0.76, pal['upperDeep'], 0.48 + 0.25 * energy),
            _clear(0.95),
        ]),
    ]


def spectral_bands(pal: dict, energy: float) -> list[Band]:
    spread = 1.0 + energy * 0.85
    lower_inner = mix(pal['lowerMid'], pal['lowerHighlight'], 0.35)
    upper_inner = mix(pal['upperMid'], pal['upperHighlight'], 0.45)
    return [
        Band(-4.8 * spread - 0.4, 0.6, 6.2 + 5.5 * energy, 0.25, [
            _clear(0.06),
            _stop(0.24, pal['upperDeep'], 0.72 + 0.20 * energy),
            _stop(0.50, pal['upperBright'], 0.96),
            _stop(0.76, pal['upperDeep'], 0.76 + 0.18 * energy),
            _clear(0.94),
        ]),
        Band(6.6 * spread - 0.4, -0.8, 8.5 + 7.5 * energy, -0.25, [
            _clear(0.03),
            _stop(0.20, pal['lowerDeep'], 0.68 + 0.22 * energy),
            _stop(0.50, pal['lowerBright'], 0.96),
            _stop(0.80, pal['lowerDeep'], 0.68 + 0.22 * energy),
            _clear(0.97),
        ]),
        Band(3.0 * spread - 0.4, -0.3, 5.8 + 5.0 * energy, -0.10, [
            _clear(0.08),
            _stop(0.26, pal['lowerMid'], 0.75 + 0.18 * energy),
            _stop(0.50, lower_inner, 0.98),
            _stop(0.74, pal['lowerMid'], 0.75 + 0.18 * energy),
            _clear(0.92),
        ]),
        Band(-1.8 * spread - 0.4, 0.2, 5.0 + 4.5 * energy, 0.10, [
            _clear(0.10),
            _stop(0.28, pal['upperMid'], 0.78 + 0.16 * energy),
            _stop(0.50, upper_inner, 0.98),
            _stop(0.72, pal['upperMid'], 0.80 + 0.16 * energy),
            _clear(0.90),
        ]),
    ]


def core_band(pal: dict, energy: float) -> Band:
    return Band(0.0, 0.0, 5.0 + 5.5 * energy, 0.0, [
        _clear(0.12),
        _stop(0.28, pal['coreTint'], 0.72 + 0.22 * energy),
        _stop(0.50, (1.0, 1.0, 0.98), 1.0),
        _stop(0.72, pal['coreTint'], 0.72 + 0.22 * energy),
        _clear(0.88),
    ])


class PrismaBeam:
    """Port of the beam geometry in OverlayView.swift."""

    def __init__(self, frame: OrbFrame, size: float = ORB_DIAMETER):
        self.frame = frame
        total = frame.voice + frame.thinking + frame.idle
        total = total if total > 1e-6 else 1.0
        self.wv = clamp(frame.voice / total)
        self.wt = clamp(frame.thinking / total)
        self.wi = clamp(frame.idle / total)
        pal = palette(frame.theme)
        self.ring = ring_stops(pal)
        self.center = (size / 2, size / 2)
        self.energy = frame.energy
        self.arch_height = 15.0 + 7.5 * self.energy
        self.size = size

        wv, wt, wi = self.wv, self.wt, self.wi
        self.open = pow(max(0.0, wv - 0.1) / 0.9, 1.5)
        self.closure = 1 - self.open
        self.end_fade = smoothstep(0, 0.16, wv)

        voice_length = float(size)
        voice_turn = 8 * self.arch_height / voice_length
        ring_radius = 41.34 * (1 + 0.035 * math.sin(frame.time * 1.5))
        idle_radius = 60.44
        closed = wt + wi
        loop_radius = (wt * ring_radius + wi * idle_radius) / closed if closed > 1e-6 else ring_radius
        self.turn = self.open * voice_turn + self.closure * 2 * math.pi
        self.length = self.open * voice_length + self.closure * 2 * math.pi * loop_radius
        self.kappa = self.turn / self.length

        lift = self._apex_to_centroid(self.turn, self.length)
        lift -= self.open * self._apex_to_centroid(voice_turn, voice_length)
        self.apex = (self.center[0], self.center[1] - lift)
        self.curvature_center = (self.apex[0], self.apex[1] + 1 / self.kappa)
        tau = frame.time + frame.idle_phase
        self.scale = (
            wv + wt * 1.12 + wi * (1.04 + 0.04 * math.sin(tau * 0.4)),
            wv + wt * 0.92 + wi * 0.94,
        )

    @staticmethod
    def _apex_to_centroid(turn: float, length: float) -> float:
        return (1 - sinc(turn / 2)) * length / turn

    def loop_factor(self, u: float) -> float:
        fade = smoothstep(0, 0.14, min(u, 1 - u))
        return 1 - self.end_fade * (1 - fade)

    def voice_horizon_y(self, u: float) -> float:
        """The horizon of the voice beam, followed by the dark sky above it."""
        centred = 2 * u - 1
        arch = max(0.0, 1 - centred * centred)
        t = self.frame.time * 1.2
        harmonics = 0.55 * math.sin(u * 6.2 - t)
        harmonics += 0.30 * math.sin(u * 12.4 + t * 1.35)
        harmonics += 0.15 * math.cos(u * 18.0 - t * 1.70)
        wave = harmonics * (0.6 + 8.5 * self.energy) * pow(arch, 1.35)
        return self.center[1] + self.arch_height * (1 - arch) + wave

    def sky_layer(self, size: int = CANVAS) -> Image.Image:
        """Dark sky clipped above the voice horizon."""
        layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        edge = 3.6
        offset = MARGIN
        path = [(-24, -24), (size + 24, -24), (size + 24, offset + self.voice_horizon_y(1) + edge)]
        for index in range(48, -1, -1):
            u = index / 48
            path.append((offset + u * self.size, offset + self.voice_horizon_y(u) + edge))
        path.append((-24, offset + self.voice_horizon_y(0) + edge))
        draw.polygon(path, fill=(4, 7, 13, 64))
        layer = layer.filter(ImageFilter.GaussianBlur(4))
        # The sky belongs to the glass: without this clip it paints the whole
        # upper half of the canvas and brings back the grey square.
        layer.putalpha(ImageChops.multiply(
            layer.getchannel('A'),
            _disc_mask(size, (size / 2, size / 2), ORB_DIAMETER / 2),
        ))
        return layer

    def _palette_color(self, position: float) -> tuple[float, float, float]:
        x = (position - math.floor(position)) * 6
        index = min(5, int(x))
        fraction = x - index
        return mix(self.ring[index], self.ring[index + 1], fraction)

    def _voice_color(self, stops: list, u: float) -> tuple[float, float, float, float]:
        if u <= stops[0][0]:
            rgb, alpha = stops[0][1], stops[0][2]
            return (*rgb, alpha)
        if u >= stops[-1][0]:
            rgb, alpha = stops[-1][1], stops[-1][2]
            return (*rgb, alpha)
        for index in range(1, len(stops)):
            if u <= stops[index][0]:
                a, b = stops[index - 1], stops[index]
                f = (u - a[0]) / max(1e-9, b[0] - a[0])
                rgb = mix(a[1], b[1], f)
                return (*rgb, a[2] + (b[2] - a[2]) * f)
        rgb, alpha = stops[-1][1], stops[-1][2]
        return (*rgb, alpha)

    def color(self, band: Band, u: float) -> tuple[int, int, int, int]:
        voice_rgb = self._voice_color(band.stops, u)
        ring_rgb = self._palette_color(u - self.frame.spin - self.frame.idle_phase * 0.16)
        voice_alpha = self.wv * voice_rgb[3]
        loop_alpha = (self.wt + self.wi * 0.28) * self.loop_factor(u)
        alpha = voice_alpha + loop_alpha
        if alpha <= 1e-5:
            return (0, 0, 0, 0)
        rgb = tuple(
            (voice_rgb[i] * voice_alpha + ring_rgb[i] * loop_alpha) / alpha
            for i in range(3)
        )
        return color_rgba(rgb, min(1.0, alpha))

    def outline(self, band: Band) -> tuple[list, list, list, tuple[float, float]]:
        frame = self.frame
        wv, wt, wi = self.wv, self.wt, self.wi
        t = frame.time
        tau = t + frame.idle_phase
        two_pi = 2 * math.pi

        loop_motion = self.closure * self.closure
        tilt = wt * loop_motion * 0.12 * math.sin(t * 0.55 + band.phase * 2)
        cos_tilt, sin_tilt = math.cos(tilt), math.sin(tilt)
        sweep_offset = band.phase * (4 * (wv + wt) + 6 * wi)
        warp_base = 0.25 * math.sin(tau * 0.22) + 0.5 * band.phase
        wave_time = t * 1.2 + band.phase
        wave_amplitude = 0.6 + 8.5 * self.energy
        idle_motion = wi * loop_motion
        inner_fold = 0.20 + 1.10 * loop_motion
        has_voice = wv > 1e-5
        has_ring = wt > 1e-5
        has_idle = wi > 1e-5

        outer, inner, spine = [], [], []
        for i in range(SAMPLES + 1):
            u = i / SAMPLES
            theta = two_pi * u
            centred = 2 * u - 1
            arch = max(0.0, 1 - centred * centred)

            warp = 0.0
            if has_idle:
                warp = idle_motion * (0.22 * math.sin(2 * theta + tau * 0.55) + warp_base)
            s = (u - 0.5 + warp / two_pi) * self.length
            phi = self.kappa * s
            half = sinc(phi / 2)
            base = (
                self.apex[0] + s * sinc(phi),
                self.apex[1] + s * phi * 0.5 * half * half,
            )
            normal = (math.sin(phi), -math.cos(phi))

            offset = 0.0
            shared = 0.0
            fold = 0.0
            if has_voice:
                log_arch = math.log(arch) if arch > 0 else -math.inf
                h1 = 0.55 * math.sin(u * 6.2 - wave_time)
                h2 = 0.30 * math.sin(u * 12.4 + wave_time * 1.35)
                h3 = 0.15 * math.cos(u * 18.0 - wave_time * 1.70)
                wave = (h1 + h2 + h3) * wave_amplitude * math.exp(1.35 * log_arch) if arch > 0 else 0.0
                offset += wv * (-band.lift + band.arch * arch - wave)
                pulse = 1 + 0.28 * self.energy * math.sin(u * 9.0 + t * 7.0 + band.phase)
                thickness = band.thickness * 0.5 * math.exp(1.4 * log_arch) if arch > 0 else 0.0
                shared += wv * thickness * pulse
            if has_ring or has_idle:
                sweep = 0.5 + 0.5 * math.sin(theta - frame.sweep + sweep_offset)
                sweep_sq = sweep * sweep
                ends = self.loop_factor(u)
                if has_ring:
                    ripple = 1.7 * math.sin(3 * theta + t * 1.15 + band.phase * 4)
                    ripple += 0.9 * math.sin(2 * theta - t * 0.8)
                    offset += wt * (-0.85 * band.lift + ripple * loop_motion)
                    shared += wt * band.thickness * 0.17 * (0.45 + 0.85 * sweep_sq) * ends
                if has_idle:
                    lobes = 8.0 * math.sin(2 * theta + tau * 0.62 + band.phase * 6)
                    lobes += 3.0 * math.sin(3 * theta - tau * 0.48)
                    offset += wi * (-1.1 * band.lift + lobes * loop_motion)
                    fold = wi * (7.0 + band.thickness * 0.45) * (0.40 + 1.70 * sweep_sq) * ends
            cx = base[0] + normal[0] * offset
            cy = base[1] + normal[1] * offset
            outward = shared + 0.20 * fold
            inward = shared + inner_fold * fold

            def place(px: float, py: float) -> tuple[float, float]:
                dx = (px - self.center[0]) * self.scale[0]
                dy = (py - self.center[1]) * self.scale[1]
                return (
                    self.center[0] + dx * cos_tilt - dy * sin_tilt,
                    self.center[1] + dx * sin_tilt + dy * cos_tilt,
                )

            outer.append(place(cx + normal[0] * outward, cy + normal[1] * outward))
            inner.append(place(cx - normal[0] * inward, cy - normal[1] * inward))
            if i % 4 == 0:
                spine.append(place(cx, cy))
        return outer, inner, spine, place(*self.curvature_center)


# ---------------------------------------------------------------------------
# Static glass layers


def _radial_circle(size: int, stops: list[tuple[float, tuple[int, int, int, int]]],
                   center: tuple[float, float], radius: float) -> Image.Image:
    """A smooth radial gradient clipped to its circle, drawn once."""
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    steps = max(24, int(radius))
    for step in range(steps, -1, -1):
        t = step / steps
        color = stops[-1][1]
        for index in range(1, len(stops)):
            if t <= stops[index][0]:
                a, b = stops[index - 1], stops[index]
                f = (t - a[0]) / max(1e-9, b[0] - a[0])
                color = tuple(round(a[1][i] + (b[1][i] - a[1][i]) * f) for i in range(4))
                break
        r = radius * t
        draw.ellipse(
            (center[0] - r, center[1] - r, center[0] + r, center[1] + r),
            fill=color,
        )
    return image


def _disc_mask(size: int, center: tuple[float, float], radius: float) -> Image.Image:
    mask = Image.new('L', (size, size), 0)
    box = (center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius)
    ImageDraw.Draw(mask).ellipse(box, fill=255)
    return mask


def _gradient_rim(size: int, radius: float, width: float,
                  stops: list[tuple[float, tuple[int, int, int, int]]]) -> Image.Image:
    """A circular stroke painted with a vertical colour gradient.

    Colouring the whole stroke from a gradient, instead of one arc at a time,
    avoids the bright seam that antialiased arc segments leave at the top.
    """
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    center = size / 2
    box = (center - radius, center - radius, center + radius, center + radius)
    draw.ellipse(box, outline=(255, 255, 255, 255), width=max(1, round(width)))

    gradient = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gradient_draw = ImageDraw.Draw(gradient)
    for y in range(size):
        t = y / max(1, size - 1)
        color = stops[-1][1]
        for index in range(1, len(stops)):
            if t <= stops[index][0]:
                a, b = stops[index - 1], stops[index]
                f = (t - a[0]) / max(1e-9, b[0] - a[0])
                color = tuple(round(a[1][i] + (b[1][i] - a[1][i]) * f) for i in range(4))
                break
        gradient_draw.line((0, y, size, y), fill=color)
    gradient.putalpha(ImageChops.multiply(layer.getchannel('A'), gradient.getchannel('A')))
    return gradient


def _horizontal_gradient(size: tuple[int, int], colors: list[tuple[int, int, int, int]]) -> Image.Image:
    """Left-to-right gradient used by the cylindrical side reflections."""
    width, height = size
    strip = Image.new('RGBA', (width, 1))
    pixels = strip.load()
    for x in range(width):
        t = x / max(1, width - 1)
        color = colors[-1]
        for index in range(1, len(colors)):
            edge = index / (len(colors) - 1)
            if t <= edge:
                a, b = colors[index - 1], colors[index]
                f = (t - (index - 1) / (len(colors) - 1)) / max(1e-9, 1 / (len(colors) - 1))
                color = tuple(round(a[i] + (b[i] - a[i]) * f) for i in range(4))
                break
        pixels[x, 0] = color
    return strip.resize((width, height), Image.Resampling.NEAREST)


def _scale_alpha(image: Image.Image, factor: float) -> Image.Image:
    scaled = image.copy()
    scaled.putalpha(image.getchannel('A').point(lambda value: round(value * clamp(factor))))
    return scaled


class OrbRenderer:
    """Caches the glass and draws the moving light of one halo theme."""

    def __init__(self, theme: str = 'prisma'):
        self.theme = theme if theme in PALETTES else 'prisma'
        self.pal = palette(self.theme)
        self.size = CANVAS
        self.hi = CANVAS * SUPERSAMPLE
        self.mask = _disc_mask(self.hi, (self.hi / 2, self.hi / 2), ORB_DIAMETER / 2 * SUPERSAMPLE)
        self._conic_cache: dict[tuple[int, int], Image.Image] = {}
        self._build_static()
        self._build_aura()
        self._build_glow()

    # -- static glass -------------------------------------------------------

    def _build_static(self):
        hi = self.hi
        center = hi / 2
        radius = ORB_DIAMETER / 2 * SUPERSAMPLE

        shadow = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse(
            (center - radius + 4 * SUPERSAMPLE, center - radius + 12 * SUPERSAMPLE,
             center + radius - 4 * SUPERSAMPLE, center + radius + 12 * SUPERSAMPLE),
            fill=(0, 0, 0, 72),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(16 * SUPERSAMPLE))

        body = _radial_circle(
            hi,
            [
                (0.0, (1, 2, 4, 242)),
                (0.30, (2, 4, 7, 240)),
                (0.62, (4, 7, 12, 234)),
                (0.88, (10, 15, 24, 222)),
                (1.0, (18, 27, 41, 210)),
            ],
            (center, center),
            radius,
        )
        body = Image.composite(body, Image.new('RGBA', (hi, hi), (0, 0, 0, 0)), self.mask)

        # Soft backdrop glow so the smoked interior still reads as glass.
        inner_light = _radial_circle(
            hi,
            [
                (0.0, (76, 112, 154, 0)),
                (0.45, (58, 90, 128, 4)),
                (0.82, (34, 54, 82, 16)),
                (1.0, (12, 20, 32, 28)),
            ],
            (center, center),
            radius,
        ).filter(ImageFilter.GaussianBlur(10 * SUPERSAMPLE))
        body = Image.alpha_composite(body, inner_light)

        base = Image.alpha_composite(shadow, body)

        # The lower hemisphere of the voice orb: smoked glass lit from below.
        lower_glass = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        ldraw = ImageDraw.Draw(lower_glass)
        stops = [
            (0.00, (205, 212, 222, 0)),
            (0.38, (205, 212, 222, 0)),
            (0.50, (205, 212, 222, 8)),
            (0.62, (205, 212, 222, 58)),
            (0.75, (205, 212, 222, 82)),
            (0.88, (205, 212, 222, 104)),
            (1.00, (205, 212, 222, 132)),
        ]
        for y in range(hi):
            t = y / max(1, hi - 1)
            color = stops[-1][1]
            for index in range(1, len(stops)):
                if t <= stops[index][0]:
                    a, b = stops[index - 1], stops[index]
                    f = (t - a[0]) / max(1e-9, b[0] - a[0])
                    color = tuple(round(a[1][i] + (b[1][i] - a[1][i]) * f) for i in range(4))
                    break
            ldraw.line((0, y, hi, y), fill=color)
        lower_glass.putalpha(ImageChops.multiply(lower_glass.getchannel('A'), self.mask))
        lower_glass = lower_glass.filter(ImageFilter.GaussianBlur(2 * SUPERSAMPLE))

        lower_glow = _radial_circle(
            hi,
            [
                (0.0, (255, 255, 255, 62)),
                (0.35, (200, 225, 250, 38)),
                (0.70, (110, 160, 210, 18)),
                (1.0, (40, 70, 110, 0)),
            ],
            (center, center + radius * 0.28),
            radius * 0.85,
        ).filter(ImageFilter.GaussianBlur(8 * SUPERSAMPLE))
        lower_glow.putalpha(ImageChops.multiply(lower_glow.getchannel('A'), self.mask))

        self.lower_glass = lower_glass.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
        self.lower_glow = lower_glow.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)

        # Cylindrical side reflections. Drawn on a separate layer and blurred
        # so they read as light caught by the glass, not as flat paint.
        reflections = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        strip = int(46 * SUPERSAMPLE)
        left = _horizontal_gradient(
            (strip, hi),
            [(255, 255, 255, 64), (255, 255, 255, 18), (255, 255, 255, 0)],
        )
        right = _horizontal_gradient(
            (strip, hi),
            [(255, 255, 255, 0), (255, 255, 255, 14), (255, 255, 255, 54)],
        )
        reflections.alpha_composite(left, (round(center - radius), 0))
        reflections.alpha_composite(right, (round(center + radius) - strip, 0))
        reflections.putalpha(ImageChops.multiply(reflections.getchannel('A'), self.mask))
        reflections = reflections.filter(ImageFilter.GaussianBlur(2 * SUPERSAMPLE))

        over = reflections

        # Outer specular rim and inner optical bevel.
        outer_rim = _gradient_rim(
            hi, radius - 1.5, 1.4 * SUPERSAMPLE,
            [
                (0.0, (107, 92, 82, 34)),
                (0.30, (255, 255, 255, 26)),
                (0.65, (255, 255, 255, 104)),
                (1.0, (255, 255, 255, 186)),
            ],
        )
        inner_rim = _gradient_rim(
            hi, radius - 2.4, 1.0 * SUPERSAMPLE,
            [
                (0.0, (255, 255, 255, 0)),
                (0.42, (255, 255, 255, 6)),
                (0.78, (189, 224, 255, 20)),
                (1.0, (255, 255, 255, 46)),
            ],
        )
        over = Image.alpha_composite(over, outer_rim)
        over = Image.alpha_composite(over, inner_rim)

        # One faint diagonal sheen across the upper-left glass.
        sheen = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(sheen)
        sdraw.polygon(
            [
                (center - radius * 0.72, center - radius * 1.02),
                (center - radius * 0.20, center - radius * 1.02),
                (center - radius * 0.58, center + radius * 0.30),
                (center - radius * 0.90, center + radius * 0.18),
            ],
            fill=(255, 255, 255, 12),
        )
        sheen.putalpha(ImageChops.multiply(sheen.getchannel('A'), self.mask))
        sheen = sheen.filter(ImageFilter.GaussianBlur(7 * SUPERSAMPLE))
        over = Image.alpha_composite(over, sheen)

        self.base = base.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
        self.over = over.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)

    # -- animated layers ----------------------------------------------------

    def _build_aura(self):
        """Warm/cool halo around the glass, kept at full strength.

        The coloured disc sits behind the body, which covers its centre, so
        only the blurred edge escapes as a soft halo. The frame's energy
        scales its alpha at paint time.
        """
        pal = self.pal
        size = CANVAS
        scale = 2
        big = size * scale
        gradient = Image.new('RGBA', (big, big), (0, 0, 0, 0))
        top = color_rgba(pal['upperBright'], 0.09)
        bottom = color_rgba(pal['lowerBright'], 0.12)
        draw = ImageDraw.Draw(gradient)
        for y in range(big):
            t = y / max(1, big - 1)
            color = tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(4))
            draw.line((0, y, big, y), fill=color)
        disc = _disc_mask(big, (big / 2, big / 2), (ORB_DIAMETER / 2 - 6) * scale)
        gradient.putalpha(ImageChops.multiply(gradient.getchannel('A'), disc))
        gradient = gradient.filter(ImageFilter.GaussianBlur(12 * scale))
        self.aura = gradient.resize((size, size), Image.Resampling.LANCZOS)

    def _build_glow(self):
        """Ambient glow that drifts behind the waiting light.

        Stored at full strength; ``render`` scales it by the idle weight.
        """
        pal = self.pal
        size = CANVAS
        primary = color_rgba(pal['idlePrimary'], 0.32)
        secondary = color_rgba(pal['idleSecondary'], 0.18)
        glow = _radial_circle(
            size,
            [
                (0.0, primary),
                (0.42, (primary[0], primary[1], primary[2], 76)),
                (0.68, secondary),
                (1.0, (secondary[0], secondary[1], secondary[2], 0)),
            ],
            (size / 2, size / 2),
            86,
        )
        glow = glow.filter(ImageFilter.GaussianBlur(10))
        glow.putalpha(ImageChops.multiply(glow.getchannel('A'), _disc_mask(size, (size / 2, size / 2), 98)))
        self.glow = glow

    def _draw_band(self, layer: Image.Image, beam: PrismaBeam, band: Band):
        draw = ImageDraw.Draw(layer)
        outer, inner, _, _ = beam.outline(band)
        scale = SUPERSAMPLE
        offset = MARGIN * SUPERSAMPLE

        def point(p):
            return (offset + p[0] * scale, offset + p[1] * scale)

        for index in range(SAMPLES):
            u = (index + 0.5) / SAMPLES
            color = beam.color(band, u)
            if color[3] == 0:
                continue
            draw.polygon(
                [point(outer[index]), point(outer[index + 1]),
                 point(inner[index + 1]), point(inner[index])],
                fill=color,
            )


    def _conic_gradient(self, beam: PrismaBeam, start_angle: float, size: int = 64) -> Image.Image:
        """Ring palette laid out by angle around the loop's curvature centre.

        The macOS beam fills each band with a conic gradient that starts at
        the first point of its spine, so the colour follows the light. Bands
        share one texture here, which keeps the loop free of the facets that
        flat quads leave where the fold overlaps itself.
        """
        frame = beam.frame
        # Quantise the rotation and the spine's start angle so the texture is
        # rebuilt only a few times per second; both change slowly enough that
        # a 1.4° step is invisible after the blur.
        key = (
            round((frame.spin + frame.idle_phase * 0.16) * 256) % 256,
            round(start_angle / (2 * math.pi) * 256) % 256,
        )
        cached = self._conic_cache.get(key)
        if cached is not None:
            return cached
        pivot_x = (beam.curvature_center[0] + MARGIN) / CANVAS * size
        pivot_y = (beam.curvature_center[1] + MARGIN) / CANVAS * size
        pixels = []
        two_pi = 2 * math.pi
        for y in range(size):
            dy = y - pivot_y
            for x in range(size):
                angle = math.atan2(dy, x - pivot_x)
                position = (angle - start_angle) / two_pi - frame.spin - frame.idle_phase * 0.16
                rgb = beam._palette_color(position)
                pixels.append(tuple(round(clamp(c) * 255) for c in rgb))
        image = Image.new('RGB', (size, size))
        image.putdata(pixels)
        image = image.resize((self.hi, self.hi), Image.Resampling.BICUBIC)
        if len(self._conic_cache) > 24:
            self._conic_cache.pop(next(iter(self._conic_cache)))
        self._conic_cache[key] = image
        return image

    def _loop_light(self, frame: OrbFrame, pal: dict) -> Image.Image:
        beam = PrismaBeam(frame)
        groups = [
            ('bloom', bloom_bands(pal, frame.energy), 0),
            ('spectrum', spectral_bands(pal, frame.energy), 2.6 * SUPERSAMPLE),
            ('core', [core_band(pal, frame.energy)], 1.2 * SUPERSAMPLE),
        ]
        outlines = {name: [beam.outline(band) for band in bands] for name, bands, _ in groups}
        starts = [
            math.atan2(spine[0][1] - pivot[1], spine[0][0] - pivot[0])
            for items in outlines.values() for _, _, spine, pivot in items
        ]
        gradient = self._conic_gradient(beam, sum(starts) / len(starts))
        alpha = clamp(frame.thinking + frame.idle * 0.28)
        offset = MARGIN * SUPERSAMPLE
        scale = SUPERSAMPLE

        def layer_for(items: list[tuple[list, list, list, tuple]], blur: float) -> Image.Image:
            layer = Image.new('RGBA', (self.hi, self.hi), (0, 0, 0, 0))
            for outer, inner, _, _ in items:
                mask = Image.new('L', (self.hi, self.hi), 0)
                draw = ImageDraw.Draw(mask)

                def point(p):
                    return (offset + p[0] * scale, offset + p[1] * scale)

                # One quad per sample keeps Pillow's fill cheap; the conic
                # texture is painted under each one, so the colour stays
                # continuous across the band.
                for index in range(SAMPLES):
                    draw.polygon(
                        [point(outer[index]), point(outer[index + 1]),
                         point(inner[index + 1]), point(inner[index])],
                        fill=round(255 * alpha),
                    )
                item = gradient.copy()
                item.putalpha(mask)
                layer = Image.alpha_composite(layer, item.convert('RGBA'))
            if blur:
                layer = layer.filter(ImageFilter.GaussianBlur(blur))
            return layer

        bloom = layer_for(outlines['bloom'], 0)
        bloom = bloom.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
        bloom = bloom.filter(ImageFilter.GaussianBlur(10))
        bloom = bloom.resize((self.hi, self.hi), Image.Resampling.BILINEAR)
        spectrum = layer_for(outlines['spectrum'], 2.6 * SUPERSAMPLE)
        core = layer_for(outlines['core'], 1.2 * SUPERSAMPLE)
        light = ImageChops.screen(bloom, spectrum)
        light = ImageChops.screen(light, core)
        mask = ImageChops.multiply(light.getchannel('A'), self.mask)
        light.putalpha(mask)
        return light.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)

    def _voice_light(self, frame: OrbFrame, pal: dict) -> Image.Image:
        beam = PrismaBeam(frame)
        energy = frame.energy
        hi = self.hi

        bloom = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        for band in bloom_bands(pal, energy):
            self._draw_band(bloom, beam, band)
        bloom = bloom.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)
        bloom = bloom.filter(ImageFilter.GaussianBlur(10 - 3 * frame.thinking))
        bloom = bloom.resize((hi, hi), Image.Resampling.BILINEAR)

        spectrum = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        for band in spectral_bands(pal, energy):
            self._draw_band(spectrum, beam, band)
        spectrum = spectrum.filter(ImageFilter.GaussianBlur((2.6 + 2.4 * frame.idle - 1.7 * frame.thinking) * SUPERSAMPLE))

        core = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        self._draw_band(core, beam, core_band(pal, energy))
        core = core.filter(ImageFilter.GaussianBlur((1.2 - 0.7 * frame.thinking) * SUPERSAMPLE))

        light = ImageChops.screen(bloom, spectrum)
        light = ImageChops.screen(light, core)
        alpha = ImageChops.multiply(light.getchannel('A'), self.mask)
        light.putalpha(alpha)
        return light.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)

    def render_light(self, frame: OrbFrame) -> Image.Image:
        """Pick the moving light path, crossfading where the two overlap.

        macOS swaps the whole hierarchy on ``frame.voice > 0.001``, so the
        light geometry changes in a single frame. Blending the two paths
        while the voice pose enters and leaves hides that swap.
        """
        if frame.voice >= LIGHT_CROSSFADE:
            return self._voice_light(frame, self.pal)
        if frame.voice <= 0.001:
            return self._loop_light(frame, self.pal)
        blend = smoothstep(0.001, LIGHT_CROSSFADE, frame.voice)
        loop = self._loop_light(frame, self.pal)
        voice = self._voice_light(frame, self.pal)
        # Both layers are pure light composited in screen mode, so a linear
        # channel blend reads as a premultiplied crossfade.
        return Image.blend(loop, voice, blend)

    def _caustics(self, frame: OrbFrame) -> Image.Image:
        """Bright refractions along the bottom of the voice glass.

        Port of liquidGlassBottomRefraction: three screen-blended strokes
        that hug the lower curve and drift with the voice meter. Only the
        voice pose shows them, so the caller fades them by ``frame.voice``.
        """
        hi = self.hi
        layer = Image.new('RGBA', (hi, hi), (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)
        energy = frame.energy
        speaking = clamp(frame.speaking)
        slow = math.sin(frame.time * 0.8)
        fast = math.sin(frame.time * 2.8)
        shift = (slow + (fast - slow) * speaking) * (4.0 + 5.0 * energy)
        width = ORB_DIAMETER
        height = 26
        left = MARGIN
        top = MARGIN + ORB_DIAMETER - height

        def point(x: float, y: float) -> tuple[float, float]:
            return ((left + x * width) * SUPERSAMPLE, (top + y * height) * SUPERSAMPLE)

        def stroke(start, control, end, alpha: float, line_width: float):
            color = (255, 255, 255, round(255 * alpha))
            samples = 24
            previous = None
            for index in range(samples + 1):
                t = index / samples
                x = (1 - t) ** 2 * start[0] + 2 * (1 - t) * t * control[0] + t * t * end[0]
                y = (1 - t) ** 2 * start[1] + 2 * (1 - t) * t * control[1] + t * t * end[1]
                current = point(x, y)
                if previous is not None:
                    draw.line((previous, current), fill=color,
                              width=max(1, round(line_width * SUPERSAMPLE)))
                previous = current
            # Round caps, like StrokeStyle(lineCap: .round).
            radius = line_width * SUPERSAMPLE / 2
            for cap in (start, end):
                x, y = point(*cap)
                draw.ellipse((x - radius, y - radius, x + radius, y + radius), fill=color)

        stroke((0.14, 0.15), (0.20, 0.72), (0.36 + shift * 0.4, 0.78),
               0.30 + 0.12 * energy, 2.8)
        stroke((0.38 - shift * 0.3, 0.82), (0.53, 0.96), (0.68 + shift * 0.3, 0.76),
               0.46 + 0.18 * energy, 3.4)
        stroke((0.72 - shift * 0.3, 0.70), (0.81, 0.68), (0.86, 0.18),
               0.28 + 0.12 * energy, 2.6)
        layer = layer.filter(ImageFilter.GaussianBlur(SUPERSAMPLE))
        layer.putalpha(ImageChops.multiply(layer.getchannel('A'), self.mask))
        return layer.resize((CANVAS, CANVAS), Image.Resampling.LANCZOS)

    def render(self, frame: OrbFrame) -> Image.Image:
        image = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
        aura = 0.30 + 0.70 * clamp((frame.energy - 0.05) / 0.95)
        image.alpha_composite(_scale_alpha(self.aura, aura))
        image.alpha_composite(self.base)

        if frame.voice > 0.001:
            image.alpha_composite(_scale_alpha(self.lower_glass, frame.voice))
            image.alpha_composite(_scale_alpha(self.lower_glow, frame.voice * (0.6 + 0.4 * frame.energy)))
            image.alpha_composite(_scale_alpha(PrismaBeam(frame).sky_layer(), frame.voice))

        if frame.idle > 0.001:
            tau = frame.time + frame.idle_phase
            glow = _scale_alpha(self.glow, frame.idle)
            offset_x = round(CANVAS * 0.18 * math.sin(tau * 0.35))
            offset_y = round(CANVAS * 0.12 * math.cos(tau * 0.30))
            moved = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
            moved.alpha_composite(glow, (offset_x, offset_y))
            premultiplied = Image.alpha_composite(
                Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255)), moved
            ).convert('RGB')
            screen_rgb = ImageChops.screen(image.convert('RGB'), premultiplied)
            image = screen_rgb.convert('RGBA')
            image.putalpha(self.base.getchannel('A'))
        light = self.render_light(frame)
        premultiplied = Image.alpha_composite(
            Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255)), light
        ).convert('RGB')
        alpha = image.getchannel('A')
        image = ImageChops.screen(image.convert('RGB'), premultiplied).convert('RGBA')
        image.putalpha(alpha)
        if frame.voice > 0.001:
            caustics = _scale_alpha(self._caustics(frame), frame.voice)
            premultiplied = Image.alpha_composite(
                Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255)), caustics
            ).convert('RGB')
            image = ImageChops.screen(image.convert('RGB'), premultiplied).convert('RGBA')
            image.putalpha(alpha)
        image.alpha_composite(self.over)
        return image


_RENDERERS: dict[str, OrbRenderer] = {}


def renderer(theme: str = 'prisma') -> OrbRenderer:
    key = theme if theme in PALETTES else 'prisma'
    if key not in _RENDERERS:
        _RENDERERS[key] = OrbRenderer(key)
    return _RENDERERS[key]


def frame_image(frame: OrbFrame) -> Image.Image:
    return renderer(frame.theme).render(frame)


class OrbAnimator:
    """Smoothly moves the Windows orb between waiting and voice poses.

    The duration and easing follow macOS ``stateChanged``: 1.05 s to the
    voice pose, 1.4 s back to the waiting loop, with a smoothstep curve.
    """

    def __init__(self, theme: str = 'prisma'):
        self.theme = theme if theme in PALETTES else 'prisma'
        self.voice = 0.0
        self.idle = 1.0
        self.speaking = 0.0
        self.target_voice = 0.0
        self.target_speaking = 0.0
        self.spin = 0.0
        self.sweep = 0.0
        self.idle_phase = 2.37
        self.last_time: float | None = None
        self._retarget = False
        self._blend_from = 0.0
        self._blend_to = 0.0
        self._blend_start = 0.0
        self._blend_duration = 0.0

    def set_speaking(self, speaking: bool):
        target = 1.0 if speaking else 0.0
        if target != self.target_voice:
            self.target_voice = target
            self.target_speaking = target
            self._retarget = True

    def frame(self, now: float) -> OrbFrame:
        if self.last_time is None:
            self.last_time = now
        dt = min(max(0.0, now - self.last_time), 0.1)
        self.last_time = now
        if self._retarget:
            self._blend_from = self.voice
            self._blend_to = self.target_voice
            self._blend_start = now
            self._blend_duration = 1.05 if self.target_voice > self.voice else 1.4
            self._retarget = False
        if self._blend_duration > 0:
            u = clamp((now - self._blend_start) / self._blend_duration)
            self.voice = self._blend_from + (self._blend_to - self._blend_from) * u * u * (3 - 2 * u)
        self.idle = 1 - self.voice
        speak_rate = 1 - math.exp(-dt / 0.14)
        self.speaking += (self.target_speaking - self.speaking) * speak_rate
        self.spin += dt * (0.03 * self.voice + 0.038 * self.idle)
        self.sweep += dt * (0.75 * self.voice + 0.75 * self.idle)
        return OrbFrame(
            time=now,
            voice=self.voice,
            idle=self.idle,
            speaking=self.speaking,
            spin=self.spin,
            sweep=self.sweep,
            idle_phase=self.idle_phase,
            theme=self.theme,
        )


def _contact_sheet():
    """Render a small preview set for visual checks: python -m orb <out-dir>."""
    import sys
    from pathlib import Path

    out = Path(sys.argv[1] if len(sys.argv) > 1 else '/tmp/prisma-orb')
    out.mkdir(parents=True, exist_ok=True)
    cases = [
        ('wait_00', OrbFrame(0.0, voice=0, idle=1, idle_phase=2.37)),
        ('wait_01', OrbFrame(0.8, voice=0, idle=1, idle_phase=2.37)),
        ('think_00', OrbFrame(1.5, voice=0, thinking=1, idle=0)),
        ('think_01', OrbFrame(2.5, voice=0, thinking=1, idle=0)),
        ('voice_00', OrbFrame(3.7, voice=1, idle=0, speaking=0.6)),
        ('voice_01', OrbFrame(4.3, voice=1, idle=0, speaking=0.9)),
        ('voice_02', OrbFrame(5.1, voice=1, idle=0, speaking=0.2)),
    ]
    for name, frame in cases:
        image = renderer(frame.theme).render(frame)
        image.save(out / f'{name}.png')
        print(out / f'{name}.png')


if __name__ == '__main__':
    _contact_sheet()
