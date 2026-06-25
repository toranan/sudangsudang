import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing required Supabase env vars.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace("Bearer ", "").trim();
  if (!token) {
    return new Response("Unauthorized", { status: 401 });
  }

  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  const userId = authData?.user?.id;
  if (authError || !userId) {
    return new Response("Unauthorized", { status: 401 });
  }

  // Collect related records.
  const { data: workerRows, error: workerRowsError } = await supabase
    .from("workers")
    .select("id")
    .eq("user_id", userId);
  if (workerRowsError) {
    return new Response(`Load workers failed: ${workerRowsError.message}`, { status: 500 });
  }
  const workerIds = (workerRows ?? []).map((row: { id: string }) => row.id);

  const { data: storeRows, error: storeRowsError } = await supabase
    .from("stores")
    .select("id")
    .eq("owner_id", userId);
  if (storeRowsError) {
    return new Response(`Load stores failed: ${storeRowsError.message}`, { status: 500 });
  }
  const storeIds = (storeRows ?? []).map((row: { id: string }) => row.id);

  if (workerIds.length > 0) {
    const { error } = await supabase.from("work_logs").delete().in("worker_id", workerIds);
    if (error) {
      return new Response(`Delete worker logs failed: ${error.message}`, { status: 500 });
    }
  }

  if (storeIds.length > 0) {
    {
      const { error } = await supabase.from("invites").delete().in("store_id", storeIds);
      if (error) {
        return new Response(`Delete invites failed: ${error.message}`, { status: 500 });
      }
    }
    {
      const { error } = await supabase.from("work_logs").delete().in("store_id", storeIds);
      if (error) {
        return new Response(`Delete store logs failed: ${error.message}`, { status: 500 });
      }
    }
    {
      const { error } = await supabase.from("workers").delete().in("store_id", storeIds);
      if (error) {
        return new Response(`Delete store workers failed: ${error.message}`, { status: 500 });
      }
    }
    {
      const { error } = await supabase.from("stores").delete().eq("owner_id", userId);
      if (error) {
        return new Response(`Delete stores failed: ${error.message}`, { status: 500 });
      }
    }
  }

  {
    const { error } = await supabase.from("workers").delete().eq("user_id", userId);
    if (error) {
      return new Response(`Delete worker link failed: ${error.message}`, { status: 500 });
    }
  }
  {
    const { error } = await supabase.from("work_logs").delete().eq("approved_by", userId);
    if (error) {
      return new Response(`Delete approvals failed: ${error.message}`, { status: 500 });
    }
  }
  {
    const { error } = await supabase.from("profiles").delete().eq("id", userId);
    if (error) {
      return new Response(`Delete profile failed: ${error.message}`, { status: 500 });
    }
  }

  const { error: authDeleteError } = await supabase.auth.admin.deleteUser(userId);
  if (authDeleteError) {
    return new Response(`Auth delete failed: ${authDeleteError.message}`, { status: 500 });
  }

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
