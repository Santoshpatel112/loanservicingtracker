/**
 * @description       : Comprehensive Test Suite for EMIReminderEmailService.
 *                      Validates batch email dispatch, overdue detection, scheduled cron execution,
 *                      payment confirmation receipts, status change alerts, and profile update notifications.
 * @author            : Santosh Patel (santoshpatelvns5@gmail.com)
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
@isTest
private class EMIReminderEmailServiceTest {

    @TestSetup
    static void setupTestData() {
        Loan__c loan = new Loan__c(
            Name                  = 'LN-TEST-MAIL',
            Borrower_Name__c      = 'Priya Sharma',
            Borrower_Email__c     = 'priya.sharma@example.com',
            Loan_Type__c          = 'Personal Loan',
            Principal_Amount__c   = 200000.00,
            Interest_Rate__c      = 12.00,
            Tenure_Months__c      = 12,
            Disbursement_Date__c  = Date.today(),
            Status__c             = 'Approved'
        );
        insert loan;

        List<Repayment_Schedule__c> schedules = [
            SELECT Id, Due_Date__c, Status__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            ORDER BY Due_Date__c ASC
            LIMIT 4
        ];

        if (schedules.size() >= 4) {
            schedules[0].Due_Date__c = Date.today().addDays(-2); // Overdue
            schedules[0].Status__c   = 'Pending';

            schedules[1].Due_Date__c = Date.today(); // Due today
            schedules[1].Status__c   = 'Pending';

            schedules[2].Due_Date__c = Date.today().addDays(1); // Due tomorrow
            schedules[2].Status__c   = 'Pending';

            schedules[3].Due_Date__c = Date.today().addDays(3); // Due in 3 days
            schedules[3].Status__c   = 'Pending';

            update schedules;
        }
    }

    @isTest
    static void testBatchExecutionWithOverdueDetection() {
        Test.startTest();
        EMIReminderEmailService batchJob = new EMIReminderEmailService(3);
        Database.executeBatch(batchJob, 50);
        Test.stopTest();

        // Verify overdue record was updated to Overdue
        List<Repayment_Schedule__c> overdueList = [
            SELECT Id, Status__c
            FROM Repayment_Schedule__c
            WHERE Due_Date__c < :Date.today()
        ];
        System.assert(!overdueList.isEmpty());
        System.assertEquals('Overdue', overdueList[0].Status__c);
    }

    @isTest
    static void testScheduledJobExecution() {
        Test.startTest();
        String cronExp = '0 0 9 * * ?';
        String jobId = System.schedule('Test_EMIReminder_Job_SaaS', cronExp, new EMIReminderEmailService());
        Test.stopTest();

        CronTrigger ct = [
            SELECT Id, CronExpression, TimesTriggered, NextFireTime
            FROM CronTrigger
            WHERE Id = :jobId
        ];
        System.assertEquals(cronExp, ct.CronExpression);
    }

    @isTest
    static void testInvocableExecution() {
        Test.startTest();
        List<String> results = EMIReminderEmailService.sendRemindersInvocable(new List<Integer>{ 5 });
        Test.stopTest();

        System.assertNotEquals(null, results);
        System.assert(results[0].contains('5 days'));
    }

    @isTest
    static void testTransactionalReceiptEmail() {
        Loan__c loan = [SELECT Id, Name, Borrower_Name__c, Borrower_Email__c FROM Loan__c LIMIT 1];
        Repayment_Schedule__c sched = [
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];

        Test.startTest();
        EMIReminderEmailService.sendPaymentReceiptEmail(sched, 180000.00, 11);
        Test.stopTest();

        Messaging.SingleEmailMessage mail = EMIReminderEmailService.buildPaymentReceiptEmail(sched, 180000.00, 11);
        System.assert(mail.getSubject().contains('Payment Receipt'));
        System.assert(mail.getHtmlBody().contains('Payment Successful'));
    }

    @isTest
    static void testTransactionalStatusChangeEmail() {
        Loan__c loan = [
            SELECT Id, Name, Borrower_Name__c, Borrower_Email__c, Principal_Amount__c
            FROM Loan__c
            LIMIT 1
        ];

        Test.startTest();
        EMIReminderEmailService.sendStatusChangeEmail(loan, 'Pending', 'Approved', 'Approved by santoshpatelvns5@gmail.com');
        EMIReminderEmailService.sendStatusChangeEmail(loan, 'Pending', 'Rejected', 'Rejected');
        EMIReminderEmailService.sendStatusChangeEmail(loan, 'Approved', 'Closed', 'Loan settled');
        Test.stopTest();

        Messaging.SingleEmailMessage mailApp = EMIReminderEmailService.buildStatusChangeEmail(loan, 'Pending', 'Approved', 'Approved');
        Messaging.SingleEmailMessage mailRej = EMIReminderEmailService.buildStatusChangeEmail(loan, 'Pending', 'Rejected', 'Reason');
        System.assert(mailApp.getSubject().contains('Approved'));
        System.assert(mailRej.getSubject().contains('Rejected'));
    }

    @isTest
    static void testTransactionalProfileUpdateEmail() {
        Loan__c loan = [
            SELECT Id, Name, Borrower_Name__c, Borrower_Email__c, Principal_Amount__c
            FROM Loan__c
            LIMIT 1
        ];

        Test.startTest();
        EMIReminderEmailService.sendProfileUpdateEmail(loan, 'Interest Rate: 10% ➔ 11%');
        Test.stopTest();

        Messaging.SingleEmailMessage mail = EMIReminderEmailService.buildProfileUpdateEmail(loan, 'Principal: ₹200000 ➔ ₹250000');
        System.assert(mail.getSubject().contains('Updated'));
        System.assert(mail.getHtmlBody().contains('Modifications Made'));
    }

    @isTest
    static void testReminderEmailVariations() {
        Loan__c loan = [
            SELECT Id, Name, Borrower_Name__c, Borrower_Email__c
            FROM Loan__c
            LIMIT 1
        ];

        Repayment_Schedule__c sched = [
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c
            FROM Repayment_Schedule__c
            WHERE Loan__c = :loan.Id
            LIMIT 1
        ];

        // 1. Overdue
        sched.Due_Date__c = Date.today().addDays(-3);
        Messaging.SingleEmailMessage mailOverdue = EMIReminderEmailService.buildReminderEmail(sched);
        System.assert(mailOverdue.getSubject().contains('OVERDUE'));

        // 2. Due Today
        sched.Due_Date__c = Date.today();
        Messaging.SingleEmailMessage mailToday = EMIReminderEmailService.buildReminderEmail(sched);
        System.assert(mailToday.getSubject().contains('DUE TODAY'));

        // 3. Due Tomorrow
        sched.Due_Date__c = Date.today().addDays(1);
        Messaging.SingleEmailMessage mailTmrw = EMIReminderEmailService.buildReminderEmail(sched);
        System.assert(mailTmrw.getSubject().contains('DUE TOMORROW'));

        // 4. Due in X Days
        sched.Due_Date__c = Date.today().addDays(4);
        Messaging.SingleEmailMessage mail4Days = EMIReminderEmailService.buildReminderEmail(sched);
        System.assert(mail4Days.getSubject().contains('Due in 4 Days'));
    }

    @isTest
    static void testNullGuards() {
        Test.startTest();
        EMIReminderEmailService.sendPaymentReceiptEmail(null, 0, 0);
        EMIReminderEmailService.sendStatusChangeEmail(null, '', '', '');
        EMIReminderEmailService.sendProfileUpdateEmail(null, '');
        Test.stopTest();
        System.assert(true, 'Null guards executed cleanly');
    }
}
