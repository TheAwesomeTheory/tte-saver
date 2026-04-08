#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 uv       [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut rubiks_vertex(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.uv = in.uv;
    return out;
}

// MARK: - Uniforms

struct RubiksUniforms {
    float time;
    float resolutionX;
    float resolutionY;
    float mouseX;
    float mouseY;
};

// MARK: - Constants

#define LOOP_DURATION 5.0
#define MOVE_COUNT 6.0
#define TIME_OFFSET 0.3
#define QUATERNION_IDENTITY float4(0, 0, 0, 1)

constant float4 moves[6] = {
    float4(1,0,0, 2.0),
    float4(0,1,0, -1.0),
    float4(0,-1,0, -3.0),
    float4(0,0,-1, 2.0),
    float4(0,-1,0, -1.0),
    float4(0,1,0, -3.0)
};

// MARK: - Utils

void pR(thread float2 &p, float a) {
    p = cos(a)*p + sin(a)*float2(p.y, -p.x);
}

float vmin3(float3 v) {
    return min(min(v.x, v.y), v.z);
}

float vmax3(float3 v) {
    return max(max(v.x, v.y), v.z);
}

float fBox(float3 p, float3 b) {
    float3 d = abs(p) - b;
    return length(max(d, float3(0))) + vmax3(min(d, float3(0)));
}

float smin2(float a, float b, float k) {
    float f = clamp(0.5 + 0.5 * ((a - b) / k), 0.0, 1.0);
    return (1.0 - f) * a + f * b - f * (1.0 - f) * k;
}

float smax2(float a, float b, float k) {
    return -smin2(-a, -b, k);
}

float range2(float vmin, float vmax, float value) {
    return clamp((value - vmin) / (vmax - vmin), 0.0, 1.0);
}

float almostIdentity(float x) {
    return x*x*(2.0-x);
}

float circularOut(float t) {
    return sqrt((2.0 - t) * t);
}

float3 pal(float t, float3 a, float3 b, float3 c, float3 d) {
    return a + b*cos(6.28318*(c*t+d));
}

float3 spectrum(float n) {
    return pal(n, float3(0.5), float3(0.5), float3(1.0), float3(0.0,0.33,0.67));
}

float3 erot(float3 p, float3 ax, float ro) {
    return mix(dot(ax,p)*ax, p, cos(ro)) + sin(ro)*cross(ax,p);
}

// MARK: - Quaternions

float4 qmul(float4 q1, float4 q2) {
    return float4(
        q2.xyz * q1.w + q1.xyz * q2.w + cross(q1.xyz, q2.xyz),
        q1.w * q2.w - dot(q1.xyz, q2.xyz)
    );
}

float3 rotate_vector(float3 v, float4 r) {
    float4 r_c = r * float4(-1, -1, -1, 1);
    return qmul(r, qmul(float4(v, 0), r_c)).xyz;
}

float4 rotate_angle_axis(float angle, float3 axis) {
    float sn = sin(angle * 0.5);
    float cs = cos(angle * 0.5);
    return float4(axis * sn, cs);
}

float4 q_conj(float4 q) {
    return float4(-q.x, -q.y, -q.z, q.w);
}

float4 q_slerp(float4 a, float4 b, float t) {
    if (length(a) == 0.0) {
        if (length(b) == 0.0) return QUATERNION_IDENTITY;
        return b;
    } else if (length(b) == 0.0) {
        return a;
    }

    float cosHalfAngle = a.w * b.w + dot(a.xyz, b.xyz);

    if (cosHalfAngle >= 1.0 || cosHalfAngle <= -1.0) return a;

    if (cosHalfAngle < 0.0) {
        b.xyz = -b.xyz;
        b.w = -b.w;
        cosHalfAngle = -cosHalfAngle;
    }

    float blendA;
    float blendB;
    if (cosHalfAngle < 0.99) {
        float halfAngle = acos(cosHalfAngle);
        float sinHalfAngle = sin(halfAngle);
        float oneOverSinHalfAngle = 1.0 / sinHalfAngle;
        blendA = sin(halfAngle * (1.0 - t)) * oneOverSinHalfAngle;
        blendB = sin(halfAngle * t) * oneOverSinHalfAngle;
    } else {
        blendA = 1.0 - t;
        blendB = t;
    }

    float4 result = float4(blendA * a.xyz + blendB * b.xyz, blendA * a.w + blendB * b.w);
    if (length(result) > 0.0) return normalize(result);
    return QUATERNION_IDENTITY;
}

