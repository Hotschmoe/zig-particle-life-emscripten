pub const particleDescription =
    \\struct Particle
    \\{
    \\    x : f32,
    \\    y : f32,
    \\    vx : f32,
    \\    vy : f32,
    \\    species : f32,
    \\}
;

pub const speciesDescription =
    \\struct Species
    \\{
    \\    color : vec4f,
    \\}
;

pub const forceDescription =
    \\struct Force
    \\{
    \\    strength: f32, // positive if attraction
    \\    radius: f32,
    \\    collisionStrength : f32,
    \\    collisionRadius: f32,
    \\}
;

pub const simulationOptionsDescription =
    \\struct SimulationOptions
    \\{
    \\    left : f32,
    \\    right : f32,
    \\    bottom : f32,
    \\    top : f32,
    \\    friction : f32,
    \\    dt : f32,
    \\    binSize : f32,
    \\    speciesCount : f32,
    \\    centralForce : f32,
    \\    loopingBorders : f32,
    \\    actionX : f32,
    \\    actionY : f32,
    \\    actionVX : f32,
    \\    actionVY : f32,
    \\    actionForce : f32,
    \\    actionRadius : f32,
    \\}
    \\
    \\struct BinInfo
    \\{
    \\    gridSize : vec2i,
    \\    binId : vec2i,
    \\    binIndex : i32,
    \\}
    \\
    \\fn getBinInfo(position : vec2f, simulationOptions : SimulationOptions) -> BinInfo
    \\{
    \\    let gridSize = vec2i(
    \\        i32(ceil((simulationOptions.right - simulationOptions.left) / simulationOptions.binSize)),
    \\        i32(ceil((simulationOptions.top - simulationOptions.bottom) / simulationOptions.binSize)),
    \\    );
    \\
    \\    let binId = vec2i(
    \\        clamp(i32(floor((position.x - simulationOptions.left) / simulationOptions.binSize)), 0, gridSize.x - 1),
    \\        clamp(i32(floor((position.y - simulationOptions.bottom) / simulationOptions.binSize)), 0, gridSize.y - 1)
    \\    );
    \\
    \\    let binIndex = binId.y * gridSize.x + binId.x;
    \\
    \\    return BinInfo(gridSize, binId, binIndex);
    \\}
;

pub const binFillSizeShader = particleDescription ++ "\n" ++ simulationOptionsDescription ++ "\n" ++
    \\
    \\@group(0) @binding(0) var<storage, read> particles : array<Particle>;
    \\
    \\@group(1) @binding(0) var<uniform> simulationOptions : SimulationOptions;
    \\
    \\@group(2) @binding(0) var<storage, read_write> binSize : array<atomic<u32>>;
    \\
    \\@compute @workgroup_size(64)
    \\fn clearBinSize(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&binSize)) {
    \\        return;
    \\    }
    \\
    \\    atomicStore(&binSize[id.x], 0u);
    \\}
    \\
    \\@compute @workgroup_size(64)
    \\fn fillBinSize(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&particles)) {
    \\        return;
    \\    }
    \\
    \\    let particle = particles[id.x];
    \\
    \\    let binIndex = getBinInfo(vec2f(particle.x, particle.y), simulationOptions).binIndex;
    \\
    \\    atomicAdd(&binSize[binIndex + 1], 1u);
    \\}
;

pub const binPrefixSumShader =
    \\@group(0) @binding(0) var<storage, read> source : array<u32>;
    \\@group(0) @binding(1) var<storage, read_write> destination : array<u32>;
    \\@group(0) @binding(2) var<uniform> stepSize : u32;
    \\
    \\@compute @workgroup_size(64)
    \\fn prefixSumStep(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&source)) {
    \\        return;
    \\    }
    \\
    \\    if (id.x < stepSize) {
    \\        destination[id.x] = source[id.x];
    \\    } else {
    \\        destination[id.x] = source[id.x - stepSize] + source[id.x];
    \\    }
    \\}
;

pub const particleSortShader = particleDescription ++ "\n" ++ simulationOptionsDescription ++ "\n" ++
    \\
    \\@group(0) @binding(0) var<storage, read> source : array<Particle>;
    \\@group(0) @binding(1) var<storage, read_write> destination : array<Particle>;
    \\@group(0) @binding(2) var<storage, read> binOffset : array<u32>;
    \\@group(0) @binding(3) var<storage, read_write> binSize : array<atomic<u32>>;
    \\
    \\@group(1) @binding(0) var<uniform> simulationOptions : SimulationOptions;
    \\
    \\@compute @workgroup_size(64)
    \\fn clearBinSize(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&binSize)) {
    \\        return;
    \\    }
    \\
    \\    atomicStore(&binSize[id.x], 0u);
    \\}
    \\
    \\@compute @workgroup_size(64)
    \\fn sortParticles(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&source)) {
    \\        return;
    \\    }
    \\
    \\    let particle = source[id.x];
    \\
    \\    let binIndex = getBinInfo(vec2f(particle.x, particle.y), simulationOptions).binIndex;
    \\
    \\    let newParticleIndex = binOffset[binIndex] + atomicAdd(&binSize[binIndex], 1);
    \\    destination[newParticleIndex] = particle;
    \\}
