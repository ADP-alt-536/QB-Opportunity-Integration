// QB_Service.cls
// This class provides various services and functionality for the Application.
public with sharing class QB_Service {

    // Static field for test configuration injection - must be public for test access
    @TestVisible
    public static QB_Config__mdt getTestableConfig;

    private static String getRealmId() {
        // Use testable config if injected by tests, otherwise use org defaults
        QB_Config__mdt cfg = getTestableConfig != null ? 
            getTestableConfig : 
            QB_Config__mdt.getInstance('Org_Defaults');
        
        if (cfg == null || String.isBlank(cfg.Realm_Id__c)) {
            throw new QB_ServiceException('Missing QuickBooks realmId. Set QB_Config__mdt or use getTestableConfig.');
        }
        return cfg.Realm_Id__c;
    }

    public static String ensureCustomer(Account acc) {
        if (String.isNotBlank(acc.QuickBooks_Customer_Id__c)) {
            return acc.QuickBooks_Customer_Id__c;
        }

        String realmId = getRealmId();
        
        // Build customer request inline
        QB_Models.CustomerUpsertReq req = new QB_Models.CustomerUpsertReq();
        req.DisplayName = acc.Name;
        req.PrimaryEmailAddr = acc.PersonEmail__c;
        
        QB_Models.BillingAddress addr = new QB_Models.BillingAddress();
        addr.Line1 = acc.BillingStreet;
        addr.City = acc.BillingCity;
        addr.State = acc.BillingState;
        addr.PostalCode = acc.BillingPostalCode;
        addr.Country = acc.BillingCountry;
        req.BillAddr = addr;
        
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

    /**
     * @description Creates an invoice with line items based on Opportunity Record Type and membership dues
     * Line 1: RecordType-based label with Opportunity Amount
     * Line 2 (optional): "1 Year Membership Discount" if Custom_Membership_Dues__c is not blank
     *                    Amount = Calculated_Dues_Amount__c - Custom_Membership_Dues__c
     */
    public static String createInvoiceFromOpportunity(Opportunity opp, Account acc, String customerId, String defaultItemRef) {
        String realmId = getRealmId();
        
        // Build invoice request with line items based on RecordType and membership dues
        QB_Models.InvoiceCreateReq req = new QB_Models.InvoiceCreateReq();
        List<QB_Models.InvoiceLine> lines = new List<QB_Models.InvoiceLine>();

        // LINE 1: Determine line item label based on RecordType
        String lineItemLabel = 'Invoice';
        if (opp.RecordType != null) {
            if (opp.RecordType.Name == 'Membership Recurring/Renewal Opportunities') {
                lineItemLabel = 'CLS Renewal Membership';
            } else if (opp.RecordType.Name == 'New Membership Opportunities') {
                lineItemLabel = 'CLS New Membership';
            }
        }

        // Create first line item with label and amount
        QB_Models.InvoiceLine line1 = new QB_Models.InvoiceLine();
        QB_Models.SalesItemLineDetail detail1 = new QB_Models.SalesItemLineDetail();
        detail1.ItemRef = String.isBlank(defaultItemRef) ? '1' : defaultItemRef;
        detail1.Amount = opp.Amount;
        line1.SalesItemLineDetail = detail1;
        lines.add(line1);

        // LINE 2 (OPTIONAL): Add discount line item if Custom_Membership_Dues__c is not null
       if (opp.Custom_Membership_Dues__c != null && opp.Calculated_Dues_Amount__c != null) {
    Decimal calculatedDues = Decimal.valueOf(opp.Calculated_Dues_Amount__c);
    Decimal discountAmount = calculatedDues - opp.Custom_Membership_Dues__c;
            
            QB_Models.InvoiceLine line2 = new QB_Models.InvoiceLine();
            QB_Models.SalesItemLineDetail detail2 = new QB_Models.SalesItemLineDetail();
            detail2.ItemRef = String.isBlank(defaultItemRef) ? '1' : defaultItemRef;
            detail2.Amount = discountAmount;
            line2.SalesItemLineDetail = detail2;
            lines.add(line2);
        }
        
        req.Line = lines;
        
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
