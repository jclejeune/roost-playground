const element = id => document.getElementById(id);
let generation = 0;
let previewURL;
let polling = false;
let lastStatus;

function render(state) {
  element('filename').textContent = state.filename;
  element('dot').dataset.phase = state.phase;
  const seconds = state.buildMilliseconds == null ? '' : ` · ${(state.buildMilliseconds / 1000).toFixed(1)}s`;
  const message = ({ building: state.progress || 'Building…', ready: `${state.cacheHit ? 'Cached' : 'Live'}${seconds}`, failed: 'Needs attention', stopped: 'Stopped' })[state.phase];
  if (element('status').textContent !== message) element('status').textContent = message;
  element('generation').textContent = state.generation ? `Build ${state.generation}` : 'First build';
  const failed = state.phase === 'failed';
  element('diagnostic-panel').hidden = !failed;
  const diagnostics = state.diagnostics || '';
  if (element('diagnostics').textContent !== diagnostics) element('diagnostics').textContent = diagnostics;
  element('log-path').textContent = state.logPath ? `Full output: ${state.logPath}` : '';
  element('preview-note').textContent = state.previewURL ? 'Last working preview remains live below' : 'Save your file to try again';
  if (state.previewURL && (state.generation !== generation || state.previewURL !== previewURL)) {
    element('preview').src = state.previewURL;
    generation = state.generation;
    previewURL = state.previewURL;
  }
  element('preview').hidden = !state.previewURL;
  element('empty').hidden = Boolean(state.previewURL) || failed;
  lastStatus = state;
}

async function poll() {
  if (polling) return;
  polling = true;
  try {
    const response = await fetch('/__playground/status', { cache: 'no-store', signal: AbortSignal.timeout(3000) });
    if (!response.ok) throw new Error(`Status ${response.status}`);
    render(await response.json());
  } catch {
    element('dot').dataset.phase = 'stopped';
    element('status').textContent = 'Runner disconnected';
    if (!lastStatus?.previewURL) element('empty-message').textContent = 'Start the playground command again to reconnect.';
  } finally { polling = false; }
}

poll();
setInterval(poll, 500);
