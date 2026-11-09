// simplex-wallpaper.frag — animated 3D simplex noise, live on the GPU.
//
// Rendered by `shaderbg` (see wallpaper-shader.nix), which speaks a
// Shadertoy-style interface: it calls mainImage() every frame and supplies
// these uniforms for us —
//   iTime       seconds since shaderbg started
//   iResolution vec3, xy = output size in pixels
//   iTimeDelta  seconds since the previous frame
//   iFrame      frame counter
//   iMouse      pointer state (unused here)
//
// This is the GPU sibling of `perlin-art` (home/caligo/scripts.nix): same
// idea (animated coherent noise, mapped through a color ramp, scrolling
// over time), but continuous instead of an ASCII density ramp, and using
// simplex rather than classic Perlin noise since simplex's usual GPU form
// needs no permutation texture — just hashing/polynomial math, which is
// much cheaper per-pixel for something that has to run at full desktop
// resolution, every frame, forever, in the background.

// ---- 3D simplex noise -----------------------------------------------
// Permutation-free formulation (Ashima/McEwan-style hashing via mod289 +
// a Taylor-series inverse sqrt), written from the well-known public
// algorithm rather than copied from any one implementation. Returns a
// value in roughly [-1, 1].

vec3 mod289(vec3 x) { return x - floor(x / 289.0) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x / 289.0) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
    const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
    const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

    vec3 i  = floor(v + dot(v, C.yyy));
    vec3 x0 = v - i + dot(i, C.xxx);

    vec3 g = step(x0.yzx, x0.xyz);
    vec3 l = 1.0 - g;
    vec3 i1 = min(g.xyz, l.zxy);
    vec3 i2 = max(g.xyz, l.zxy);

    vec3 x1 = x0 - i1 + C.xxx;
    vec3 x2 = x0 - i2 + C.yyy;
    vec3 x3 = x0 - D.yyy;

    i = mod289(i);
    vec4 p = permute(permute(permute(
              i.z + vec4(0.0, i1.z, i2.z, 1.0))
            + i.y + vec4(0.0, i1.y, i2.y, 1.0))
            + i.x + vec4(0.0, i1.x, i2.x, 1.0));

    float n_ = 0.142857142857; // 1/7
    vec3 ns = n_ * D.wyz - D.xzx;

    vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

    vec4 x_ = floor(j * ns.z);
    vec4 y_ = floor(j - 7.0 * x_);

    vec4 x = x_ * ns.x + ns.yyyy;
    vec4 y = y_ * ns.x + ns.yyyy;
    vec4 h = 1.0 - abs(x) - abs(y);

    vec4 b0 = vec4(x.xy, y.xy);
    vec4 b1 = vec4(x.zw, y.zw);

    vec4 s0 = floor(b0) * 2.0 + 1.0;
    vec4 s1 = floor(b1) * 2.0 + 1.0;
    vec4 sh = -step(h, vec4(0.0));

    vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

    vec3 p0 = vec3(a0.xy, h.x);
    vec3 p1 = vec3(a0.zw, h.y);
    vec3 p2 = vec3(a1.xy, h.z);
    vec3 p3 = vec3(a1.zw, h.w);

    vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
    p0 *= norm.x; p1 *= norm.y; p2 *= norm.z; p3 *= norm.w;

    vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
    m = m * m;
    return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

// A few octaves of the above, so the field reads as soft drifting cloud
// shapes rather than one flat frequency of noise — same reason perlin-art
// isn't just raw noise piped straight to the ramp.
float fbm(vec3 p) {
    float sum = 0.0;
    float amp = 0.5;
    float freq = 1.0;
    for (int i = 0; i < 4; i++) {
        sum += amp * snoise(p * freq);
        amp *= 0.5;
        freq *= 2.0;
    }
    return sum;
}

// ---- Color ramp --------------------------------------------------------
// Catppuccin Mocha stops (same hex values as hyprland.nix's theme) so the
// background reads as part of the same desktop, not a random demo shader:
// crust/base for the dark end, mauve/lavender for the highlights.
const vec3 crust    = vec3(0.0667, 0.0667, 0.1059); // #11111b
const vec3 base     = vec3(0.1176, 0.1176, 0.1804); // #1e1e2e
const vec3 mauve    = vec3(0.7961, 0.6510, 0.9686); // #cba6f7
const vec3 lavender = vec3(0.7059, 0.7451, 0.9961); // #b4befe

vec3 ramp(float t) {
    t = clamp(t, 0.0, 1.0);
    if (t < 0.5) {
        return mix(crust, base, t * 2.0);
    }
    return mix(base, mix(mauve, lavender, 0.5), (t - 0.5) * 2.0);
}

// ---- Tunables -----------------------------------------------------------
// Mirrors perlin-art's --scale/--speed in spirit. Edit and rebuild to taste
// (shaderbg re-execs on the raw .frag, no recompilation step of ours needed
// beyond `home-manager`/`nixos-rebuild` re-symlinking the file).
const float SCALE = 2.2;   // higher = more zoomed out / smoother
const float SPEED = 0.03;  // higher = faster drift

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    uv.x *= iResolution.x / iResolution.y; // keep noise features square, not stretched

    float n = fbm(vec3(uv * SCALE, iTime * SPEED));
    n = n * 0.5 + 0.5; // [-1, 1] -> [0, 1]

    fragColor = vec4(ramp(n), 1.0);
}