;

pub const particleComputeForcesShader = particleDescription ++ "\n" ++ forceDescription ++ "\n" ++ simulationOptionsDescription ++ "\n" ++
    \\
    \\@group(0) @binding(0) var<storage, read> particlesSource : array<Particle>;
    \\@group(0) @binding(1) var<storage, read_write> particlesDestination : array<Particle>;
    \\@group(0) @binding(2) var<storage, read> binOffset : array<u32>;
    \\@group(0) @binding(3) var<storage, read> forces : array<Force>;
    \\
    \\@group(1) @binding(0) var<uniform> simulationOptions : SimulationOptions;
    \\
    \\@compute @workgroup_size(64)
    \\fn computeForces(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&particlesSource)) {
    \\        return;
    \\    }
    \\
    \\    var particle = particlesSource[id.x];
    \\    let species = u32(particle.species);
    \\
    \\    let binInfo = getBinInfo(vec2f(particle.x, particle.y), simulationOptions);
    \\
    \\    let loopingBorders = simulationOptions.loopingBorders == 1.0;
    \\
    \\    var binXMin = binInfo.binId.x - 1;
    \\    var binYMin = binInfo.binId.y - 1;
    \\
    \\    var binXMax = binInfo.binId.x + 1;
    \\    var binYMax = binInfo.binId.y + 1;
    \\
    \\    if (!loopingBorders) {
    \\        binXMin = max(0, binXMin);
    \\        binYMin = max(0, binYMin);
    \\        binXMax = min(binInfo.gridSize.x - 1, binXMax);
    \\        binYMax = min(binInfo.gridSize.y - 1, binYMax);
    \\    }
    \\
    \\    let width = simulationOptions.right - simulationOptions.left;
    \\    let height = simulationOptions.top - simulationOptions.bottom;
    \\
    \\    var totalForce = vec2f(0.0, 0.0);
    \\
    \\    let particlePosition = vec2f(particle.x, particle.y);
    \\
    \\    totalForce -= particlePosition * simulationOptions.centralForce;
    \\
    \\    for (var binX = binXMin; binX <= binXMax; binX += 1) {
    \\        for (var binY = binYMin; binY <= binYMax; binY += 1) {
    \\            var realBinX = (binX + binInfo.gridSize.x) % binInfo.gridSize.x;
    \\            var realBinY = (binY + binInfo.gridSize.y) % binInfo.gridSize.y;
    \\
    \\            let binIndex = realBinY * binInfo.gridSize.x + realBinX;
    \\            let binStart = binOffset[binIndex];
    \\            let binEnd = binOffset[binIndex + 1];
    \\
    \\            for (var j = binStart; j < binEnd; j += 1) {
    \\                if (j == id.x) {
    \\                    continue;
    \\                }
    \\
    \\                let other = particlesSource[j];
    \\                let otherSpecies = u32(other.species);
    \\
    \\                let force = forces[species * u32(simulationOptions.speciesCount) + otherSpecies];
    \\
    \\                var r = vec2f(other.x, other.y) - particlePosition;
    \\
    \\                if (loopingBorders) {
    \\                    if (abs(r.x) >= width * 0.5) {
    \\                        r.x -= sign(r.x) * width;
    \\                    }
    \\
    \\                    if (abs(r.y) >= height * 0.5) {
    \\                        r.y -= sign(r.y) * height;
    \\                    }
    \\                }
    \\
    \\                let d = length(r);
    \\                if (d > 0.0 && d < force.radius) {
    \\                    let n = r / d;
    \\
    \\                    totalForce += force.strength * max(0.0, 1.0 - d / force.radius) * n;
    \\                    totalForce -= force.collisionStrength * max(0.0, 1.0 - d / force.collisionRadius) * n;
    \\                }
    \\            }
    \\        }
    \\    }
    \\
    \\    // Assume mass = 1
    \\    particle.vx += totalForce.x * simulationOptions.dt;
    \\    particle.vy += totalForce.y * simulationOptions.dt;
    \\
    \\    particlesDestination[id.x] = particle;
    \\}
;

