# Korea Worker Refund Estimate Reference (2026-02)

This document records the formula set used by `PayrollCalculator.estimateAnnualRefund` as of 2026-02.
The app uses a simplified estimate for part-time workers and does not replace official year-end settlement.

## Scope in app
- Annualized from current monthly taxable pay (`monthly * 12`)
- Applies only when deduction type is `withholding_3_3`
- Assumes only self basic deduction (1 person)
- Excludes dependents, child credit, special tax credits, and other itemized conditions

## Formula set
- Earned income deduction (근로소득공제, 소득세법 제47조)
  - <= 5,000,000: 70%
  - 5,000,000~15,000,000: 3,500,000 + excess * 40%
  - 15,000,000~45,000,000: 7,500,000 + excess * 15%
  - 45,000,000~100,000,000: 12,000,000 + excess * 5%
  - > 100,000,000: 14,750,000 + excess * 2%
- Basic deduction (기본공제, 소득세법 제50조): 1,500,000 (self)
- Progressive income tax (소득세법 제55조)
  - 14,000,000 / 50,000,000 / 88,000,000 / 150,000,000 / 300,000,000 / 500,000,000 / 1,000,000,000 brackets
  - Rates: 6%, 15%, 24%, 35%, 38%, 40%, 42%, 45%
- Earned income tax credit (근로소득세액공제, 소득세법 제59조)
  - Calculated tax <= 1,300,000: 55%
  - Calculated tax > 1,300,000: 715,000 + excess * 30%
  - Credit cap by annual gross:
    - <= 33,000,000: 740,000
    - 33,000,000~70,000,000: 740,000 - (excess * 8/1000), floor 660,000
    - 70,000,000~120,000,000: 660,000 - (excess * 1/2), floor 500,000
    - > 120,000,000: 500,000 - (excess * 1/2), floor 200,000

## Sources checked (2026-02)
- 소득세법 제47조(근로소득공제): https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0047&lsiSeq=276127&urlMode=lsScJoRltInfoR
- 소득세법 제50조(기본공제): https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0050&lsiSeq=276127&urlMode=lsScJoRltInfoR
- 소득세법 제55조(세율): https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0055&lsiSeq=276127&urlMode=lsScJoRltInfoR
- 소득세법 제59조(근로소득세액공제): https://www.law.go.kr/LSW/lsSideInfoP.do?docCls=jo&joBrNo=00&joNo=0059&lsiSeq=276127&urlMode=lsScJoRltInfoR
