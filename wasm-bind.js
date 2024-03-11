let memory;

const width = 1140;
const height = 640;

const scale = `vec2(${width / 2.0}, ${height / 2.0})`;

const _rect_vertexShader = `
attribute vec2 a_position;

uniform vec4 u_rect;
uniform float u_rot;

varying highp vec2 v_textureCoord;

void main() {
    vec2 coord = a_position;
    coord = coord * (u_rect.zw / vec2(${width / 2.0}, ${height / 2.0}));
    coord = coord + (u_rect.xy / vec2(${width / 2.0}, ${height / 2.0}));
    gl_Position = vec4(coord - vec2(1, 1), 0, 1);
    v_textureCoord = vec2(a_position.x, 1.0 - a_position.y);
}
`;

const rect_vertexShader = `
attribute vec2 a_position;

uniform vec4 u_rect;
uniform float u_rot;

varying highp vec2 v_textureCoord;

void main() {
    vec2 coord = a_position;
    coord = coord * u_rect.zw;
    coord -= (u_rect.zw) / 2.0;
    coord *= mat2(cos(u_rot),-sin(u_rot),
                  sin(u_rot), cos(u_rot));
    coord += (u_rect.zw) / 2.0;
    coord = coord + u_rect.xy;
    coord /= vec2(${width / 2.0}, ${height / 2.0});
    gl_Position = vec4(coord - vec2(1, 1), 0, 1);
    v_textureCoord = vec2(a_position.x, 1.0 - a_position.y);
}
`;

const rect_fragmentShader = `
precision mediump float;

uniform vec4 u_color;

void main() {
    gl_FragColor = u_color;
}
`;

const borderRect_fragmentShader = `
precision mediump float;

varying highp vec2 v_textureCoord;

uniform vec4 u_color;
uniform highp vec4 u_rect;
uniform float u_border;

void main() {
    vec2 coord = u_rect.zw * v_textureCoord;
    if (u_border < coord.x && coord.x < u_rect.z - u_border &&
        u_border < coord.y && coord.y < u_rect.w - u_border) {
        discard;
    } else {
        gl_FragColor = u_color;
    }
}
`;

const texturedRect_fragmentShader = `
precision mediump float;

varying highp vec2 v_textureCoord;

uniform sampler2D u_sampler;

void main() {
    gl_FragColor = texture2D(u_sampler, v_textureCoord);
}
`;

const circle_fragmentShader = `
precision mediump float;

varying highp vec2 v_textureCoord;
uniform highp vec4 u_rect;
uniform vec4 u_color;

void main() {
    float dist = distance(v_textureCoord, vec2(0.5,0.5));

    float radius = 0.5;
    float eps = 0.5 / u_rect.w;
    gl_FragColor = vec4(
        u_color.rgb, 
        u_color.a * (1.0 - smoothstep(radius - eps, radius + eps, dist))
    );
}
`;

const readCharStr = (ptr, len) => {
  const bytes = new Uint8Array(memory.buffer, ptr, len);
  return new TextDecoder("utf-8").decode(bytes);
}
const canvas = document.getElementById("canvas"); 
canvas.setAttribute("width", width);
canvas.setAttribute("height", height);

/** @type{WebGLRenderingContext} */
const gl = canvas.getContext('webgl', { 
    alpha: false,
    premultipliedAlpha: false,
})
    || canvas.getContext('experimental-webgl');
gl.viewport(0, 0, canvas.width, canvas.height);

const fpsCounter = document.getElementById("fps-display");

// --- GLOBALS ---
const shaders = [];
const glPrograms = [];
let texturedRectProgram;
let rectProgram;
let borderRectProgram;
let circleProgram;

const glBuffers = [];
let quadPositionBuffer;
let quadTextureCoordBuffer;

const glUniformLocations = [];
const textures = [];

// --- WebGL ---

function createTexturedRectProgram() {
    const texturedRectProgramId = createShaderProgram(
        rect_vertexShader,
        texturedRect_fragmentShader
    );

    texturedRectProgram = {
        id: texturedRectProgramId,
        attribs: {
            position: gl.getAttribLocation(
                glPrograms[texturedRectProgramId],
                "a_position"
            ),
        },
        uniforms: {
            rect: gl.getUniformLocation(
                glPrograms[texturedRectProgramId],
                "u_rect",
            ),
            rot: gl.getUniformLocation(
                glPrograms[texturedRectProgramId],
                "u_rot",
            ),
            sampler: gl.getUniformLocation(
                glPrograms[texturedRectProgramId],
                "u_sampler",
            ),
        }
    };
}

