# 사장님 급여·해고 리스크 저감 설계안 (구현 전)

작성일: 2026-02-19  
대상: 수당수당(사장님/알바 공용 앱)  
목표: 사장님의 급여·해고 관련 분쟁/소송 리스크를 제품 기능으로 선제적으로 낮춘다.

## 1) 왜 필요한가 (실제 분쟁 패턴)

아래 유형이 반복되면 매장 운영 리스크가 급격히 커진다.

1. 면접 구두합의와 계약서 문구 불일치
- 예: "주휴 포함 13,000원"으로 설명했지만 계약서에는 `시급 13,000원`만 기재.
- 결과: 주휴수당 별도청구 분쟁 발생.

2. 근로조건 명시/교부 누락
- 임금 구성항목, 계산방법, 소정근로시간, 휴일, 연차 등의 명시가 모호하거나 누락.
- 결과: 임금 재산정 분쟁 시 사업주 불리.

3. 해고 절차 하자
- 서면 통지 누락, 해고사유/시기 불명확, 예고수당 판단 누락.
- 결과: 해고 사유가 있더라도 절차 위반으로 무효 판단 가능.

4. 근태 증빙/임금명세 증빙 부족
- 출퇴근 원본과 정정 이력이 분리되지 않거나, 임금명세서 교부 기록이 없음.
- 결과: "지급/설명했다"는 주장 입증 실패.

5. 계산 규칙 미고정
- 주휴, 연장/야간/휴일 가산, 최저임금 검증 규칙이 매번 수기로 달라짐.
- 결과: 누락·오산·사후 재계산으로 분쟁 장기화.

## 2) 제품 원칙

1. 구두가 아니라 `서면 + 로그`가 기준이다.
2. 원본은 잠그고, 정정은 이력으로만 남긴다.
3. 애매한 입력을 막고(가드레일), 분쟁 가능 문구를 표준화한다.
4. 법적 필수 절차는 완료 전 다음 단계로 못 넘어가게 한다.
5. 분쟁 시 제출 가능한 패키지(PDF/로그)를 자동 생성한다.

## 3) 핵심 기능 설계

### A. 근로계약/시급 설정 가드레일

1. `시급`과 `주휴수당`을 분리 입력
- 계약서 시급 항목은 `기본시급`만 입력 가능.
- "주휴 포함 시급" 단일 입력은 금지.

2. 계약서 자동 문구 표준화
- 필수 기재: 임금 구성항목/계산방법/지급방법, 소정근로시간, 휴일, 연차.
- 전자문서 교부(앱 내 확인 + 다운로드)와 수령 로그 저장.

3. 근로조건 버전관리
- 변경 시 새 버전 발행.
- 버전별 효력일, 변경자, 변경사유, 근로자 확인시각 기록.

### B. 주휴·최저·가산 자동 검증

1. 주휴 자격 자동 판정
- 원칙: `1주 소정근로일 개근 + 1주 소정근로시간 15시간 이상` 기준.
- 계약 기준과 실제 근태 기준을 함께 표시(왜 지급/미지급인지 설명 가능하게).

2. 최저임금 미달 사전 차단
- 마감 전 "유효시급(총지급/유급시간)" 자동 검사.
- 미달 예상 시 급여확정 버튼 비활성화.

3. 연장/야간/휴일 계산식 고정
- 가산율/시간 구간을 시스템 계산으로 통일.
- 계산식이 명세서에 그대로 노출되게 설계.

### C. 출퇴근·정정 이력 분리

1. 출퇴근 원본 로그 잠금
- check-in/out 원본은 수정 금지.

2. 정정은 별도 엔티티
- 정정사유, 요청자, 승인자, 변경 전/후 값, 증빙 첨부 저장.
- 급여 계산은 "원본 + 승인된 정정"만 반영.

### D. 해고/퇴사 워크플로우 분리

1. 상태를 분리
- `자진퇴사`, `합의종료`, `해고`를 분리 입력.
- 해고 선택 시 절차 체크리스트 자동 활성화.

2. 해고 서면통지서 생성 강제
- 해고사유, 해고시기, 작성일, 통지수단, 전달시각 저장.
- 통지 기록이 없으면 해고 확정 불가.

