/**
 * @description       : Comprehensive Test Suite for Loan Servicing & EMI Repayment SaaS Platform.
 *                      Validates LoanServicingHandler, LoanController, Admin Portfolio Metrics,
 *                      Borrower Loan Applications, Status Transitions, Profile Updates,
 *                      Authentication (Admin vs Borrower), and Payment DML Actions.
 * @author            : Santosh Patel (santoshpatelvns5@gmail.com)
 * @created           : 2026
 * @last modified on  : 2026-09-21
 * @test coverage     : Target >90% code coverage across all Apex modules.
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
            Name                 = 'LN-TEST-' + String.valueOf(Math.abs(Crypto.getRandomInteger())).substring(0, 5),
            Borrower_Name__c     = 'Rahul Verma',
            Borrower_Email__c    = 'rahul.verma@example.com',
            Principal_Amount__c  = principal,
            Interest_Rate__c     = interestRate,
            Tenure_Months__c     = tenure,
            Status__c            = status,
            Loan_Type__c         = 'Personal Loan',
            Disbursement_Date__c = Date.today()
        );
    }

    // ─── Authentication Tests ────────────────────────────────────────────────

    @IsTest
    static void testAdminLoginAndRegistration() {
        Test.startTest();
        // 1. Admin Login (santoshpatelvns5@gmail.com)
        Map<String, Object> adminSession = LoanController.loginUser('santoshpatelvns5@gmail.com', 'AdminPass123!');
        System.assertEquals('SUCCESS', (String) adminSession.get('status'));
        System.assertEquals('ADMIN', (String) adminSession.get('role'));
        System.assertEquals(true, (Boolean) adminSession.get('isAdmin'));

        // 2. Admin Register
        Map<String, Object> adminReg = LoanController.registerUser('Santosh Patel', 'santoshpatelvns5@gmail.com', 'AdminPass123!', '9876543210');
        System.assertEquals('ADMIN', (String) adminReg.get('role'));
        System.assertEquals(true, (Boolean) adminReg.get('isAdmin'));
        Test.stopTest();
    }

    @IsTest
    static void testBorrowerLoginAndRegistration() {
        Loan__c loan = createLoan('Approved', 400000, 10, 12);
        loan.Borrower_Name__c = 'Priya Sharma';
        loan.Borrower_Email__c = 'priya.sharma@example.com';
        insert loan;

        Test.startTest();
        // 1. Existing Borrower Login
        Map<String, Object> borrowerSession = LoanController.loginUser('priya.sharma@example.com', 'Secret123');
        System.assertEquals('SUCCESS', (String) borrowerSession.get('status'));
        System.assertEquals('BORROWER', (String) borrowerSession.get('role'));
        System.assertEquals(false, (Boolean) borrowerSession.get('isAdmin'));
        System.assertEquals('Priya Sharma', (String) borrowerSession.get('name'));

        // 2. New Borrower Registration
        Map<String, Object> newReg = LoanController.registerUser('Amit Kumar', 'amit.k@example.com', 'SecurePass123!', '9999888877');
        System.assertEquals('SUCCESS', (String) newReg.get('status'));
        System.assertEquals('BORROWER', (String) newReg.get('role'));
        System.assertEquals(false, (Boolean) newReg.get('isAdmin'));

        // 3. Fallback Borrower Login
        Map<String, Object> fallbackSession = LoanController.loginUser('john.doe@test.com', 'Pass123');
        System.assertEquals('BORROWER', (String) fallbackSession.get('role'));
        Test.stopTest();
    }

    @IsTest
    static void testAuthValidationGuards() {
        Test.startTest();
        try {
            LoanController.loginUser('', '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.loginUser('test@mail.com', '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.registerUser('', '', '', '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.registerUser('Name', 'email@test.com', '123', '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    // ─── Trigger & Handler Tests ──────────────────────────────────────────────

    @IsTest
    static void testLoanApprovalGeneratesSchedules() {
        Loan__c loan = createLoan('Pending', 500000, 10.5, 12);
        insert loan;

        Test.startTest();
        loan.Status__c = 'Approved';
        update loan;
        Test.stopTest();

        List<Repayment_Schedule__c> schedules = [
            SELECT Id, Status__c, EMI_Amount__c, Due_Date__c, Principal_Component__c, Interest_Component__c, Outstanding_Balance__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            ORDER BY Due_Date__c ASC
        ];

        System.assertEquals(12, schedules.size(), 'Should generate 12 EMI schedules for a 12-month tenure');
        for (Repayment_Schedule__c s : schedules) {
            System.assertEquals('Pending', s.Status__c);
            System.assert(s.EMI_Amount__c > 0);
            System.assertNotEquals(null, s.Due_Date__c);
        }
    }

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

        System.assertEquals(12, schedules.size());
        System.assertEquals(10000, schedules[0].EMI_Amount__c, 'Zero interest EMI should be Principal / Tenure');
    }

    @IsTest
    static void testDuplicateSchedulePrevention() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;

        loan.Status__c = 'Approved';
        update loan;

        // Toggle back and forth
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
        System.assertEquals(12, count, 'Duplicate schedules should not be generated on re-approval');
    }

    @IsTest
    static void testBulkLoanApproval() {
        List<Loan__c> loans = new List<Loan__c>();
        for (Integer i = 0; i < 15; i++) {
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
        System.assertEquals(180, totalSchedules, '15 loans x 12 months = 180 schedules');
    }

    // ─── LoanController Tests ────────────────────────────────────────────────

    @IsTest
    static void testGetLoanDetailsAndSchedules() {
        Loan__c loan = createLoan('Approved', 400000, 10, 6);
        insert loan;

        Test.startTest();
        Loan__c fetchedLoan = LoanController.getLoanDetails(loan.Id);
        List<Repayment_Schedule__c> schedules = LoanController.getLoanSchedules(loan.Id);
        Map<String, Object> stats = LoanController.getLoanSummaryStats(loan.Id);
        Test.stopTest();

        System.assertNotEquals(null, fetchedLoan);
        System.assertEquals(6, schedules.size());
        System.assertEquals(6, (Integer) stats.get('totalCount'));
        System.assertEquals(6, (Integer) stats.get('pendingCount'));
        System.assertEquals(0, (Integer) stats.get('paidCount'));
    }

    @IsTest
    static void testGetBorrowerLoans() {
        Loan__c loan1 = createLoan('Approved', 200000, 10, 12);
        loan1.Borrower_Email__c = 'priya@test.com';
        insert loan1;

        Test.startTest();
        List<Loan__c> specificLoans = LoanController.getBorrowerLoans('priya@test.com');
        List<Loan__c> allBorrowerLoans = LoanController.getBorrowerLoans('');
        Test.stopTest();

        System.assert(!specificLoans.isEmpty());
        System.assert(!allBorrowerLoans.isEmpty());
    }

    @IsTest
    static void testAdminPortfolioMetricsAndGetAllLoans() {
        Loan__c loan1 = createLoan('Approved', 500000, 10, 12);
        Loan__c loan2 = createLoan('Pending', 300000, 12, 12);
        Loan__c loan3 = createLoan('Closed', 200000, 10, 6);
        Loan__c loan4 = createLoan('Rejected', 100000, 10, 6);
        insert new List<Loan__c>{ loan1, loan2, loan3, loan4 };

        Test.startTest();
        Map<String, Object> metrics = LoanController.getAdminPortfolioMetrics();
        List<Loan__c> allLoansList = LoanController.getAllLoans('All', '');
        List<Loan__c> pendingLoansList = LoanController.getAllLoans('Pending', 'Rahul');
        Test.stopTest();

        System.assertNotEquals(null, metrics);
        System.assert((Integer) metrics.get('totalLoans') >= 4);
        System.assert(!allLoansList.isEmpty());
        System.assert(!pendingLoansList.isEmpty());
    }

    @IsTest
    static void testCreateLoanApplication() {
        Test.startTest();
        Loan__c newApp = LoanController.createLoanApplication(
            'LN-APP-101',
            'Ananya Singh',
            'ananya@example.com',
            600000,
            11.5,
            24,
            'Auto Loan'
        );
        Test.stopTest();

        System.assertNotEquals(null, newApp.Id);
        System.assertEquals('Pending', newApp.Status__c);
        System.assertEquals('Ananya Singh', newApp.Borrower_Name__c);
    }

    @IsTest
    static void testCreateLoanApplicationValidation() {
        Test.startTest();
        try {
            LoanController.createLoanApplication('', '', '', 0, 0, 0, '');
            System.assert(false, 'Should fail validation');
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void testUpdateLoanStatus() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;

        Test.startTest();
        LoanController.updateLoanStatus(loan.Id, 'Approved', 'Approved by Senior Underwriter.');
        Test.stopTest();

        Loan__c updated = [SELECT Status__c FROM Loan__c WHERE Id = :loan.Id];
        System.assertEquals('Approved', updated.Status__c);
    }

    @IsTest
    static void testUpdateBorrowerProfile() {
        Loan__c loan = createLoan('Pending', 500000, 10, 12);
        insert loan;

        Test.startTest();
        LoanController.updateBorrowerProfile(
            loan.Id,
            'Rahul Kumar Verma',
            'rahul.k.verma@example.com',
            550000,
            11.0,
            18,
            'Business Loan'
        );
        Test.stopTest();

        Loan__c updated = [
            SELECT Borrower_Name__c, Borrower_Email__c, Principal_Amount__c, Interest_Rate__c, Tenure_Months__c, Loan_Type__c
            FROM Loan__c
            WHERE Id = :loan.Id
        ];
        System.assertEquals('Rahul Kumar Verma', updated.Borrower_Name__c);
        System.assertEquals('rahul.k.verma@example.com', updated.Borrower_Email__c);
        System.assertEquals(550000, updated.Principal_Amount__c);
    }

    @IsTest
    static void testMarkAsPaidWithReceipt() {
        Loan__c loan = createLoan('Approved', 200000, 10, 12);
        insert loan;

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
        System.assertEquals('Paid', updated.Status__c);
    }

    @IsTest
    static void testMarkMultipleAsPaidAndOverdue() {
        Loan__c loan = createLoan('Approved', 300000, 10, 12);
        insert loan;

        List<Id> schedIds = new List<Id>();
        for (Repayment_Schedule__c s : [
            SELECT Id FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 2
        ]) {
            schedIds.add(s.Id);
        }

        Test.startTest();
        LoanController.markMultipleAsPaid(schedIds);
        
        Repayment_Schedule__c thirdSched = [
            SELECT Id FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            AND Status__c != 'Paid'
            LIMIT 1
        ];
        LoanController.markAsOverdue(thirdSched.Id);
        Test.stopTest();

        Integer paidCount = [
            SELECT COUNT()
            FROM Repayment_Schedule__c
            WHERE Id IN :schedIds
            AND Status__c = 'Paid'
        ];
        System.assertEquals(2, paidCount);

        Repayment_Schedule__c overdueSched = [
            SELECT Status__c
            FROM Repayment_Schedule__c
            WHERE Id = :thirdSched.Id
        ];
        System.assertEquals('Overdue', overdueSched.Status__c);
    }

    @IsTest
    static void testRunReminderBatchNow() {
        Test.startTest();
        String result = LoanController.runReminderBatchNow(3);
        Test.stopTest();

        System.assert(result.contains('Batch Reminder Job queued'));
    }

    @IsTest
    static void testControllerExceptions() {
        Test.startTest();
        try {
            LoanController.getLoanDetails(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.getLoanSchedules(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.getLoanSummaryStats(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.updateLoanStatus(null, '', '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.updateBorrowerProfile(null, '', '', 0, 0, 0, '');
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markAsPaid(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markMultipleAsPaid(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }

        try {
            LoanController.markAsOverdue(null);
            System.assert(false);
        } catch (AuraHandledException e) {
            System.assertNotEquals(null, e.getMessage());
        }
        Test.stopTest();
    }
}
