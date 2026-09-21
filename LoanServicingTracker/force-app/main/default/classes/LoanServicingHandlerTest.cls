/**
 * @description       : Comprehensive Test Class for Loan Servicing & EMI Tracker
 *                      Covers: LoanServicingHandler, LoanController, edge cases
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 * @test coverage     : Targets 90%+ code coverage
 **/
@IsTest
public class LoanServicingHandlerTest {

    // ─── Test Data Factory ─────────────────────────────────────────────────────

    private static Loan__c createLoan(
        String status,
        Decimal principal,
        Decimal interestRate,
        Integer tenure
    ) {
        return new Loan__c(
            Name              = 'TEST-LOAN-' + String.valueOf(System.now().millisecond()),
            Borrower_Name__c  = 'Test Borrower',
            Principal_Amount__c = principal,
            Interest_Rate__c    = interestRate,
            Tenure_Months__c    = tenure,
            Status__c           = status,
            Loan_Type__c        = 'Home Loan',
            Disbursement_Date__c = System.today()
        );
    }

    // ─── Test: Standard Loan Approval → Schedule Generation ───────────────────

    @IsTest
    static void testLoanApprovalGeneratesSchedules() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;

        Test.startTest();
        loan.Status__c = 'Approved';
        update loan;
        Test.stopTest();

        List<Repayment_Schedule__c> schedules = [
            SELECT Id, Status__c, EMI_Amount__c, Due_Date__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            ORDER BY Due_Date__c ASC
        ];

        System.assertEquals(12, schedules.size(), 'Should generate 12 EMI schedules for 12-month tenure');