3. 해고예고수당 체크
- 해고일 기준 예고기간/예외 여부 점검 UI 제공.
- 지급 필요 시 자동으로 정산 항목 생성.

### E. 임금명세서·급여마감 증빙

1. 월 마감(락) 프로세스
- 마감 후 소급수정 금지.
- 수정은 `정산조정`으로 다음 지급에 반영.

2. 명세서 교부 로그
- 생성시각, 수신채널, 수신확인시각 저장.
- 미교부/미열람 알림.

3. 분쟁 대응 패키지 PDF
- 근로계약 버전, 스케줄, 출퇴근 원본/정정, 계산식, 명세서 교부 로그, 종료문서 일괄 내보내기.

### F. 법적 효력 문서 모듈 (필수)

아래 문서는 앱에서 "법적 효력 문서"로 별도 관리한다.

1. 근로계약서(체결/변경)
- 필수: 당사자, 임금구성항목, 소정근로시간, 휴일, 연차, 적용일.
- 상태: `초안 -> 양측확인 -> 확정(잠금)`.

2. 임금명세서(매 지급시)
- 필수: 임금항목, 계산방법, 공제내역, 실지급액, 지급일.
- 상태: `생성 -> 교부 -> 열람확인`.

3. 해고예고/해고통지서
- 필수: 해고사유, 해고시기, 예고/예고수당 처리내역, 통지일시.
- 상태: `작성 -> 전달증빙 첨부 -> 확정`.

4. 퇴직 정산서
- 필수: 미지급 임금, 수당, 공제, 지급기한, 지급일, 지급수단.
- 상태: `정산안 -> 지급완료`.

5. 합의서(있는 경우)
- 분쟁 종결 합의금, 지급기한, 비밀유지/청구포기 등 조항 관리.
- 조항별 체크박스와 최종 전자서명 기록.

### G. 전자문서/전자서명 효력 확보 요건

전자문서로 운영하되, 아래 조건이 있어야 실무상 입증력이 높다.

1. 본인확인
- 로그인 계정 + 휴대폰 본인확인(또는 2차 인증) 후 서명.

2. 위변조 방지
- 문서 원문 해시값(hash) 저장.
- 서명 후 내용 변경 시 새 버전만 생성(원본 수정 금지).

3. 시점 증명
- 서버 기준 `signed_at`, `delivered_at`, `viewed_at` 타임스탬프 저장.

4. 전달 증빙
- 앱 열람, 이메일/문자 발송 결과, 다운로드 이력 저장.

5. 원본 보존
- 문서 원본 PDF + 메타데이터(작성자, 기기, IP, 버전) 3년 이상 보존 정책 적용.

## 4) 데이터 모델(초안)

1. `employment_terms_versions`
- worker_id, store_id, effective_from, base_hourly_wage, weekly_scheduled_hours, pay_day, contract_snapshot_json, owner_signed_at, worker_signed_at

2. `attendance_corrections`
- work_log_id, requested_by, approved_by, reason, before_check_in, before_check_out, after_check_in, after_check_out, evidence_url, approved_at

3. `termination_cases`
- worker_id, type(resignation/mutual/dismissal), reason_code, fact_summary, effective_date, notice_required, notice_delivered_at, severance_due, closed_at

4. `termination_documents`
- termination_case_id, file_url, file_hash, delivered_channel, delivered_at

5. `payroll_closings`
- worker_id, month_key, gross_pay, weekly_holiday_pay, overtime_pay, deductions, net_pay, min_wage_check_result, closed_at, closed_by

6. `payslip_dispatch_logs`
- payroll_closing_id, delivered_channel, delivered_at, read_at

7. `compliance_alerts`
- store_id, worker_id, alert_type, severity, payload_json, resolved_at

## 5) 화면/운영 정책 (MVP)

1. 사장님 `급여설정` 화면
- 기본시급 입력 + 주휴정책 안내 + 최저임금 검증 배지.

2. 사장님 `근로계약` 화면
- 필수항목 누락 시 저장 불가.
- 근로자 확인 전 "적용중" 전환 불가.

