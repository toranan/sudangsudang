import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// 앱의 '문의하기'를 받아 inquiries 테이블에 남기고, 운영자 메일로 바로 보낸다.
// 필요한 시크릿: RESEND_API_KEY, INQUIRY_TO_EMAIL
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const INQUIRY_TO_EMAIL = Deno.env.get("INQUIRY_TO_EMAIL") ?? "";

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
  throw new Error("Missing required Supabase env vars.");
}

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

type InquiryBody = {
  category?: string;
  message?: string;
  role?: string;
  contact?: string;
  appVersion?: string;
  device?: string;
};

function escapeHtml(text: string): string {
  return text
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const token = (req.headers.get("authorization") ?? "").replace("Bearer ", "").trim();
  if (!token) {
    return new Response("Unauthorized", { status: 401 });
  }
  const { data: authData, error: authError } = await supabase.auth.getUser(token);
  const user = authData?.user;
  if (authError || !user) {
    return new Response("Unauthorized", { status: 401 });
  }

  let body: InquiryBody;
  try {
    body = await req.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }
  const message = (body.message ?? "").trim().slice(0, 4000);
  if (!message) {
    return new Response("Empty message", { status: 400 });
  }
  const category = (body.category ?? "기타").slice(0, 40);
  const role = (body.role ?? "").slice(0, 20);
  const contact = (body.contact ?? "").trim().slice(0, 200);
  const appVersion = (body.appVersion ?? "").slice(0, 40);
  const device = (body.device ?? "").slice(0, 80);

  const { data: inserted, error: insertError } = await supabase
    .from("inquiries")
    .insert({
      user_id: user.id,
      role,
      category,
      message,
      contact: contact || null,
      app_version: appVersion || null,
      device: device || null,
    })
    .select("id")
    .single();
  if (insertError) {
    return new Response(`Save inquiry failed: ${insertError.message}`, { status: 500 });
  }

  // 메일은 실패해도 문의는 테이블에 남아 있으니 성공으로 돌려준다.
  let emailed = false;
  if (RESEND_API_KEY && INQUIRY_TO_EMAIL) {
    const replyTo = contact.includes("@") ? contact : user.email ?? undefined;
    const html = [
      `<p><b>${escapeHtml(category)}</b> · ${escapeHtml(role || "알 수 없음")}</p>`,
      `<p style="white-space:pre-wrap">${escapeHtml(message)}</p>`,
      "<hr>",
      `<p>연락처: ${escapeHtml(contact || "-")}<br>계정: ${escapeHtml(user.email ?? user.id)}<br>`,
      `앱 ${escapeHtml(appVersion || "-")} · ${escapeHtml(device || "-")}<br>문의 ID: ${inserted.id}</p>`,
    ].join("");
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "수당수당 문의 <onboarding@resend.dev>",
        to: [INQUIRY_TO_EMAIL],
        reply_to: replyTo,
        subject: `[수당수당 문의] ${category} - ${message.slice(0, 30)}`,
        html,
      }),
    });
    emailed = response.ok;
    if (!response.ok) {
      console.error("Resend failed", response.status, await response.text());
    }
  }

  return Response.json({ id: inserted.id, emailed });
});
