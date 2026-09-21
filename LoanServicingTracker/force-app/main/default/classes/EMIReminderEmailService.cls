/**
 * @description       : Automated Email Servicing Engine for Loan Servicing & EMI Repayment Platform.
 *                      Implements Schedulable & Database.Batchable<sObject> for daily automated reminders.
 *                      Provides transactional email methods for:
 *                      1. Daily Due Date & Overdue EMI Reminders (recursive until paid)
 *                      2. Instant Payment Receipt Confirmations ("Mark as Paid")
 *                      3. Loan Approval / Rejection / Closure Notifications
 *                      4. Borrower Profile & Loan Parameter Modification Alerts
 * @author            : Santosh Patel (santoshpatelvns5@gmail.com)
 * @created           : 2026
 * @last modified on  : 2026-09-21
 **/
public with sharing class EMIReminderEmailService implements Schedulable, Database.Batchable<sObject> {

    // Default reminder window in days (default = 3 days)
    private Integer daysAhead;

    /**
     * @description Default constructor checking EMIs due in the next 3 days.
     */
    public EMIReminderEmailService() {
        this(3);
    }

    /**
     * @description Parameterized constructor allowing custom reminder window.
     * @param daysAhead Number of days ahead of due date to trigger reminder
     */
    public EMIReminderEmailService(Integer daysAhead) {
        this.daysAhead = (daysAhead != null && daysAhead >= 0) ? daysAhead : 3;
    }

    // ─── Schedulable Interface ───────────────────────────────────────────────

    public void execute(SchedulableContext sc) {
        Database.executeBatch(new EMIReminderEmailService(this.daysAhead), 50);
    }

    // ─── Database.Batchable Interface ────────────────────────────────────────

    /**
     * @description Start method queries pending schedules whose due date falls between TODAY and TODAY + daysAhead,
     *              as well as overdue pending schedules (Due_Date__c < TODAY).
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        Date todayDate = Date.today();
        Date targetDueDate = todayDate.addDays(this.daysAhead);

        return Database.getQueryLocator([
            SELECT Id, Name, EMI_Amount__c, Due_Date__c, Status__c,
                   Principal_Component__c, Interest_Component__c, Outstanding_Balance__c,
                   Loan__c, Loan__r.Name, Loan__r.Borrower_Name__c, Loan__r.Borrower_Email__c,
                   Loan__r.Loan_Type__c, Loan__r.Interest_Rate__c, Loan__r.Principal_Amount__c
            FROM Repayment_Schedule__c
            WHERE (Status__c = 'Pending' OR Status__c = 'Overdue')
            AND Due_Date__c <= :targetDueDate
            AND Loan__r.Borrower_Email__c != null
            ORDER BY Due_Date__c ASC
        ]);
    }

    /**
     * @description Execute method marks past-due items as Overdue and dispatches tailored reminder emails.
     */
    public void execute(Database.BatchableContext bc, List<Repayment_Schedule__c> schedules) {
        if (schedules == null || schedules.isEmpty()) {
            return;
        }

        List<Repayment_Schedule__c> schedulesToUpdate = new List<Repayment_Schedule__c>();
        List<Messaging.SingleEmailMessage> emailsToSend = new List<Messaging.SingleEmailMessage>();
        Date todayDate = Date.today();

        for (Repayment_Schedule__c sched : schedules) {
            // Auto-flag past-due records as Overdue if not already marked
            if (sched.Due_Date__c < todayDate && sched.Status__c == 'Pending') {
                sched.Status__c = 'Overdue';
                schedulesToUpdate.add(new Repayment_Schedule__c(
                    Id = sched.Id,
                    Status__c = 'Overdue'
                ));
            }

            if (String.isNotBlank(sched.Loan__r.Borrower_Email__c)) {
                Messaging.SingleEmailMessage email = buildReminderEmail(sched);
                emailsToSend.add(email);
            }
        }

        // Update overdue statuses
        if (!schedulesToUpdate.isEmpty()) {
            try {
                update schedulesToUpdate;
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Failed to update overdue schedule statuses: ' + ex.getMessage());
            }
        }

        // Dispatch emails
        if (!emailsToSend.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emailsToSend, false);
                for (Messaging.SendEmailResult res : results) {
                    if (!res.isSuccess()) {
                        for (Messaging.SendEmailError err : res.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Email dispatch warning: ' + err.getMessage());
                        }
                    }
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Exception in dispatching batch reminder emails: ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Finish method for batch logging and metrics tracking.
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('EMIReminderEmailService batch job finished successfully.');
    }

    // ─── Transactional Dispatch Methods ──────────────────────────────────────

    /**
     * @description Sends an instant payment receipt confirmation email upon EMI payment.
     * @param sched The Repayment_Schedule__c record that was marked as paid
     * @param remainingBalance Outstanding loan balance after payment
     * @param remainingCount Number of remaining pending installments
     */
    public static void sendPaymentReceiptEmail(Repayment_Schedule__c sched, Decimal remainingBalance, Integer remainingCount) {
        if (sched == null || String.isBlank(sched.Loan__r.Borrower_Email__c)) {
            return;
        }

        Messaging.SingleEmailMessage email = buildPaymentReceiptEmail(sched, remainingBalance, remainingCount);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error sending payment receipt email: ' + ex.getMessage());
        }
    }

    /**
     * @description Sends an email notification when a loan status changes (Approved, Rejected, Closed).
     * @param loan The Loan__c record
     * @param previousStatus Previous loan status
     * @param newStatus New loan status
     * @param adminComments Optional comments from administrator
     */
    public static void sendStatusChangeEmail(Loan__c loan, String previousStatus, String newStatus, String adminComments) {
        if (loan == null || String.isBlank(loan.Borrower_Email__c)) {
            return;
        }

        Messaging.SingleEmailMessage email = buildStatusChangeEmail(loan, previousStatus, newStatus, adminComments);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error sending loan status change email: ' + ex.getMessage());
        }
    }

    /**
     * @description Sends an email notification when borrower profile or loan parameters are modified.
     * @param loan The Loan__c record
     * @param updateSummary Human readable summary of updated fields
     */
    public static void sendProfileUpdateEmail(Loan__c loan, String updateSummary) {
        if (loan == null || String.isBlank(loan.Borrower_Email__c)) {
            return;
        }

        Messaging.SingleEmailMessage email = buildProfileUpdateEmail(loan, updateSummary);
        try {
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email }, false);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error sending profile update notification email: ' + ex.getMessage());
        }
    }

    // ─── Email Template Builders ─────────────────────────────────────────────

    /**
     * @description Builds a scheduled due date or overdue reminder email with Finspectra dark theme.
     */
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
        String urgencyTag;
        String badgeColor;
        String badgeBorder;

        if (daysLeft < 0) {
            urgencyTag  = 'OVERDUE by ' + Math.abs(daysLeft) + ' Day(s)';
            badgeColor  = 'rgba(239, 68, 68, 0.2)';
            badgeBorder = '#ef4444';
        } else if (daysLeft == 0) {
            urgencyTag  = 'DUE TODAY';
            badgeColor  = 'rgba(245, 158, 11, 0.2)';
            badgeBorder = '#f59e0b';
        } else if (daysLeft == 1) {
            urgencyTag  = 'DUE TOMORROW';
            badgeColor  = 'rgba(245, 158, 11, 0.2)';
            badgeBorder = '#f59e0b';
        } else {
            urgencyTag  = 'Due in ' + daysLeft + ' Days';
            badgeColor  = 'rgba(99, 102, 241, 0.2)';
            badgeBorder = '#6366f1';
        }

        mail.setSubject('🔔 Payment Reminder: EMI of ' + formattedAmt + ' for Loan ' + loanNumber + ' is ' + urgencyTag);

        String htmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
            + '<body style="margin: 0; padding: 0; background-color: #0b0f19; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; color: #f1f5f9;">'
            + '<table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #0b0f19; padding: 30px 10px;">'
            + '  <tr><td align="center">'
            + '    <table border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #111827; border: 1px solid #1f2937; border-radius: 16px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.6);">'
            + '      <tr><td style="padding: 28px 32px; background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%); border-bottom: 1px solid #374151;">'
            + '        <div style="display: inline-block; background: #6366f1; color: #ffffff; padding: 4px 12px; border-radius: 6px; font-weight: 700; font-size: 11px; letter-spacing: 1px; margin-bottom: 10px;">FINSPECTRA PRIZM SERVICING</div>'
            + '        <h1 style="color: #ffffff; font-size: 22px; margin: 0; font-weight: 700;">EMI Installment Notice</h1>'
            + '        <p style="color: #cbd5e1; font-size: 13px; margin: 6px 0 0 0;">Dear ' + borrowerName + ', please review your upcoming loan installment details below.</p>'
            + '      </td></tr>'
            + '      <tr><td style="padding: 30px 32px;">'
            + '        <div style="background-color: #161d2e; border: 1px solid #374151; border-radius: 12px; padding: 20px; margin-bottom: 24px; text-align: center;">'
            + '          <span style="color: #94a3b8; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Total Installment Due</span>'
            + '          <div style="color: #818cf8; font-size: 34px; font-weight: 800; margin: 6px 0;">' + formattedAmt + '</div>'
            + '          <div style="display: inline-block; background: ' + badgeColor + '; color: #ffffff; border: 1px solid ' + badgeBorder + '; padding: 3px 12px; border-radius: 20px; font-size: 11px; font-weight: 700;">' + urgencyTag + ' &bull; ' + dueDateStr + '</div>'
            + '        </div>'
            + '        <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 24px; border-collapse: collapse;">'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Loan Reference</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + loanNumber + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Installment ID</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + emiRef + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Due Date</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + dueDateStr + '</td></tr>'
            + '          <tr><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Status</td><td style="padding: 10px 0; color: #f59e0b; font-size: 13px; font-weight: 600; text-align: right;">' + sched.Status__c + '</td></tr>'
            + '        </table>'
            + '        <div style="background: rgba(99, 102, 241, 0.08); border-left: 3px solid #6366f1; padding: 12px 16px; border-radius: 4px; margin-bottom: 24px;">'
            + '          <p style="color: #94a3b8; font-size: 12px; margin: 0; line-height: 1.5;">To maintain a strong credit score and prevent late penalty fees, kindly ensure adequate funds are maintained in your designated bank account.</p>'
            + '        </div>'
            + '        <div style="border-top: 1px solid #1f2937; padding-top: 16px; font-size: 11px; color: #64748b; line-height: 1.5;">'
            + '          Admin Contact: santoshpatelvns5@gmail.com &bull; &copy; 2026 Finspectra Prizm Loan Servicing.'
            + '        </div>'
            + '      </td></tr>'
            + '    </table>'
            + '  </td></tr>'
            + '</table></body></html>';

        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody('Payment Reminder for Loan ' + loanNumber + ' (' + emiRef + '): ' + formattedAmt + ' is ' + urgencyTag + ' (' + dueDateStr + ').\nAdmin: santoshpatelvns5@gmail.com');

        return mail;
    }

    /**
     * @description Builds a payment confirmation receipt email sent immediately after payment.
     */
    public static Messaging.SingleEmailMessage buildPaymentReceiptEmail(Repayment_Schedule__c sched, Decimal remainingBalance, Integer remainingCount) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ sched.Loan__r.Borrower_Email__c });
        mail.setSaveAsActivity(false);

        String borrowerName = String.isNotBlank(sched.Loan__r.Borrower_Name__c) ? sched.Loan__r.Borrower_Name__c : 'Valued Customer';
        String loanNumber   = sched.Loan__r.Name;
        String emiRef       = sched.Name;
        String formattedAmt = (sched.EMI_Amount__c != null) ? '₹ ' + sched.EMI_Amount__c.setScale(2).format() : '₹ 0.00';
        String formattedRem = (remainingBalance != null) ? '₹ ' + remainingBalance.setScale(2).format() : '₹ 0.00';
        String paidDateStr  = DateTime.now().format('dd MMM yyyy, hh:mm a');

        mail.setSubject('✅ Payment Receipt: ' + formattedAmt + ' Received for Loan ' + loanNumber + ' (' + emiRef + ')');

        String htmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
            + '<body style="margin: 0; padding: 0; background-color: #0b0f19; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; color: #f1f5f9;">'
            + '<table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #0b0f19; padding: 30px 10px;">'
            + '  <tr><td align="center">'
            + '    <table border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #111827; border: 1px solid #1f2937; border-radius: 16px; overflow: hidden; box-shadow: 0 20px 40px rgba(0,0,0,0.6);">'
            + '      <tr><td style="padding: 28px 32px; background: linear-gradient(135deg, #064e3b 0%, #065f46 100%); border-bottom: 1px solid #047857;">'
            + '        <div style="display: inline-block; background: #10b981; color: #ffffff; padding: 4px 12px; border-radius: 6px; font-weight: 700; font-size: 11px; letter-spacing: 1px; margin-bottom: 10px;">TRANSACTION CONFIRMED</div>'
            + '        <h1 style="color: #ffffff; font-size: 22px; margin: 0; font-weight: 700;">Payment Successful</h1>'
            + '        <p style="color: #a7f3d0; font-size: 13px; margin: 6px 0 0 0;">Dear ' + borrowerName + ', we have received your payment. Thank you for your prompt repayment.</p>'
            + '      </td></tr>'
            + '      <tr><td style="padding: 30px 32px;">'
            + '        <div style="background-color: #064e3b; background: rgba(16, 185, 129, 0.1); border: 1px solid rgba(16, 185, 129, 0.3); border-radius: 12px; padding: 20px; margin-bottom: 24px; text-align: center;">'
            + '          <span style="color: #6ee7b7; font-size: 11px; text-transform: uppercase; letter-spacing: 1px; font-weight: 600;">Amount Paid Successfully</span>'
            + '          <div style="color: #34d399; font-size: 34px; font-weight: 800; margin: 6px 0;">' + formattedAmt + '</div>'
            + '          <div style="color: #94a3b8; font-size: 12px;">Processed on ' + paidDateStr + '</div>'
            + '        </div>'
            + '        <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 24px; border-collapse: collapse;">'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Loan Account</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + loanNumber + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Receipt Reference</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + emiRef + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Remaining Balance</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + formattedRem + '</td></tr>'
            + '          <tr><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Pending Installments</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + remainingCount + ' EMIs remaining</td></tr>'
            + '        </table>'
            + '        <div style="border-top: 1px solid #1f2937; padding-top: 16px; font-size: 11px; color: #64748b; line-height: 1.5;">'
            + '          This is an electronically generated receipt. Administrator: santoshpatelvns5@gmail.com &bull; &copy; 2026 Finspectra Prizm Servicing.'
            + '        </div>'
            + '      </td></tr>'
            + '    </table>'
            + '  </td></tr>'
            + '</table></body></html>';

        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody('Payment Confirmation for Loan ' + loanNumber + ': ' + formattedAmt + ' received successfully for ' + emiRef + ' on ' + paidDateStr + '. Remaining Balance: ' + formattedRem + '.');

        return mail;
    }

    /**
     * @description Builds a loan status change notification email (Approved / Rejected / Closed).
     */
    public static Messaging.SingleEmailMessage buildStatusChangeEmail(Loan__c loan, String previousStatus, String newStatus, String adminComments) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ loan.Borrower_Email__c });
        mail.setSaveAsActivity(false);

        String borrowerName = String.isNotBlank(loan.Borrower_Name__c) ? loan.Borrower_Name__c : 'Valued Applicant';
        String formattedAmt = (loan.Principal_Amount__c != null) ? '₹ ' + loan.Principal_Amount__c.setScale(2).format() : '₹ 0.00';
        
        String headerBg;
        String statusTitle;
        if (newStatus == 'Approved') {
            headerBg = 'linear-gradient(135deg, #064e3b 0%, #065f46 100%)';
            statusTitle = '🎉 Loan Application Approved!';
        } else if (newStatus == 'Rejected') {
            headerBg = 'linear-gradient(135deg, #881337 0%, #9f1239 100%)';
            statusTitle = 'Loan Application Status Update';
        } else {
            headerBg = 'linear-gradient(135deg, #1e1b4b 0%, #312e81 100%)';
            statusTitle = 'Loan Status Updated to ' + newStatus;
        }

        mail.setSubject('📢 Loan ' + loan.Name + ' Status Update: ' + newStatus);

        String commentsSection = String.isNotBlank(adminComments) 
            ? '<div style="background: rgba(255,255,255,0.05); border-left: 3px solid #6366f1; padding: 12px; margin-bottom: 20px; border-radius: 4px;"><strong style="color: #cbd5e1; font-size: 12px;">Admin Note:</strong><p style="color: #94a3b8; font-size: 12px; margin: 4px 0 0 0;">' + adminComments + '</p></div>'
            : '';

        String htmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
            + '<body style="margin: 0; padding: 0; background-color: #0b0f19; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; color: #f1f5f9;">'
            + '<table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #0b0f19; padding: 30px 10px;">'
            + '  <tr><td align="center">'
            + '    <table border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #111827; border: 1px solid #1f2937; border-radius: 16px; overflow: hidden;">'
            + '      <tr><td style="padding: 28px 32px; background: ' + headerBg + '; border-bottom: 1px solid #374151;">'
            + '        <h1 style="color: #ffffff; font-size: 22px; margin: 0; font-weight: 700;">' + statusTitle + '</h1>'
            + '        <p style="color: #cbd5e1; font-size: 13px; margin: 6px 0 0 0;">Dear ' + borrowerName + ', your loan status has been updated by the administration team.</p>'
            + '      </td></tr>'
            + '      <tr><td style="padding: 30px 32px;">'
            + '        ' + commentsSection
            + '        <table border="0" cellpadding="0" cellspacing="0" width="100%" style="margin-bottom: 24px; border-collapse: collapse;">'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Loan Number</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + loan.Name + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">Principal Amount</td><td style="padding: 10px 0; color: #f1f5f9; font-size: 13px; font-weight: 600; text-align: right;">' + formattedAmt + '</td></tr>'
            + '          <tr style="border-bottom: 1px solid #1f2937;"><td style="padding: 10px 0; color: #94a3b8; font-size: 13px;">New Status</td><td style="padding: 10px 0; color: #38bdf8; font-size: 13px; font-weight: 700; text-align: right;">' + newStatus + '</td></tr>'
            + '        </table>'
            + '        <div style="border-top: 1px solid #1f2937; padding-top: 16px; font-size: 11px; color: #64748b;">'
            + '          Administrator: santoshpatelvns5@gmail.com &bull; &copy; 2026 Finspectra Prizm Servicing.'
            + '        </div>'
            + '      </td></tr>'
            + '    </table>'
            + '  </td></tr>'
            + '</table></body></html>';

        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody('Loan ' + loan.Name + ' status updated to ' + newStatus + '. Contact: santoshpatelvns5@gmail.com');

        return mail;
    }

    /**
     * @description Builds a profile/loan modification notification email.
     */
    public static Messaging.SingleEmailMessage buildProfileUpdateEmail(Loan__c loan, String updateSummary) {
        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setToAddresses(new List<String>{ loan.Borrower_Email__c });
        mail.setSaveAsActivity(false);

        String borrowerName = String.isNotBlank(loan.Borrower_Name__c) ? loan.Borrower_Name__c : 'Valued Borrower';

        mail.setSubject('⚙️ Profile / Loan Details Updated for Loan ' + loan.Name);

        String htmlBody = '<!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head>'
            + '<body style="margin: 0; padding: 0; background-color: #0b0f19; font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, Helvetica, Arial, sans-serif; color: #f1f5f9;">'
            + '<table border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #0b0f19; padding: 30px 10px;">'
            + '  <tr><td align="center">'
            + '    <table border="0" cellpadding="0" cellspacing="0" width="600" style="background-color: #111827; border: 1px solid #1f2937; border-radius: 16px; overflow: hidden;">'
            + '      <tr><td style="padding: 24px 32px; background: linear-gradient(135deg, #1e1b4b 0%, #312e81 100%); border-bottom: 1px solid #374151;">'
            + '        <h1 style="color: #ffffff; font-size: 20px; margin: 0; font-weight: 700;">Account Record Updated</h1>'
            + '        <p style="color: #cbd5e1; font-size: 13px; margin: 6px 0 0 0;">Dear ' + borrowerName + ', your loan and borrower profile details were updated.</p>'
            + '      </td></tr>'
            + '      <tr><td style="padding: 26px 32px;">'
            + '        <div style="background: rgba(99, 102, 241, 0.1); border: 1px solid rgba(99, 102, 241, 0.3); border-radius: 8px; padding: 16px; margin-bottom: 20px;">'
            + '          <strong style="color: #818cf8; font-size: 12px; text-transform: uppercase;">Modifications Made:</strong>'
            + '          <p style="color: #e2e8f0; font-size: 13px; margin: 8px 0 0 0; line-height: 1.5;">' + updateSummary + '</p>'
            + '        </div>'
            + '        <div style="border-top: 1px solid #1f2937; padding-top: 14px; font-size: 11px; color: #64748b;">'
            + '          If you did not authorize this modification, please contact santoshpatelvns5@gmail.com immediately.'
            + '        </div>'
            + '      </td></tr>'
            + '    </table>'
            + '  </td></tr>'
            + '</table></body></html>';

        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody('Your loan details for ' + loan.Name + ' were updated: ' + updateSummary);

        return mail;
    }

    /**
     * @description Invocable action for Flow or UI execution.
     */
    @InvocableMethod(label='Send EMI Due Date Reminders' description='Dispatches automated reminder notifications for upcoming EMIs.')
    public static List<String> sendRemindersInvocable(List<Integer> daysAheadList) {
        Integer days = (daysAheadList != null && !daysAheadList.isEmpty() && daysAheadList[0] != null) ? daysAheadList[0] : 3;
        Database.executeBatch(new EMIReminderEmailService(days), 50);
        return new List<String>{ 'Batch job initiated for EMIs due in the next ' + days + ' days.' };
    }
}