pub const particleAdvanceShader = particleDescription ++ "\n" ++ simulationOptionsDescription ++ "\n" ++
    \\
    \\@group(0) @binding(0) var<storage, read_write> particles : array<Particle>;
    \\
    \\@group(1) @binding(0) var<uniform> simulationOptions : SimulationOptions;
    \\
    \\@compute @workgroup_size(64)
    \\fn particleAdvance(@builtin(global_invocation_id) id : vec3u)
    \\{
    \\    if (id.x >= arrayLength(&particles)) {
    \\        return;
    \\    }
    \\
    \\    let width = simulationOptions.right - simulationOptions.left;
    \\    let height = simulationOptions.top - simulationOptions.bottom;
    \\
    \\    var particle = particles[id.x];
    \\
    \\    var actionR = vec2f(particle.x, particle.y) - vec2f(simulationOptions.actionX, simulationOptions.actionY);
    \\    if (simulationOptions.loopingBorders == 1.0) {
    \\        if (abs(actionR.x) >= width * 0.5) {
    \\            actionR.x -= sign(actionR.x) * width;
    \\        }
    \\
    \\        if (abs(actionR.y) >= height * 0.5) {
    \\            actionR.y -= sign(actionR.y) * height;
    \\        }
    \\    }
    \\    let actionFactor = simulationOptions.actionForce * exp(- dot(actionR, actionR) / (simulationOptions.actionRadius * simulationOptions.actionRadius));
    \\    particle.vx += simulationOptions.actionVX * actionFactor;
    \\    particle.vy += simulationOptions.actionVY * actionFactor;
    \\
    \\    particle.vx *= simulationOptions.friction;
    \\    particle.vy *= simulationOptions.friction;
    \\
    \\    particle.x += particle.vx * simulationOptions.dt;
    \\    particle.y += particle.vy * simulationOptions.dt;
    \\
    \\    let loopingBorders = simulationOptions.loopingBorders == 1.0;
    \\
    \\    if (loopingBorders) {
    \\        if (particle.x < simulationOptions.left) {
    \\            particle.x += width;
    \\        }
    \\    
    \\        if (particle.x > simulationOptions.right) {
    \\            particle.x -= width;
    \\        }
    \\
    \\        if (particle.y < simulationOptions.bottom) {
    \\            particle.y += height;
    \\        }
    \\    
    \\        if (particle.y > simulationOptions.top) {
    \\            particle.y -= height;
    \\        }
    \\    } else {
    \\        if (particle.x < simulationOptions.left) {
    \\            particle.x = simulationOptions.left;
    \\            particle.vx *= -1.0;
    \\        }
    \\
    \\        if (particle.x > simulationOptions.right) {
    \\            particle.x = simulationOptions.right;
    \\            particle.vx *= -1.0;
    \\        }
    \\
    \\        if (particle.y < simulationOptions.bottom) {
    \\            particle.y = simulationOptions.bottom;
    \\            particle.vy *= -1.0;
    \\        }
    \\
    \\        if (particle.y > simulationOptions.top) {
    \\            particle.y = simulationOptions.top;
    \\            particle.vy *= -1.0;
    \\        }
    \\    }
    \\
    \\    particles[id.x] = particle;
    \\}
;

