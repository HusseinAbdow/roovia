# FUTURE FEATURES AND ROADMAP

## 1. DEVELOPMENT PHILOSOPHY

- Do NOT over-engineer early
- Build features in phases
- Start simple → evolve later
- Avoid fake or inaccurate data
- Prioritize real user value over complexity
- Keep UI compatible with future upgrades

## 2. FINANCIAL SYSTEM (CRITICAL FEATURE)

### PROBLEM DEFINITION

Bills vary monthly and depend on usage.
We cannot calculate real averages without real expense data.

Therefore:

- Any calculated average without real tracking is inaccurate
- We must avoid fake precision

### PHASE 1 — SIMPLE IMPLEMENTATION (CURRENT TARGET)

DEFINE EXACTLY:

Fields:

- rentPerPerson (double)
- estimatedBillsPerPerson (double)

RULES:

- Values are manually entered when creating a house
- These are estimates, not calculated values
- UI must display bills as "Estimated"

CALCULATION:

totalMonthlyCost = rentPerPerson + estimatedBillsPerPerson

EXAMPLE:

Rent: 3500
Estimated Bills: 800
Total: 4300

PURPOSE:

- Allow users to evaluate houses quickly
- Enable filtering in search
- Match real-world behavior (students estimate costs)

### PHASE 2 — REAL EXPENSE TRACKING (FUTURE)

DEFINE DATA MODEL:

expenses
 - houseId
 - type (electricity, water, internet, groceries)
 - amount
 - paidBy
 - month
 - createdAt

### CALCULATION LOGIC (STRICT)

IMPLEMENTATION LOGIC:

1. Collect all expenses grouped by month
2. Compute total expense per month
3. Select last N months (e.g., last 2–3 months)
4. Compute average:

averageMonthlyExpense = (sum of monthly totals) / N

5. Convert to per person:

expensePerPerson = averageMonthlyExpense / numberOfMembers

### DESIGN RULES

- Cost must always be per person
- Bills must be labeled "Estimated" until Phase 2 is complete
- UI must NOT change between Phase 1 and Phase 2
- Backend logic will evolve, UI stays stable

## 3. FUTURE SYSTEMS

DEFINE CLEARLY:

PHASE 2 FEATURES:

- expense tracking
- bill splitting
- payment tracking
- payment reminders

PHASE 3 FEATURES:

- smart averages
- spending insights
- cost comparison between houses
- intelligent recommendations

## 4. FILE RULES (IMPORTANT)

- This file contains ONLY future features
- When a feature is implemented:
   → REMOVE it from this file
   → ADD it to PROJECT_CONTEXT_FOR_CHATGPT.md
- DO NOT duplicate information
- Keep explanations detailed and technical
