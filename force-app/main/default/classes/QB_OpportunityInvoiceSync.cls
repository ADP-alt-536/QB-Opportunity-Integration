/**
 * @description Invocable orchestrator to sync Opportunity -> QuickBooks Invoice when Stage = Paid.
 * - Ensures Account has QuickBooks Customer (creates if Account.QuickBooks_Customer_Id__c is blank)
 * - Creates Invoice in QuickBooks using single non-taxable line from Opportunity Amount
 * - Writes back QuickBooks_Invoice_Id__c on Opportunity
 * Designed for use from Flows and from the Queueable/Trigger handler.
 * Complies with bulkification and governor best practices.
 * Note: Default ItemRef is a placeholder '1' unless overridden via input.
 */
public with sharing class QB_OpportunityInvoiceSync {

    public class Input {
        @InvocableVariable(required=true)
        public Id opportunityId;

        @InvocableVariable(required=false)
        public String defaultItemRef;
    }

    public class Output {
        @InvocableVariable
        public Id opportunityId;
        @InvocableVariable
        public String quickBooksInvoiceId;
        @InvocableVariable
        public String quickBooksCustomerId;
        @InvocableVariable
        public String message;
        @InvocableVariable
        public Boolean success;
    }

    @InvocableMethod(label='Sync Opportunity to QuickBooks Invoice', description='Creates/ensures QuickBooks Customer for the Account, then creates an Invoice for the Opportunity when Stage=Paid.')
    public static List<Output> sync(List<Input> inputs) {
        List<Output> results = new List<Output>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }

        // Collect Opportunity Ids
        Set<Id> oppIds = new Set<Id>();
        Map<Id, String> itemOverride = new Map<Id, String>();
        for (Input inRec : inputs) {
            if (inRec == null || inRec.opportunityId == null) continue;
            oppIds.add(inRec.opportunityId);
            if (!String.isBlank(inRec.defaultItemRef)) {
                itemOverride.put(inRec.opportunityId, inRec.defaultItemRef);
            }
        }
        if (oppIds.isEmpty()) return results;

        // Load Opportunities with Account
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, Amount, StageName, AccountId, QuickBooks_Invoice_Id__c
            FROM Opportunity
            WHERE Id IN :oppIds
            WITH USER_MODE
        ]);

        Set<Id> accountIds = new Set<Id>();
        for (Opportunity o : opps.values()) {
            if (o.AccountId != null) accountIds.add(o.AccountId);
        }

        Map<Id, Account> accounts = accountIds.isEmpty() ? new Map<Id, Account>() :
            new Map<Id, Account>([
                SELECT Id, Name, Phone, PersonEmail__c, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                       QuickBooks_Company_Id__c, QuickBooks_Customer_Id__c
                FROM Account
                WHERE Id IN :accountIds
                WITH USER_MODE
            ]);

        // Process each input
        for (Input inRec : inputs) {
            Output outRec = new Output();
            outRec.opportunityId = (inRec != null) ? inRec.opportunityId : null;
            outRec.success = false;
            String defaultItem = itemOverride.containsKey(outRec.opportunityId) ? itemOverride.get(outRec.opportunityId) : '1';

            try {
                Opportunity opp = opps.get(outRec.opportunityId);
                if (opp == null) {
                    outRec.message = 'Opportunity not found';
                    results.add(outRec);
                    continue;
                }
                if (opp.StageName != QB_Enums.STAGE_PAID) {
                    outRec.message = 'Opportunity Stage is not Paid; skipping';
                    results.add(outRec);
                    continue;
                }
                if (opp.AccountId == null) {
                    outRec.message = 'Opportunity has no Account';
                    results.add(outRec);
                    continue;
                }

                Account acc = accounts.get(opp.AccountId);
                if (acc == null) {
                    outRec.message = 'Account not found';
                    results.add(outRec);
                    continue;
                }

                if (String.isBlank(acc.QuickBooks_Company_Id__c)) {
                    outRec.message = 'Missing QuickBooks Company Id (realmId) on Account';
                    results.add(outRec);
                    continue;
                }

                // Ensure Customer
                String customerId = QB_Service.ensureCustomer(acc);

                // Create Invoice (non-taxable, single line from Amount)
                String invoiceId = QB_Service.createInvoiceFromOpportunity(opp, acc, customerId, defaultItem);

                outRec.quickBooksCustomerId = customerId;
                outRec.quickBooksInvoiceId = invoiceId;
                outRec.success = true;
                outRec.message = 'Invoice created';

            } catch (Exception ex) {
                outRec.message = 'Error: ' + ex.getMessage();
            }
            results.add(outRec);
        }

        return results;
    }
}
