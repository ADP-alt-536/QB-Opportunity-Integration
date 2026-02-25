/**
 * @description Service layer for syncing Salesforce data to QuickBooks:
 * - Upsert Customer from Account when QuickBooks_Customer_Id__c is blank
 * - Create Invoice from Opportunity when Stage = Paid (single line: Opportunity Amount, non-taxable)
 * Security:
 * - with sharing, DML in USER_MODE
 * - FLS/CRUD checks are expected to be enforced via Flows/UI or Named Credential; add explicit checks if needed.
 * Notes:
 * - Assumes Named Credential 'QuickBooks_NC' exists and OAuth is configured.
 * - Uses central custom setting QB_Config__c.Realm_Id__c as the QuickBooks realmId.
 * - Does not create Payment; relies on QuickBooks auto numbering.
 */
public with sharing class QB_Service {

    /**
     * @description Returns QuickBooks realmId from central Hierarchy Custom Setting QB_Config__c.Realm_Id__c
     */
    private static String getRealmId() {
        QB_Config__c cfg = QB_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Realm_Id__c)) {
            throw new QB_ServiceException('Missing QuickBooks realmId. Set QB_Config__c.Realm_Id__c.');
        }
        return cfg.Realm_Id__c;
    }

    /**
     * @description Ensures a QuickBooks Customer exists for the Account. If QuickBooks_Customer_Id__c is blank, creates it and updates the Account in USER_MODE.
     * @return QuickBooks Customer Id
     */
    public static String ensureCustomer(Account acc) {
        if (String.isNotBlank((String)acc.get('QuickBooks_Customer_Id__c'))) {
            return (String)acc.get('QuickBooks_Customer_Id__c');
        }
        String realmId = getRealmId();
        QB_Models.CustomerUpsertReq req = QB_Models.Builders.customerFrom(acc);
        String body = JSON.serialize(req);
        HttpResponse res = QB_HttpClient.post(realmId, QB_Enums.CUSTOMER_RESOURCE, body);
        QB_Models.CreatedCustomerRes parsed = (QB_Models.CreatedCustomerRes)JSON.deserialize(res.getBody(), QB_Models.CreatedCustomerRes.class);
        if (parsed == null || parsed.Customer == null || String.isBlank(parsed.Customer.Id)) {
            throw new QB_ServiceException('Failed to parse Customer creation response.');
        }
        // Write back to Account in USER_MODE
        Account upd = new Account(Id = acc.Id);
        upd.put('QuickBooks_Customer_Id__c', parsed.Customer.Id);
        Database.SaveResult sr = Database.update(upd, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            Database.Error e = sr.getErrors().isEmpty() ? null : sr.getErrors()[0];
            throw new QB_ServiceException('Failed to update Account with QuickBooks Customer Id: ' + (e != null ? e.getMessage() : 'Unknown error'));
        }
        return parsed.Customer.Id;
    }

    /**
     * @description Creates a QuickBooks Invoice from an Opportunity for a given QuickBooks Customer Id
     * Behavior: Single non-taxable line using Opportunity Amount and a default ItemRef placeholder '1' (or configured value).
     * @returns QuickBooks Invoice Id
     */
    public static String createInvoiceFromOpportunity(Opportunity opp, Account acc, String customerId, String defaultItemRef) {
        String realmId = getRealmId();
        String taxCodeRef = null; // non-taxable per requirements
        QB_Models.InvoiceCreateReq req = QB_Models.Builders.singleLineInvoiceFrom(opp, customerId, defaultItemRef, taxCodeRef);
        String body = JSON.serialize(req);
        HttpResponse res = QB_HttpClient.post(realmId, QB_Enums.INVOICE_RESOURCE, body);
        QB_Models.CreatedInvoiceRes parsed = (QB_Models.CreatedInvoiceRes)JSON.deserialize(res.getBody(), QB_Models.CreatedInvoiceRes.class);
        if (parsed == null || parsed.Invoice == null || String.isBlank(parsed.Invoice.Id)) {
            throw new QB_ServiceException('Failed to parse Invoice creation response.');
        }
        // Persist back to Opportunity in USER_MODE if field exists
        Opportunity upd = new Opportunity(Id = opp.Id);
        upd.put('QuickBooks_Invoice_Id__c', parsed.Invoice.Id);
        Database.SaveResult sr = Database.update(upd, AccessLevel.USER_MODE);
        if (!sr.isSuccess()) {
            Database.Error e = sr.getErrors().isEmpty() ? null : sr.getErrors()[0];
            throw new QB_ServiceException('Failed to update Opportunity with QuickBooks Invoice Id: ' + (e != null ? e.getMessage() : 'Unknown error'));
        }
        return parsed.Invoice.Id;
    }

    public class QB_ServiceException extends Exception {}
}