function createRectProgram() {
    const rectProgramId = createShaderProgram(
        rect_vertexShader,
        rect_fragmentShader,
    );

    rectProgram = {
        id: rectProgramId,
        attribs: {
            position: gl.getAttribLocation(
                glPrograms[rectProgramId],
                "a_position"
            ),
        },
        uniforms: {
            rect: gl.getUniformLocation(
                glPrograms[rectProgramId],
                "u_rect",
            ),
            color: gl.getUniformLocation(
                glPrograms[rectProgramId],
                "u_color",
            ),
        }
    };
}

function createBorderRectProgram() {
    const borderRectProgramId = createShaderProgram(
        rect_vertexShader,
        borderRect_fragmentShader,
    );

    borderRectProgram = {
        id: borderRectProgramId,
        attribs: {
            position: gl.getAttribLocation(
                glPrograms[borderRectProgramId],
                "a_position"
            ),
        },
        uniforms: {
            rect: gl.getUniformLocation(
                glPrograms[borderRectProgramId],
                "u_rect",
            ),
            color: gl.getUniformLocation(
                glPrograms[borderRectProgramId],
                "u_color",
            ),
            border: gl.getUniformLocation(
                glPrograms[borderRectProgramId],
                "u_border",
            ),
        }
    };
}

function createCircleProgram() {
    const circleProgramId = createShaderProgram(
        rect_vertexShader,
        circle_fragmentShader,
    );

    circleProgram = {
        id: circleProgramId,
        attribs: {
            position: gl.getAttribLocation(
                glPrograms[circleProgramId],
                "a_position"
            ),
        },
        uniforms: {
            rect: gl.getUniformLocation(
                glPrograms[circleProgramId],
                "u_rect",
            ),
            color: gl.getUniformLocation(
                glPrograms[circleProgramId],
                "u_color",
            ),
        }
    };
}

const initGL = () => {
    gl.clearColor(0.1, 0.1, 0.1, 1.0);
    // gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    createTexturedRectProgram();
    createRectProgram();
    createBorderRectProgram();
    createCircleProgram();

    // Position Buffer
    const quadPositions = [ 
        0, 0, 
        0, 1, 
        1, 1,
        1, 0,
    ];
    quadPositionBuffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, quadPositionBuffer);
    gl.bufferData(
        gl.ARRAY_BUFFER,
        new Float32Array(quadPositions), 
        gl.STATIC_DRAW,
    );
}

function createShader(source, type) {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if(!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
        throw "Error compiling shader:" + gl.getShaderInfoLog(shader);
    }
    shaders.push(shader);
    return shaders.length - 1;
}

const linkShaderProgram = (vertexShaderId, fragmentShaderId) => {
    const program = gl.createProgram();
    gl.attachShader(program, shaders[vertexShaderId]);
    gl.attachShader(program, shaders[fragmentShaderId]);
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
        throw ("Error linking program:" + gl.getProgramInfoLog (program));
    }
    glPrograms.push(program);
    return glPrograms.length - 1;
}

// --- BINDINGS ---

function createShaderProgram(vertexShaderSource, fragmentShaderSource) {
    const vertexShaderId = createShader(
        vertexShaderSource,
        gl.VERTEX_SHADER
    );
    const fragmentShaderId = createShader(
        fragmentShaderSource,
        gl.FRAGMENT_SHADER
    );

    return linkShaderProgram(vertexShaderId, fragmentShaderId);
}

