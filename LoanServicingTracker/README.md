# 🏦 Enterprise Loan Servicing & EMI Tracker
### Built with Salesforce · Apex · LWC · Premium Finspectra-style UI

> **Author:** Santosh Patel | **API Version:** 61.0 | **2026**

---

## 📋 Project Overview

A production-ready Salesforce application that automates EMI repayment schedule generation and provides a modern, real-time payment tracking dashboard.

### ✅ Key Features
- **Automatic EMI Generation** — Trigger fires on Loan approval, calculates reducing-balance amortization
- **Zero-Interest Handling** — EMI = Principal / Tenure (no division-by-zero)
- **Duplicate Prevention** — Checks existing schedules before inserting new ones
- **Amortization Breakdown** — Per-EMI principal, interest, and outstanding balance
- **Bulk Handling** — Fully bulkified DML — handles 200+ loans simultaneously
- **Premium Dashboard** — Dark Finspectra-style LWC with KPIs, progress bar, search, filters
- **90%+ Test Coverage** — Comprehensive test class with 12+ scenarios

---

## 🏗️ Project Structure

```
LoanServicingTracker/
├── force-app/main/default/
│   ├── classes/
│   │   ├── LoanController.cls              ← @AuraEnabled methods for LWC
│   │   ├── LoanServicingHandler.cls        ← Business logic & EMI calculation
│   │   ├── LoanServicingHandlerTest.cls    ← Comprehensive test coverage
│   │   ├── EMIReminderEmailService.cls     ← Schedulable/Batchable email alerts
│   │   └── EMIReminderEmailServiceTest.cls ← 100% email service test coverage
│   │
│   ├── triggers/
│   │   └── LoanServicingTrigger.trigger    ← Thin trigger (Handler Pattern)
│   │
│   ├── objects/
│   │   ├── Loan__c/
│   │   │   ├── Loan__c.object-meta.xml
│   │   │   └── fields/
│   │   │       ├── Principal_Amount__c     (Currency)
│   │   │       ├── Interest_Rate__c        (Percent)
│   │   │       ├── Tenure_Months__c        (Number)
│   │   │       ├── Status__c               (Picklist: Pending/Approved/Closed)
│   │   │       ├── Borrower_Name__c        (Text)
│   │   │       ├── Loan_Type__c            (Picklist)
│   │   │       ├── Disbursement_Date__c    (Date)
│   │   │       ├── Total_EMI_Amount__c     (Currency)
│   │   │       ├── Total_Interest_Payable__c (Currency)
│   │   │       └── Total_Amount_Payable__c (Currency)
│   │   │
│   │   └── Repayment_Schedule__c/
│   │       ├── Repayment_Schedule__c.object-meta.xml
│   │       └── fields/
│   │           ├── Loan__c                 (Master-Detail → Loan__c)
│   │           ├── EMI_Amount__c           (Currency)
│   │           ├── Due_Date__c             (Date)
│   │           ├── Status__c               (Picklist: Pending/Paid/Overdue)
│   │           ├── Principal_Component__c  (Currency) ← NEW
│   │           ├── Interest_Component__c   (Currency) ← NEW
│   │           └── Outstanding_Balance__c  (Currency) ← NEW
│   │
│   ├── lwc/loanServicingDashboard/
│   │   ├── loanServicingDashboard.html     ← Premium UI template
│   │   ├── loanServicingDashboard.js       ← Controller with all logic
│   │   ├── loanServicingDashboard.css      ← Finspectra dark theme CSS
│   │   └── loanServicingDashboard.js-meta.xml
│   │
│   └── flexipages/
│       └── Loan_Record_Page.flexipage-meta.xml
│
├── sfdx-project.json
└── README.md
```

---

## 🚀 Quick Setup Guide

### Prerequisites
```bash
node --version    # v18+ required
sf --version      # Salesforce CLI 2.x
```

### Step 1 — Clone / Open Project
```bash
cd "LoanServicingTracker"
code .
```

### Step 2 — Authorize Salesforce Org
```bash
sf org login web --alias LoanDevOrg
sf config set target-org=LoanDevOrg
sf org display
```

### Step 3 — Deploy Objects First
```bash
sf project deploy start --source-dir force-app/main/default/objects
```

### Step 4 — Deploy All Metadata
```bash
sf project deploy start --source-dir force-app/main/default
```

### Step 5 — Run Apex Tests
```bash
sf apex run test --test-level RunLocalTests --wait 10 --result-format human
```

