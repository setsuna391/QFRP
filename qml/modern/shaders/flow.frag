#version 440
layout(location = 0) in vec2 qt_UV;
layout(location = 0) out vec4 fragColor;

//Qt 6 着色器烘焙要求 uniform 放进 block(Vulkan/SPIR-V 目标的硬性要求)
layout(std140, binding = 0) uniform buf {
    float qt_Opacity;
    float uTime;   //QML 里 ShaderEffect 的 uTime 属性自动绑定到同名成员
};

//仿 xinghuisama.top:四色粉彩流动渐变(#a18cd1/#fbc2eb/#a1c4fd/#c2e9fb)
//整块 quad 在 GPU 上逐像素计算,CPU 零开销
void main()
{
    vec2 uv = qt_UV;
    float t = uTime * 0.05;

    //三组错相位的正弦波叠加,产生 -45 度方向的缓慢流动
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

    //斜向光带:给玻璃后面一点可被磨砂模糊的高频结构(液态玻璃的"内容")
    float streak = sin((p.x * 6.5 - p.y * 2.8) + t * 0.9) * 0.5 + 0.5;
    col += pow(streak, 3.0) * 0.085 * vec3(1.0, 0.98, 0.95);
    float band = sin((p.y * 2.4 + p.x * 1.1) - t * 0.6) * 0.5 + 0.5;
    col += pow(band, 2.5) * 0.05 * vec3(0.95, 1.0, 1.05);

    fragColor = vec4(col, qt_Opacity);
}
