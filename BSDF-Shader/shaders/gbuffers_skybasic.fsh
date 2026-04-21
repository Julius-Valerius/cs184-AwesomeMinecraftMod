#version 330 compatibility

in vec4 glcolor;
in vec3 wPos;

// --- 引入 Iris 内置的动态环境变量 ---
// 这两个变量会根据游戏内的世界时间、天气、群系自动且极其平滑地变化！
uniform vec3 skyColor; 
uniform vec3 fogColor; 

/* RENDERTARGETS: 0,1,2 */
layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec4 normalData;
layout(location = 2) out vec4 pbrData;

void main() {
    // 1. 将原版的“天空盒子”在数学上投影成一个完美的平滑球体
    vec3 dir = normalize(wPos);
    
    // 计算仰角：0.0 是地平线，1.0 是头顶正上方
    float elevation = clamp(dir.y, 0.0, 1.0);
    
    // 2. 模拟真实大气的平滑渐变 (大气散射曲线)
    // 越靠近地平线，颜色越接近雾色(fogColor)；越往高空，越接近天空色(skyColor)
    float gradient = 1.0 - exp(-3.5 * elevation);
    vec3 proceduralSky = mix(fogColor, skyColor, gradient);
    
    vec3 finalColor = proceduralSky;

    // 3. 保护原版星星：原版星星通常是纯白的顶点块
    // 如果不加这句，满天繁星会被我们的平滑天空盖住
    if (glcolor.r > 0.99 && glcolor.g > 0.99 && glcolor.b > 0.99) {
        finalColor = glcolor.rgb; 
    }

    // 输出最终颜色
    fragColor = vec4(finalColor, 1.0);
    
    normalData = vec4(0.5, 1.0, 0.5, 1.0);
    pbrData = vec4(1.0, 0.0, 0.0, 1.0); 
}