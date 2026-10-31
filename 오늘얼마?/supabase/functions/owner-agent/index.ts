import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

// 사장님용 AI 에이전트. 이 함수는 Claude 호출만 대신한다.
// 도구 실행(조회·급여 계산)은 앱이 화면과 같은 코드로 하고, 결과를 tool_result로 다시 보낸다.
// 근무를 바꾸는 도구는 앱이 확인 카드를 띄우고, 사장님이 확인한 뒤에만 저장한다.
// 그래서 대화 기록 전체를 매 요청마다 앱이 보낸다.

type AgentRequest = {
  storeId: string;
  messages: Anthropic.MessageParam[];
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
const ANTHROPIC_MODEL = Deno.env.get("OWNER_AGENT_MODEL") ?? "claude-sonnet-5-5";

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !ANTHROPIC_API_KEY) {
  throw new Error("Missing required agent env vars.");
}

const anthropic = new Anthropic({ apiKey: ANTHROPIC_API_KEY });

// 한 대화에서 받을 최대 메시지 수. 도구 왕복도 메시지라 넉넉히 둔다.
const MAX_MESSAGES = 60;

const SYSTEM_PROMPT = [
  "너는 소규모 매장 사장님의 근무·급여 관리를 돕는 비서다.",
  "숫자(시간, 금액, 건수)는 반드시 도구 결과에 있는 값만 쓴다. 직접 더하거나 곱해서 새 숫자를 만들지 않는다.",
  "도구 결과에 basis(계산 기준)가 있으면 답에 짧게 함께 쓴다. 예: '승인된 근무 기준'.",
  "이번 달 인건비를 답할 때 homeEstimate가 있으면 승인 기준 금액을 말한 뒤, 대기 근무와 남은 스케줄까지 더한 홈 화면 예상 금액(homeEstimate.total)도 한 문장으로 함께 말한다.",
  "근무 추가·수정, 승인·반려는 도구로 제안하면 앱이 사장님께 확인 카드를 보여 주고, 사장님이 확인해야 저장된다. 확인 전에는 저장됐다고 말하지 않는다.",
  "어떤 알바인지 정해지지 않았으면 글로 묻지 말고 choose_worker를 불러 사장님이 버튼으로 고르게 한다.",
  "주휴수당을 줄지 뺄지, 이번 달 근무에도 적용할지, 승인할지 반려할지처럼 답이 몇 가지로 정해진 질문은 글로 묻지 말고 ask_choice로 버튼을 보여 준다. 날짜·시각·금액처럼 정해지지 않은 값은 글로 묻는다.",
  "근무 길이만 말하면(예: 3시간 근무) 날짜와 출근 시각을 묻고, 퇴근 시각은 출근 시각에 그 길이를 더해 정한다.",
  "근무 추가에는 알바, 날짜, 출근 시각, 퇴근 시각이 모두 필요하다. 사장님 말에 하나라도 분명하지 않으면 추측하거나 스케줄로 채우지 말고 먼저 물어본다. 사장님이 '스케줄대로'라고 하면 get_schedule로 시각을 찾아 쓴다.",
  "'어제', '지난 화요일' 같은 말은 오늘 날짜를 기준으로 YYYY-MM-DD로 바꾼다. '오후 6시'는 18:00이다. 오전·오후가 불분명하면 물어본다.",
  "근무 수정·승인·반려에 필요한 근무 기록 id는 get_work_logs나 list_pending_approvals로 찾는다. 대상이 여러 건으로 해석되면 어느 것인지 묻는다.",
  "시급, 야간·주휴수당, 휴게 설정은 update_payroll_settings로 바꾼다. 알바 이름을 주면 그 알바만, 생략하면 매장 전체가 바뀐다. 누구에게 적용할지 분명하지 않으면 묻는다.",
  "급여 설정을 바꿀 때는 이번 달 이미 일한 근무에도 적용할지(this_month), 앞으로의 근무만 바꿀지(future) ask_choice로 먼저 물어본다. 지난달 이전 근무는 바꿀 수 없다고 안내한다.",
  "결근은 mark_absent로 처리한다. '다', '모두', '전부'처럼 대상이 뭉뚱그려지면 get_schedule로 그날 스케줄이 있는 알바를 찾아 이름을 하나씩 넣는다. 확인 카드에서 사장님이 사람마다 체크를 풀 수 있다.",
  "사장님이 카드를 보고 정정하면(예: '사실 한 명이었어') 누구인지 분명할 때만 새 카드로 다시 제안하고, 분명하지 않으면 누구인지 묻는다. 이전 카드 내용은 저장되지 않았다.",
  "확인 결과에 저장된 대상이 나오면 그 대상만 저장된 것이다. 답할 때 저장된 대상만 말한다.",
  "근무 삭제, 공제 방식·급여일 변경은 아직 할 수 없다. 부탁받으면 할 수 없다고 말하고, 알바관리 화면에서 하면 된다고 알려 준다.",
  "알바 이름이 여러 명과 겹치거나 없으면 도구가 돌려준 이름 목록을 보여 주고 누구인지 묻는다.",
  "연장·휴일 가산수당, 연차, 퇴직금은 앱이 계산하지 않는다. 그걸 물었을 때만 계산에 포함되지 않는다고 말한다.",
  "법 해석이 필요한 질문에는 일반적인 기준만 짧게 말하고, 정확한 판단은 노무사나 고용노동부(국번 없이 1350)에 확인하라고 안내한다.",
  "물어본 것에만 답한다. 묻지 않은 안내, 앞 대화에 대한 덧붙임, '원하시면 ~해 드릴게요' 같은 제안은 쓰지 않는다.",
  "답은 한국어 해요체(~예요, ~있어요)로, 사장님이 바로 읽을 수 있게 짧게 쓴다. 금액은 1,234원처럼 쓴다. 마크다운 표나 제목은 쓰지 않는다.",
].join("\n");

