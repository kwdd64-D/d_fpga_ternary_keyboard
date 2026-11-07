import configparser
import json
import math
import os

# repo root
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

INI_FILE = os.path.join(ROOT, "data", "oklch", "theme.ini")
OUT_JSON = os.path.join(ROOT, "build", "oklch_rgb.json")

def oklch_to_srgb(L, C, H):
    # Convert hue degrees → radians
    h_rad = math.radians(H)

    # OKLCH → OKLab
    a = math.cos(h_rad) * C
    b = math.sin(h_rad) * C

    # OKLab → LMS cube roots
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b

    # Undo cube root
    l = l_ * l_ * l_
    m = m_ * m_ * m_
    s = s_ * s_ * s_

    # LMS → linear RGB
    r_lin = ( 4.0767416621 * l) - (3.3077115913 * m) + (0.2309699292 * s)
    g_lin = (-1.2684380046 * l) + (2.6097574011 * m) - (0.3413193965 * s)
    b_lin = (-0.0041960863 * l) - (0.7034186147 * m) + (1.7076147010 * s)

    # Linear RGB → sRGB with gamma correction
    def to_srgb(c):
        c = max(0.0, min(1.0, c))  # clamp
        if c <= 0.0031308:
            return 12.92 * c
        return 1.055 * (c ** (1.0 / 2.4)) - 0.055

    r = int(to_srgb(r_lin) * 255)
    g = int(to_srgb(g_lin) * 255)
    b = int(to_srgb(b_lin) * 255)

    return r, g, b

def main():
    config = configparser.ConfigParser()
    config.read(INI_FILE)

    L = float(config["White"]["L"])
    C = float(config["White"]["C"])
    H = float(config["White"]["H"])

    r, g, b = oklch_to_srgb(L, C, H)

    with open(OUT_JSON, "w") as f:
        json.dump({"r": r, "g": g, "b": b}, f, indent=4)

    print(f"OKLCH → RGB: ({r}, {g}, {b})")

if __name__ == "__main__":
    main()