        for (Repayment_Schedule__c s : schedules) {
            System.assertEquals('Pending', s.Status__c, 'All schedules should start as Pending');
            System.assert(s.EMI_Amount__c > 0, 'EMI Amount should be positive');
            System.assertNotEquals(null, s.Due_Date__c, 'Due Date should not be null');
        }
    }

    // ─── Test: Direct Insert with Approved Status ──────────────────────────────

    @IsTest
    static void testDirectInsertApprovedLoan() {
        Test.startTest();
        Loan__c loan = createLoan('Approved', 300000, 8, 24);
        insert loan;
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
        ];
        System.assertEquals(24, count, 'Direct insert of Approved loan should generate 24 schedules');
    }

    // ─── Test: Zero Interest Rate ──────────────────────────────────────────────

    @IsTest
    static void testZeroInterestLoan() {
        Loan__c loan = createLoan('Pending', 120000, 0, 12);
        insert loan;

        Test.startTest();
        loan.Status__c = 'Approved';
        update loan;
        Test.stopTest();

        List<Repayment_Schedule__c> schedules = [
            SELECT EMI_Amount__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
        ];

        System.assertEquals(12, schedules.size(), 'Should generate 12 schedules for zero-interest loan');
        // EMI should be 10,000 (120,000 / 12)
        System.assertEquals(10000, schedules[0].EMI_Amount__c, 'Zero-interest EMI should be principal/tenure');
    }

    // ─── Test: No Schedule Regeneration on Duplicate Approval ─────────────────

    @IsTest
    static void testDuplicateSchedulePrevention() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;

        loan.Status__c = 'Approved';
        update loan;

        // Simulate re-approval attempt (Approved → Pending → Approved)
        loan.Status__c = 'Pending';
        update loan;

        Test.startTest();
        loan.Status__c = 'Approved';
        update loan;
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
        ];
        // Duplicate prevention: should still be 12, not 24
        System.assertEquals(12, count, 'Duplicate schedules should NOT be generated');
    }

    // ─── Test: Pending Status Does Not Generate Schedules ─────────────────────

    @IsTest
    static void testPendingLoanNoSchedules() {
        Test.startTest();
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;
        Test.stopTest();

        Integer count = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
        ];
        System.assertEquals(0, count, 'Pending loan should not generate schedules');
    }

    // ─── Test: Bulk Loan Approval ──────────────────────────────────────────────

    @IsTest
    static void testBulkLoanApproval() {
        List<Loan__c> loans = new List<Loan__c>();
        for (Integer i = 0; i < 20; i++) {
            loans.add(createLoan('Pending', 100000 + (i * 10000), 10, 12));
        }
        insert loans;

        Test.startTest();
        for (Loan__c l : loans) {
            l.Status__c = 'Approved';
        }
        update loans;
        Test.stopTest();

        Integer totalSchedules = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Loan__c IN :loans
        ];
        System.assertEquals(240, totalSchedules, 'Bulk approval of 20 loans x 12 months = 240 schedules');
    }

    // ─── Test: LoanController.getLoanSchedules() ──────────────────────────────

    @IsTest
    static void testGetLoanSchedules() {
        Loan__c loan = createLoan('Pending', 500000, 10, 6);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        Test.startTest();
        List<Repayment_Schedule__c> result = LoanController.getLoanSchedules(loan.Id);
        Test.stopTest();

        System.assertEquals(6, result.size(), 'Controller should return 6 schedules');
    }

    // ─── Test: LoanController.getLoanSchedules() Null Id ──────────────────────

    @IsTest
    static void testGetLoanSchedulesNullId() {
        Test.startTest();
        try {
            LoanController.getLoanSchedules(null);
            System.assert(false, 'Should have thrown exception');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── Test: LoanController.markAsPaid() ────────────────────────────────────

    @IsTest
    static void testMarkAsPaid() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        Repayment_Schedule__c schedule = [
            SELECT Id, Status__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];

        Test.startTest();
        LoanController.markAsPaid(schedule.Id);
        Test.stopTest();

        Repayment_Schedule__c updated = [
            SELECT Status__c
            FROM Repayment_Schedule__c
            WHERE Id = :schedule.Id
        ];
        System.assertEquals('Paid', updated.Status__c, 'Status should be updated to Paid');
    }

    // ─── Test: LoanController.markAsPaid() Already Paid ──────────────────────

    @IsTest
    static void testMarkAsPaidAlreadyPaid() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        Repayment_Schedule__c schedule = [
            SELECT Id, Status__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];
        schedule.Status__c = 'Paid';
        update schedule;

        Test.startTest();
        try {
            LoanController.markAsPaid(schedule.Id);
            System.assert(false, 'Should have thrown exception for already-paid record');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage(), 'Should catch AuraHandledException');
        }
        Test.stopTest();
    }

    // ─── Test: LoanController.markMultipleAsPaid() ────────────────────────────

    @IsTest
    static void testMarkMultipleAsPaid() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        List<Id> scheduleIds = new List<Id>();
        for (Repayment_Schedule__c s : [
            SELECT Id FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 3
        ]) {
            scheduleIds.add(s.Id);
        }

        Test.startTest();
        LoanController.markMultipleAsPaid(scheduleIds);
        Test.stopTest();

        Integer paidCount = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Id IN :scheduleIds
            AND Status__c = 'Paid'
        ];
        System.assertEquals(3, paidCount, 'All 3 selected schedules should be Paid');
    }

    // ─── Test: LoanController.getLoanDetails() ────────────────────────────────

    @IsTest
    static void testGetLoanDetails() {
        Loan__c loan = createLoan('Approved', 500000, 10, 12);
        insert loan;

        Test.startTest();
        Loan__c result = LoanController.getLoanDetails(loan.Id);
        Test.stopTest();

        System.assertNotEquals(null, result);
        System.assertEquals(500000, result.Principal_Amount__c);
    }

    // ─── Test: LoanController.getLoanSummaryStats() ───────────────────────────

    @IsTest
    static void testGetLoanSummaryStats() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        Test.startTest();
        Map<String, Object> stats = LoanController.getLoanSummaryStats(loan.Id);
        Test.stopTest();

        System.assertNotEquals(null, stats);
        System.assertEquals(12, (Integer) stats.get('totalCount'));
        System.assertEquals(0, (Integer) stats.get('paidCount'));
        System.assertEquals(12, (Integer) stats.get('pendingCount'));
    }

    // ─── Test: 24-month Tenure ────────────────────────────────────────────────

    @IsTest
    static void test24MonthTenure() {
        Loan__c loan = createLoan('Pending', 1000000, 12, 24);
        insert loan;

        Test.startTest();
        loan.Status__c = 'Approved';
        update loan;
        Test.stopTest();

        Integer count = [SELECT COUNT() FROM Repayment_Schedule__c WHERE Loan__c = :loan.Id];
        System.assertEquals(24, count, 'Should generate 24 monthly schedules');
    }

    // ─── Test: LoanController.markAsOverdue() ──────────────────────────────────

    @IsTest
    static void testMarkAsOverdue() {
        Loan__c loan = createLoan('Pending', 200000, 10, 12);
        insert loan;
        loan.Status__c = 'Approved';
        update loan;

        Repayment_Schedule__c schedule = [
            SELECT Id, Status__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];

        Test.startTest();
        LoanController.markAsOverdue(schedule.Id);
        Test.stopTest();

        Repayment_Schedule__c updated = [
            SELECT Status__c
            FROM Repayment_Schedule__c
            WHERE Id = :schedule.Id
        ];
        System.assertEquals('Overdue', updated.Status__c, 'Status should be updated to Overdue');
    }

    // ─── Test: Null Parameter Exception Checks ────────────────────────────────

    @IsTest
    static void testNullParameterHandling() {
        Test.startTest();
        try {
            LoanController.getLoanDetails(null);
            System.assert(false, 'Should throw exception for null Loan ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.getLoanSummaryStats(null);
            System.assert(false, 'Should throw exception for null Loan ID in stats');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markAsPaid(null);
            System.assert(false, 'Should throw exception for null Schedule ID');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markMultipleAsPaid(null);
            System.assert(false, 'Should throw exception for null list');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markAsOverdue(null);
            System.assert(false, 'Should throw exception for null Schedule ID in overdue');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
