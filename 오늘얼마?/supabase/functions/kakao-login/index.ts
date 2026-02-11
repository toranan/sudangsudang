import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT } from "npm:jose@5.2.4";

type KakaoUserResponse = {
  id: number;
  kakao_account?: {
    email?: string;
  };
};

type LoginRequest = {
  access_token?: string;
};

type LoginResponse = {
  access_token: string;
  token_type: "bearer";
  expires_in: number;
  user_id: string;
  email?: string | null;
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_JWT_SECRET =
  Deno.env.get("JWT_SECRET") ??
  Deno.env.get("SUPABASE_JWT_SECRET") ??
  "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !SUPABASE_JWT_SECRET) {
  throw new Error("Missing required Supabase env vars.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

const JWT_TTL_SECONDS = 60 * 60 * 24 * 90; // 90 days

async function ensureProfile(userId: string, email: string | null, kakaoId: string) {
  const { data: existingProfile, error: profileByIdError } = await supabase
    .from("profiles")
    .select("id")
    .eq("id", userId)
    .maybeSingle();

  if (profileByIdError) {
    return new Response(`Profile lookup failed: ${profileByIdError.message}`, {
      status: 500,
    });
  }

  if (existingProfile?.id) {
    const { error: updateError } = await supabase
      .from("profiles")
      .update({ kakao_id: kakaoId, email })
      .eq("id", userId);
    if (updateError) {
      return new Response(`Profile update failed: ${updateError.message}`, {
        status: 500,
      });
    }
  } else {
    const { error: insertError } = await supabase
      .from("profiles")
      .insert({ id: userId, email, kakao_id: kakaoId });
    if (insertError) {
      return new Response(`Profile insert failed: ${insertError.message}`, {
        status: 500,
      });
    }
  }

  return null;
}

async function findUserByEmail(email: string) {
  const { data, error } = await supabase.auth.admin.listUsers({ email });
  if (error) {
    return { user: null as typeof data.users[number] | null, error };
  }
  const normalized = email.toLowerCase();
  const user = data?.users?.find((item) => item.email?.toLowerCase() === normalized) ?? null;
  return { user, error: null };
}

Deno.serve(async (req) => {
  console.log("kakao-login invoked", { method: req.method });
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  let payload: LoginRequest;
  try {
    payload = await req.json();
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  if (!payload.access_token) {
    console.error("Missing access_token in request body");
    return new Response("Missing access_token", { status: 400 });
  }

  const kakaoResponse = await fetch("https://kapi.kakao.com/v2/user/me", {
    headers: {
      Authorization: `Bearer ${payload.access_token}`,
    },
  });

  if (!kakaoResponse.ok) {
    const text = await kakaoResponse.text();
    console.error("Kakao validation failed", {
      status: kakaoResponse.status,
      body: text,
    });
    return new Response(`Kakao validation failed: ${text}`, { status: 401 });
  }

  const kakaoData = (await kakaoResponse.json()) as KakaoUserResponse;
  const kakaoId = String(kakaoData.id);
  const kakaoEmail = kakaoData.kakao_account?.email ?? null;

  const { data: profile, error: profileError } = await supabase
    .from("profiles")
    .select("id,email")
    .eq("kakao_id", kakaoId)
    .maybeSingle();

  if (profileError) {
    return new Response(`Profile lookup failed: ${profileError.message}`, { status: 500 });
  }

  let userId = profile?.id as string | undefined;
  let email = profile?.email ?? kakaoEmail;

  if (!userId && kakaoEmail) {
    const { user: existingUser, error: existingUserError } =
      await findUserByEmail(kakaoEmail);
    if (existingUserError) {
      return new Response(`User lookup failed: ${existingUserError.message}`, {
        status: 500,
      });
    }
    if (existingUser) {
      userId = existingUser.id;
      email = existingUser.email ?? kakaoEmail;
      const ensureError = await ensureProfile(userId, email, kakaoId);
      if (ensureError) {
        return ensureError;
      }
    }
  }

  if (!userId) {
    const generatedEmail = kakaoEmail ?? `kakao_${kakaoId}@kakao.local`;
    const { data: userData, error: userError } = await supabase.auth.admin.createUser({
      email: generatedEmail,
      email_confirm: true,
      user_metadata: {
        kakao_id: kakaoId,
        provider: "kakao",
      },
    });

    if (userError || !userData?.user) {
      const message = userError?.message ?? "unknown";
      if (
        message.includes("already been registered") ||
        message.toLowerCase().includes("already exists")
      ) {
        const { user: existingUser, error: existingUserError } =
          await findUserByEmail(generatedEmail);
        if (existingUserError || !existingUser) {
          return new Response(`User lookup failed: ${existingUserError?.message ?? "unknown"}`, {
            status: 500,
          });
        }
        userId = existingUser.id;
        email = existingUser.email ?? generatedEmail;
        const ensureError = await ensureProfile(userId, email, kakaoId);
        if (ensureError) {
          return ensureError;
        }
      } else {
        return new Response(`User create failed: ${message}`, { status: 500 });
      }
    }

    if (!userId && userData?.user) {
      userId = userData.user.id;
      email = userData.user.email ?? generatedEmail;
      const ensureError = await ensureProfile(userId, email, kakaoId);
      if (ensureError) {
        return ensureError;
      }
    }
  }

  const now = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({
    role: "authenticated",
    email,
    app_metadata: { provider: "kakao" },
    user_metadata: { kakao_id: kakaoId },
  })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuedAt(now)
    .setExpirationTime(now + JWT_TTL_SECONDS)
    .setSubject(userId)
    .setAudience("authenticated")
    .sign(new TextEncoder().encode(SUPABASE_JWT_SECRET));

  const response: LoginResponse = {
    access_token: jwt,
    token_type: "bearer",
    expires_in: JWT_TTL_SECONDS,
    user_id: userId,
    email,
  };

  return new Response(JSON.stringify(response), {
    status: 200,
    headers: {
      "Content-Type": "application/json",
    },
  });
});