function loadTexture(url_ptr, url_len) {
    const url = readCharStr(url_ptr, url_len);
    const texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);

    // Because images have to be downloaded over the internet
    // they might take a moment until they are ready.
    // Until then put a single pixel in the texture so we can
    // use it immediately. When the image has finished downloading
    // we'll update the texture with the contents of the image.

    const level = 0;
    const internalFormat = gl.RGBA;
    const width = 1;
    const height = 1;
    const border = 0;
    const srcFormat = gl.RGBA;
    const srcType = gl.UNSIGNED_BYTE;
    const pixel = new Uint8Array([0, 0, 255, 0]); // opaque blue
    gl.texImage2D(
        gl.TEXTURE_2D,
        level,
        internalFormat,
        width,
        height,
        border,
        srcFormat,
        srcType,
        pixel,
    );

    const image = new Image();
    image.onload = () => {
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(
            gl.TEXTURE_2D,
            level,
            internalFormat,
            srcFormat,
            srcType,
            image,
        );

        // WebGL1 has different requirements for power of 2 images
        // vs. non power of 2 images so check if the image is a
        // power of 2 in both dimensions.
        if (isPowerOf2(image.width) && isPowerOf2(image.height)) {
            // Yes, it's a power of 2. Generate mips.
            gl.generateMipmap(gl.TEXTURE_2D);
        } else {
            // No, it's not a power of 2. Turn off mips and set
            // wrapping to clamp to edge
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
            gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
        }
    };
    image.src = url;

    textures.push(texture);
    return textures.length - 1;
}

function isPowerOf2(value) {
  return (value & (value - 1)) === 0;
}

const log_err = 0;
const log_warn = 1;
const log_info = 2;
const log_debug = 3;
const logExt = (logPtr, logLen, messageLevel) => {
    switch(messageLevel) {
        case log_err:
            console.error(readCharStr(logPtr, logLen));
            break;
        case log_warn: 
            console.warn(readCharStr(logPtr, logLen));
            break;
        case log_info: 
            console.info(readCharStr(logPtr, logLen));
            break;
        case log_debug: 
            console.log(readCharStr(logPtr, logLen));
            break;
    }
}

/**
 * @param {number} x
 * @param {number} y
 * @param {number} r
 * @param {number} w
 * @param {number} h
 * @param {number} texture_index
 */
function drawTextureRect(x, y, r, w, h, texture_id) {
    gl.useProgram(glPrograms[texturedRectProgram.id]);
    gl.enableVertexAttribArray(texturedRectProgram.attribs.position);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadPositionBuffer);
    gl.vertexAttribPointer(quadPositionBuffer, 2, gl.FLOAT, 0, 0, 0);

    gl.uniform4fv(
        texturedRectProgram.uniforms.rect,
        [x, y, w, h],
    );
    gl.uniform1f(
        texturedRectProgram.uniforms.rot,
        r
    );

    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, textures[texture_id]);
    gl.uniform1i(texturedRectProgram.uniforms.sampler, 0);

    gl.drawArrays(
        gl.TRIANGLE_FAN,
        0,
        4,
    );
}

/**
 * @param {number} x
 * @param {number} y
 * @param {number} w
 * @param {number} h
 * @param {number} r
 * @param {number} g
 * @param {number} b
 * @param {number} a
 */
function drawRect(x, y, w, h, r, g, b, a) {
    gl.useProgram(glPrograms[rectProgram.id]);
    gl.enableVertexAttribArray(rectProgram.attribs.position);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadPositionBuffer);
    gl.vertexAttribPointer(quadPositionBuffer, 2, gl.FLOAT, 0, 0, 0);

    gl.uniform4fv(
        rectProgram.uniforms.rect,
        [x, y, w, h],
    );

    gl.uniform4fv(rectProgram.uniforms.color, [r, g, b, a]);

    gl.drawArrays(
        gl.TRIANGLE_FAN,
        0,
        4,
    );
}

/**
 * @param {number} x
 * @param {number} y
 * @param {number} w
 * @param {number} h
 * @param {number} border
 * @param {number} r
 * @param {number} g
 * @param {number} b
 * @param {number} a
 */
function drawBorderRect(x, y, w, h, border, r, g, b, a) {
    gl.useProgram(glPrograms[borderRectProgram.id]);
    gl.enableVertexAttribArray(borderRectProgram.attribs.position);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadPositionBuffer);
    gl.vertexAttribPointer(quadPositionBuffer, 2, gl.FLOAT, 0, 0, 0);

    gl.uniform4fv(
        borderRectProgram.uniforms.rect,
        [x, y, w, h],
    );

    gl.uniform4fv(borderRectProgram.uniforms.color, [r, g, b, a]);
    gl.uniform1f(borderRectProgram.uniforms.border, border);

    gl.drawArrays(
        gl.TRIANGLE_FAN,
        0,
        4,
    );
}

