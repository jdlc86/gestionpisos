(()=> {
  const $ = id => document.getElementById(id);
  const overlay = $('cameraOverlay');
  const video = $('cameraVideo');
  const canvas = $('captureCanvas');
  const loading = $('cameraLoading');
  const flashButton = $('flashCamera');
  const message = $('cameraMessage');
  const preview = $('preview');

  let stream = null;
  let torchOn = false;
  let capturedUrl = null;

  function activeTrack() {
    return stream?.getVideoTracks?.()[0] || null;
  }

  function updateFlashUi() {
    const track = activeTrack();
    let supported = false;
    try {
      supported = Boolean(track?.getCapabilities?.().torch);
    } catch {}

    flashButton.classList.toggle('is-on', torchOn);
    flashButton.classList.toggle('is-unsupported', !supported);
    flashButton.disabled = !track;
    flashButton.setAttribute('aria-label', torchOn ? 'Desactivar flash' : 'Activar flash');
  }

  async function setTorch(next) {
    const track = activeTrack();
    if (!track) return;

    let supported = false;
    try {
      supported = Boolean(track.getCapabilities?.().torch);
    } catch {}

    if (!supported) {
      torchOn = false;
      updateFlashUi();
      message.textContent = 'El flash no está disponible en este dispositivo o navegador.';
      return;
    }

    try {
      await track.applyConstraints({ advanced: [{ torch: Boolean(next) }] });
      const settings = track.getSettings?.();
      torchOn = typeof settings?.torch === 'boolean' ? settings.torch : Boolean(next);
      updateFlashUi();
    } catch {
      torchOn = false;
      updateFlashUi();
      message.textContent = 'No se pudo controlar el flash en este dispositivo.';
    }
  }

  function stopCamera() {
    const current = stream;
    stream = null;
    torchOn = false;
    if (current) current.getTracks().forEach(track => track.stop());
    video.srcObject = null;
    overlay.hidden = true;
    document.documentElement.classList.remove('camera-open');
    updateFlashUi();
  }

  async function openCamera() {
    if (!navigator.mediaDevices?.getUserMedia) {
      message.textContent = 'Este navegador no permite acceso directo a la cámara.';
      return;
    }

    loading.hidden = false;
    overlay.hidden = false;
    document.documentElement.classList.add('camera-open');

    try {
      stream = await navigator.mediaDevices.getUserMedia({
        audio: false,
        video: {
          facingMode: { ideal: 'environment' },
          width: { ideal: 1920 },
          height: { ideal: 1080 }
        }
      });

      video.srcObject = stream;
      await video.play();
      updateFlashUi();
      loading.hidden = true;
      message.textContent = '';
    } catch (error) {
      stopCamera();
      const name = String(error?.name || '');
      message.textContent = name === 'NotAllowedError'
        ? 'Necesitamos permiso de cámara para realizar la fotoverificación.'
        : 'No se pudo abrir la cámara en este dispositivo.';
    }
  }

  async function capture() {
    if (!video.videoWidth || !video.videoHeight) return;

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;
    const ctx = canvas.getContext('2d', { alpha: false });
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);

    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/jpeg', 0.9));
    if (!blob) {
      message.textContent = 'No se pudo generar la fotografía.';
      return;
    }

    if (capturedUrl) URL.revokeObjectURL(capturedUrl);
    capturedUrl = URL.createObjectURL(blob);
    preview.src = capturedUrl;
    preview.hidden = false;

    window.dispatchEvent(new CustomEvent('allaiso:photo-captured', {
      detail: {
        blob,
        width: canvas.width,
        height: canvas.height,
        alignmentScore: null
      }
    }));

    stopCamera();
    message.textContent = 'Fotografía capturada. La subida privada se conectará al cerrar el flujo autenticado.';
  }

  $('openCamera').addEventListener('click', openCamera);
  $('closeCamera').addEventListener('click', stopCamera);
  $('captureCamera').addEventListener('click', capture);
  flashButton.addEventListener('click', () => setTorch(!torchOn));

  document.addEventListener('visibilitychange', () => {
    if (document.hidden && !overlay.hidden) stopCamera();
  });

  window.addEventListener('pagehide', stopCamera);
})();

const cameraMode = new URLSearchParams(window.location.search).get("mode");
if (cameraMode !== "pattern") {
  import("./photo-alignment.js").catch(()=>{});
}
