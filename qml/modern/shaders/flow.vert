#version 440
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_UV;

void main()
{
    qt_UV = qt_MultiTexCoord0;
    gl_Position = qt_Vertex;
}
