/**
 * @description       : Automated Email Service for EMI Due Date Reminders.
 *                      Implements Schedulable and Database.Batchable for scalable daily execution.
 *                      Sends modern HTML reminder emails to borrowers with upcoming/today's EMI due dates.
 * @author            : Santosh Patel
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
public with sharing class EMIReminderEmailService implements Schedulable, Database.Batchable<sObject> {

    // Default reminder window: EMIs due within the next N days (default = 3 days)
    private Integer daysAhead;

    /**
     * @description Default constructor checking EMIs due in the next 3 days.
     **/
    public EMIReminderEmailService() {
        this(3);
    }

    /**
     * @description Parameterized constructor allowing custom reminder window.
     * @param daysAhead Number of days ahead of due date to trigger reminder
     **/
    public EMIReminderEmailService(Integer daysAhead) {
        this.daysAhead = (daysAhead != null && daysAhead >= 0) ? daysAhead : 3;
    }

    // ─── Schedulable Interface ───────────────────────────────────────────────
    public void execute(SchedulableContext sc) {
        // Launch batch execution with scope of 50 records per chunk
        Database.executeBatch(new EMIReminderEmailService(this.daysAhead), 50);
    }

    // ─── Database.Batchable Interface ────────────────────────────────────────

    /**
     * @description Start method queries pending schedules whose due date falls between TODAY and TODAY + daysAhead.
     **/
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date todayDate = Date.today();
        Date targetDueDate = todayDate.addDays(this.daysAhead);

        return Database.getQueryLocator([
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Principal_Component__c, Interest_Component__c, Outstanding_Balance__c,
                   Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c,
                   Loan__r.Loan_Type__c, Loan__r.Interest_Rate__c
            FROM Repayment_Schedule__c
            WHERE Status__c = 'Pending'
            AND Due_Date__c >= :todayDate
            AND Due_Date__c <= :targetDueDate
            AND Loan__r.Borrower_Email__c != null
            ORDER BY Due_Date__c ASC
        ]);
    }

    /**
     * @description Execute method compiles and sends rich HTML emails to borrowers.
     **/
    public void execute(Database.BatchableContext bc, List<Repayment_Schedule__c> schedules) {
        if (schedules == null || schedules.isEmpty()) {
            return;
        }

        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();

        for (Repayment_Schedule__c sched : schedules) {
            if (String.isNotBlank(sched.Loan__r.Borrower_Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(sched);
                emailsToSend.add(email);
            }
        }

        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
                for (Messaging.SendEmailResult res : results) {
                    if (!res.isSuccess()) {
                        for (Messaging.SendEmailError err : res.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Failed to send EMI reminder email: ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Exception in sending reminder emails: ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Finish method for batch post-processing or logging.
     **/
    public void finish(Database.BatchableContext bc) {
        System.debug('EMIReminderEmailService batch job completed successfully.');
    }

    // ─── Email Template Builder ──────────────────────────────────────────────

    /**
     * @description Builds a single SingleEmailMessage with a responsive modern fintech HTML layout.
     * @param sched Repayment_Schedule__c record
     * @return Messaging.SingleEmailMessage
     **/
    public static Messaging.SingleEmailMessage buildReminderEmail(Repayment_Schedule__c sched) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

        mail.setToAddresses(new List<String>{ sched.Loan__r.Borrower_Email__c });
        mail.setSaveAsActivity(false);

        String borrowerName = String.isNotBlank(sched.Loan__r.Borrower_Name__c) ? sched.Loan__r.Borrower_Name__c : 'Valued Customer';
        String loanNumber   = sched.Loan__r.Name;
        String emiRef       = sched.Name;
        String formattedAmt = (sched.EMI_Amount__c != null) ? '₹ ' + sched.EMI_Amount__c.setScale(2).format() : '₹ 0.00';
        String dueDateStr   = (sched.Due_Date__c != null) ? DateTime.newInstance(sched.Due_Date__c.year(), sched.Due_Date__c.month(), sched.Due_Date__c.day()).format('dd MMM yyyy') : 'Upcoming';
        
        Integer daysLeft    = (sched.Due_Date__c != null) ? Date.today().daysBetween(sched.Due_Date__c) : 0;
        String urgencyTag   = (daysLeft == 0) ? 'Due Today' : (daysLeft == 1 ? 'Due Tomorrow' : 'Due in ' + daysLeft + ' Days');

        mail.setSubject('🔔 Payment Reminder: EMI of ' + formattedAmt + ' for Loan ' + loanNumber + ' is ' + urgencyTag);

        String htmlBody = '<!DOCTYPE html>'
            + '<html>'
            + '<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
            + '<body style="margin: 0; padding: 0; background-color: #0a0d14; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif;">'
            + '<table border="0" cellpadding="0" cellspacing="0" width="100%" style="table-layout: fixed; background-color: #0a0d14; padding: 40px 10px;">'
            + '  <tr>'
            + '    <td align="center">'
            + '      <table border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #111827; border: 1px solid rgba(255,255,255,0.1); border-radius: 16px; overflow: hidden; box-shadow: 0 10px 30px rgba(0,0,0,0.5);">'
            + '        <!-- Header -->'
            + '        <tr>'
            + '          <td style="padding: 32px 36px; background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%); border-bottom: 1px solid rgba(255,255,255,0.08);">'
            + '            <table border="0" cellpadding="0" cellspacing="0" width="100%">'
            + '              <tr>'
            + '                <td>'
            + '                  <div style="display: inline-block; background: #6366f1; color: #ffffff; padding: 6px 14px; border-radius: 8px; font-weight: 700; font-size: 13px; letter-spacing: 0.5px; margin-bottom: 12px;">PRIZM LOAN SERVICING</div>'
            + '                  <h1 style="color: #ffffff; font-size: 24px; margin: 0; font-weight: 700;">Upcoming EMI Payment Due</h1>'
            + '                  <p style="color: #cbd5e1; font-size: 14px; margin: 6px 0 0 0;">Dear ' + borrowerName + ', this is a friendly reminder regarding your scheduled loan installment.</p>'
            + '                </td>'
            + '              </tr>'
            + '            </table>'
            + '          </td>'
            + '        </tr>'
            + '        <!-- Content Card -->'
            + '        <tr>'
            + '          <td style="padding: 36px;">'
            + '            <div style="background-color: #161d2e; border: 1px solid rgba(99,102,241,0.25); border-radius: 12px; padding: 24px; margin-bottom: 28px; text-align: center;">'
            + '              <span style="color: #94a3b8; font-size: 12px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Total Installment Due</span>'
            + '              <div style="color: #818cf8; font-size: 36px; font-weight: 800; margin: 8px 0; letter-spacing: -1px;">' + formattedAmt + '</div>'
            + '              <div style="display: inline-block; background: rgba(245, 158, 11, 0.15); color: #f59e0b; border: 1px solid rgba(245, 158, 11, 0.3); padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600;">' + urgencyTag + ' (' + dueDateStr + ')</div>'
            + '            </div>'
            + '            <!-- Breakdown Table -->'
            + '            <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 28px; border-collapse: collapse;">'
            + '              <tr style="border-bottom: 1px solid rgba(255,255,255,0.06);">'
            + '                <td style="padding: 12px 0; color: #94a3b8; font-size: 13px;">Loan Reference</td>'
            + '                <td style="padding: 12px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + loanNumber + '</td>'
            + '              </tr>'
            + '              <tr style="border-bottom: 1px solid rgba(255,255,255,0.06);">'
            + '                <td style="padding: 12px 0; color: #94a3b8; font-size: 13px;">Schedule Reference</td>'
            + '                <td style="padding: 12px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + emiRef + '</td>'
            + '              </tr>'
            + '              <tr style="border-bottom: 1px solid rgba(255,255,255,0.06);">'
            + '                <td style="padding: 12px 0; color: #94a3b8; font-size: 13px;">Due Date</td>'
            + '                <td style="padding: 12px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + dueDateStr + '</td>'
            + '              </tr>'
            + '              <tr>'
            + '                <td style="padding: 12px 0; color: #94a3b8; font-size: 13px;">Payment Status</td>'
            + '                <td style="padding: 12px 0; color: #f59e0b; font-size: 13px; font-weight: 600; text-align: right;">Pending</td>'
            + '              </tr>'
            + '            </table>'
            + '            <!-- Notice -->'
            + '            <p style="color: #94a3b8; font-size: 13px; line-height: 1.6; margin: 0 0 24px 0;">To ensure a seamless credit rating and avoid late payment penalties, please ensure adequate funds are available in your repayment account on or before the due date.</p>'
            + '            <!-- Support Footer -->'
            + '            <div style="border-top: 1px solid rgba(255,255,255,0.08); padding-top: 20px; font-size: 12px; color: #64748b; line-height: 1.5;">'
            + '              Need help? Contact our support team or reply directly to this email.<br>'
            + '              &copy; 2026 Prizm Loan Servicing & Financial Technologies.'
            + '            </div>'
            + '          </td>'
            + '        </tr>'
            + '      </table>'
            + '    </td>'
            + '  </tr>'
            + '</table>'
            + '</body>'
            + '</html>';

        mail.setHtmlBody(htmlBody);

        String plainBody = 'Dear ' + borrowerName + ',\n\n'
            + 'This is a payment reminder for your scheduled loan installment.\n\n'
            + 'Loan Reference: ' + loanNumber + '\n'
            + 'EMI Reference: ' + emiRef + '\n'
            + 'EMI Amount: ' + formattedAmt + '\n'
            + 'Due Date: ' + dueDateStr + ' (' + urgencyTag + ')\n'
            + 'Status: Pending\n\n'
            + 'Please ensure your account has sufficient funds prior to the due date.\n\n'
            + 'Regards,\nPrizm Loan Servicing Team';

        mail.setPlainTextBody(plainBody);

        return mail;
    }

    /**
     * @description Invocable method to manually trigger reminder dispatch (e.g. from Flow or Apex Anonymous).
     * @param daysAheadList List of integer days ahead
     * @return List<String> Status summaries
     **/
    @InvocableMethod(label='Send EMI Due Date Reminders' description='Sends automated email notifications for upcoming EMIs.')
    public static List<String> sendRemindersInvocable(List<Integer> daysAheadList) {
        Integer days = (daysAheadList != null && !daysAheadList.isEmpty() && daysAheadList[0] != null) ? daysAheadList[0] : 3;
        Database.executeBatch(new EMIReminderEmailService(days), 50);
        return new List<String>{ 'Batch job initiated for EMIs due in the next ' + days + ' days.' };
    }
}
