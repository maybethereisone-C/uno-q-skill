// Front-end logic — talks to python/main.py over Socket.IO.
// Based on: app-bricks-examples/examples/blink-with-ui/assets/app.js
//
// Event-name contract (must match main.py):
//   we emit  'get_initial_state' / 'command'   -> ui.on_message(...) in Python
//   we listen 'state_update'                   <- ui.send_message('state_update', ...)
// The web_ui brick serves Socket.IO at the same origin, so io(...) connects back to it.

const valueEl = document.getElementById('value');
const actionButton = document.getElementById('action-button');
let errorContainer;

// Connect to the server that served this page (the web_ui brick on port 7000).
const socket = io(`http://${window.location.host}`);

document.addEventListener('DOMContentLoaded', () => {
    errorContainer = document.getElementById('error-container');
    initSocketIO();
    actionButton.addEventListener('click', handleAction);
});

function initSocketIO() {
    socket.on('connect', () => {
        socket.emit('get_initial_state', {});   // ask main.py for current state
        hideError();
    });

    // TODO match this to whatever main.py broadcasts via ui.send_message(...)
    socket.on('state_update', (msg) => render(msg));

    socket.on('disconnect', () => {
        showError('Connection to the board lost. Check the cable / app.');
    });
}

// TODO render your real state
function render(state) {
    valueEl.textContent = state.value;
}

// TODO send your real command. main.py handles it via ui.on_message('command', ...)
function handleAction() {
    socket.emit('command', { /* TODO payload */ });
}

function showError(text) {
    if (!errorContainer) return;
    errorContainer.textContent = text;
    errorContainer.style.display = 'block';
}

function hideError() {
    if (!errorContainer) return;
    errorContainer.style.display = 'none';
    errorContainer.textContent = '';
}
