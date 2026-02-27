public with sharing class QB_Models_Builders {
    
    public static QB_Models.CustomerUpsertReq customerFrom(Account acc) {
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
        
        return req;
    }

    public static QB_Models.InvoiceCreateReq singleLineInvoiceFrom(
        Opportunity opp, 
        String customerId, 
        String defaultItemRef, 
        String taxCodeRef
    ) {
        QB_Models.InvoiceCreateReq req = new QB_Models.InvoiceCreateReq();
        QB_Models.InvoiceLine line = new QB_Models.InvoiceLine();
        QB_Models.SalesItemLineDetail detail = new QB_Models.SalesItemLineDetail();
        detail.ItemRef = String.isBlank(defaultItemRef) ? '1' : defaultItemRef;
        detail.Amount = opp.Amount;
        line.SalesItemLineDetail = detail;
        req.Line = new List<QB_Models.InvoiceLine>{line};
        
        return req;
    }
}