### Step 6 — Verify in Org
1. Go to **App Launcher** → search `Loan`
2. Create a new **Loan** record (Status = Pending)
3. Edit → change **Status to Approved** → Save
4. Verify **Repayment Schedule** records are generated
5. Open **Loan Record Page** → add `loanServicingDashboard` LWC
6. Click **Mark Paid** on any EMI

---

## 🧠 Architecture

```
                    ┌─────────────────┐
                    │    Loan__c      │
                    │  Status=Approved│
                    └────────┬────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ LoanServicingTrigger │  (thin — delegates)
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ LoanServicingHandler │
                  │                     │
                  │  • Duplicate check  │
                  │  • EMI formula      │
                  │  • Amortization     │
                  │  • Bulk insert      │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │ Repayment_Schedule__c│
                  │                     │
                  │  EMI-0001..EMI-00N  │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │   LoanController    │  @AuraEnabled methods
                  │                     │
                  │  getLoanSchedules() │
                  │  getLoanDetails()   │
                  │  getSummaryStats()  │
                  │  markAsPaid()       │
                  │  markMultiplePaid() │
                  └──────────┬──────────┘
                             │
                             ▼
                  ┌─────────────────────┐
                  │  loanServicingDash  │  LWC Dashboard
                  │                     │
                  │  ■ KPI Cards        │
                  │  ■ Progress Bar     │
                  │  ■ Loan Summary     │
                  │  ■ EMI Table        │
                  │  ■ Search/Filter    │
                  │  ■ Mark as Paid     │
                  │  ■ Toast Alerts     │
                  └─────────────────────┘
```

---

## 💡 EMI Formula

**Reducing-Balance Amortization:**

```
Monthly Rate (r) = Annual Rate / 12 / 100
EMI = P × r × (1+r)^n / ((1+r)^n - 1)

Where:
  P = Principal Amount
  r = Monthly Interest Rate
  n = Tenure in Months
```

**Zero-Interest edge case:**
```
EMI = Principal / Tenure
```

---

## 🎨 Dashboard Features

| Feature | Details |
|---------|---------|
| **Theme** | Dark mode (Finspectra-inspired) |
| **KPI Cards** | Total, Paid, Pending, Overdue with animated glows |
| **Progress Bar** | Gradient shimmer animation |
| **Loan Stats** | Principal, Rate, Tenure, EMI, Total Payable |
| **Table** | Per-EMI principal, interest, outstanding balance |
| **Search** | Real-time name/status filtering |
| **Status Filters** | All / Pending / Paid / Overdue tabs |
| **Mark as Paid** | Optimistic UI with loading state |
| **Toast Notifications** | Success/error with auto-dismiss |
| **Responsive** | Mobile-first, works on all screen sizes |

---

## 🧪 Test Scenarios Covered

| Test | Scenario |
|------|----------|
| `testLoanApprovalGeneratesSchedules` | Standard 12-month loan approval |
| `testDirectInsertApprovedLoan` | Insert with Approved status |
| `testZeroInterestLoan` | 0% annual rate — EMI = P/N |
| `testDuplicateSchedulePrevention` | Approved→Pending→Approved no dup |
| `testPendingLoanNoSchedules` | Pending loan = no schedules |
| `testBulkLoanApproval` | 20 loans × 12 months = 240 records |
| `testGetLoanSchedules` | Controller SOQL fetch |
| `testGetLoanSchedulesNullId` | Null input guard |
| `testMarkAsPaid` | DML update to Paid |
| `testMarkAsPaidAlreadyPaid` | Guard: already-paid exception |
| `testMarkMultipleAsPaid` | Bulk Paid update |
| `testGetLoanDetails` | Loan header data fetch |
| `testGetLoanSummaryStats` | KPI aggregation |
| `test24MonthTenure` | Extended 24-month tenure |

---

## 📝 Salesforce Concepts Demonstrated

| Concept | Implementation |
|---------|----------------|
| Custom Objects | Loan__c, Repayment_Schedule__c |
| Master-Detail | Repayment → Loan |
| Apex Trigger | After insert/update on Loan__c |
| Trigger Handler Pattern | Thin trigger → Handler class |
| Bulkified DML | List collect + single insert |
| SOQL | Indexed queries with ORDER BY |
| @AuraEnabled | 5 controller methods |
| @wire | 3 wire adapters in LWC |
| refreshApex | UI refresh post-DML |
| LWC CSS | Scoped :host design tokens |
| Error Handling | AuraHandledException |
| with sharing | Record-level security |
| Test Class | 90%+ coverage, 14 test methods |
