public with sharing class QB_Service {

    private static String getRealmId() {
        QB_Config__c cfg = QB_Config__c.getOrgDefaults();
        if (cfg == null || String.isBlank(cfg.Realm_Id__c)) {
            throw new QB_ServiceException('Missing QuickBooks realmId. Set QB_Config__c.Realm_Id__c.');
        }
        return cfg.Realm_Id__c;
    }

    public static String ensureCustomer(Account acc) {
        if (String.isNotBlank(acc.QuickBooks_Customer_Id__c)) {
            return acc.QuickBooks_Customer_Id__c;
        }

        String realmId = getRealmId();
        QB_Models.CustomerUpsertReq req = QB_Models.Builders.customerFrom(acc); // you can implement Builders class separately
        String body = JSON.serialize(req);
        HttpResponse res = QB_HttpClient.post(realmId, QB_Enums.CUSTOMER_RESOURCE, body);
        QB_Models.CreatedCustomerRes parsed = (QB_Models.CreatedCustomerRes)JSON.deserialize(res.getBody(), QB_Models.CreatedCustomerRes.class);

        if (parsed == null || parsed.Customer == null || String.isBlank(parsed.Customer.Id)) {
            throw new QB_ServiceException('Failed to parse Customer creation response.');
        }

        Account upd = new Account(Id = acc.Id);
        upd.QuickBooks_Customer_Id__c = parsed.Customer.Id;
        Database.update(upd, AccessLevel.USER_MODE);

        return parsed.Customer.Id;
    }

    public static String createInvoiceFromOpportunity(Opportunity opp, Account acc, String customerId, String defaultItemRef) {
        String realmId = getRealmId();
        String taxCodeRef = null; // non-taxable
        QB_Models.InvoiceCreateReq req = QB_Models.Builders.singleLineInvoiceFrom(opp, customerId, defaultItemRef, taxCodeRef);
        String body = JSON.serialize(req);
        HttpResponse res = QB_HttpClient.post(realmId, QB_Enums.INVOICE_RESOURCE, body);
        QB_Models.CreatedInvoiceRes parsed = (QB_Models.CreatedInvoiceRes)JSON.deserialize(res.getBody(), QB_Models.CreatedInvoiceRes.class);

        if (parsed == null || parsed.Invoice == null || String.isBlank(parsed.Invoice.Id)) {
            throw new QB_ServiceException('Failed to parse Invoice creation response.');
        }

        Opportunity upd = new Opportunity(Id = opp.Id);
        upd.QuickBooks_Invoice_Id__c = parsed.Invoice.Id;
        Database.update(upd, AccessLevel.USER_MODE);

        return parsed.Invoice.Id;
    }

    public class QB_ServiceException extends Exception {}
}