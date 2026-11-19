import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.0";

const C = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const R = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...C, "Content-Type": "application/json" } });

function target(seed: number, count: number): number {
  let a = seed >>> 0;
  const random = () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  for (let i = 0; i < count; i++) {
    random();
    random();
  }
  return Math.floor(random() * count);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: C });
  if (req.method !== "POST") return R({ error: "POST required" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anon = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const authz = req.headers.get("Authorization");
  if (!url || !anon || !serviceRole || !authz) {
    return R({ error: "Server authentication is not configured" }, 500);
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return R({ error: "Invalid JSON" }, 400);
  }

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: authz } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const user = userData?.user;
  if (userError || !user) return R({ error: "Valid player session required" }, 401);

  const db = createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (payload.action === "start_run") {
    if (!["daily", "endless"].includes(payload.mode)) {
      return R({ error: "Invalid game mode" }, 400);
    }

    const date = new Date().toISOString().slice(0, 10);
    const seed = payload.mode === "daily"
      ? Number(date.replaceAll("-", ""))
      : crypto.getRandomValues(new Uint32Array(1))[0] % 100000000;
    const device = ["mobile", "tablet", "desktop"].includes(payload.device_class)
      ? payload.device_class
      : "unknown";

    const { error: playerError } = await db.from("backward_players").upsert(
      { user_id: user.id, last_seen_at: new Date().toISOString() },
      { onConflict: "user_id" },
    );
    if (playerError) return R({ error: playerError.message }, 500);

    const { data: run, error } = await db.from("backward_game_runs").insert({
      player_id: user.id,
      mode: payload.mode,
      challenge_date: payload.mode === "daily" ? date : null,
      challenge_seed: seed,
      device_class: device,
      client_version: String(payload.client_version || "1.3.0").slice(0, 32),
    }).select("id,challenge_date,challenge_seed").single();

    if (error || !run) return R({ error: error?.message || "Run creation failed" }, 500);
    return R({ run_id: run.id, challenge_date: run.challenge_date, seed: run.challenge_seed });
  }

  if (payload.action === "resume_run") {
    const id = String(payload.run_id || "");
    if (!id) return R({ error: "Run ID required" }, 400);

    const { data: run, error: runError } = await db.from("backward_game_runs")
      .select("id,mode,challenge_date,challenge_seed,status,claimed_score,verified_score,rounds_completed")
      .eq("id", id)
      .eq("player_id", user.id)
      .maybeSingle();

    if (runError) return R({ error: runError.message }, 500);
    if (!run) return R({ error: "Saved run not found" }, 404);

    const { data: trials, error: trialsError } = await db.from("backward_game_trials")
      .select("round_index,level,outcome,rt_ms,verification_status")
      .eq("run_id", id)
      .order("round_index", { ascending: true });

    if (trialsError) return R({ error: trialsError.message }, 500);
    return R({ run, trials: trials || [] });
  }

  if (payload.action === "submit_trial") {
    const id = String(payload.run_id || "");
    const roundIndex = Number(payload.round_index);
    const level = Number(payload.level);
    const cols = Number(payload.grid_cols);
    const rows = Number(payload.grid_rows);
    const cell = payload.response_cell_index === null
      ? null
      : Number(payload.response_cell_index);
    const rt = Number(payload.rt_ms);
    const variance = Number(payload.speed_variance);

    if (!id || ![roundIndex, level, cols, rows, rt].every(Number.isInteger)
        || !Number.isFinite(variance) || roundIndex < 1) {
      return R({ error: "Invalid trial payload" }, 400);
    }

    const { data: run, error: runError } = await db.from("backward_game_runs")
      .select("id,mode,challenge_seed,status")
      .eq("id", id)
      .eq("player_id", user.id)
      .maybeSingle();

    if (runError) return R({ error: runError.message }, 500);
    if (!run) return R({ error: "Run not found" }, 404);
    if (run.status !== "in_progress") return R({ error: "Run inactive" }, 409);

    const roundSeed = (Number(run.challenge_seed) * 100 + roundIndex - 1) >>> 0;
    const expectedCell = target(roundSeed, cols * rows);
    const { data: result, error: rpcError } = await db.rpc("backward_submit_trial", {
      p_run_id: id,
      p_player_id: user.id,
      p_round_index: roundIndex,
      p_level: level,
      p_grid_cols: cols,
      p_grid_rows: rows,
      p_speed_variance: variance,
      p_round_seed: roundSeed,
      p_response_cell_index: cell,
      p_rt_ms: rt,
      p_expected_cell_index: expectedCell,
    });

    if (rpcError) return R({ error: rpcError.message }, 500);
    if (!result?.ok) {
      return R({ error: result?.error || "Trial rejected" }, Number(result?.status) || 409);
    }
    return R({
      trial: result.trial,
      verified_correct: result.verified_correct,
      idempotent: Boolean(result.idempotent),
    });
  }

  if (payload.action === "finish_run") {
    const id = String(payload.run_id || "");
    const claimedScore = Number(payload.claimed_score);
    if (!id || !Number.isInteger(claimedScore) || claimedScore < 0) {
      return R({ error: "Invalid finish payload" }, 400);
    }

    const { data: result, error } = await db.rpc("backward_finalize_run", {
      p_run_id: id,
      p_player_id: user.id,
      p_claimed_score: claimedScore,
    });
    if (error) return R({ error: error.message }, 500);
    if (!result?.ok) {
      return R({ error: result?.error || "Run finalization rejected" }, Number(result?.status) || 409);
    }
    return R(result);
  }

  return R({ error: "Unknown action" }, 400);
});
