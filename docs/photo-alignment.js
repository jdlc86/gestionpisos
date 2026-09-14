(()=> {
  const $ = id => document.getElementById(id);
  const overlay = $('cameraOverlay');
  const video = $('cameraVideo');
  const guide = $('cameraGuide');
  const hint = $('alignmentHint');

  const frameCanvas = document.createElement('canvas');
  const maskCanvas = document.createElement('canvas');
  const frameCtx = frameCanvas.getContext('2d', { willReadFrequently: true });
  const maskCtx = maskCanvas.getContext('2d', { willReadFrequently: true });
  const guideImage = new Image();
  guideImage.src = './bench-guide-approved.svg';

  const ZONE_COLS = 3;
  const ZONE_ROWS = 2;
  const GREEN_SCORE = 0.56;
  const YELLOW_SCORE = 0.34;
  const MIN_GREEN_ZONE = 0.28;
  const MIN_YELLOW_ZONE = 0.16;
  const GREEN_FRAMES_REQUIRED = 4;

  let filteredScore = 0;
  let timer = 0;
  let greenFrames = 0;

  function renderState(score, zoneScores) {
    const usefulZones = zoneScores.filter(v => v >= MIN_YELLOW_ZONE).length;
    const greenZones = zoneScores.filter(v => v >= MIN_GREEN_ZONE).length;
    const stableGreen =
      score >= GREEN_SCORE &&
      greenZones >= 5 &&
      Math.min(...zoneScores) >= 0.12;

    greenFrames = stableGreen ? greenFrames + 1 : 0;

    guide.classList.remove(
      'photo-camera__guide--pending',
      'photo-camera__guide--warn',
      'photo-camera__guide--ok'
    );

    if (greenFrames >= GREEN_FRAMES_REQUIRED) {
      guide.classList.add('photo-camera__guide--ok');
      hint.textContent =
        'Encuadre correcto · ' + Math.round(score * 100) + '% · ' + greenZones + '/6 zonas';
    } else if (score >= YELLOW_SCORE && usefulZones >= 4) {
      guide.classList.add('photo-camera__guide--warn');
      hint.textContent =
        'Casi alineado · ' + Math.round(score * 100) + '% · ' + usefulZones + '/6 zonas';
    } else {
      guide.classList.add('photo-camera__guide--pending');
      hint.textContent =
        'Ajusta el encuadre · ' + Math.round(score * 100) + '% · ' + usefulZones + '/6 zonas';
    }

    window.__allaisoAlignmentScore = +score.toFixed(3);
    window.__allaisoAlignmentZones = zoneScores.map(v => +v.toFixed(3));
  }

  function drawVideoFrame(w, h) {
    const vw = video.videoWidth;
    const vh = video.videoHeight;
    if (!vw || !vh) return false;

    let sx = 0, sy = 0, sw = vw, sh = vh;
    const videoRatio = vw / vh;
    const targetRatio = w / h;

    if (videoRatio > targetRatio) {
      sw = vh * targetRatio;
      sx = (vw - sw) / 2;
    } else {
      sh = vw / targetRatio;
      sy = (vh - sh) / 2;
    }

    frameCtx.drawImage(video, sx, sy, sw, sh, 0, 0, w, h);
    return true;
  }

  function drawGuideMask(w, h) {
    if (!guideImage.complete || !guideImage.naturalWidth) return false;

    maskCtx.clearRect(0, 0, w, h);

    const overlayRect = overlay.getBoundingClientRect();
    const guideRect = guide.getBoundingClientRect();
    if (!overlayRect.width || !guideRect.width) return false;

    const kx = w / overlayRect.width;
    const ky = h / overlayRect.height;
    const gx = (guideRect.left - overlayRect.left) * kx;
    const gy = (guideRect.top - overlayRect.top) * ky;
    const gw = guideRect.width * kx;
    const gh = guideRect.height * ky;

    const imageRatio = guideImage.naturalWidth / guideImage.naturalHeight;
    const boxRatio = gw / gh;
    let dw = gw;
    let dh = gh;

    if (imageRatio > boxRatio) dh = gw / imageRatio;
    else dw = gh * imageRatio;

    maskCtx.drawImage(
      guideImage,
      gx + (gw - dw) / 2,
      gy + (gh - dh) / 2,
      dw,
      dh
    );
    return true;
  }

  function analyze() {
    if (overlay.hidden || video.readyState < 2) return;

    const ow = Math.max(1, overlay.clientWidth);
    const oh = Math.max(1, overlay.clientHeight);
    const scale = 240 / Math.max(ow, oh);
    const w = Math.max(108, Math.round(ow * scale));
    const h = Math.max(108, Math.round(oh * scale));

    if (frameCanvas.width !== w || frameCanvas.height !== h) {
      frameCanvas.width = maskCanvas.width = w;
      frameCanvas.height = maskCanvas.height = h;
    }

    if (!drawVideoFrame(w, h) || !drawGuideMask(w, h)) return;

    const frame = frameCtx.getImageData(0, 0, w, h).data;
    const mask = maskCtx.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h);

    for (let i = 0, p = 0; i < frame.length; i += 4, p++) {
      gray[p] = (frame[i] * 77 + frame[i + 1] * 150 + frame[i + 2] * 29) >> 8;
    }

    const zoneStrength = new Float32Array(ZONE_COLS * ZONE_ROWS);
    const zoneHits = new Uint32Array(ZONE_COLS * ZONE_ROWS);
    const zoneSamples = new Uint32Array(ZONE_COLS * ZONE_ROWS);

    for (let y = 3; y < h - 3; y += 2) {
      for (let x = 3; x < w - 3; x += 2) {
        const p = y * w + x;
        if (mask[p * 4 + 3] < 48) continue;

        let best = 0;
        for (let oy = -2; oy <= 2; oy++) {
          for (let ox = -2; ox <= 2; ox++) {
            const q = (y + oy) * w + x + ox;
            const gx = Math.abs(gray[q + 1] - gray[q - 1]);
            const gy = Math.abs(gray[q + w] - gray[q - w]);
            const edge = gx + gy;
            if (edge > best) best = edge;
          }
        }

        const strength = Math.min(1, Math.max(0, (best - 28) / 118));
        const zx = Math.min(ZONE_COLS - 1, Math.floor(x * ZONE_COLS / w));
        const zy = Math.min(ZONE_ROWS - 1, Math.floor(y * ZONE_ROWS / h));
        const zone = zy * ZONE_COLS + zx;

        zoneStrength[zone] += strength;
        zoneSamples[zone]++;
        if (strength >= 0.42) zoneHits[zone]++;
      }
    }

    const zoneScores = [];
    let populated = 0;

    for (let i = 0; i < zoneSamples.length; i++) {
      if (zoneSamples[i] < 4) {
        zoneScores.push(0);
        continue;
      }

      populated++;
      const meanStrength = zoneStrength[i] / zoneSamples[i];
      const hitCoverage = zoneHits[i] / zoneSamples[i];
      zoneScores.push(meanStrength * 0.55 + hitCoverage * 0.45);
    }

    if (populated < 4) return;

    const ordered = [...zoneScores].sort((a, b) => a - b);
    const trimmed = ordered.slice(1);
    const spatialScore = trimmed.reduce((a, b) => a + b, 0) / trimmed.length;
    const balancePenalty = 0.7 + 0.3 * Math.min(1, ordered[1] / 0.35);
    const rawScore = spatialScore * balancePenalty;

    filteredScore = filteredScore
      ? filteredScore * 0.68 + rawScore * 0.32
      : rawScore;

    renderState(filteredScore, zoneScores);
  }

  function watchCamera() {
    if (!overlay.hidden && !timer) {
      filteredScore = 0;
      greenFrames = 0;
      renderState(0, [0, 0, 0, 0, 0, 0]);
      analyze();
      timer = setInterval(analyze, 250);
    } else if (overlay.hidden && timer) {
      clearInterval(timer);
      timer = 0;
      greenFrames = 0;
    }
  }

  setInterval(watchCamera, 200);

  window.addEventListener('pagehide', () => {
    if (timer) clearInterval(timer);
  });
})();

window.addEventListener('allaiso:photo-captured', event => {
  if (!event.detail) return;
  event.detail.alignmentScore = window.__allaisoAlignmentScore ?? null;
  event.detail.alignmentZones = window.__allaisoAlignmentZones ?? null;
});
