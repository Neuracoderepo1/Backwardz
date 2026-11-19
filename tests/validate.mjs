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

assert.doesNotMatch(html, /service_role/i);
assert.ok(scripts.length >= 1, 'Application script not found.');
new vm.Script(scripts[scripts.length - 1], { filename: "BACKWARDZ inline application" });
console.log("BACKWARDZ frontend validation: PASS");
console.log("Root entrypoint, required controls, auth/API markers, mobile handling and JS syntax checked.");
console.log("This is static validation, not a real browser or device test.");
