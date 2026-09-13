#version 440
layout(location = 0) in vec2 qt_UV;
layout(location = 0) out vec4 fragColor;

//Qt 6 着色器烘焙要求 uniform 放进 block(Vulkan/SPIR-V 目标硬性要求)
layout(std140, binding = 0) uniform buf {
    float qt_Opacity;
    float uTime;
    float uOffX;     //面板在背景 uv 中的位置
    float uOffY;
    float uScaleX;   //面板宽占背景宽的比例
    float uScaleY;
    float uAspect;   //背景 宽/高
    float uRadius;   //圆角(相对面板高的比例)
    float uBlur;     //模糊半径(相对背景高的比例)
    float uGlow;     //边缘液态高光强度
};

//与背景 flow.frag 完全相同的渐变函数——磨砂采样天然对齐流动动画
vec3 bgColor(vec2 uv, float t)
{
    vec2 p = uv * vec2(1.6, 1.0);
    float w1 = sin((p.x + p.y) * 3.14159 + t * 2.0);
    float w2 = sin((p.x - p.y) * 2.2 - t * 1.4 + 1.7);
    float w3 = sin(p.y * 4.5 - t * 0.9 + 3.1);
    float flow = 0.5 + 0.28 * sin(w1 + w2 * 0.7 + w3 * 0.5);
    vec3 cPurple = vec3(0.631, 0.549, 0.820); // #a18cd1
    vec3 cPink   = vec3(0.984, 0.761, 0.922); // #fbc2eb
    vec3 cBlue   = vec3(0.631, 0.769, 0.992); // #a1c4fd
    vec3 cCyan   = vec3(0.761, 0.914, 0.984); // #c2e9fb
    vec3 col = mix(cPurple, cPink, smoothstep(0.15, 0.85, flow));
    col = mix(col, mix(cBlue, cCyan, 0.5 + 0.5 * sin(w2 + w3)), 0.30 + 0.25 * sin(w1 * 0.8));
    return col;
}

void main()
{
    float t = uTime * 0.05;
    vec2 buv = vec2(uOffX + qt_UV.x * uScaleX, uOffY + qt_UV.y * uScaleY);

    //圆角矩形 SDF(校正宽高比后计算)
    vec2 asp = vec2(uAspect, 1.0);
    vec2 q = (qt_UV - 0.5) * asp;
    vec2 hsize = vec2(0.5 * uAspect, 0.5);
    float rad = uRadius;
    vec2 dcorner = abs(q) - (hsize - vec2(rad));
    float dist = length(max(dcorner, vec2(0.0))) + min(max(dcorner.x, dcorner.y), 0.0) - rad;

    //液态折射:靠边缘处轻微向内偏折采样点(凸透镜边缘效应)
    float rimGlow = 1.0 - smoothstep(0.0, rad * 0.8, -dist);
    vec2 refract = normalize(q + vec2(0.0001)) * rimGlow * 0.014;
    vec2 suv = buv - refract;

    //磨砂:9 点采样近似高斯模糊(采样的是实时流动的背景函数)
    vec3 acc = bgColor(suv, t) * 0.25;
    float dx = uBlur * uAspect * 0.9;
    float dy = uBlur;
    acc += bgColor(suv + vec2( dx,  dy), t) * 0.0625;
    acc += bgColor(suv + vec2( dx, -dy), t) * 0.0625;
    acc += bgColor(suv + vec2(-dx,  dy), t) * 0.0625;
    acc += bgColor(suv + vec2(-dx, -dy), t) * 0.0625;
    acc += bgColor(suv + vec2( dx, 0.0), t) * 0.125;
    acc += bgColor(suv + vec2(-dx, 0.0), t) * 0.125;
    acc += bgColor(suv + vec2(0.0,  dy), t) * 0.125;
    acc += bgColor(suv + vec2(0.0, -dy), t) * 0.125;

    //玻璃质感:整体提白 + 边缘液态高光
    vec3 col = mix(acc, vec3(1.0), 0.16);
    col += rimGlow * uGlow * vec3(0.30);

    //圆角裁切:角落外露出背景本体
    float alpha = 1.0 - smoothstep(-1.0, 0.6, dist);
    fragColor = vec4(col, alpha * qt_Opacity);
}
