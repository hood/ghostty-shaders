
const float DURATION = 0.8;          // animation length in seconds
const float TWIRL_RADIUS = 0.015;     // twirl extent in normalized units
const float TWIRL_STRENGTH = 4.14;   // max rotation in radians

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

float ease(float x) {
    return pow(1.0 - x, 2.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 vu = normPos(fragCoord);

    vec4 currentCursor  = vec4(normPos(iCurrentCursor.xy),  normSize(iCurrentCursor.zw));
    vec4 previousCursor = vec4(normPos(iPreviousCursor.xy), normSize(iPreviousCursor.zw));

    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress); // 1 at start, 0 at end

    vec2 centerCC = vec2(currentCursor.x  + currentCursor.z  * 0.5, currentCursor.y  - currentCursor.w  * 0.5);
    vec2 centerCP = vec2(previousCursor.x + previousCursor.z * 0.5, previousCursor.y - previousCursor.w * 0.5);

    // Twirl center sweeps from previous → current as the animation plays.
    vec2 twirlCenter = mix(centerCP, centerCC, 1.0 - easedProgress);

    // Rotate sample coords around the twirl center, with strength
    // that falls off with distance and decays over the animation.
    vec2 delta = vu - twirlCenter;
    float dist = length(delta);
    float falloff = 1.0 - smoothstep(0.0, TWIRL_RADIUS, dist);
    float angle = TWIRL_STRENGTH * falloff * easedProgress;
    float c = cos(angle), s = sin(angle);
    vec2 rotated = vec2(c * delta.x - s * delta.y, s * delta.x + c * delta.y);
    vec2 warpedVu = twirlCenter + rotated;

    // Inverse of normPos: convert warped normalized coord back to texture UV.
    vec2 sampleUv = (warpedVu * iResolution.y + iResolution.xy) * 0.5 / iResolution.xy;

    #if !defined(WEB)
    fragColor = texture(iChannel0, sampleUv);
    vec4 baseColor = texture(iChannel0, fragCoord.xy / iResolution.xy);
    #else
    fragColor = vec4(0.0);
    vec4 baseColor = vec4(0.0);
    #endif

    // Keep the cursor itself unwarped so it stays legible.
    vec2 offsetFactor = vec2(-0.5, 0.5);
    float sdfCursor = getSdfRectangle(vu, currentCursor.xy - currentCursor.zw * offsetFactor, currentCursor.zw * 0.5);
    fragColor = mix(fragColor, baseColor, step(sdfCursor, 0.0));
}