const MONTH = { type: "string", description: "YYYY-MM. 생략하면 이번 달." };
const DATE = (what: string) => ({ type: "string", description: `${what} (YYYY-MM-DD, 한국 날짜)` });
const WORKER_NAME = {
  type: "string",
  description: "알바 이름 또는 이름 일부. 생략하면 매장 전체.",
};

const TOOLS: Anthropic.Tool[] = [
  {
    name: "list_workers",
    description: "매장 알바 목록과 각자의 시급, 야간수당·주휴수당 적용 여부, 휴게 설정, 재직 여부를 조회한다.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "get_month_payroll",
    description:
      "한 달 인건비를 알바별로 조회한다. 승인된 근무 기준의 근무시간, 근무 급여, 주휴수당, 세전 합계와, 아직 승인 대기인 근무의 건수·예상 금액을 따로 돌려준다. 앱의 '상세' 화면과 같은 계산이다. 매장 전체의 이번 달이면 사장님 홈의 '예상 인건비'(대기 근무와 남은 스케줄 포함)도 homeEstimate로 돌려준다.",
    input_schema: {
      type: "object",
      properties: { month: MONTH, worker_name: WORKER_NAME },
    },
  },
  {
    name: "get_weekly_allowance_status",
    description:
      "한 주(월~일)의 주휴수당 상황을 알바별로 조회한다. 지금까지 일한 시간, 남은 스케줄 시간, 주 15시간을 채울지, 받게 될 주휴수당을 돌려준다. 주휴수당이 켜진 알바만 나온다.",
    input_schema: {
      type: "object",
      properties: { date: DATE("이 날짜가 속한 주. 생략하면 이번 주") },
    },
  },
  {
    name: "list_pending_approvals",
    description: "승인을 기다리는 근무 기록을 오래된 순으로 조회한다. 날짜, 출퇴근 시각, 근무시간, 예상 금액이 나온다.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "get_work_logs",
    description: "기간 안의 근무 기록(id, 출퇴근 시각, 승인 상태, 근무시간, 금액)을 조회한다. 최대 100건.",
    input_schema: {
      type: "object",
      properties: {
        from: DATE("시작일"),
        to: DATE("종료일(포함)"),
        worker_name: WORKER_NAME,
      },
      required: ["from", "to"],
    },
  },
  {
    name: "choose_worker",
    description:
      "어떤 알바인지 정해지지 않았을 때 사장님께 매장 알바 이름을 버튼으로 보여 주고 고르게 한다. 결과로 고른 알바 이름이 온다. 사장님이 버튼 대신 글을 쓰면 그 글이 함께 온다.",
    input_schema: {
      type: "object",
      properties: {
        question: { type: "string", description: "버튼 위에 보여 줄 짧은 질문. 예: 누구 근무를 추가할까요?" },
      },
      required: ["question"],
    },
  },
  {
    name: "ask_choice",
    description:
      "답이 몇 가지로 정해진 질문을 사장님께 버튼으로 보여 주고 고르게 한다. 결과로 고른 버튼 글자가 온다. 사장님이 버튼 대신 글을 쓰면 그 글이 함께 온다. 알바를 고를 때는 choose_worker를 쓴다.",
    input_schema: {
      type: "object",
      properties: {
        question: { type: "string", description: "버튼 위에 보여 줄 짧은 질문. 예: 언제부터 적용할까요?" },
        options: {
          type: "array",
          items: { type: "string" },
          minItems: 2,
          maxItems: 4,
          description: "버튼 글자 2~4개. 짧고 뜻이 바로 보이게. 예: [\"이번 달 근무부터\", \"앞으로의 근무만\"]",
        },
      },
      required: ["question", "options"],
    },
  },
  {
    name: "add_work_log",
    description:
      "끝난 근무 하나를 추가하자고 제안한다. 바로 저장되지 않고, 앱이 사장님께 확인 카드를 보여 준다. 사장님이 확인하면 승인된 근무로 저장된다. 퇴근 시각이 출근보다 이르면 다음 날 퇴근으로 본다. 네 값 모두 사장님이 말한 값이어야 한다.",
    input_schema: {
      type: "object",
      properties: {
        worker_name: { type: "string", description: "알바 이름" },
        date: DATE("출근한 날"),
        start_time: { type: "string", description: "출근 시각 HH:mm (24시간)" },
        end_time: { type: "string", description: "퇴근 시각 HH:mm (24시간)" },
      },
      required: ["worker_name", "date", "start_time", "end_time"],
    },
  },
  {
    name: "update_work_log",
    description:
      "기존 근무 기록의 출퇴근 시각을 고치자고 제안한다. 확인 카드로 전후가 보이고, 사장님이 확인하면 저장되며 승인 상태가 된다.",
    input_schema: {
      type: "object",
      properties: {
        log_id: { type: "string", description: "근무 기록 id (get_work_logs 결과의 id)" },
        date: DATE("출근한 날. 바꾸지 않으면 생략"),
        start_time: { type: "string", description: "새 출근 시각 HH:mm" },
        end_time: { type: "string", description: "새 퇴근 시각 HH:mm" },
      },
      required: ["log_id", "start_time", "end_time"],
    },
  },
  {
    name: "set_work_log_status",
    description:
      "퇴근까지 끝난 근무 기록을 승인하거나 반려하자고 제안한다. 여러 건을 한 번에 할 수 있다(최대 30건). 사장님이 확인 카드에서 확인해야 저장된다.",
    input_schema: {
      type: "object",
      properties: {
        log_ids: { type: "array", items: { type: "string" }, description: "근무 기록 id 목록" },
        status: { type: "string", enum: ["approved", "rejected"] },
      },
      required: ["log_ids", "status"],
    },
  },
  {
    name: "update_payroll_settings",
    description:
      "시급, 야간수당, 주휴수당, 무급 휴게 설정을 바꾸자고 제안한다. 바꿀 값만 넣는다. 앱이 확인 카드로 전후와 이번 달 금액 변화를 보여 주고, 사장님이 확인하면 저장된다. 지난달 이전 근무는 바뀌지 않는다.",
    input_schema: {
      type: "object",
      properties: {
        worker_name: { type: "string", description: "알바 이름. 생략하면 매장 전체" },
        hourly_wage: { type: "integer", description: "새 시급(원)" },
        night_allowance: { type: "boolean", description: "야간수당(22~06시 50% 가산) 지급 여부" },
        weekly_allowance: { type: "boolean", description: "주휴수당 지급 여부" },
        break_policy: {
          type: "string",
          enum: ["none", "statutory", "custom"],
          description: "무급 휴게: none 없음, statutory 법정 기준(4시간 30분·8시간 1시간), custom 근무마다 정한 분",
        },
        break_minutes: { type: "integer", description: "break_policy가 custom일 때 근무마다 빼는 분(0~240)" },
        apply_to: {
          type: "string",
          enum: ["future", "this_month"],
          description: "future: 앞으로의 근무만, this_month: 이번 달 이미 일한 근무에도 적용",
        },
      },
      required: ["apply_to"],
    },
  },
  {
    name: "mark_absent",
    description:
      "한 날짜에 알바가 결근했다고 처리하자고 제안한다. 결근으로 기록하고, 그날 출근 기록이 있으면 반려한다. 앱이 사람마다 체크할 수 있는 확인 카드와 그 주 주휴수당 변화를 보여 주고, 사장님이 확인한 사람만 저장된다. 오늘 이후 날짜는 안 된다.",
    input_schema: {
      type: "object",
      properties: {
        date: DATE("결근한 날"),
        worker_names: {
          type: "array",
          items: { type: "string" },
          description: "결근한 알바 이름 목록. '모두'가 아니라 이름을 하나씩 넣는다",
        },
      },
      required: ["date", "worker_names"],
    },
  },
  {
    name: "get_schedule",
    description: "기간 안의 근무 스케줄(누가 언제 출근 예정인지, 결근 처리됐는지)을 조회한다.",
    input_schema: {
      type: "object",
      properties: {
        from: DATE("시작일"),
        to: DATE("종료일(포함)"),
        worker_name: WORKER_NAME,
      },
      required: ["from", "to"],
    },
  },
];

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method Not Allowed" }, 405);
  }

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json({ error: "Unauthorized" }, 401);
  }

  let payload: AgentRequest;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  if (!payload.storeId || !Array.isArray(payload.messages) || payload.messages.length === 0) {
    return json({ error: "Missing fields" }, 400);
  }
  if (payload.messages.length > MAX_MESSAGES) {
    return json({ error: "Conversation too long" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  // 요청한 사람이 이 매장 사장님인지 확인한다. 다른 사람의 API 비용으로 쓰이지 않게.
  const { data: userData } = await supabase.auth.getUser();
  const userId = userData.user?.id;
  if (!userId) {
    return json({ error: "Unauthorized" }, 401);
  }
  const { data: store, error: storeError } = await supabase
    .from("stores")
    .select("id,name")
    .eq("id", payload.storeId)
    .eq("owner_id", userId)
    .maybeSingle();
  if (storeError || !store) {
    return json({ error: "Only the store owner can use the agent" }, 403);
  }

  try {
    const response = await anthropic.beta.messages.create({
      model: ANTHROPIC_MODEL,
      max_tokens: 4096,
      output_config: { effort: "low" },
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      system: `${SYSTEM_PROMPT}\n\n매장: ${store.name}\n오늘: ${todayKST()}`,
      tools: TOOLS,
      messages: payload.messages,
    } as Parameters<typeof anthropic.beta.messages.create>[0]);

    return json({ content: response.content, stop_reason: response.stop_reason }, 200);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return json({ error: message }, 500);
  }
});

function todayKST() {
  const formatter = new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    weekday: "short",
  });
  return formatter.format(new Date());
}

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
