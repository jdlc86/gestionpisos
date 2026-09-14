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
  const GREEN_SCORE = 0.50;
  const YELLOW_SCORE = 0.29;
  const MIN_GREEN_ZONE = 0.22;
  const MIN_YELLOW_ZONE = 0.12;
  const GREEN_FRAMES_REQUIRED = 5;

  let filteredScore = 0;
  let timer = 0;
  let greenFrames = 0;

  function renderState(score, zoneScores, texturePenalty = 1) {
    const usefulZones = zoneScores.filter(v => v >= MIN_YELLOW_ZONE).length;
    const greenZones = zoneScores.filter(v => v >= MIN_GREEN_ZONE).length;
    const weakest = Math.min(...zoneScores);

    const stableGreen =
      score >= GREEN_SCORE &&
      greenZones >= 5 &&
      weakest >= 0.10 &&
      texturePenalty >= 0.72;

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
    window.__allaisoTexturePenalty = +texturePenalty.toFixed(3);
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
    const scale = 260 / Math.max(ow, oh);
    const w = Math.max(116, Math.round(ow * scale));
    const h = Math.max(116, Math.round(oh * scale));

    if (frameCanvas.width !== w || frameCanvas.height !== h) {
      frameCanvas.width = maskCanvas.width = w;
      frameCanvas.height = maskCanvas.height = h;
    }

    if (!drawVideoFrame(w, h) || !drawGuideMask(w, h)) return;

    const frame = frameCtx.getImageData(0, 0, w, h).data;
    const mask = maskCtx.getImageData(0, 0, w, h).data;
    const gray = new Uint8Array(w * h);
    const alpha = new Uint8Array(w * h);

    for (let i = 0, p = 0; i < frame.length; i += 4, p++) {
      gray[p] = (frame[i] * 77 + frame[i + 1] * 150 + frame[i + 2] * 29) >> 8;
      alpha[p] = mask[i + 3];
    }

    const zoneStrength = new Float32Array(ZONE_COLS * ZONE_ROWS);
    const zoneHits = new Uint32Array(ZONE_COLS * ZONE_ROWS);
    const zoneSamples = new Uint32Array(ZONE_COLS * ZONE_ROWS);

    let outsideEdgeTotal = 0;
    let outsideSamples = 0;

    for (let y = 3; y < h - 3; y += 3) {
      for (let x = 3; x < w - 3; x += 3) {
        const p = y * w + x;
        if (alpha[p] >= 32) continue;

        const gx = gray[p + 1] - gray[p - 1];
        const gy = gray[p + w] - gray[p - w];
        outsideEdgeTotal += Math.min(1, Math.hypot(gx, gy) / 110);
        outsideSamples++;
      }
    }

    const outsideEdgeMean = outsideSamples ? outsideEdgeTotal / outsideSamples : 0;

    for (let y = 4; y < h - 4; y += 2) {
      for (let x = 4; x < w - 4; x += 2) {
        const p = y * w + x;
        if (alpha[p] < 48) continue;

        const mgx = alpha[p + 1] - alpha[p - 1];
        const mgy = alpha[p + w] - alpha[p - w];
        const mNorm = Math.hypot(mgx, mgy);

        if (mNorm < 18) continue;

        const enx = mgx / mNorm;
        const eny = mgy / mNorm;

        let best = 0;

        for (let oy = -2; oy <= 2; oy++) {
          for (let ox = -2; ox <= 2; ox++) {
            const q = (y + oy) * w + x + ox;
            const fgx = gray[q + 1] - gray[q - 1];
            const fgy = gray[q + w] - gray[q - w];
            const fNorm = Math.hypot(fgx, fgy);
            if (fNorm < 16) continue;

            const strength = Math.min(1, Math.max(0, (fNorm - 18) / 95));
            const orientation = Math.abs((fgx / fNorm) * enx + (fgy / fNorm) * eny);
            const oriented = strength * orientation * orientation;

            if (oriented > best) best = oriented;
          }
        }

        const zx = Math.min(ZONE_COLS - 1, Math.floor(x * ZONE_COLS / w));
        const zy = Math.min(ZONE_ROWS - 1, Math.floor(y * ZONE_ROWS / h));
        const zone = zy * ZONE_COLS + zx;

        zoneStrength[zone] += best;
        zoneSamples[zone]++;
        if (best >= 0.34) zoneHits[zone]++;
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
      zoneScores.push(meanStrength * 0.60 + hitCoverage * 0.40);
    }

    if (populated < 4) return;

    const ordered = [...zoneScores].sort((a, b) => a - b);
    const trimmed = ordered.slice(1);
    const spatialScore = trimmed.reduce((a, b) => a + b, 0) / trimmed.length;
    const balancePenalty = 0.68 + 0.32 * Math.min(1, ordered[1] / 0.30);

    const texturePenalty = Math.max(
      0.58,
      Math.min(1, 1.08 - Math.max(0, outsideEdgeMean - 0.20) * 1.35)
    );

    const rawScore = spatialScore * balancePenalty * texturePenalty;

    filteredScore = filteredScore
      ? filteredScore * 0.70 + rawScore * 0.30
      : rawScore;

    renderState(filteredScore, zoneScores, texturePenalty);
  }

  function watchCamera() {
    if (!overlay.hidden && !timer) {
      filteredScore = 0;
      greenFrames = 0;
      renderState(0, [0, 0, 0, 0, 0, 0], 1);
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
  event.detail.texturePenalty = window.__allaisoTexturePenalty ?? null;
});
