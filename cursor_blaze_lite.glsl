const float DURATION = 0.4; // IN SECONDS

// Cleaner normalization functions
vec2 normPos(vec2 p) {
    return (p * 2.0 - iResolution.xy) / iResolution.y;
}

vec2 normSize(vec2 s) {
    return (s * 2.0) / iResolution.y;
}

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b) {
    vec2 d = abs(p - xy) - b;

    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Standard, highly optimised unsigned distance to a line segment
float sdSegment(in vec2 p, in vec2 a, in vec2 b) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);

    return length(pa - ba * h);
}

// 2D Cross product for fast half-plane tests
float cross2d(vec2 a, vec2 b) {
    return a.x * b.y - a.y * b.x;
}

// Optimized Parallelogram SDF
float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    // 1. Distance to the closest edge
    float d = sdSegment(p, v0, v1);
    d = min(d, sdSegment(p, v1, v2));
    d = min(d, sdSegment(p, v2, v3));
    d = min(d, sdSegment(p, v3, v0));

    // 2. Fast inside/outside check using half-planes
    float s1 = cross2d(v1 - v0, p - v0);
    float s2 = cross2d(v2 - v1, p - v1);
    float s3 = cross2d(v3 - v2, p - v2);
    float s4 = cross2d(v0 - v3, p - v3);

    // If the pixel is on the same side of all directed edges, it's inside the polygon
    bool inside = (s1 <= 0.0 && s2 <= 0.0 && s3 <= 0.0 && s4 <= 0.0) || 
                  (s1 >= 0.0 && s2 >= 0.0 && s3 >= 0.0 && s4 >= 0.0);
    
    return inside ? -d : d;
}

float ease(float x) {
    return pow(1.0 - x, 2.0);
}

// Saturated altered to only process the RGB channels directly
vec4 saturate(vec4 color, float factor) {
    float gray = dot(color.rgb, vec3(0.9, 0.987, 0.514)); 
    return vec4(mix(vec3(gray), color.rgb, factor), color.a);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    #if !defined(WEB)
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #endif
    
    // 1. Pixel Coordinates
    vec2 vu = normPos(fragCoord);
    
    // 2. Frame Constants (The compiler handles these much better now)
    vec4 currentCursor = vec4(normPos(iCurrentCursor.xy), normSize(iCurrentCursor.zw));
    vec4 previousCursor = vec4(normPos(iPreviousCursor.xy), normSize(iPreviousCursor.zw));
    
    // Simpler logical condition instead of heavy branchless step math
    bool condition = (currentCursor.x < previousCursor.x && currentCursor.y > previousCursor.y) || 
                     (currentCursor.x > previousCursor.x && currentCursor.y < previousCursor.y);
    float vertexFactor = condition ? 0.0 : 1.0; 
    float invertedVertexFactor = 1.0 - vertexFactor;

    // Set every vertex of the parallelogram
    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    vec2 v2 = vec2(previousCursor.x + currentCursor.z * invertedVertexFactor, previousCursor.y);
    vec2 v3 = vec2(previousCursor.x + currentCursor.z * vertexFactor, previousCursor.y - previousCursor.w);

    // Pre-calculate saturated trail color ONCE
    vec4 trailColor = saturate(iCurrentCursorColor, 2.0);
    
    // Animation progress
    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    
    vec2 centerCC = vec2(currentCursor.x + (currentCursor.z * 0.5), currentCursor.y - (currentCursor.w * 0.5));
    vec2 centerCP = vec2(previousCursor.x + (previousCursor.z * 0.5), previousCursor.y - (previousCursor.w * 0.5));
    float lineLength = distance(centerCC, centerCP);

    // 3. SDF Evaluations
    vec2 offsetFactor = vec2(-0.5, 0.5);
    float sdfCurrentCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

    // 4. Compositing with optimized AA
    float aaPixel = 2.0 / iResolution.y; 
    float alphaTrail = 1.0 - smoothstep(0.0, aaPixel, sdfTrail);
    float alphaCursor = 1.0 - smoothstep(0.0, aaPixel, sdfCurrentCursor);
    
    vec4 newColor = fragColor;
    newColor = mix(newColor, trailColor, alphaTrail);
    newColor = mix(newColor, trailColor, alphaCursor);
    
    // Restore current cursor base color
    newColor = mix(newColor, fragColor, step(sdfCurrentCursor, 0.0));

    // Final mix
    fragColor = mix(fragColor, newColor, step(sdfCurrentCursor, easedProgress * lineLength));
}
