import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const html = readFileSync(new URL("../index.html", import.meta.url), "utf8");
const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)]
  .map(match => match[1]).filter(source => source.trim());

for (const token of [
  '<title>BACKWARD', 'id="cv"', 'id="bd"', 'id="be"', 'id="br"',
  'id="retry"', 'id="finishretry"', 'id="playstatus"', 'viewport-fit=cover',
  '100dvh', 'touch-action:none', 'backward_daily_leaderboard_public',
  'functions/v1/backward-game', 'signInAnonymously', 'verified_score',
  'visibilitychange', 'resume_run', 'backward_active_run'
]) assert.ok(html.includes(token), 'Missing frontend requirement: ' + token);

// Regression guard: successful selections and timeouts share settle(),
// which must enter reveal before the asynchronous save begins.
assert.ok(html.includes("async function settle(ok,rt,responseIndex){\n if(st.phase!=='play')return;\n st.phase='reveal';"),
  'Selection/timeout settlement must enter the reveal phase before saving.');
assert.ok(html.includes("function continueAfterTrial(ok){\n st.phase='reveal';"),
  'The saved-round continuation must preserve the reveal phase.');
assert.ok(html.includes("st.phase==='reveal'&&i===st.odd"),
  'The correct orbit must be highlighted while the reveal phase is active.');
assert.ok(html.includes("if(f<=0)settle(false,st.limit*1000,null);"),
  'A round timeout must settle through the same reveal path as a selection.');
assert.ok(html.includes("ctx.shadowColor=acc;ctx.shadowBlur=Math.max(12,cell*.22)"),
  'The revealed correct orbit must have a strong green glow for clear visibility.');
assert.ok(html.includes("ctx.lineWidth=Math.max(5,cell*.085)"),
  'The revealed correct orbit ring must be thick enough to distinguish clearly.');
assert.ok(html.includes("reveal?Math.max(4,cell*.11)"),
  'The revealed moving dot must be enlarged for clear visibility.');
assert.ok(html.includes("Correct orbit revealed · saving round "),
  'The reveal state must be announced while the round save is pending.');
assert.ok(html.includes("ctx.fillStyle=reveal?acc:(i===st.flash?bad:dot)"),
  'The correct orbit reveal must also color its moving dot using the success accent.');
assert.ok(html.includes("},ok?700:1100);"),
  'The reveal must remain visible before advancing after success or timeout.');

// Native share rejection can happen after the tap's transient user activation expires.
// Never attempt an asynchronous clipboard fallback from that rejection handler.
assert.ok(html.includes("navigator.share({text:txt}).catch(function(err){$('bs').textContent=err&&err.name==='AbortError'?'Share result':'Share unavailable';});"),
  'Native share cancellation/failure must not trigger a clipboard write outside the tap.');
assert.ok(!html.includes('.catch(()=>copyShare(txt))'),
  'Do not fall back to clipboard after the native share promise rejects.');

assert.ok(html.includes('id="tm" aria-label="Time remaining"'),
  'A visible countdown label must be present in the HUD.');
assert.ok(html.includes('role="progressbar" aria-label="Time remaining"'),
  'The countdown bar must expose progress semantics to assistive technology.');
assert.ok(html.includes("$('tm').textContent=label"),
  'The visible countdown must update during active gameplay.');

assert.doesNotMatch(html, /service_role/i);
assert.ok(scripts.length >= 1, 'Application script not found.');
new vm.Script(scripts[scripts.length - 1], { filename: "BACKWARDZ inline application" });
console.log("BACKWARDZ frontend validation: PASS");
console.log("Root entrypoint, required controls, auth/API markers, mobile handling and JS syntax checked.");
console.log("This is static validation, not a real browser or device test.");