// MARK: - Animation

void applyMomentum(thread float4 &q, float time, int i, float4 move) {
    float turns = move.w;
    float3 axis = move.xyz;
    float duration = abs(turns);
    float rotation = M_PI_F / 2.0 * turns * 0.75;
    float start = float(i + 1);
    float t = time * MOVE_COUNT;
    float ramp = range2(start, start + duration, t);
    float angle = circularOut(ramp) * rotation;
    float4 q2 = rotate_angle_axis(angle, axis);
    q = qmul(q, q2);
}

void applyMove(thread float3 &p, float time, int i, float4 move) {
    float turns = move.w;
    float3 axis = move.xyz;
    float rotation = M_PI_F / 2.0 * turns;
    float start = float(i);
    float t = time * MOVE_COUNT;
    float ramp = range2(start, start + 1.0, t);
    ramp = pow(almostIdentity(ramp), 2.5);
    float angle = ramp * rotation;

    bool animSide = vmax3(p * -axis) > 0.0;
    if (animSide) angle = 0.0;

    p = erot(p, axis, angle);
}

float4 momentum(float time) {
    float4 q = QUATERNION_IDENTITY;
    applyMomentum(q, time, 5, moves[5]);
    applyMomentum(q, time, 4, moves[4]);
    applyMomentum(q, time, 3, moves[3]);
    applyMomentum(q, time, 2, moves[2]);
    applyMomentum(q, time, 1, moves[1]);
    applyMomentum(q, time, 0, moves[0]);
    return q;
}

float4 momentumLoop(float time) {
    float4 q;
    q = momentum(3.0);
    q = q_conj(q);
    q = q_slerp(QUATERNION_IDENTITY, q, time);
    q = qmul(momentum(time + 1.0), q);
    q = qmul(momentum(time), q);
    return q;
}

// MARK: - Modelling

float4 mapBox(float3 p) {
    pR(p.xy, step(0.0, -p.z) * M_PI_F / -2.0);
    pR(p.xz, step(0.0, p.y) * M_PI_F);
    pR(p.yz, step(0.0, -p.x) * M_PI_F * 1.5);

    float3 face = step(float3(vmax3(abs(p))), abs(p)) * sign(p);
    float faceIndex = max(vmax3(face * float3(0,1,2)), vmax3(face * -float3(3,4,5)));
    float3 col = spectrum(faceIndex / 6.0 + 0.1 + 0.5);

    float thick = 0.033;
    float d = length(p + float3(0.1, 0.02, 0.05)) - 0.4;
    d = max(d, -d - thick);

    float3 ap = abs(p);
    float3 plane = cross(abs(face), normalize(float3(1)));
    float groove = max(-dot(ap.yzx, plane), dot(ap.zxy, plane));
    d = smax2(d, -abs(groove), 0.01);

    float gap = 0.005;
    float r = 0.05;
    float cut = -fBox(abs(p) - (1.0 + r + gap), float3(1.0)) + r;
    d = smax2(d, -cut, thick / 2.0);

    float opp = vmin3(abs(p)) + gap;
    opp = max(opp, length(p) - 1.0);
    if (opp < d) {
        return float4(opp, float3(-1));
    }

    return float4(d, col * 0.4);
}

float4 map(float3 p, float time) {
    pR(p.xz, time * M_PI_F * 2.0);

    float4 q = momentumLoop(time);
    p = rotate_vector(p, q);

    applyMove(p, time, 5, moves[5]);
    applyMove(p, time, 4, moves[4]);
    applyMove(p, time, 3, moves[3]);
    applyMove(p, time, 2, moves[2]);
    applyMove(p, time, 1, moves[1]);
    applyMove(p, time, 0, moves[0]);

    return mapBox(p);
}

// MARK: - Rendering

float3x3 calcLookAtMatrix(float3 ro, float3 ta, float roll) {
    float3 ww = normalize(ta - ro);
    float3 uu = normalize(cross(ww, float3(sin(roll), cos(roll), 0.0)));
    float3 vv = normalize(cross(uu, ww));
    return float3x3(uu, vv, ww);
}