3. 사장님 `종료처리` 화면
- 퇴사/해고 분리.
- 해고 선택 시 서면통지서 자동작성 폼 노출.

4. 사장님 `월마감` 화면
- 리스크 경고(최저임금 미달/미교부/미정정) 해결 전 마감 불가.

5. 알바 `내 문서함`
- 계약서, 명세서, 종료통지서 열람 가능.
- 열람기록 자동 저장.

## 6) 사례별 방어 시나리오

### 시나리오 1: "주휴 포함 13,000원" 분쟁

대응 설계:
1. 계약서 시급 필드는 `기본시급`만 허용.
2. 주휴수당은 별도 항목으로 자동 계산/표기.
3. 계약 체결 전 "이번 조건으로 예상 지급 예시"를 양측에게 동일 표시.
4. 사장·알바 확인 로그(시각/IP/디바이스) 저장.

### 시나리오 2: 업무불량 근로자 해고 분쟁

대응 설계:
1. 해고 전 경고/교육/배치조정 이력 체크리스트.
2. 해고사유·시기 서면통지서 미작성 시 해고 버튼 비활성화.
3. 해고예고수당 대상 여부 자동 안내.
4. 종료 이후 분쟁 패키지 즉시 출력 가능.

## 7) 구현 우선순위

P0 (즉시):
1. 계약서 가드레일(기본시급 분리)
2. 해고/퇴사 분기 + 해고서면통지서 강제
3. 월마감 전 최저임금·명세서 교부 점검

P1:
1. 출퇴근 정정 이력 분리 저장
2. 분쟁 대응 PDF 자동 생성
3. 경고 알림 자동화(14일 정산, 미교부, 미확정)

P2:
1. 정책별 자동 감사리포트(매장 리스크 점수)
2. 노무대리인 제출용 확장 양식

## 8) 법적 근거(공식 링크, 2026-02-19 확인)

1. 근로기준법 제17조(근로조건의 명시)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0017&lsiSeq=265959&urlMode=lsScJoRltInfoR

2. 근로기준법 제26조(해고의 예고)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0026&lsiSeq=265959&urlMode=lsScJoRltInfoR

3. 근로기준법 제27조(해고사유와 시기의 서면통지)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0027&lsiSeq=265959&urlMode=lsScJoRltInfoR

4. 근로기준법 제36조(금품 청산)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0036&lsiSeq=265959&urlMode=lsScJoRltInfoR

5. 근로기준법 제43조(임금 지급)  
https://www.law.go.kr/lsLinkCommonInfo.do?lsJoLnkSeq=1007688469

6. 근로기준법 제48조(임금대장 및 임금명세서)  
https://www.law.go.kr/lsLawLinkInfo.do?lsJoLnkSeq=1000610123&chrClsCd=010202

7. 근로기준법 제55조(휴일)  
https://www.law.go.kr/lsLinkCommonInfo.do?lsJoLnkSeq=1015677471&chrClsCd=010202&ancYnChk=

8. 근로기준법 시행령 제30조(휴일: 개근 요건 등)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0030&lsiSeq=270551&urlMode=lsScJoRltInfoR

9. 근로기준법 제56조(연장·야간 및 휴일 근로)  
https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0056&lsiSeq=265959&urlMode=lsScJoRltInfoR

10. 대법원 2024.6.27. 선고 2020도16541 (근로조건 명시의무 관련)  
https://law.go.kr/LSW/precInfoP.do?mode=0&precSeq=240951

11. 대법원 2020.6.25. 선고 2017다262184 (해고서면통지 관련)  
https://law.go.kr/precInfoP.do?precSeq=214235

12. 2026년 적용 최저임금 고시(최저임금위원회 알림)  
https://www.minimumwage.go.kr/customer/notice/list.do

13. 고용노동부 임금명세서 작성기/가이드  
https://www.moel.go.kr/wageCal.do  
https://www.moel.go.kr/wageCalMain.do

## 9) 유의사항

이 문서는 제품 설계를 위한 리스크 저감안이다.  
최종 개별 사건 판단(해고 정당성, 예고수당 예외, 계산 특례 등)은 노무사/변호사 검토를 전제로 한다.