/**
 * @param {number} x
 * @param {number} y
 * @param {number} w
 * @param {number} h
 * @param {number} r
 * @param {number} g
 * @param {number} b
 * @param {number} a
 */
function drawCircle(x, y, w, h, r, g, b, a) {
    gl.useProgram(glPrograms[circleProgram.id]);
    gl.enableVertexAttribArray(circleProgram.attribs.position);
    gl.bindBuffer(gl.ARRAY_BUFFER, quadPositionBuffer);
    gl.vertexAttribPointer(quadPositionBuffer, 2, gl.FLOAT, 0, 0, 0);

    gl.uniform4fv(
        circleProgram.uniforms.rect,
        [x, y, w, h],
    );

    gl.uniform4fv(circleProgram.uniforms.color, [r, g, b, a]);

    gl.drawArrays(
        gl.TRIANGLE_FAN,
        0,
        4,
    );
}

function clear() {
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
}

const env = {
    loadTexture,
    logExt,
    drawTextureRect,
    drawRect,
    drawBorderRect,
    drawCircle,
    clear,
};

// ---- INPUT HANDLING ---

// Event Type enum
const EventType__button_down = 0;
const EventType__button_up = 1;

const keycodes = {
    "KeyW": 0,
    "KeyA": 1,
    "KeyS": 2,
    "KeyD": 3,
    "MouseL": 4,
    "MouseR": 5,
}

function captureMouse() {
}

function registerEventHandlers(handler, mouseHandler, gameState) {
    window.addEventListener("click", () => {
        canvas.requestPointerLock();
    });

    window.addEventListener("keydown", event => {
        const keycode = keycodes[event.code];

        if (keycode !== undefined) {
            handler(gameState, EventType__button_down, keycode);
        }
    });

    window.addEventListener("keyup", event => {
        const keycode = keycodes[event.code];

        if (keycode !== undefined) {
            handler(gameState, EventType__button_up, keycode);
        }
    });

    window.addEventListener("mousedown", event => {
        if (document.pointerLockElement === canvas) {
            let keycode = undefined;

            switch (event.button) {
                case 0:
                    keycode = keycodes["MouseL"];
                    break;
                case 2:
                    keycode = keycodes["MouseR"];
                    break;
            }

            if (keycode !== undefined) {
                handler(gameState, EventType__button_down, keycode);
            }
        }
    });

    window.addEventListener("mouseup", event => {
        if (document.pointerLockElement === canvas) {
            let keycode = undefined;

            switch (event.button) {
                case 0:
                    keycode = keycodes["MouseL"];
                    break;
                case 2:
                    keycode = keycodes["MouseR"];
                    break;
            }

            if (keycode !== undefined) {
                handler(gameState, EventType__button_up, keycode);
            }
        }
    });

    window.addEventListener("mousemove", event => {
        if (document.pointerLockElement === canvas) {
            mouseHandler(
                gameState,
                event.movementX,
                event.movementY,
            );
        }
    });
}

// ---- ENTRY POINT ----

fetchAndInstantiate('main.wasm', {env}).then(function(instance) {
    initGL();

    memory = instance.exports.memory;
    const gameState = instance.exports.onInit(width, height);

    const onAnimationFrame = instance.exports.onAnimationFrame;

    const handleEvent = instance.exports.handleEvent;
    const handleMouse = instance.exports.handleMouse;
    registerEventHandlers(handleEvent, handleMouse, gameState);

    var prevTimestamp = 0;

    const updateFPSTime = 100;
    var updateFPSTimeElapsed = -1;

    function step(timestamp) {
        const delta = timestamp - prevTimestamp;
        updateFPSTimeElapsed -= delta;
        if(updateFPSTimeElapsed < 0) {
            fpsCounter.innerText = `FPS: ${(1000/delta).toFixed(1)}`;
            updateFPSTimeElapsed = updateFPSTime;
        }
        prevTimestamp = timestamp;
        
        onAnimationFrame(gameState, timestamp);
        window.requestAnimationFrame(step);
    }
    window.requestAnimationFrame(step);
});

async function fetchAndInstantiate(url, importObject) {
    const response = await fetch(url);
    const bytes = await response.arrayBuffer();
    const results = await WebAssembly.instantiate(bytes, importObject);
    return results.instance;
}

