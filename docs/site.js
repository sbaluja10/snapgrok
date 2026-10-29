const desk = document.querySelector(".desk");
const snap = document.getElementById("snap");
const send = document.getElementById("send");
const typed = document.getElementById("typed");
const status = document.getElementById("status");

const link = "https://is.gd/fold";
let timer = 0;
let typing = 0;
let busy = false;

function click() {
  const AudioCtx = window.AudioContext || window.webkitAudioContext;
  if (!AudioCtx) return;
  const ctx = new AudioCtx();
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = "triangle";
  osc.frequency.value = 210;
  gain.gain.setValueAtTime(0.05, ctx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.09);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start();
  osc.stop(ctx.currentTime + 0.09);
  osc.onended = () => ctx.close();
}

function typeLink() {
  window.clearInterval(typing);
  typed.textContent = "";
  let i = 0;
  typing = window.setInterval(() => {
    i += 1;
    typed.textContent = link.slice(0, i);
    if (i >= link.length) {
      window.clearInterval(typing);
      typed.innerHTML = `<a href="https://example.com/fitted-sheet?attempt=4">${link}</a>`;
      status.textContent = "Staged. The short link still opens attempt 4. You send it.";
    }
  }, 45);
}

function play() {
  if (busy) return;
  busy = true;
  window.clearTimeout(timer);
  send.classList.remove("is-yours");
  send.textContent = "Send";
  desk.classList.remove("is-snapped");
  desk.classList.remove("is-arming");
  typed.textContent = "";
  snap.classList.add("is-pressed");
  status.textContent = "Crop marks on the window…";
  click();
  requestAnimationFrame(() => desk.classList.add("is-arming"));
  timer = window.setTimeout(() => {
    desk.classList.add("is-snapped");
    status.textContent = "In the composer. Still unsent.";
    typeLink();
    snap.classList.remove("is-pressed");
    busy = false;
  }, 420);
}

snap.addEventListener("click", play);

window.addEventListener("keydown", (event) => {
  if (event.repeat) return;
  if (event.altKey && event.shiftKey && event.code === "KeyG") {
    event.preventDefault();
    play();
  }
});

send.addEventListener("click", () => {
  if (!desk.classList.contains("is-snapped")) {
    status.textContent = "Nothing is staged yet.";
    return;
  }
  send.textContent = "That’s yours";
  send.classList.add("is-yours");
  status.textContent = "Snapgrok stops here. Return is still on your keyboard.";
});
