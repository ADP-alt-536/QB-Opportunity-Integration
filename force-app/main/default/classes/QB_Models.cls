/**
 * @description DTOs and helper models for QuickBooks requests/responses
 * @author Agentforce
 */
public with sharing class QB_Models {

    // Request payloads
    public class CustomerUpsertReq {
        public String DisplayName;
        public String GivenName;
        public String FamilyName;
        public String PrimaryEmailAddr;
        public String PrimaryPhone;
        public String CompanyName;
        public BillingAddress BillAddr;

        public class BillingAddress {
            public String Line1;
            public String City;
            public String Country;
            public String CountrySubDivisionCode;
            public String PostalCode;
        }
    }

    public class InvoiceLine {
        public String DetailType = 'SalesItemLineDetail';
        public Decimal Amount;
        public SalesItemLineDetail SalesItemLineDetail;

        public class SalesItemLineDetail {
            public String ItemRef; // QuickBooks Item Id
            public String TaxCodeRef; // e.g., 'NON' for non-taxable if configured
        }
    }

    public class InvoiceCreateReq {
        public String CustomerRef; // QuickBooks Customer Id
        public String PrivateNote; // Memo
        public List<InvoiceLine> Line = new List<InvoiceLine>();
        public Boolean AllowOnlineCreditCardPayment;
        public Boolean AllowOnlineACHPayment;
    }

    // Response fragments (minimal)
    public class CreatedCustomerRes {
        public Customer Customer;
        public class Customer {
            public String Id;
            public String DisplayName;
        }
    }

    public class CreatedInvoiceRes {
        public Invoice Invoice;
        public class Invoice {
            public String Id;
            public String DocNumber;
            public Decimal TotalAmt;
        }
    }

    // Helpers to build payloads from SObject
    public class Builders {
        public static CustomerUpsertReq customerFrom(Account acc) {
            CustomerUpsertReq req = new CustomerUpsertReq();
            req.DisplayName = acc.Name;
            req.CompanyName = acc.Name;
            if (acc.PersonEmail != null) req.PrimaryEmailAddr = acc.PersonEmail;
            if (acc.Phone != null) req.PrimaryPhone = acc.Phone;
            // Billing address if present (works for Person/Business accounts)
            if (acc.BillingStreet != null || acc.BillingCity != null) {
                req.BillAddr = new CustomerUpsertReq.BillingAddress();
                req.BillAddr.Line1 = acc.BillingStreet;
                req.BillAddr.City = acc.BillingCity;
                req.BillAddr.CountrySubDivisionCode = acc.BillingState;
                req.BillAddr.PostalCode = acc.BillingPostalCode;
                req.BillAddr.Country = acc.BillingCountry;
            }
            return req;
        }

        public static InvoiceCreateReq singleLineInvoiceFrom(Opportunity opp, String customerId, String defaultItemRef, String taxCodeRef) {
            InvoiceCreateReq req = new InvoiceCreateReq();
            req.CustomerRef = customerId;
            req.PrivateNote = 'SF Opportunity ' + opp.Id + ' - ' + opp.Name;
            QB_Models.InvoiceLine line = new QB_Models.InvoiceLine();
            line.Amount = opp.Amount != null ? opp.Amount : 0;
            line.SalesItemLineDetail = new QB_Models.InvoiceLine.SalesItemLineDetail();
            line.SalesItemLineDetail.ItemRef = defaultItemRef;
            if (taxCodeRef != null) {
                line.SalesItemLineDetail.TaxCodeRef = taxCodeRef;
            }
            req.Line.add(line);
            req.AllowOnlineACHPayment = false;
            req.AllowOnlineCreditCardPayment = false;
            return req;
        }
    }
}