float3 calcNormal(float3 p, float time) {
    const float h = 0.001;
    float3 n = float3(0.0);
    for (int i = 0; i < 4; i++) {
        float3 e = 0.5773 * (2.0 * float3((((i+3)>>1)&1), ((i>>1)&1), (i&1)) - 1.0);
        n += e * map(p + e*h, time).x;
    }
    return normalize(n);
}

float2 iSphere(float3 ro, float3 rd, float r) {
    float3 oc = ro;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - r*r;
    float h = b*b - c;
    if (h < 0.0) return float2(-1.0);
    h = sqrt(h);
    return float2(-b-h, -b+h);
}

float softshadow(float3 ro, float3 rd, float mint, float tmax, float time) {
    float res = 1.0;
    float2 bound = iSphere(ro, rd, 0.55);
    tmax = min(tmax, bound.y);
    float t = mint;
    for (int i = 0; i < 100; i++) {
        float4 hit = map(ro + rd*t, time);
        float h = hit.x;
        if (hit.y > 0.0) {
            res = min(res, 10.0*h/t);
        }
        t += h;
        if (res < 0.0001 || t > tmax) break;
    }
    return clamp(res, 0.0, 1.0);
}

float3 render(float2 p, float time) {
    float3 col = float3(0.02, 0.01, 0.025);

    float3 camPos = float3(0, 0, 2.0);
    float3x3 camMat = calcLookAtMatrix(camPos, float3(0, 0, -1), 0.0);
    float3 rd = normalize(camMat * float3(p.xy, 2.8));
    float3 pos = camPos;

    float2 bound = iSphere(pos, rd, 0.55);
    if (bound.x < 0.0) return col;

    float rayLength = bound.x;
    float dist = 0.0;
    bool background = true;
    float4 res;

    for (int i = 0; i < 200; i++) {
        rayLength += dist;
        pos = camPos + rd * rayLength;
        res = map(pos, time);
        dist = res.x;
        if (abs(dist) < 0.001) {
            background = false;
            break;
        }
        if (rayLength > bound.y) break;
    }

    if (!background) {
        col = res.yzw;
        float3 nor = calcNormal(pos, time);
        float3 lig = normalize(float3(-0.33, 0.3, 0.25));
        float3 lba = normalize(float3(0.5, -1.0, -0.5));
        float3 hal = normalize(lig - rd);
        float amb = sqrt(clamp(0.5 + 0.5*nor.y, 0.0, 1.0));
        float dif = clamp(dot(nor, lig), 0.0, 1.0);
        float bac = clamp(dot(nor, lba), 0.0, 1.0) * clamp(1.0 - pos.y, 0.0, 1.0);
        float fre = pow(clamp(1.0 + dot(nor, rd), 0.0, 1.0), 2.0);

        if (dif > 0.001) dif *= softshadow(pos, lig, 0.001, 0.9, time);

        float spe = pow(clamp(dot(nor, hal), 0.0, 1.0), 16.0) *
            dif * (0.04 + 0.96*pow(clamp(1.0 + dot(hal, rd), 0.0, 1.0), 5.0));

        float3 lin = float3(0.0);
        lin += 2.80*dif*float3(1.30, 1.00, 0.70);
        lin += 0.55*amb*float3(0.40, 0.60, 1.15);
        lin += 1.55*bac*float3(0.25, 0.25, 0.25)*float3(2, 0, 1);
        lin += 0.25*fre*float3(1.00, 1.00, 1.00);

        col = col*lin;
        col += 5.00*spe*float3(1.10, 0.90, 0.70);
    }

    return col;
}

// MARK: - Fragment

fragment float4 rubiksFragment(VertexOut in [[stage_in]],
                                constant RubiksUniforms &uniforms [[buffer(0)]]) {
    float2 resolution = float2(uniforms.resolutionX, uniforms.resolutionY);
    float mTime = (uniforms.time + TIME_OFFSET) / LOOP_DURATION;
    float time = fmod(mTime, 1.0);

    float2 fragCoord = float2(in.uv.x, 1.0 - in.uv.y) * resolution;
    float2 p = (-resolution + 2.0 * fragCoord) / resolution.y;

    float3 col = render(p, time);
    col = pow(col, float3(0.4545));

    return float4(col, 1.0);
}
