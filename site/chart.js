// The web of rhumb lines sea charts were drawn on, the same one Kaizu shows
// in an empty space: a rose in the middle and sixteen around it, each casting
// the 32 compass bearings. The eight winds are dark, half winds green, quarter
// winds red.
const INKS = [
  { color: "28, 37, 65", alpha: 0.2, width: 0.8, step: 4, from: 0 },
  { color: "78, 125, 108", alpha: 0.3, width: 0.65, step: 4, from: 2 },
  { color: "140, 44, 39", alpha: 0.22, width: 0.65, step: 2, from: 1 },
];
const DRAWING = 1600;
const calm = matchMedia("(prefers-reduced-motion: reduce)").matches;

function fit(canvas) {
  const scale = Math.min(devicePixelRatio || 1, 2);
  const { width, height } = canvas.getBoundingClientRect();
  canvas.width = width * scale;
  canvas.height = height * scale;
  const paint = canvas.getContext("2d");
  paint.scale(scale, scale);
  return { paint, width, height };
}

function drawWeb({ paint, width, height }, x, y, radius, reach) {
  const length = Math.hypot(width, height) * 1.3 * reach;
  const roses = [[x, y]];
  for (let i = 0; i < 16; i++) {
    const angle = (i * Math.PI) / 8;
    roses.push([x + radius * Math.cos(angle), y + radius * Math.sin(angle)]);
  }
  paint.clearRect(0, 0, width, height);
  for (const ink of INKS) {
    paint.strokeStyle = `rgba(${ink.color}, ${ink.alpha})`;
    paint.lineWidth = ink.width;
    paint.beginPath();
    for (const [rx, ry] of roses) {
      for (let bearing = ink.from; bearing < 32; bearing += ink.step) {
        const angle = (bearing * Math.PI) / 16;
        paint.moveTo(rx, ry);
        paint.lineTo(rx + length * Math.cos(angle), ry + length * Math.sin(angle));
      }
    }
    paint.stroke();
  }
}

// The hero's web grows out from the rose once, as the rose finds north.
const heroCanvas = document.getElementById("web");
const rose = document.getElementById("rose");
let drawnAt = 0;

let heroPaper;

function drawHero(reach) {
  const box = heroCanvas.getBoundingClientRect();
  const mark = rose.getBoundingClientRect();
  const x = mark.left + mark.width / 2 - box.left;
  const y = mark.top + mark.height / 2 - box.top;
  heroPaper ||= fit(heroCanvas);
  drawWeb(heroPaper, x, y, Math.max(box.width, box.height) * 0.3, reach);
}

function growHero(now) {
  drawnAt ||= now;
  const progress = Math.min(1, (now - drawnAt) / DRAWING);
  drawHero(1 - (1 - progress) ** 3);
  if (progress < 1) requestAnimationFrame(growHero);
}

// How far each harbour sits from the straight edge of the land, in shares of
// the page width: enough to swing the names, as a real shore would.
const BAYS = [0.015, 0.035, 0.01, -0.02, -0.005, 0.02, 0.03, 0.01, -0.015, 0, 0.02];
// Rows don't get taller on a wide screen, so the bays stop getting deeper.
const WIDEST_SWAY = 1440;
const SHORE_STEP = 9;
// Radians. Past this a name leans into its neighbours.
const STEEPEST_NAME = 0.2;

function drawCoast() {
  const coast = document.getElementById("coast");
  const land = document.getElementById("land");
  const ports = document.getElementById("ports");
  const items = [...ports.children];
  const { width, height } = coast.getBoundingClientRect();
  const name = items[0].querySelector("h2");
  name.style.transform = "none";
  const edge = name.getBoundingClientRect().right - coast.getBoundingClientRect().left;
  name.style.transform = "";

  // Off the left of the page, out along every harbour, and back: a headland.
  const knots = [
    { y: -40, x: -60 },
    ...items.map((item, i) => {
      const title = item.querySelector("h2");
      return {
        y: ports.offsetTop + title.offsetTop + title.offsetHeight / 2,
        x: edge + BAYS[i % BAYS.length] * Math.min(width, WIDEST_SWAY),
        item,
      };
    }),
    { y: height + 40, x: -60 },
  ];
  const slopes = knots.map((knot, i) => {
    const before = knots[Math.max(i - 1, 0)];
    const after = knots[Math.min(i + 1, knots.length - 1)];
    return (after.x - before.x) / (after.y - before.y);
  });

  const shoreAt = (y) => {
    let i = 0;
    while (i < knots.length - 2 && knots[i + 1].y < y) i++;
    const a = knots[i];
    const b = knots[i + 1];
    const span = b.y - a.y;
    const t = (y - a.y) / span;
    const t2 = t * t;
    const t3 = t2 * t;
    return (
      (2 * t3 - 3 * t2 + 1) * a.x +
      (t3 - 2 * t2 + t) * span * slopes[i] +
      (-2 * t3 + 3 * t2) * b.x +
      (t3 - t2) * span * slopes[i + 1]
    );
  };
  // Small bays and points on top of the long curve.
  const rough = (y) => 5 * Math.sin(y / 37) + 3 * Math.sin(y / 17 + 1) + 1.6 * Math.sin(y / 7 + 2);

  const shore = [];
  for (let y = -40; y <= height + 40; y += SHORE_STEP) {
    shore.push(`${(shoreAt(y) + rough(y)).toFixed(1)} ${y}`);
  }
  const line = `M${shore.join("L")}`;
  const marks = [];
  for (const [i, knot] of knots.entries()) {
    if (!knot.item) continue;
    const major = knot.item.classList.contains("major");
    knot.item.style.setProperty("--shift", `${knot.x - edge}px`);
    const tilt = Math.atan(-slopes[i]);
    knot.item.style.setProperty(
      "--tilt",
      `${Math.max(-STEEPEST_NAME, Math.min(STEEPEST_NAME, tilt))}rad`,
    );
    marks.push(
      `<circle cx="${(knot.x + rough(knot.y)).toFixed(1)}" cy="${knot.y.toFixed(1)}" r="${major ? 4.5 : 3}" fill="${major ? "#7A2335" : "#1C2541"}"/>`,
    );
  }
  land.setAttribute("viewBox", `0 0 ${width} ${height}`);
  land.innerHTML = `
    <path d="${line}V${height + 40}H-60V-40Z" fill="#EBE2CC"/>
    <path d="${line}" fill="none" stroke="#A37A33" stroke-opacity=".35" stroke-width="7"/>
    <path d="${line}" fill="none" stroke="#1C2541" stroke-width="1.25"/>
    ${marks.join("")}`;

  drawWeb(fit(document.getElementById("sea")), width * 0.78, height * 0.5, height * 0.3, 1);
}

function redraw() {
  heroPaper = null;
  drawHero(1);
  drawCoast();
}

let settled = false;
const sizes = new ResizeObserver(() => {
  if (settled) redraw();
});
sizes.observe(document.body);

drawCoast();
document.fonts?.ready.then(() => {
  drawCoast();
  settled = true;
});

if (calm) {
  drawHero(1);
} else {
  requestAnimationFrame(growHero);
}

document.getElementById("copy").addEventListener("click", async (event) => {
  const text = document.getElementById("command").textContent;
  await navigator.clipboard.writeText(text);
  event.target.textContent = "Copied";
  setTimeout(() => {
    event.target.textContent = "Copy";
  }, 1600);
});