pub const particleRenderShader = particleDescription ++ "\n" ++ speciesDescription ++ "\n" ++
    \\
    \\struct Camera
    \\{
    \\    center : vec2f,
    \\    extent : vec2f,
    \\    pixelsPerUnit : f32,
    \\}
    \\
    \\@group(0) @binding(0) var<storage, read> particles : array<Particle>;
    \\@group(0) @binding(1) var<storage, read> species : array<Species>;
    \\
    \\@group(1) @binding(0) var<uniform> camera : Camera;
    \\
    \\struct CircleVertexOut
    \\{
    \\    @builtin(position) position : vec4f,
    \\    @location(0) offset : vec2f,
    \\    @location(1) color : vec4f,
    \\}
    \\
    \\const offsets = array<vec2f, 6>(
    \\    vec2f(-1.0, -1.0),
    \\    vec2f( 1.0, -1.0),
    \\    vec2f(-1.0,  1.0),
    \\    vec2f(-1.0,  1.0),
    \\    vec2f( 1.0, -1.0),
    \\    vec2f( 1.0,  1.0),
    \\);
    \\
    \\@vertex
    \\fn vertexGlow(@builtin(vertex_index) id : u32) -> CircleVertexOut
    \\{
    \\    let particle = particles[id / 6u];
    \\    let offset = offsets[id % 6u];
    \\    let position = vec2f(particle.x, particle.y) + 12.0 * offset;
    \\    return CircleVertexOut(
    \\        vec4f((position - camera.center) / camera.extent, 0.0, 1.0),
    \\        offset,
    \\        species[u32(particle.species)].color
    \\    );
    \\}
    \\
    \\@fragment
    \\fn fragmentGlow(in : CircleVertexOut) -> @location(0) vec4f
    \\{
    \\    let l = length(in.offset);
    \\    let alpha = exp(- 6.0 * l * l) / 64.0;
    \\    return in.color * vec4f(1.0, 1.0, 1.0, alpha);
    \\}
    \\
    \\@vertex
    \\fn vertexCircle(@builtin(vertex_index) id : u32) -> CircleVertexOut
    \\{
    \\    let particle = particles[id / 6u];
    \\    let offset = offsets[id % 6u] * 1.5;
    \\    let position = vec2f(particle.x, particle.y) + offset;
    \\    return CircleVertexOut(
    \\        vec4f((position - camera.center) / camera.extent, 0.0, 1.0),
    \\        offset,
    \\        species[u32(particle.species)].color
    \\    );
    \\}
    \\
    \\@fragment
    \\fn fragmentCircle(in : CircleVertexOut) -> @location(0) vec4f
    \\{
    \\    let alpha = clamp(camera.pixelsPerUnit - length(in.offset) * camera.pixelsPerUnit + 0.5, 0.0, 1.0);
    \\    return in.color * vec4f(1.0, 1.0, 1.0, alpha);
    \\}
    \\
    \\@vertex
    \\fn vertexPoint(@builtin(vertex_index) id : u32) -> CircleVertexOut
    \\{
    \\    let particle = particles[id / 6u];
    \\    let offset = 2.0 * offsets[id % 6u] / camera.pixelsPerUnit;
    \\    let position = vec2f(particle.x, particle.y) + offset;
    \\    return CircleVertexOut(
    \\        vec4f((position - camera.center) / camera.extent, 0.0, 1.0),
    \\        offset,
    \\        species[u32(particle.species)].color
    \\    );
    \\}
    \\
    \\const PI = 3.1415926535;
    \\
    \\@fragment
    \\fn fragmentPoint(in : CircleVertexOut) -> @location(0) vec4f
    \\{
    \\    let d = max(vec2(0.0), min(in.offset * camera.pixelsPerUnit + 0.5, vec2(camera.pixelsPerUnit)) - max(in.offset * camera.pixelsPerUnit - 0.5, - vec2(camera.pixelsPerUnit)));
    \\    let alpha = (PI / 4.0) * d.x * d.y;
    \\    return vec4f(in.color.rgb, in.color.a * alpha);
    \\}
;

pub const composeShader =
    \\@group(0) @binding(0) var hdrTexture : texture_2d<f32>;
    \\@group(0) @binding(1) var blueNoiseTexture : texture_2d<f32>;
    \\
    \\const vertices = array<vec2f, 3>(
    \\    vec2f(-1.0, -1.0),
    \\    vec2f( 3.0, -1.0),
    \\    vec2f(-1.0,  3.0),
    \\);
    \\
    \\struct VertexOut
    \\{
    \\    @builtin(position) position : vec4f,
    \\    @location(0) texcoord : vec2f,
    \\}
    \\
    \\@vertex
    \\fn vertexMain(@builtin(vertex_index) id : u32) -> VertexOut
    \\{
    \\    let vertex = vertices[id];
    \\    return VertexOut(
    \\        vec4f(vertex, 0.0, 1.0),
    \\        vertex * 0.5 + vec2f(0.5)
    \\    );
    \\}
    \\
    \\fn acesTonemap(x : vec3f) -> vec3f
    \\{
    \\    let a = 2.51;
    \\    let b = 0.03;
    \\    let c = 2.43;
    \\    let d = 0.59;
    \\    let e = 0.14;
    \\    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3f(0.0), vec3f(1.0));
    \\}
    \\
    \\fn dither(x : vec3f, n : f32) -> vec3f
    \\{
    \\    let c = x * 255.0;
    \\    let c0 = floor(c);
    \\    let c1 = c0 + vec3f(1.0);
    \\    let dc = c - c0;
    \\
    \\    var r = c0;
    \\    if (dc.r > n) { r.r = c1.r; }
    \\    if (dc.g > n) { r.g = c1.g; }
    \\    if (dc.b > n) { r.b = c1.b; }
    \\
    \\    return r / 255.0;
    \\}
    \\
    \\@fragment
    \\fn fragmentMain(in : VertexOut) -> @location(0) vec4f
    \\{
    \\    var sample = textureLoad(hdrTexture, vec2i(in.position.xy), 0); 
    \\    let noise = textureLoad(blueNoiseTexture, vec2u(in.position.xy) % textureDimensions(blueNoiseTexture), 0).r;
    \\
    \\    var color = sample.rgb;
    \\    color = acesTonemap(color);
    \\    color = pow(color, vec3f(1.0 / 2.2));
    \\    color = dither(color, noise);
    \\
    \\    return vec4f(color, 1.0);
    \\}
;
